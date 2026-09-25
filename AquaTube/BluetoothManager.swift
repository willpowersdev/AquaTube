import CoreBluetooth

final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    enum ConnectionPhase: Equatable {
        case idle
        case connecting(UUID)
        case discovering(UUID)
        case ready(UUID)
        case reconnecting(UUID, reason: String, attempt: Int)
        case failed(String)
    }

    /// The most recent unexpected disconnect, kept around so the UI can report it after reconnecting
    struct DisconnectEvent: Equatable {
        let reason: String
        let date: Date
    }

    @Published var peripherals: [CBPeripheral] = []
    @Published var rssiForIdentifier: [UUID: Int] = [:]
    @Published var colorWheelCharacteristic: CBCharacteristic?
    @Published var colorCommandCharacteristic: CBCharacteristic?
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var lastDisconnect: DisconnectEvent?

    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    private var targetPeripheral: CBPeripheral?
    private var timeoutWorkItem: DispatchWorkItem?

    // CoreBluetooth never times out a connection attempt on its own
    private static let connectionTimeout: TimeInterval = 10
    private static let maxReconnectAttempts = 5

    // UUIDs of the BLE service and characteristics on the Arduino Nano 33 BLE
    private static let serviceUUID = CBUUID(string: "19B10010-E8F2-537E-4F6C-D104768A1214")
    private static let colorWheelCharacteristicUUID = CBUUID(string: "19B10011-E8F2-537E-4F6C-D104768A1214")
    private static let colorCommandCharacteristicUUID = CBUUID(string: "19B10012-E8F2-537E-4F6C-D104768A1214")

    var connectedPeripheral: CBPeripheral? {
        guard case .ready = phase else { return nil }
        return targetPeripheral
    }

    var hasInitializedConnection: Bool {
        connectedPeripheral != nil && colorWheelCharacteristic != nil && colorCommandCharacteristic != nil
    }

    /// The peripheral of an established session, including while it is reconnecting
    var sessionPeripheral: CBPeripheral? {
        switch phase {
        case .ready, .reconnecting:
            return targetPeripheral
        default:
            return nil
        }
    }

    var isSessionActive: Bool {
        sessionPeripheral != nil
    }

    func connectToDevice(peripheral: CBPeripheral) {
        switch phase {
        case .connecting, .discovering, .ready, .reconnecting:
            return
        case .idle, .failed:
            break
        }
        lastDisconnect = nil

        // Scanning while connecting slows down the connection
        centralManager.stopScan()

        targetPeripheral = peripheral
        peripheral.delegate = self
        phase = .connecting(peripheral.identifier)
        centralManager.connect(peripheral, options: nil)
        startTimeout(for: peripheral)
    }

    /// A disconnect the user asked for; it is never followed by a reconnect
    func cancelConnection() {
        let peripheral = targetPeripheral
        // Clear the target first so the disconnect callback is ignored
        reset(to: .idle)
        lastDisconnect = nil
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func dismissFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }

    func scanForPeripherals() {
        guard centralManager.state == .poweredOn, !centralManager.isScanning else { return }
        switch phase {
        case .connecting, .discovering, .ready, .reconnecting:
            return
        case .idle, .failed:
            break
        }
        // Allow duplicates so RSSI keeps updating while the list is visible
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .reconnecting = phase {
                attemptReconnect()
            } else {
                scanForPeripherals()
            }
        case .poweredOff:
            // Pending connections are dropped when Bluetooth turns off, so wait for it to come back
            if isSessionActive {
                beginReconnecting(reason: "Bluetooth on this iPhone was turned off.", startImmediately: false)
            } else {
                reset(to: .failed("Bluetooth is turned off."))
            }
        case .unauthorized:
            reset(to: .failed("Bluetooth access is not allowed. Enable it in Settings."))
        case .unsupported:
            reset(to: .failed("Bluetooth is not supported on this device."))
        default:
            break
        }
    }

    func clearPeripherals() {
        peripherals = []
        rssiForIdentifier = [:]
        colorWheelCharacteristic = nil
        colorCommandCharacteristic = nil
    }

    func centralManager(
            _ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String : Any],
            rssi RSSI: NSNumber
        ) {
        if !peripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            peripherals.append(peripheral)
        }
        // 127 means the RSSI could not be read
        let value = Int(truncating: RSSI)
        if value != 127 {
            rssiForIdentifier[peripheral.identifier] = value
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == targetPeripheral?.identifier else { return }
        // Connected to the Arduino Nano 33 BLE, discover services.
        // While reconnecting, stay in that phase until the characteristics are found again.
        if case .reconnecting = phase {} else {
            phase = .discovering(peripheral.identifier)
        }
        peripheral.readRSSI()
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == targetPeripheral?.identifier else { return }
        if case .reconnecting = phase {
            scheduleNextReconnect()
            return
        }
        fail("Could not connect to \(peripheral.displayName). \(error?.localizedDescription ?? "")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Manual disconnects clear the target first, so they never get here
        guard peripheral.identifier == targetPeripheral?.identifier else { return }
        switch phase {
        case .ready:
            beginReconnecting(reason: Self.disconnectReason(for: error))
        case .reconnecting:
            // Dropped again during service discovery
            scheduleNextReconnect()
        case .connecting, .discovering:
            fail("\(peripheral.displayName) disconnected while connecting. \(Self.disconnectReason(for: error))")
        case .idle, .failed:
            break
        }
    }

    func setColor(values: [UInt8]) {
        guard
            let peripheral = connectedPeripheral,
            let characteristic = colorWheelCharacteristic
        else { return }

        // this *must* be withResponse or it won't work
        peripheral.writeValue(Data(values), for: characteristic, type: .withResponse)
    }

    /// Commands understood by onColorCommandWrite in AquaTube.ino
    enum Command: UInt8 {
        case off = 0
        case firelight = 1
        case storms = 2
        case defaultColor = 5
    }

    func send(command: Command) {
        guard
            let peripheral = connectedPeripheral,
            let characteristic = colorCommandCharacteristic
        else { return }

        peripheral.writeValue(Data([command.rawValue]), for: characteristic, type: .withResponse)
    }

    private func startTimeout(for peripheral: CBPeripheral) {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.targetPeripheral?.identifier == peripheral.identifier else { return }
            switch self.phase {
            case .connecting, .discovering:
                self.fail("\(peripheral.displayName) did not respond. Make sure it is powered on and nearby.")
            case .reconnecting:
                self.centralManager.cancelPeripheralConnection(peripheral)
                self.scheduleNextReconnect()
            default:
                break
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: workItem)
    }

    private func beginReconnecting(reason: String, startImmediately: Bool = true) {
        guard let peripheral = targetPeripheral else { return }
        lastDisconnect = DisconnectEvent(reason: reason, date: Date())
        colorWheelCharacteristic = nil
        colorCommandCharacteristic = nil
        phase = .reconnecting(peripheral.identifier, reason: reason, attempt: 0)
        if startImmediately {
            attemptReconnect()
        }
    }

    private func attemptReconnect() {
        guard
            case let .reconnecting(id, reason, attempt) = phase,
            let peripheral = targetPeripheral,
            centralManager.state == .poweredOn
        else { return }

        guard attempt < Self.maxReconnectAttempts else {
            fail("Lost connection to \(peripheral.displayName): \(reason) Reconnecting failed after \(Self.maxReconnectAttempts) attempts.")
            return
        }
        phase = .reconnecting(id, reason: reason, attempt: attempt + 1)
        centralManager.connect(peripheral, options: nil)
        startTimeout(for: peripheral)
    }

    private func scheduleNextReconnect() {
        timeoutWorkItem?.cancel()
        guard case let .reconnecting(id, _, attempt) = phase else { return }
        // Back off a little more after each failed attempt
        let delay = min(Double(attempt), 4)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, case .reconnecting(id, _, attempt) = self.phase else { return }
            self.attemptReconnect()
        }
    }

    private static func disconnectReason(for error: Error?) -> String {
        guard let error else {
            return "The connection was closed."
        }
        if let cbError = error as? CBError {
            switch cbError.code {
            case .connectionTimeout:
                return "The signal was lost. The device may be out of range or blocked."
            case .peripheralDisconnected:
                return "The device ended the connection. It may have been reset or powered off."
            case .connectionFailed:
                return "The connection failed."
            case .connectionLimitReached:
                return "The device has too many connections."
            case .encryptionTimedOut:
                return "The secure connection timed out."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func fail(_ message: String) {
        if let peripheral = targetPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        reset(to: .failed(message))
    }

    private func reset(to newPhase: ConnectionPhase) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        targetPeripheral = nil
        colorWheelCharacteristic = nil
        colorCommandCharacteristic = nil
        phase = newPhase
        scanForPeripherals()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == targetPeripheral?.identifier else { return }

        if let error {
            if case .reconnecting = phase {
                centralManager.cancelPeripheralConnection(peripheral)
                scheduleNextReconnect()
            } else {
                fail("Could not read services: \(error.localizedDescription)")
            }
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("\(peripheral.displayName) is not an AquaTube.")
            return
        }
        // Found the service, discover characteristics
        peripheral.discoverCharacteristics([Self.colorWheelCharacteristicUUID, Self.colorCommandCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == targetPeripheral?.identifier else { return }

        if let error {
            if case .reconnecting = phase {
                centralManager.cancelPeripheralConnection(peripheral)
                scheduleNextReconnect()
            } else {
                fail("Could not read characteristics: \(error.localizedDescription)")
            }
            return
        }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.colorWheelCharacteristicUUID:
                colorWheelCharacteristic = characteristic
            case Self.colorCommandCharacteristicUUID:
                colorCommandCharacteristic = characteristic
            default:
                break
            }
        }

        guard colorWheelCharacteristic != nil, colorCommandCharacteristic != nil else {
            if case .reconnecting = phase {
                centralManager.cancelPeripheralConnection(peripheral)
                scheduleNextReconnect()
            } else {
                fail("\(peripheral.displayName) is missing required characteristics.")
            }
            return
        }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        phase = .ready(peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        rssiForIdentifier[peripheral.identifier] = Int(truncating: RSSI)
    }
}

extension CBPeripheral {
    var displayName: String {
        name ?? "Unknown Device"
    }
}

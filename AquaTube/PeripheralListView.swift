///
/// PeripheralListView.swift
/// AquaTube
/// Created by William Powers on 7/15/23.
/// Copyright © 2023 ION6, LLC. All rights reserved.
///

import SwiftUI
import CoreBluetooth

struct PeripheralListView: View {
    @StateObject var manager = BluetoothManager()
    @State private var selectedPeripheral: CBPeripheral?
    
    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    if manager.peripherals.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching for nearby AquaTubes...")
                                .font(.headline)
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        Section() {
                            ForEach(manager.peripherals, id: \.self) { peripheral in
                                Button {
                                    selectedPeripheral = peripheral
                                    manager.connectToDevice(peripheral: peripheral)
                                } label: {
                                    PeripheralItemView(
                                        manager: manager,
                                        peripheral: peripheral,
                                        isConnecting: isConnecting(to: peripheral)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isBusy)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
                .navigationTitle("Peripherals")
                .navigationDestination(isPresented: Binding<Bool>(
                    // Stay on the color screen while an unexpected disconnect is being recovered
                    get: { manager.isSessionActive },
                    set: { _ in }
                )) {
                    if let peripheral = manager.sessionPeripheral {
                        ColorChangerView(manager: manager, peripheral: peripheral)
                            .navigationBarBackButtonHidden(true)
                    }
                }
                .refreshable {
                    manager.scanForPeripherals()
                }
            }
            .onAppear() {
                manager.scanForPeripherals()
            }
        }
        .overlay() {
            if showsPopup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                PopupView(
                    phase: manager.phase,
                    peripheralName: selectedPeripheral?.displayName ?? "device",
                    onCancel: { manager.cancelConnection() },
                    onRetry: {
                        manager.dismissFailure()
                        if let peripheral = selectedPeripheral {
                            manager.connectToDevice(peripheral: peripheral)
                        }
                    },
                    onDismiss: { manager.dismissFailure() }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.phase)
        .preferredColorScheme(.dark)
    }

    private var isBusy: Bool {
        switch manager.phase {
        case .connecting, .discovering: return true
        default: return false
        }
    }

    private var showsPopup: Bool {
        switch manager.phase {
        case .connecting, .discovering, .failed: return true
        case .idle, .ready, .reconnecting: return false
        }
    }

    private func isConnecting(to peripheral: CBPeripheral) -> Bool {
        switch manager.phase {
        case .connecting(let id), .discovering(let id): return id == peripheral.identifier
        default: return false
        }
    }
}

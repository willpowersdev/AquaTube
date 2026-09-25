///
/// PeripheralItemView.swift
/// AquaTube
/// Created by William Powers on 7/15/23.
/// Copyright © 2023 ION6, LLC. All rights reserved.
///

import SwiftUI
import CoreBluetooth

struct PeripheralItemView: View {
    @ObservedObject var manager: BluetoothManager
    var peripheral: CBPeripheral
    var isConnecting: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            if let RSSI = manager.rssiForIdentifier[peripheral.identifier] {
                RSSIView(RSSI: RSSI)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(peripheral.name ?? "Unknown Name")")
                    .font(.title2)
                Text("\(peripheral.identifier)")
                    .font(.custom("Helvetica", fixedSize: 12))
            }
            Spacer()
            if isConnecting {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        // Make the whole row tappable, not just the text
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
}

struct RSSIView: View {
    var RSSI: Int

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: "cellularbars")
            Text("\(RSSI)")
                .font(.custom("Helvetica", fixedSize: 12))
        }
    }
}

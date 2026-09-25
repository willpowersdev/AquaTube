///
/// PopupView.swift
/// AquaTube
/// Created by William Powers on 7/14/23.
/// Copyright © 2023 ION6, LLC. All rights reserved.
///

import SwiftUI
import CoreBluetooth

struct PopupView: View {
    var phase: BluetoothManager.ConnectionPhase
    var peripheralName: String
    var onCancel: () -> Void
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .connecting:
                ProgressView()
                    .controlSize(.large)
                Text("Connecting to \(peripheralName)…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel, action: onCancel)
            case .discovering:
                ProgressView()
                    .controlSize(.large)
                Text("Setting up \(peripheralName)…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel, action: onCancel)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.yellow)
                Text("Connection Failed")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    Button("Dismiss", action: onDismiss)
                    Button("Try Again", action: onRetry)
                        .bold()
                }
            case .idle, .ready, .reconnecting:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}

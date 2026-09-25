///
/// ColorChanger.swift
/// AquaTube
/// Created by William Powers on 7/13/23.
/// Copyright © 2023 ION6, LLC. All rights reserved.
///

import SwiftUI
import CoreBluetooth

struct ColorChangerView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedSwatch: ColorSwatch?
    @State private var selectedRoutine: LightRoutine?
    @State private var showsReconnectedBanner = false
    @ObservedObject var manager: BluetoothManager
    var peripheral: CBPeripheral

    var body: some View {
        VStack(alignment: .leading) {
            ConnectionBanner(phase: manager.phase, lastDisconnect: manager.lastDisconnect, showsReconnected: showsReconnectedBanner)
            Text(statusText)
            Text("\(peripheral.name ?? "")")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Routines")
                        .font(.headline)
                    ForEach(LightRoutine.allCases) { routine in
                        RoutineRow(routine: routine, isSelected: selectedRoutine == routine) {
                            selectedSwatch = nil
                            selectedRoutine = routine
                            manager.send(command: routine.command)
                        }
                    }
                    Text("Colors")
                        .font(.headline)
                        .padding(.top, 8)
                    SwatchGrid(selection: selectedSwatch) { swatch in
                        selectedRoutine = nil
                        selectedSwatch = swatch
                        manager.setColor(values: swatch.values)
                    }
                }
                .padding(.vertical, 8)
            }
            .disabled(!manager.hasInitializedConnection)
            .opacity(manager.hasInitializedConnection ? 1 : 0.4)
        }
        .navigationTitle("Color Changer")
        .padding(.top, 10)
        .padding(.horizontal, 16)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Disconnect") {
                    manager.cancelConnection()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.phase)
        .animation(.easeInOut(duration: 0.2), value: showsReconnectedBanner)
        .onChange(of: manager.phase) { phase in
            guard case .ready = phase, manager.lastDisconnect != nil else { return }
            // Reconnected: restore the color in case the device reset, and say what happened
            if let selectedSwatch {
                manager.setColor(values: selectedSwatch.values)
            } else if let selectedRoutine {
                manager.send(command: selectedRoutine.command)
            }
            showsReconnectedBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                showsReconnectedBanner = false
            }
        }
        .onChange(of: manager.isSessionActive) { isActive in
            if isActive == false {
                manager.clearPeripherals()
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    private var statusText: String {
        if case .reconnecting = manager.phase {
            return "Reconnecting"
        }
        return peripheral.state.description
    }
}

struct ColorSwatch: Identifiable, Equatable {
    let name: String
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var id: String { name }
    var values: [UInt8] { [red, green, blue] }
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    // Black is left out on purpose: it would just turn the LEDs off
    static let palette: [ColorSwatch] = [
        ColorSwatch(name: "Red", red: 255, green: 0, blue: 0),
        ColorSwatch(name: "Orange", red: 255, green: 96, blue: 0),
        ColorSwatch(name: "Amber", red: 255, green: 160, blue: 0),
        ColorSwatch(name: "Yellow", red: 255, green: 255, blue: 0),
        ColorSwatch(name: "Lime", red: 128, green: 255, blue: 0),
        ColorSwatch(name: "Green", red: 0, green: 255, blue: 0),
        ColorSwatch(name: "Spring", red: 0, green: 255, blue: 128),
        ColorSwatch(name: "Cyan", red: 0, green: 255, blue: 255),
        ColorSwatch(name: "Sky", red: 0, green: 128, blue: 255),
        ColorSwatch(name: "Blue", red: 0, green: 0, blue: 255),
        ColorSwatch(name: "Violet", red: 128, green: 0, blue: 255),
        ColorSwatch(name: "Magenta", red: 255, green: 0, blue: 255),
        ColorSwatch(name: "Pink", red: 255, green: 0, blue: 128),
        ColorSwatch(name: "Rose", red: 255, green: 64, blue: 96),
        ColorSwatch(name: "Warm White", red: 255, green: 180, blue: 100),
        ColorSwatch(name: "White", red: 255, green: 255, blue: 255),
    ]
}

enum LightRoutine: String, CaseIterable, Identifiable {
    case firelight = "Firelight"
    case storms = "Storms"

    var id: String { rawValue }
    var name: String { rawValue }

    var command: BluetoothManager.Command {
        switch self {
        case .firelight: return .firelight
        case .storms: return .storms
        }
    }

    var summary: String {
        switch self {
        case .firelight: return "Flickering torch light in reds and oranges"
        case .storms: return "Moonlight broken by blue and white lightning"
        }
    }

    var iconName: String {
        switch self {
        case .firelight: return "flame.fill"
        case .storms: return "cloud.bolt.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .firelight: return .orange
        case .storms: return Color(.sRGB, red: 0.55, green: 0.7, blue: 1.0)
        }
    }

    /// A sample of the colors the routine moves through, left to right
    var gradient: Gradient {
        switch self {
        case .firelight: return FirelightPreview.gradient
        case .storms: return StormsPreview.gradient
        }
    }
}

/// Mirrors setFireColor() in AquaTube.ino so the preview matches the device
enum FirelightPreview {
    static func color(heat: Double, brightness: Double) -> Color {
        let red = 255 * brightness
        let green = (18 + heat * 112) * brightness * brightness
        return Color(.sRGB, red: red / 255, green: green / 255, blue: 0)
    }

    // (heat, brightness) samples covering normal flicker, a flare and a gutter
    private static let samples: [(Double, Double)] = [
        (0.50, 0.80), (0.35, 0.70), (0.60, 0.88), (0.45, 0.75),
        (0.95, 0.98), (0.70, 0.90), (0.40, 0.72), (0.10, 0.35),
        (0.25, 0.55), (0.55, 0.85), (0.35, 0.65), (0.88, 0.96),
        (0.50, 0.80),
    ]

    static let gradient = Gradient(colors: samples.map { color(heat: $0.0, brightness: $0.1) })
}

/// Mirrors the Storms colors in AquaTube.ino: long stretches of moonlight
/// with sharp flashes that fall back to it
enum StormsPreview {
    private static let moonlight = RGB(22, 26, 40)
    private static let white = RGB(255, 255, 255)
    private static let blueWhite = RGB(170, 200, 255)
    private static let blue = RGB(30, 80, 255)

    private struct RGB {
        let red: Double, green: Double, blue: Double
        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }

        /// The flash partway through decaying back to moonlight
        func fading(to base: RGB, level: Double) -> Color {
            Color(.sRGB,
                  red: (base.red + (red - base.red) * level) / 255,
                  green: (base.green + (green - base.green) * level) / 255,
                  blue: (base.blue + (blue - base.blue) * level) / 255)
        }

        var color: Color { fading(to: self, level: 1) }
    }

    // A single strike, a quiet stretch, then a three-flash strike
    static let gradient = Gradient(stops: [
        .init(color: moonlight.color, location: 0.00),
        .init(color: moonlight.color, location: 0.20),
        .init(color: white.color, location: 0.22),
        .init(color: white.fading(to: moonlight, level: 0.3), location: 0.26),
        .init(color: moonlight.color, location: 0.31),
        .init(color: moonlight.color, location: 0.58),
        .init(color: blue.color, location: 0.60),
        .init(color: blue.fading(to: moonlight, level: 0.25), location: 0.63),
        .init(color: blueWhite.color, location: 0.65),
        .init(color: blueWhite.fading(to: moonlight, level: 0.35), location: 0.68),
        .init(color: white.color, location: 0.70),
        .init(color: white.fading(to: moonlight, level: 0.3), location: 0.74),
        .init(color: moonlight.color, location: 0.80),
        .init(color: moonlight.color, location: 1.00),
    ])
}

struct RoutineRow: View {
    var routine: LightRoutine
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(gradient: routine.gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white, lineWidth: isSelected ? 3 : 0)
                    )
                    .overlay(alignment: .trailing) {
                        Image(systemName: "checkmark")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .padding(.trailing, 14)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .shadow(color: routine.accentColor.opacity(isSelected ? 0.6 : 0), radius: 12)
                HStack(spacing: 6) {
                    Image(systemName: routine.iconName)
                        .foregroundColor(routine.accentColor)
                    Text(routine.name)
                        .font(.subheadline.bold())
                    Text(routine.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(routine.name). \(routine.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct SwatchGrid: View {
    var selection: ColorSwatch?
    var onSelect: (ColorSwatch) -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(ColorSwatch.palette) { swatch in
                Button {
                    onSelect(swatch)
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: selection == swatch ? 3 : 0)
                                    .padding(-5)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.headline.bold())
                                    .foregroundColor(.black.opacity(0.7))
                                    .opacity(selection == swatch ? 1 : 0)
                            )
                            .shadow(color: swatch.color.opacity(0.6), radius: selection == swatch ? 10 : 0)
                        Text(swatch.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(selection == swatch ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

struct ConnectionBanner: View {
    var phase: BluetoothManager.ConnectionPhase
    var lastDisconnect: BluetoothManager.DisconnectEvent?
    var showsReconnected: Bool

    var body: some View {
        if case let .reconnecting(_, reason, attempt) = phase {
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disconnected")
                        .font(.headline)
                    Text(reason)
                        .font(.subheadline)
                    Text(attempt == 0 ? "Waiting for Bluetooth to turn back on…" : "Reconnecting (attempt \(attempt))…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if showsReconnected, case .ready = phase, let lastDisconnect {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reconnected")
                        .font(.headline)
                    Text("Disconnected at \(lastDisconnect.date.formatted(date: .omitted, time: .shortened)): \(lastDisconnect.reason)")
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension CBPeripheralState {
    var description: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnecting:
            return "Disconnecting"
        case .disconnected:
            return "Disconnected"
        @unknown default:
            return "Unknown"
        }
    }
}

struct PeripheralStateLabel: View {
    var state: CBPeripheralState

    var body: some View {
        switch state {
        case .connected:
            Text("Connected")
        case .connecting:
            Text("Connecting")
        case .disconnecting:
            Text("Disconnecting")
        case .disconnected:
            Text("Disconnected")
        @unknown default:
            Text("Unknown")
        }
    }
}

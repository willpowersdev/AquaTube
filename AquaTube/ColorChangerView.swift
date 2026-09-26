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
    case christmas = "Christmas"
    case fourthOfJuly = "4th of July"

    var id: String { rawValue }
    var name: String { rawValue }

    var command: BluetoothManager.Command {
        switch self {
        case .firelight: return .firelight
        case .storms: return .storms
        case .christmas: return .christmas
        case .fourthOfJuly: return .fourthOfJuly
        }
    }

    var summary: String {
        switch self {
        case .firelight: return "Flickering flames in reds, oranges and yellows"
        case .storms: return "Moonlight broken by blue and white lightning"
        case .christmas: return "Red, gold and green with twinkling sparkles"
        case .fourthOfJuly: return "Red, white and blue, then a fireworks show"
        }
    }

    var iconName: String {
        switch self {
        case .firelight: return "flame.fill"
        case .storms: return "cloud.bolt.fill"
        case .christmas: return "tree.fill"
        case .fourthOfJuly: return "sparkles"
        }
    }

    var accentColor: Color {
        switch self {
        case .firelight: return .orange
        case .storms: return Color(.sRGB, red: 0.55, green: 0.7, blue: 1.0)
        case .christmas: return Color(.sRGB, red: 1.0, green: 0.78, blue: 0.2)
        case .fourthOfJuly: return Color(.sRGB, red: 0.4, green: 0.55, blue: 1.0)
        }
    }

    /// A sample of the colors the routine moves through, left to right
    var gradient: Gradient {
        switch self {
        case .firelight: return FirelightPreview.gradient
        case .storms: return StormsPreview.gradient
        case .christmas: return ChristmasPreview.gradient
        case .fourthOfJuly: return FourthOfJulyPreview.gradient
        }
    }
}

/// Runs the same heat simulation as updateFirelight() in AquaTube.ino
/// (adapted from Electriangle/Fire_Main) and samples the blended color over
/// time, so the preview shows the course the LED actually takes
enum FirelightPreview {
    private static let cells = 50
    private static let flameHeight = 50
    private static let sparks = 100

    /// Small seeded generator so the preview looks the same on every launch
    private struct SeededRandom {
        var state: UInt64
        mutating func next(_ lower: Int, _ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return lower + Int((state >> 33) % UInt64(upper - lower))
        }
    }

    /// Fire_Main's setPixelHeatColor()
    private static func heatColor(_ temperature: Int) -> (Int, Int, Int) {
        let t192 = Int((Double(temperature) / 255 * 191).rounded())
        let heatramp = (t192 & 0x3F) << 2
        if t192 > 0x80 { return (255, 255, heatramp) }
        if t192 > 0x40 { return (255, heatramp, 0) }
        return (heatramp, 0, 0)
    }

    static let gradient: Gradient = {
        var random = SeededRandom(state: 7)
        var heat = [Int](repeating: 0, count: cells)
        var colors: [Color] = []

        // Let the fire build for a second, then sample every 60ms for ~1.5s
        for frame in 0..<250 {
            for i in 0..<cells {
                heat[i] = max(0, heat[i] - random.next(0, (flameHeight * 10) / cells + 2))
            }
            for k in stride(from: cells - 1, through: 2, by: -1) {
                heat[k] = (heat[k - 1] + heat[k - 2] + heat[k - 2]) / 3
            }
            if random.next(0, 255) < sparks {
                let y = random.next(0, 7)
                heat[y] = min(255, heat[y] + random.next(160, 255))
            }

            guard frame >= 100, frame % 6 == 0 else { continue }
            var red = 0, green = 0, blue = 0
            for temperature in heat {
                let rgb = heatColor(temperature)
                red += rgb.0
                green += rgb.1
                blue += rgb.2
            }
            colors.append(Color(.sRGB,
                                red: Double(red / cells) / 255,
                                green: Double(green / cells) / 255,
                                blue: Double(blue / cells) / 255))
        }
        return Gradient(colors: colors)
    }()
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

/// Mirrors the Christmas colors and timings in AquaTube.ino: one full cycle
/// of holds and crossfades, with a sparkle during each hold
enum ChristmasPreview {
    private static let colors: [(Double, Double, Double)] = [
        (255, 0, 0),     // red
        (255, 140, 0),   // gold
        (0, 255, 20),    // green
        (255, 140, 0),   // gold
    ]
    private static let sparkle = (255.0, 200.0, 80.0)
    private static let holdSeconds = 2.5
    private static let fadeSeconds = 1.5

    private static func color(_ rgb: (Double, Double, Double)) -> Color {
        Color(.sRGB, red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }

    static let gradient: Gradient = {
        let segment = holdSeconds + fadeSeconds
        let cycle = segment * Double(colors.count)
        var stops: [Gradient.Stop] = []

        for (index, rgb) in colors.enumerated() {
            let start = Double(index) * segment / cycle
            let holdEnd = start + holdSeconds / cycle
            // Sparkle partway through the hold
            let sparkleAt = start + holdSeconds * 0.45 / cycle
            stops.append(.init(color: color(rgb), location: start))
            stops.append(.init(color: color(rgb), location: sparkleAt - 0.004))
            stops.append(.init(color: color(sparkle), location: sparkleAt))
            stops.append(.init(color: color(rgb), location: sparkleAt + 0.025))
            stops.append(.init(color: color(rgb), location: holdEnd))
        }
        // The last fade returns to the first color
        stops.append(.init(color: color(colors[0]), location: 1))
        return Gradient(stops: stops)
    }()
}

/// Mirrors the 4th of July colors and timings in AquaTube.ino: the red,
/// white and blue crossfades, then a fireworks show ending in a finale
enum FourthOfJulyPreview {
    private typealias RGB = (Double, Double, Double)
    private static let night: RGB = (2, 2, 8)
    private static let red: RGB = (255, 0, 0)
    private static let white: RGB = (255, 255, 255)
    private static let blue: RGB = (0, 40, 255)
    private static let launchGlow: RGB = (255, 120, 30)

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    static let gradient: Gradient = {
        // (seconds, color) points along one full loop
        var points: [(Double, RGB)] = [
            (0, night), (1, red), (3, red), (4, white), (6, white), (7, blue), (9, blue), (10, night),
        ]
        var time = 10.3

        func firework(_ color: RGB, launch: Double, fade: Double, endLevel: Double, gap: Double) {
            points.append((time, points.last?.1 ?? night))
            time += launch
            points.append((time, mix(night, launchGlow, 0.25)))
            points.append((time + 0.01, color))
            time += 0.07
            points.append((time, color))
            time += fade * 0.5
            // A crackle as the burst dies
            let fading = mix(night, color, 0.45)
            points.append((time, fading))
            points.append((time + 0.03, mix(fading, white, 0.5)))
            points.append((time + 0.06, fading))
            time += fade * 0.5
            points.append((time, mix(night, color, endLevel)))
            time += gap
        }

        // The show
        for color in [red, white, blue, red, white] {
            firework(color, launch: 0.6, fade: 1.0, endLevel: 0, gap: 0.6)
        }
        // The finale: rockets go up before the last burst has faded
        for color in [blue, red, white, blue, red] {
            firework(color, launch: 0.2, fade: 0.45, endLevel: 0.35, gap: 0)
        }
        time += 0.6
        points.append((time, night))

        return Gradient(stops: points.map { point in
            .init(color: Color(.sRGB, red: point.1.0 / 255, green: point.1.1 / 255, blue: point.1.2 / 255),
                  location: point.0 / time)
        })
    }()
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

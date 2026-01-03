//
//  PS4ControllerView.swift
//  ClaudeConsole
//
//  Visual representation of PlayStation controller with button states
//  Supports both DualShock 4 (PS4) and DualSense (PS5) controllers
//

import SwiftUI

struct PS4ControllerView: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @ObservedObject var profileManager: RadialMenuProfileManager
    @State private var showConfiguration = false
    @State private var configuringButton: PS4Button?

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                let statusText = monitor.isConnected
                    ? "\(monitor.controllerType.displayName) Connected"
                    : "No Controller Connected"

                Label(statusText,
                      systemImage: monitor.isConnected ? "gamecontroller.fill" : "gamecontroller")
                    .foregroundColor(monitor.isConnected ? .green : .gray)

                Spacer()

                Button(action: { showConfiguration.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Radial Menu Profile Selector
            RadialMenuProfileSelector(profileManager: profileManager)
                .padding(.horizontal)

            Divider()

            // Controller visual
            ZStack {
                // Controller body shape
                ControllerBody()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        ControllerBody()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(width: 350, height: 240)

                // All button components
                VStack(spacing: 35) {
                    // Top section (L1/R1, L2/R2)
                    HStack(spacing: 160) {
                        VStack(spacing: 8) {
                            ShoulderButton(
                                label: "L2",
                                isPressed: monitor.pressedButtons.contains(.l2),
                                mapping: mapping.getCommand(for: .l2)?.displayString
                            )
                            ShoulderButton(
                                label: "L1",
                                isPressed: monitor.pressedButtons.contains(.l1),
                                mapping: mapping.getCommand(for: .l1)?.displayString
                            )
                        }

                        VStack(spacing: 8) {
                            ShoulderButton(
                                label: "R2",
                                isPressed: monitor.pressedButtons.contains(.r2),
                                mapping: mapping.getCommand(for: .r2)?.displayString
                            )
                            ShoulderButton(
                                label: "R1",
                                isPressed: monitor.pressedButtons.contains(.r1),
                                mapping: mapping.getCommand(for: .r1)?.displayString
                            )
                        }
                    }

                    // Middle section (sticks, d-pad, buttons, center)
                    HStack(alignment: .bottom, spacing: 30) {
                        // Left side - D-pad and left stick
                        VStack(alignment: .center, spacing: 20) {
                            DPadView(monitor: monitor, mapping: mapping)
                                .frame(height: 70) // Match face buttons height
                            AnalogStick(
                                label: "L3",
                                x: monitor.leftStickX,
                                y: monitor.leftStickY,
                                isPressed: monitor.pressedButtons.contains(.l3),
                                mapping: mapping.getCommand(for: .l3)?.displayString
                            )
                        }
                        .frame(width: 70) // Fixed width for alignment

                        // Center - Share/Create, Touchpad, Options, PS, Mute
                        VStack(spacing: 8) {
                            HStack(spacing: 20) {
                                // Show Share (PS4) or Create (PS5) button depending on controller type
                                if monitor.controllerType == .dualSense {
                                    CenterButton(
                                        label: "Create",
                                        isPressed: monitor.pressedButtons.contains(.create),
                                        mapping: mapping.getCommand(for: .create)?.displayString,
                                        width: 35
                                    )
                                } else {
                                    CenterButton(
                                        label: "Share",
                                        isPressed: monitor.pressedButtons.contains(.share),
                                        mapping: mapping.getCommand(for: .share)?.displayString,
                                        width: 35
                                    )
                                }

                                CenterButton(
                                    label: "Options",
                                    isPressed: monitor.pressedButtons.contains(.options),
                                    mapping: mapping.getCommand(for: .options)?.displayString,
                                    width: 35
                                )
                            }

                            TouchpadButton(
                                isPressed: monitor.pressedButtons.contains(.touchpad),
                                mapping: mapping.getCommand(for: .touchpad)?.displayString
                            )

                            PSButton(
                                isPressed: monitor.pressedButtons.contains(.psButton),
                                mapping: mapping.getCommand(for: .psButton)?.displayString
                            )

                            // Show Mute button for DualSense controllers
                            if monitor.controllerType == .dualSense {
                                CenterButton(
                                    label: "Mute",
                                    isPressed: monitor.pressedButtons.contains(.mute),
                                    mapping: mapping.getCommand(for: .mute)?.displayString,
                                    width: 35
                                )
                            }
                        }

                        // Right side - Face buttons and right stick
                        VStack(alignment: .center, spacing: 20) {
                            FaceButtonsView(monitor: monitor, mapping: mapping)
                                .frame(height: 70) // Match D-pad height
                            AnalogStick(
                                label: "R3",
                                x: monitor.rightStickX,
                                y: monitor.rightStickY,
                                isPressed: monitor.pressedButtons.contains(.r3),
                                mapping: mapping.getCommand(for: .r3)?.displayString
                            )
                        }
                        .frame(width: 70) // Fixed width for alignment
                    }
                }
                .offset(y: -10)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showConfiguration) {
            PS4EnhancedConfigView(mapping: mapping)
        }
    }
}

// Controller body shape
struct ControllerBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 40

        // Create a rounded rectangle with grip extensions
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        return path
    }
}

// D-Pad component
struct DPadView: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping

    var body: some View {
        ZStack {
            // D-pad background
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 60, height: 60)
                .cornerRadius(4)

            // D-pad buttons
            VStack(spacing: 0) {
                DPadButton(
                    symbol: "↑",
                    isPressed: monitor.pressedButtons.contains(.dpadUp),
                    mapping: mapping.getCommand(for: .dpadUp)?.displayString
                )

                HStack(spacing: 0) {
                    DPadButton(
                        symbol: "←",
                        isPressed: monitor.pressedButtons.contains(.dpadLeft),
                        mapping: mapping.getCommand(for: .dpadLeft)?.displayString
                    )
                    Spacer().frame(width: 20)
                    DPadButton(
                        symbol: "→",
                        isPressed: monitor.pressedButtons.contains(.dpadRight),
                        mapping: mapping.getCommand(for: .dpadRight)?.displayString
                    )
                }

                DPadButton(
                    symbol: "↓",
                    isPressed: monitor.pressedButtons.contains(.dpadDown),
                    mapping: mapping.getCommand(for: .dpadDown)?.displayString
                )
            }
        }
    }
}

// Individual D-pad button
struct DPadButton: View {
    let symbol: String
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isPressed ? Color.blue : Color.gray)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? .blue : .clear, radius: isPressed ? 4 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -15)
            }
        }
    }
}

// Face buttons (Cross, Circle, Square, Triangle)
struct FaceButtonsView: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 70, height: 70)

            // Face buttons in perfect diamond pattern
            ZStack {
                // Triangle (top)
                FaceButton(
                    symbol: "△",
                    color: .green,
                    isPressed: monitor.pressedButtons.contains(.triangle),
                    mapping: mapping.getCommand(for: .triangle)?.displayString
                )
                .offset(y: -20)

                // Square (left)
                FaceButton(
                    symbol: "□",
                    color: .pink,
                    isPressed: monitor.pressedButtons.contains(.square),
                    mapping: mapping.getCommand(for: .square)?.displayString
                )
                .offset(x: -20)

                // Circle (right)
                FaceButton(
                    symbol: "○",
                    color: .red,
                    isPressed: monitor.pressedButtons.contains(.circle),
                    mapping: mapping.getCommand(for: .circle)?.displayString
                )
                .offset(x: 20)

                // Cross (bottom)
                FaceButton(
                    symbol: "✕",
                    color: .blue,
                    isPressed: monitor.pressedButtons.contains(.cross),
                    mapping: mapping.getCommand(for: .cross)?.displayString
                )
                .offset(y: 20)
            }
        }
    }
}

// Individual face button
struct FaceButton: View {
    let symbol: String
    let color: Color
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? color : color.opacity(0.3))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(color, lineWidth: 1)
                )
                .overlay(
                    Text(symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? color : .clear, radius: isPressed ? 6 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -18)
            }
        }
    }
}

// Shoulder button
struct ShoulderButton: View {
    let label: String
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isPressed ? Color.orange : Color.gray)
                .frame(width: 50, height: 20)
                .overlay(
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? .orange : .clear, radius: isPressed ? 4 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -15)
            }
        }
    }
}

// Analog stick
struct AnalogStick: View {
    let label: String
    let x: Float
    let y: Float
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: 1)
                )

            Circle()
                .fill(isPressed ? Color.purple : Color.gray)
                .frame(width: 25, height: 25)
                .offset(x: CGFloat(x) * 7, y: CGFloat(-y) * 7)
                .shadow(color: isPressed ? .purple : .clear, radius: isPressed ? 4 : 0)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -25)
            }
        }
    }
}

// Center button (Share, Options)
struct CenterButton: View {
    let label: String
    let isPressed: Bool
    let mapping: String?
    let width: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isPressed ? Color.cyan : Color.gray)
                .frame(width: width, height: 15)
                .overlay(
                    Text(label)
                        .font(.system(size: 7))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? .cyan : .clear, radius: isPressed ? 4 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -12)
            }
        }
    }
}

// Touchpad button
struct TouchpadButton: View {
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isPressed ? Color.indigo : Color.black.opacity(0.3))
                .frame(width: 70, height: 35)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .overlay(
                    Text("Touchpad")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? .indigo : .clear, radius: isPressed ? 4 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -22)
            }
        }
    }
}

// PS button
struct PSButton: View {
    let isPressed: Bool
    let mapping: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? Color.blue : Color.black.opacity(0.5))
                .frame(width: 25, height: 25)
                .overlay(
                    Text("PS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? .blue : .clear, radius: isPressed ? 6 : 0)

            if let mapping = mapping, isPressed {
                Text(mapping)
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .offset(y: -18)
            }
        }
    }
}
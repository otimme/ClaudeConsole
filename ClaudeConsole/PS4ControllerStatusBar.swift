//
//  PS4ControllerStatusBar.swift
//  ClaudeConsole
//
//  Compact status bar showing PlayStation controller button mappings
//  Supports both DualShock 4 (PS4) and DualSense (PS5) controllers
//  Fallout Pip-Boy style
//

import SwiftUI

struct PS4ControllerStatusBar: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @State private var hoveredButton: PS4Button?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Connection indicator
                FalloutConnectionIndicator(isConnected: monitor.isConnected)

                FalloutDivider(.vertical)
                    .frame(height: 35)
                    .padding(.horizontal, 4)

                // Face buttons group
                FalloutButtonGroup(title: "FACE", buttons: [.cross, .circle, .square, .triangle],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                FalloutDivider(.vertical)
                    .frame(height: 35)
                    .padding(.horizontal, 4)

                // D-Pad group
                FalloutButtonGroup(title: "D-PAD", buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                FalloutDivider(.vertical)
                    .frame(height: 35)
                    .padding(.horizontal, 4)

                // Shoulders group
                FalloutButtonGroup(title: "SHOULDER", buttons: [.l1, .r1, .l2, .r2],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                FalloutDivider(.vertical)
                    .frame(height: 35)
                    .padding(.horizontal, 4)

                // Sticks group
                FalloutButtonGroup(title: "STICKS", buttons: [.l3, .r3],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                FalloutDivider(.vertical)
                    .frame(height: 35)
                    .padding(.horizontal, 4)

                // Menu buttons group - changes based on controller type
                if monitor.controllerType == .dualSense {
                    FalloutButtonGroup(title: "MENU", buttons: [.options, .create, .touchpad, .mute],
                               monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)
                } else {
                    FalloutButtonGroup(title: "MENU", buttons: [.options, .share, .touchpad],
                               monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 60)
        .background(Color.Fallout.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.Fallout.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// Fallout-styled connection status indicator
struct FalloutConnectionIndicator: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.Fallout.primary : Color.Fallout.inactive)
                .frame(width: 8, height: 8)
                .shadow(color: isConnected ? Color.Fallout.glow.opacity(0.6) : .clear, radius: 4)

            Image(systemName: isConnected ? "gamecontroller.fill" : "gamecontroller")
                .font(.system(size: 16))
                .foregroundColor(isConnected ? Color.Fallout.primary : Color.Fallout.tertiary)
                .falloutGlow(radius: isConnected ? 2 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            BeveledRectangle(cornerSize: 4)
                .fill(isConnected ? Color.Fallout.primary.opacity(0.1) : Color.Fallout.inactive.opacity(0.3))
        )
        .overlay(
            BeveledRectangle(cornerSize: 4)
                .stroke(isConnected ? Color.Fallout.border : Color.Fallout.borderDim, lineWidth: 1)
        )
    }
}

// Fallout-styled button group
struct FalloutButtonGroup: View {
    let title: String
    let buttons: [PS4Button]
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @Binding var hoveredButton: PS4Button?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.Fallout.caption)
                .foregroundColor(Color.Fallout.tertiary)
                .tracking(1)

            HStack(spacing: 4) {
                ForEach(buttons, id: \.self) { button in
                    FalloutCompactButtonView(
                        button: button,
                        isPressed: monitor.pressedButtons.contains(button),
                        keyMapping: mapping.getCommand(for: button),
                        isHovered: hoveredButton == button
                    )
                    .onHover { hovering in
                        hoveredButton = hovering ? button : nil
                    }
                }
            }
        }
    }
}

// Fallout-styled individual button in the status bar
struct FalloutCompactButtonView: View {
    let button: PS4Button
    let isPressed: Bool
    let keyMapping: KeyCommand?
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 3) {
            // Button symbol
            Text(buttonSymbol)
                .font(.Fallout.caption)
                .fontWeight(.bold)
                .foregroundColor(isPressed ? Color.Fallout.background : Color.Fallout.primary)
                .frame(width: buttonWidth, height: 20)
                .background(
                    BeveledRectangle(cornerSize: 3)
                        .fill(isPressed ? Color.Fallout.primary : Color.Fallout.inactive)
                )
                .overlay(
                    BeveledRectangle(cornerSize: 3)
                        .stroke(Color.Fallout.border.opacity(isPressed ? 1 : 0.4), lineWidth: 1)
                )
                .shadow(color: isPressed ? Color.Fallout.glow.opacity(0.6) : .clear, radius: 4)
                .scaleEffect(isPressed ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)

            // Key mapping
            Text(keyMapping?.displayString ?? "—")
                .font(.Fallout.caption)
                .foregroundColor(isPressed ? Color.Fallout.primary : Color.Fallout.secondary)
                .falloutGlow(radius: isPressed ? 2 : 0)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.Fallout.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.Fallout.borderDim, lineWidth: 0.5)
                        )
                )
                .lineLimit(1)
                .frame(minWidth: buttonWidth)
        }
        .help(helpText)
        .opacity(isHovered ? 1.0 : 0.95)
    }

    var buttonSymbol: String {
        switch button {
        case .cross, .circle, .square, .triangle:
            return button.rawValue
        case .dpadUp: return "↑"
        case .dpadDown: return "↓"
        case .dpadLeft: return "←"
        case .dpadRight: return "→"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .options: return "OPT"
        case .share: return "SHR"
        case .create: return "CRT"
        case .touchpad: return "PAD"
        case .psButton: return "PS"
        case .mute: return "MUT"
        }
    }

    var buttonWidth: CGFloat {
        switch button {
        case .options, .share, .create, .touchpad, .mute:
            return 38
        default:
            return 32
        }
    }

    var helpText: String {
        let buttonName = button.displayName
        let mapping = keyMapping?.displayString ?? "Not mapped"
        return "\(buttonName)\nMapped to: \(mapping)"
    }
}

// Fallout-styled minimalist status bar
struct PS4ControllerMiniBar: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @State private var showExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(monitor.isConnected ? Color.Fallout.primary : Color.Fallout.inactive)
                    .frame(width: 6, height: 6)
                    .shadow(color: monitor.isConnected ? Color.Fallout.glow.opacity(0.5) : .clear, radius: 3)

                Image(systemName: monitor.isConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 12))
                    .foregroundColor(monitor.isConnected ? Color.Fallout.primary : Color.Fallout.tertiary)
            }

            if monitor.isConnected {
                FalloutDivider(.vertical)
                    .frame(height: 16)

                // Currently pressed buttons
                if !monitor.pressedButtons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(monitor.pressedButtons), id: \.self) { button in
                            HStack(spacing: 2) {
                                Text(button.rawValue)
                                    .font(.Fallout.caption)
                                    .fontWeight(.bold)
                                if let command = mapping.getCommand(for: button) {
                                    Text("→")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color.Fallout.secondary)
                                    Text(command.displayString)
                                        .font(.Fallout.caption)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                BeveledRectangle(cornerSize: 3)
                                    .fill(Color.Fallout.primary)
                            )
                            .foregroundColor(Color.Fallout.background)
                        }
                    }
                } else {
                    Text("AWAITING INPUT")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)
                        .tracking(1)
                }

                Spacer()

                // Quick reference toggle
                Button(action: { showExpanded.toggle() }) {
                    Image(systemName: showExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Color.Fallout.secondary)
                }
                .buttonStyle(.plain)
                .help("Show/hide button mappings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.Fallout.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.Fallout.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

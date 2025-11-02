//
//  PS4ControllerStatusBar.swift
//  ClaudeConsole
//
//  Compact status bar showing PS4 controller button mappings
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
                ConnectionIndicator(isConnected: monitor.isConnected)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Face buttons group
                ButtonGroup(title: "Face", buttons: [.cross, .circle, .square, .triangle],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // D-Pad group
                ButtonGroup(title: "D-Pad", buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Shoulders group
                ButtonGroup(title: "Shoulders", buttons: [.l1, .r1, .l2, .r2],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Sticks group
                ButtonGroup(title: "Sticks", buttons: [.l3, .r3],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Menu buttons group
                ButtonGroup(title: "Menu", buttons: [.options, .share, .touchpad],
                           monitor: monitor, mapping: mapping, hoveredButton: $hoveredButton)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 55)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            // Bottom border
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
}

// Connection status indicator
struct ConnectionIndicator: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isConnected ? "gamecontroller.fill" : "gamecontroller")
                .font(.system(size: 16))
                .foregroundColor(isConnected ? .green : .gray)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isConnected ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        )
    }
}

// Group of related buttons
struct ButtonGroup: View {
    let title: String
    let buttons: [PS4Button]
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @Binding var hoveredButton: PS4Button?

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(buttons, id: \.self) { button in
                    CompactButtonView(
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

// Individual button in the status bar
struct CompactButtonView: View {
    let button: PS4Button
    let isPressed: Bool
    let keyMapping: KeyCommand?
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 2) {
            // Button symbol
            Text(buttonSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isPressed ? .white : buttonColor)
                .frame(width: buttonWidth, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPressed ? buttonColor : buttonColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(buttonColor.opacity(0.4), lineWidth: 1)
                        )
                )
                .shadow(color: isPressed ? buttonColor.opacity(0.6) : .clear,
                       radius: isPressed ? 4 : 0)
                .scaleEffect(isPressed ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)

            // Key mapping with better contrast
            Text(keyMapping?.displayString ?? "—")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isPressed ? buttonColor : Color.primary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
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
        case .touchpad: return "PAD"
        case .psButton: return "PS"
        }
    }

    var buttonWidth: CGFloat {
        switch button {
        case .options, .share, .touchpad:
            return 38
        default:
            return 32
        }
    }

    var buttonColor: Color {
        switch button {
        case .cross: return .blue
        case .circle: return .red
        case .square: return .pink
        case .triangle: return .green
        case .l1, .r1, .l2, .r2: return .orange
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return .gray
        case .l3, .r3: return .purple
        case .options, .share: return .cyan
        case .touchpad: return .indigo
        case .psButton: return .blue
        }
    }

    var helpText: String {
        let buttonName = button.displayName
        let mapping = keyMapping?.displayString ?? "Not mapped"
        return "\(buttonName)\nMapped to: \(mapping)"
    }
}

// Alternative minimalist status bar
struct PS4ControllerMiniBar: View {
    @ObservedObject var monitor: PS4ControllerMonitor
    @ObservedObject var mapping: PS4ButtonMapping
    @State private var showExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            // Connection status
            HStack(spacing: 4) {
                Image(systemName: monitor.isConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 12))
                    .foregroundColor(monitor.isConnected ? .green : .gray)
            }

            if monitor.isConnected {
                Divider()
                    .frame(height: 16)

                // Currently pressed buttons
                if !monitor.pressedButtons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(monitor.pressedButtons), id: \.self) { button in
                            HStack(spacing: 2) {
                                Text(button.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                if let command = mapping.getCommand(for: button) {
                                    Text("→")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text(command.displayString)
                                        .font(.system(size: 9, design: .monospaced))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(buttonBackgroundColor(for: button))
                            )
                            .foregroundColor(.white)
                        }
                    }
                } else {
                    Text("Press any button")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Quick reference toggle
                Button(action: { showExpanded.toggle() }) {
                    Image(systemName: showExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Show/hide button mappings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }

    func buttonBackgroundColor(for button: PS4Button) -> Color {
        switch button {
        case .cross: return .blue
        case .circle: return .red
        case .square: return .pink
        case .triangle: return .green
        case .l1, .r1, .l2, .r2: return .orange
        default: return .gray
        }
    }
}
//
//  RadialMenuView.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import SwiftUI

struct RadialMenuView: View {
    @ObservedObject var controller: RadialMenuController

    // Menu dimensions
    private let menuRadius: CGFloat = 200
    private let innerRadius: CGFloat = 60
    private let segmentAngle: Double = 45  // 360° / 8 segments

    var body: some View {
        ZStack {
            // Dimmed background
            SwiftUI.Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            // Radial menu circle
            if let config = controller.activeConfiguration {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(SwiftUI.Color(hex: "#1A1A1A").opacity(0.95))
                        .frame(width: menuRadius * 2, height: menuRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(SwiftUI.Color.white.opacity(0.2), lineWidth: 2)
                        )
                        .shadow(radius: 20)

                    // 8 segments
                    ForEach(CompassDirection.allCases, id: \.self) { direction in
                        if let action = config.action(for: direction) {
                            RadialSegmentView(
                                direction: direction,
                                action: action,
                                isSelected: controller.selectedDirection == direction,
                                menuRadius: menuRadius,
                                innerRadius: innerRadius
                            )
                        }
                    }

                    // Center label showing selected action
                    if let selectedDirection = controller.selectedDirection,
                       let selectedAction = config.action(for: selectedDirection) {
                        ActionPreviewTooltip(
                            direction: selectedDirection,
                            action: selectedAction
                        )
                        .frame(width: innerRadius * 2 - 20)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Menu title when no selection
                        Text(config.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SwiftUI.Color.white.opacity(0.8))
                            .transition(.opacity)
                    }

                    // Analog stick position indicator (optional, helpful for learning)
                    // Commented out for production - uncomment for debugging joystick input
                    // AnalogStickIndicator(position: controller.stickPosition)
                    //     .offset(y: menuRadius + 40)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.isVisible)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: controller.selectedDirection)
    }
}

// MARK: - Radial Segment View

struct RadialSegmentView: View {
    let direction: CompassDirection
    let action: ButtonAction
    let isSelected: Bool
    let menuRadius: CGFloat
    let innerRadius: CGFloat

    var body: some View {
        ZStack {
            // Pie slice shape with glow effect
            // Subtract 90° to convert our North=0° to SwiftUI's Up=270°
            PieSlice(
                startAngle: .degrees(direction.angle - 90 - 22.5),
                endAngle: .degrees(direction.angle - 90 + 22.5),
                innerRadius: innerRadius,
                outerRadius: menuRadius
            )
            .fill(isSelected ? SwiftUI.Color(hex: "#4A9EFF") : SwiftUI.Color(hex: "#2A2A2A"))
            .shadow(
                color: isSelected ? SwiftUI.Color(hex: "#4A9EFF").opacity(0.6) : SwiftUI.Color.clear,
                radius: isSelected ? 12 : 0,
                x: 0,
                y: 0
            )
            .overlay(
                PieSlice(
                    startAngle: .degrees(direction.angle - 90 - 22.5),
                    endAngle: .degrees(direction.angle - 90 + 22.5),
                    innerRadius: innerRadius,
                    outerRadius: menuRadius
                )
                .stroke(
                    isSelected ? SwiftUI.Color.white.opacity(0.4) : SwiftUI.Color.white.opacity(0.1),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .animation(
                isSelected
                    ? .spring(response: 0.3, dampingFraction: 0.7)
                    : .easeOut(duration: 0.15),
                value: isSelected
            )

            // Icon and label with enhanced animations
            VStack(spacing: 4) {
                Image(systemName: iconForAction(action))
                    .font(.system(size: isSelected ? 26 : 24))
                    .foregroundColor(isSelected ? SwiftUI.Color.white : SwiftUI.Color.gray)
                    .shadow(
                        color: isSelected ? SwiftUI.Color.white.opacity(0.3) : SwiftUI.Color.clear,
                        radius: 4
                    )

                Text(shortLabel(for: action))
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? SwiftUI.Color.white : SwiftUI.Color.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 60)
            .offset(labelOffset(for: direction))
        }
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(
            isSelected
                ? .spring(response: 0.25, dampingFraction: 0.65)
                : .easeOut(duration: 0.12),
            value: isSelected
        )
    }

    // Calculate position for label based on direction
    private func labelOffset(for direction: CompassDirection) -> CGSize {
        let labelDistance = (menuRadius + innerRadius) / 2
        // Subtract 90° to match the rotated pie slices
        let adjustedAngle = direction.angle - 90
        let angleRadians = adjustedAngle * .pi / 180

        let x = cos(angleRadians) * labelDistance
        let y = sin(angleRadians) * labelDistance

        return CGSize(width: x, height: y)
    }

    // Get appropriate SF Symbol for action
    private func iconForAction(_ action: ButtonAction) -> String {
        switch action {
        case .keyCommand(let cmd):
            if cmd.key == "\t" { return "arrow.right.circle" }
            if cmd.modifiers.contains(.control) && cmd.key == "c" { return "xmark.circle" }
            if cmd.modifiers.contains(.control) && cmd.key == "z" { return "arrow.uturn.backward" }
            return "keyboard"
        case .textMacro(let text, _):
            if text.hasPrefix("git status") { return "doc.text.magnifyingglass" }
            if text.hasPrefix("git push") { return "arrow.up.circle" }
            if text.hasPrefix("git pull") { return "arrow.down.circle" }
            if text.hasPrefix("git add") { return "plus.circle" }
            if text.hasPrefix("git commit") { return "checkmark.circle" }
            if text.hasPrefix("git diff") { return "doc.plaintext" }
            if text.hasPrefix("git branch") { return "arrow.triangle.branch" }
            if text.hasPrefix("git stash") { return "archivebox" }
            return "terminal"
        case .applicationCommand(let cmd):
            switch cmd {
            case .pushToTalkSpeech: return "mic.circle"
            case .triggerSpeechToText: return "mic.fill"
            case .stopSpeechToText: return "mic.slash"
            case .copyToClipboard: return "doc.on.doc"
            case .pasteFromClipboard: return "doc.on.clipboard"
            case .clearTerminal: return "trash"
            case .showUsage: return "chart.bar"
            case .showContext: return "info.circle"
            case .togglePS4Panel: return "gamecontroller"
            case .toggleStatusBar: return "menubar.rectangle"
            case .refreshStats: return "arrow.clockwise"
            }
        case .shellCommand: return "terminal"
        case .systemCommand: return "gearshape"
        case .sequence: return "list.bullet"
        }
    }

    // Get short label for action
    private func shortLabel(for action: ButtonAction) -> String {
        switch action {
        case .textMacro(let text, _):
            if text.hasPrefix("git ") {
                let command = text.dropFirst(4).split(separator: " ").first ?? ""
                return String(command)
            }
            return action.shortDescription
        case .applicationCommand(let cmd):
            switch cmd {
            case .pushToTalkSpeech: return "Speech"
            case .triggerSpeechToText: return "Toggle"
            case .stopSpeechToText: return "Stop"
            case .copyToClipboard: return "Copy"
            case .pasteFromClipboard: return "Paste"
            case .clearTerminal: return "Clear"
            case .showUsage: return "Usage"
            case .showContext: return "Context"
            case .togglePS4Panel: return "Panel"
            case .toggleStatusBar: return "Status"
            case .refreshStats: return "Refresh"
            }
        default:
            return action.shortDescription
        }
    }
}

// MARK: - Action Preview Tooltip

struct ActionPreviewTooltip: View {
    let direction: CompassDirection
    let action: ButtonAction

    var body: some View {
        VStack(spacing: 6) {
            // Direction indicator
            Text(direction.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SwiftUI.Color.white.opacity(0.6))
                .textCase(.uppercase)

            // Action type badge
            Text(actionTypeName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(SwiftUI.Color.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(actionTypeColor.opacity(0.3))
                .cornerRadius(4)

            // Action details
            VStack(spacing: 2) {
                Text(actionTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SwiftUI.Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                if let subtitle = actionSubtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(SwiftUI.Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var actionTypeName: String {
        switch action {
        case .keyCommand: return "KEY PRESS"
        case .textMacro: return "TEXT MACRO"
        case .applicationCommand: return "APP COMMAND"
        case .shellCommand: return "SHELL"
        case .systemCommand: return "SYSTEM"
        case .sequence: return "SEQUENCE"
        }
    }

    private var actionTypeColor: SwiftUI.Color {
        switch action {
        case .keyCommand: return SwiftUI.Color.blue
        case .textMacro: return SwiftUI.Color.green
        case .applicationCommand: return SwiftUI.Color.purple
        case .shellCommand: return SwiftUI.Color.orange
        case .systemCommand: return SwiftUI.Color.red
        case .sequence: return SwiftUI.Color.cyan
        }
    }

    private var actionTitle: String {
        switch action {
        case .keyCommand(let cmd):
            return cmd.displayString
        case .textMacro(let text, _):
            // Truncate long text
            if text.count > 30 {
                return String(text.prefix(27)) + "..."
            }
            return text
        case .applicationCommand(let cmd):
            return cmd.displayString
        case .shellCommand(let command):
            // Truncate long commands
            if command.count > 30 {
                return String(command.prefix(27)) + "..."
            }
            return command
        case .systemCommand(let cmd):
            return cmd.displayString
        case .sequence(let actions):
            return "\(actions.count) actions"
        }
    }

    private var actionSubtitle: String? {
        switch action {
        case .textMacro(_, let autoEnter):
            return autoEnter ? "Auto-enter: ON" : "Auto-enter: OFF"
        case .shellCommand:
            return "⚠️ Executes with permissions"
        default:
            return nil
        }
    }
}

// MARK: - Pie Slice Shape

struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Move to inner arc start
        let innerStartX = center.x + innerRadius * cos(CGFloat(startAngle.radians))
        let innerStartY = center.y + innerRadius * sin(CGFloat(startAngle.radians))
        path.move(to: CGPoint(x: innerStartX, y: innerStartY))

        // Draw outer arc
        let outerStartX = center.x + outerRadius * cos(CGFloat(startAngle.radians))
        let outerStartY = center.y + outerRadius * sin(CGFloat(startAngle.radians))
        path.addLine(to: CGPoint(x: outerStartX, y: outerStartY))
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)

        // Draw line to inner arc
        let innerEndX = center.x + innerRadius * cos(CGFloat(endAngle.radians))
        let innerEndY = center.y + innerRadius * sin(CGFloat(endAngle.radians))
        path.addLine(to: CGPoint(x: innerEndX, y: innerEndY))

        // Draw inner arc back to start
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)

        path.closeSubpath()
        return path
    }
}

// MARK: - Analog Stick Indicator

struct AnalogStickIndicator: View {
    let position: CGPoint

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(SwiftUI.Color(hex: "#2A2A2A").opacity(0.8))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(SwiftUI.Color.white.opacity(0.3), lineWidth: 1)
                )

            // Stick position dot
            Circle()
                .fill(SwiftUI.Color.white)
                .frame(width: 10, height: 10)
                .offset(x: position.x * 15, y: position.y * 15)
        }
    }
}

// MARK: - Color Extension

extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

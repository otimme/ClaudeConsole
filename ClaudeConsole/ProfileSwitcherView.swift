//
//  ProfileSwitcherView.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import SwiftUI

struct ProfileSwitcherView: View {
    @ObservedObject var controller: ProfileSwitcherController

    // Menu dimensions
    private let menuRadius: CGFloat = 220
    private let innerRadius: CGFloat = 70
    private let segmentAngle: Double = 45  // 360° / 8 profiles

    var body: some View {
        ZStack {
            // Dimmed background
            SwiftUI.Color.black
                .opacity(0.5)
                .ignoresSafeArea()

            // Radial profile selector
            if controller.isVisible {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(SwiftUI.Color(hex: "#1A1A2E").opacity(0.95))
                        .frame(width: menuRadius * 2, height: menuRadius * 2)
                        .overlay(
                            Circle()
                                .stroke(SwiftUI.Color(hex: "#4A9EFF").opacity(0.3), lineWidth: 3)
                        )
                        .shadow(radius: 25)

                    // 8 profile segments
                    ForEach(0..<8, id: \.self) { index in
                        if index < controller.profileManager.profiles.count {
                            ProfileSegmentView(
                                profile: controller.profileManager.profiles[index],
                                index: index,
                                direction: indexToDirection(index),
                                isSelected: controller.selectedProfileIndex == index,
                                isActive: controller.profileManager.activeProfile.id == controller.profileManager.profiles[index].id,
                                menuRadius: menuRadius,
                                innerRadius: innerRadius
                            )
                        }
                    }

                    // Center label
                    VStack(spacing: 8) {
                        if let selectedIndex = controller.selectedProfileIndex,
                           selectedIndex < controller.profileManager.profiles.count {
                            // Show selected profile name
                            let selectedProfile = controller.profileManager.profiles[selectedIndex]
                            Text(selectedProfile.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(SwiftUI.Color.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: innerRadius * 2 - 30)
                                .transition(.scale.combined(with: .opacity))

                            Text("Release to switch")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(SwiftUI.Color.white.opacity(0.7))
                                .transition(.opacity)
                        } else {
                            // Menu title when no selection
                            Text("Profile Switcher")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SwiftUI.Color.white.opacity(0.8))
                                .transition(.opacity)

                            Text("Move stick to select")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(SwiftUI.Color.white.opacity(0.6))
                                .transition(.opacity)
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.isVisible)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: controller.selectedProfileIndex)
    }

    // Map profile index to compass direction
    private func indexToDirection(_ index: Int) -> CompassDirection {
        switch index {
        case 0: return .north
        case 1: return .northeast
        case 2: return .east
        case 3: return .southeast
        case 4: return .south
        case 5: return .southwest
        case 6: return .west
        case 7: return .northwest
        default: return .north
        }
    }
}

// MARK: - Profile Segment View

struct ProfileSegmentView: View {
    let profile: RadialMenuProfile
    let index: Int
    let direction: CompassDirection
    let isSelected: Bool
    let isActive: Bool  // Currently active profile
    let menuRadius: CGFloat
    let innerRadius: CGFloat

    var body: some View {
        ZStack {
            // Pie slice shape with glow effect
            PieSlice(
                startAngle: .degrees(direction.angle - 90 - 22.5),
                endAngle: .degrees(direction.angle - 90 + 22.5),
                innerRadius: innerRadius,
                outerRadius: menuRadius
            )
            .fill(fillColor)
            .shadow(
                color: shadowColor,
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
                    strokeColor,
                    lineWidth: strokeWidth
                )
            )
            .animation(
                isSelected
                    ? .spring(response: 0.3, dampingFraction: 0.7)
                    : .easeOut(duration: 0.15),
                value: isSelected
            )

            // Profile name and icon
            VStack(spacing: 4) {
                // Icon based on profile name
                Image(systemName: iconForProfile(profile.name))
                    .font(.system(size: isSelected ? 28 : 26))
                    .foregroundColor(isSelected ? SwiftUI.Color.white : SwiftUI.Color.gray)
                    .shadow(
                        color: isSelected ? SwiftUI.Color.white.opacity(0.3) : SwiftUI.Color.clear,
                        radius: 4
                    )

                Text(profile.name)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 70)

                // Active indicator
                if isActive {
                    Circle()
                        .fill(SwiftUI.Color(hex: "#4CAF50"))
                        .frame(width: 6, height: 6)
                }
            }
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

    // Colors based on state
    private var fillColor: SwiftUI.Color {
        if isSelected {
            return SwiftUI.Color(hex: "#4A9EFF")
        } else if isActive {
            return SwiftUI.Color(hex: "#2D5A3D")  // Subtle green for active
        } else {
            return SwiftUI.Color(hex: "#2A2A2A")
        }
    }

    private var shadowColor: SwiftUI.Color {
        isSelected ? SwiftUI.Color(hex: "#4A9EFF").opacity(0.6) : SwiftUI.Color.clear
    }

    private var strokeColor: SwiftUI.Color {
        if isSelected {
            return SwiftUI.Color.white.opacity(0.4)
        } else if isActive {
            return SwiftUI.Color(hex: "#4CAF50").opacity(0.5)
        } else {
            return SwiftUI.Color.white.opacity(0.1)
        }
    }

    private var strokeWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var textColor: SwiftUI.Color {
        if isSelected {
            return SwiftUI.Color.white
        } else if isActive {
            return SwiftUI.Color(hex: "#8BC34A")
        } else {
            return SwiftUI.Color.gray
        }
    }

    // Calculate label offset based on direction
    private func labelOffset(for direction: CompassDirection) -> CGSize {
        let labelRadius = (menuRadius + innerRadius) / 2
        let angleInRadians = direction.angle * .pi / 180
        return CGSize(
            width: labelRadius * sin(angleInRadians),
            height: -labelRadius * cos(angleInRadians)
        )
    }

    // Icon for profile name
    private func iconForProfile(_ name: String) -> String {
        switch name.lowercased() {
        case "default":
            return "star.fill"
        case "docker":
            return "shippingbox.fill"
        case "npm", "node":
            return "square.stack.3d.up.fill"
        case "navigation":
            return "folder.fill"
        case "claude":
            return "brain.head.profile"
        case "dev tools":
            return "wrench.and.screwdriver.fill"
        case "git advanced":
            return "point.3.connected.trianglepath.dotted"
        case "testing":
            return "checkmark.seal.fill"
        default:
            return "folder.fill"
        }
    }
}

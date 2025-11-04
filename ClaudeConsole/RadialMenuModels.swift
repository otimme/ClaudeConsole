//
//  RadialMenuModels.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import Foundation

/// Compass direction for radial menu segments
enum CompassDirection: String, CaseIterable, Codable {
    case north = "N"
    case northeast = "NE"
    case east = "E"
    case southeast = "SE"
    case south = "S"
    case southwest = "SW"
    case west = "W"
    case northwest = "NW"

    /// The center angle in degrees for this direction (0° = North/Up)
    var angle: Double {
        switch self {
        case .north: return 0
        case .northeast: return 45
        case .east: return 90
        case .southeast: return 135
        case .south: return 180
        case .southwest: return 225
        case .west: return 270
        case .northwest: return 315
        }
    }

    /// Determine compass direction from angle (0-360°, where 0° = North)
    static func from(angle: Double) -> CompassDirection? {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        let adjusted = normalized < 0 ? normalized + 360 : normalized

        // Each segment covers 45° (360° / 8 segments)
        // North is centered at 0°, so it covers 337.5° - 22.5°
        switch adjusted {
        case 337.5...360, 0..<22.5:
            return .north
        case 22.5..<67.5:
            return .northeast
        case 67.5..<112.5:
            return .east
        case 112.5..<157.5:
            return .southeast
        case 157.5..<202.5:
            return .south
        case 202.5..<247.5:
            return .southwest
        case 247.5..<292.5:
            return .west
        case 292.5..<337.5:
            return .northwest
        default:
            return nil
        }
    }
}

/// Configuration for a single radial menu (8 segments)
struct RadialMenuConfiguration {
    let name: String
    let segments: [CompassDirection: ButtonAction]

    /// Get action for a specific direction, returns nil if empty segment
    func action(for direction: CompassDirection) -> ButtonAction? {
        return segments[direction]
    }

    /// Check if a direction has an action assigned
    func hasAction(for direction: CompassDirection) -> Bool {
        return segments[direction] != nil
    }
}

// MARK: - Default Configurations

extension RadialMenuConfiguration {
    /// Default L1 menu - Quick Actions
    static let defaultL1Menu = RadialMenuConfiguration(
        name: "Quick Actions",
        segments: [
            .north: .applicationCommand(.showUsage),
            .northeast: .applicationCommand(.pasteFromClipboard),
            .east: .applicationCommand(.clearTerminal),
            .southeast: .keyCommand(KeyCommand(key: "\t", modifiers: [])),  // Tab
            .south: .keyCommand(KeyCommand(key: "c", modifiers: [.control])),  // Ctrl+C
            .southwest: .keyCommand(KeyCommand(key: "z", modifiers: [.control])),  // Ctrl+Z
            .west: .applicationCommand(.pushToTalkSpeech),
            .northwest: .applicationCommand(.copyToClipboard)
        ]
    )

    /// Default R1 menu - Git Commands
    static let defaultR1Menu = RadialMenuConfiguration(
        name: "Git Commands",
        segments: [
            .north: .textMacro(text: "git status", autoEnter: true),
            .northeast: .textMacro(text: "git push", autoEnter: true),
            .east: .textMacro(text: "git add .", autoEnter: true),
            .southeast: .textMacro(text: "git diff", autoEnter: true),
            .south: .textMacro(text: "git commit -m \"\"", autoEnter: false),
            .southwest: .textMacro(text: "git branch", autoEnter: true),
            .west: .textMacro(text: "git pull", autoEnter: true),
            .northwest: .textMacro(text: "git stash", autoEnter: true)
        ]
    )
}

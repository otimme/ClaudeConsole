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
struct RadialMenuConfiguration: Codable, Equatable, Hashable {
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

/// Complete profile containing L1 and R1 menu configurations
struct RadialMenuProfile: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var l1Menu: RadialMenuConfiguration
    var r1Menu: RadialMenuConfiguration

    init(id: UUID = UUID(), name: String, l1Menu: RadialMenuConfiguration, r1Menu: RadialMenuConfiguration) {
        self.id = id
        self.name = name
        self.l1Menu = l1Menu
        self.r1Menu = r1Menu
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

    /// Docker Commands menu
    static let dockerMenu = RadialMenuConfiguration(
        name: "Docker",
        segments: [
            .north: .textMacro(text: "docker ps", autoEnter: true),
            .northeast: .textMacro(text: "docker images", autoEnter: true),
            .east: .textMacro(text: "docker compose up -d", autoEnter: true),
            .southeast: .textMacro(text: "docker compose down", autoEnter: true),
            .south: .textMacro(text: "docker logs ", autoEnter: false),
            .southwest: .textMacro(text: "docker exec -it ", autoEnter: false),
            .west: .textMacro(text: "docker compose logs -f", autoEnter: true),
            .northwest: .textMacro(text: "docker system prune -a", autoEnter: false)
        ]
    )

    /// NPM/Node.js Commands menu
    static let npmMenu = RadialMenuConfiguration(
        name: "NPM",
        segments: [
            .north: .textMacro(text: "npm start", autoEnter: true),
            .northeast: .textMacro(text: "npm run build", autoEnter: true),
            .east: .textMacro(text: "npm test", autoEnter: true),
            .southeast: .textMacro(text: "npm run dev", autoEnter: true),
            .south: .textMacro(text: "npm install ", autoEnter: false),
            .southwest: .textMacro(text: "npm run lint", autoEnter: true),
            .west: .textMacro(text: "npm outdated", autoEnter: true),
            .northwest: .textMacro(text: "npm update", autoEnter: true)
        ]
    )

    /// Terminal Navigation menu
    static let navigationMenu = RadialMenuConfiguration(
        name: "Navigation",
        segments: [
            .north: .textMacro(text: "ls -la", autoEnter: true),
            .northeast: .textMacro(text: "cd ..", autoEnter: true),
            .east: .textMacro(text: "pwd", autoEnter: true),
            .southeast: .textMacro(text: "find . -name ", autoEnter: false),
            .south: .textMacro(text: "cd ", autoEnter: false),
            .southwest: .textMacro(text: "mkdir ", autoEnter: false),
            .west: .textMacro(text: "cd ~", autoEnter: true),
            .northwest: .textMacro(text: "tree -L 2", autoEnter: true)
        ]
    )

    /// Claude Commands menu
    static let claudeMenu = RadialMenuConfiguration(
        name: "Claude",
        segments: [
            .north: .applicationCommand(.showUsage),
            .northeast: .applicationCommand(.showContext),
            .east: .applicationCommand(.refreshStats),
            .southeast: .applicationCommand(.togglePS4Panel),
            .south: .textMacro(text: "/clear", autoEnter: true),
            .southwest: .textMacro(text: "/help", autoEnter: true),
            .west: .applicationCommand(.pushToTalkSpeech),
            .northwest: .applicationCommand(.clearTerminal)
        ]
    )

    /// Development Tools menu
    static let devToolsMenu = RadialMenuConfiguration(
        name: "Dev Tools",
        segments: [
            .north: .textMacro(text: "code .", autoEnter: true),
            .northeast: .textMacro(text: "git log --oneline -10", autoEnter: true),
            .east: .textMacro(text: "grep -r ", autoEnter: false),
            .southeast: .textMacro(text: "tail -f ", autoEnter: false),
            .south: .textMacro(text: "ps aux | grep ", autoEnter: false),
            .southwest: .textMacro(text: "kill -9 ", autoEnter: false),
            .west: .textMacro(text: "chmod +x ", autoEnter: false),
            .northwest: .textMacro(text: "sudo ", autoEnter: false)
        ]
    )

    /// Git Advanced menu
    static let gitAdvancedMenu = RadialMenuConfiguration(
        name: "Git Advanced",
        segments: [
            .north: .textMacro(text: "git log --graph --oneline --all", autoEnter: true),
            .northeast: .textMacro(text: "git rebase -i HEAD~5", autoEnter: false),
            .east: .textMacro(text: "git cherry-pick ", autoEnter: false),
            .southeast: .textMacro(text: "git stash pop", autoEnter: true),
            .south: .textMacro(text: "git reset --soft HEAD~1", autoEnter: true),
            .southwest: .textMacro(text: "git reflog", autoEnter: true),
            .west: .textMacro(text: "git merge ", autoEnter: false),
            .northwest: .textMacro(text: "git checkout -b ", autoEnter: false)
        ]
    )

    /// Testing menu
    static let testingMenu = RadialMenuConfiguration(
        name: "Testing",
        segments: [
            .north: .textMacro(text: "npm test", autoEnter: true),
            .northeast: .textMacro(text: "npm run test:watch", autoEnter: true),
            .east: .textMacro(text: "pytest", autoEnter: true),
            .southeast: .textMacro(text: "pytest -v", autoEnter: true),
            .south: .textMacro(text: "cargo test", autoEnter: true),
            .southwest: .textMacro(text: "go test ./...", autoEnter: true),
            .west: .textMacro(text: "swift test", autoEnter: true),
            .northwest: .textMacro(text: "npm run test:coverage", autoEnter: true)
        ]
    )
}

// MARK: - Default Profiles

extension RadialMenuProfile {
    /// Default profile - Quick Actions + Git
    static let defaultProfile = RadialMenuProfile(
        name: "Default",
        l1Menu: .defaultL1Menu,
        r1Menu: .defaultR1Menu
    )

    /// Docker profile - Quick Actions + Docker
    static let dockerProfile = RadialMenuProfile(
        name: "Docker",
        l1Menu: .defaultL1Menu,
        r1Menu: .dockerMenu
    )

    /// NPM profile - Quick Actions + NPM
    static let npmProfile = RadialMenuProfile(
        name: "NPM",
        l1Menu: .defaultL1Menu,
        r1Menu: .npmMenu
    )

    /// Navigation profile - Quick Actions + Terminal Navigation
    static let navigationProfile = RadialMenuProfile(
        name: "Navigation",
        l1Menu: .defaultL1Menu,
        r1Menu: .navigationMenu
    )

    /// Claude profile - Claude Commands + Git
    static let claudeProfile = RadialMenuProfile(
        name: "Claude",
        l1Menu: .claudeMenu,
        r1Menu: .defaultR1Menu
    )

    /// Dev Tools profile - Development Tools + Git
    static let devToolsProfile = RadialMenuProfile(
        name: "Dev Tools",
        l1Menu: .devToolsMenu,
        r1Menu: .defaultR1Menu
    )

    /// Git Advanced profile - Quick Actions + Git Advanced
    static let gitAdvancedProfile = RadialMenuProfile(
        name: "Git Advanced",
        l1Menu: .defaultL1Menu,
        r1Menu: .gitAdvancedMenu
    )

    /// Testing profile - Quick Actions + Testing Commands
    static let testingProfile = RadialMenuProfile(
        name: "Testing",
        l1Menu: .defaultL1Menu,
        r1Menu: .testingMenu
    )

    /// All default profiles
    static let allDefaults: [RadialMenuProfile] = [
        .defaultProfile,
        .dockerProfile,
        .npmProfile,
        .navigationProfile,
        .claudeProfile,
        .devToolsProfile,
        .gitAdvancedProfile,
        .testingProfile
    ]
}

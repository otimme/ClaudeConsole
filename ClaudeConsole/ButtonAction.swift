//
//  ButtonAction.swift
//  ClaudeConsole
//
//  Defines the new action system for PS4 controller button mappings
//  Supports multiple action types beyond simple key commands
//

import Foundation

// MARK: - Main Button Action Enum
enum ButtonAction: Codable, Equatable, Hashable {
    case keyCommand(KeyCommand)
    case textMacro(text: String, autoEnter: Bool)
    case applicationCommand(AppCommand)
    case systemCommand(SystemCommand)
    case sequence([ButtonAction])
    case shellCommand(String)

    // Custom Codable implementation for enum with associated values
    enum CodingKeys: String, CodingKey {
        case type
        case keyCommand
        case text
        case autoEnter
        case appCommand
        case systemCommand
        case actions
        case shellCommand
    }

    enum ActionType: String, Codable {
        case keyCommand
        case textMacro
        case applicationCommand
        case systemCommand
        case sequence
        case shellCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .keyCommand:
            let command = try container.decode(KeyCommand.self, forKey: .keyCommand)
            self = .keyCommand(command)

        case .textMacro:
            let text = try container.decode(String.self, forKey: .text)
            let autoEnter = try container.decode(Bool.self, forKey: .autoEnter)
            self = .textMacro(text: text, autoEnter: autoEnter)

        case .applicationCommand:
            let command = try container.decode(AppCommand.self, forKey: .appCommand)
            self = .applicationCommand(command)

        case .systemCommand:
            let command = try container.decode(SystemCommand.self, forKey: .systemCommand)
            self = .systemCommand(command)

        case .sequence:
            let actions = try container.decode([ButtonAction].self, forKey: .actions)
            self = .sequence(actions)

        case .shellCommand:
            let command = try container.decode(String.self, forKey: .shellCommand)
            self = .shellCommand(command)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .keyCommand(let command):
            try container.encode(ActionType.keyCommand, forKey: .type)
            try container.encode(command, forKey: .keyCommand)

        case .textMacro(let text, let autoEnter):
            try container.encode(ActionType.textMacro, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(autoEnter, forKey: .autoEnter)

        case .applicationCommand(let command):
            try container.encode(ActionType.applicationCommand, forKey: .type)
            try container.encode(command, forKey: .appCommand)

        case .systemCommand(let command):
            try container.encode(ActionType.systemCommand, forKey: .type)
            try container.encode(command, forKey: .systemCommand)

        case .sequence(let actions):
            try container.encode(ActionType.sequence, forKey: .type)
            try container.encode(actions, forKey: .actions)

        case .shellCommand(let command):
            try container.encode(ActionType.shellCommand, forKey: .type)
            try container.encode(command, forKey: .shellCommand)
        }
    }

    // Display string for UI
    var displayString: String {
        switch self {
        case .keyCommand(let command):
            return command.displayString

        case .textMacro(let text, let autoEnter):
            let truncated = text.count > 20 ? String(text.prefix(17)) + "..." : text
            return autoEnter ? "\(truncated)⏎" : truncated

        case .applicationCommand(let command):
            return command.displayString

        case .systemCommand(let command):
            return command.displayString

        case .sequence(let actions):
            return "[\(actions.count) actions]"

        case .shellCommand(let command):
            let truncated = command.count > 20 ? String(command.prefix(17)) + "..." : command
            return "$ \(truncated)"
        }
    }

    // Short description for status bar
    var shortDescription: String {
        switch self {
        case .keyCommand(_):
            return "Key"

        case .textMacro(_, _):
            return "Text"

        case .applicationCommand(_):
            return "App"

        case .systemCommand(_):
            return "System"

        case .sequence(_):
            return "Sequence"

        case .shellCommand(_):
            return "Shell"
        }
    }
}

// MARK: - Application Commands
enum AppCommand: String, Codable, CaseIterable {
    case triggerSpeechToText         // Toggle mode: press to start/stop
    case stopSpeechToText            // Explicit stop (for sequences)
    case pushToTalkSpeech            // Push-to-talk: hold to record, release to transcribe
    case togglePS4Panel
    case toggleStatusBar
    case copyToClipboard
    case pasteFromClipboard
    case clearTerminal
    case showUsage
    case showContext
    case refreshStats

    var displayString: String {
        switch self {
        case .triggerSpeechToText:
            return "🎤 Toggle Speech"
        case .stopSpeechToText:
            return "🔇 Stop Speech"
        case .pushToTalkSpeech:
            return "🎤 Push-to-Talk"
        case .togglePS4Panel:
            return "🎮 Toggle Panel"
        case .toggleStatusBar:
            return "📊 Toggle Status"
        case .copyToClipboard:
            return "📋 Copy"
        case .pasteFromClipboard:
            return "📋 Paste"
        case .clearTerminal:
            return "🧹 Clear"
        case .showUsage:
            return "📊 /usage"
        case .showContext:
            return "📊 /context"
        case .refreshStats:
            return "🔄 Refresh Stats"
        }
    }

    var description: String {
        switch self {
        case .triggerSpeechToText:
            return "Toggle speech-to-text recording (on/off)"
        case .stopSpeechToText:
            return "Stop speech-to-text recording"
        case .pushToTalkSpeech:
            return "Hold to record, release to transcribe"
        case .togglePS4Panel:
            return "Toggle PS4 controller panel visibility"
        case .toggleStatusBar:
            return "Toggle PS4 status bar visibility"
        case .copyToClipboard:
            return "Copy selected text to clipboard"
        case .pasteFromClipboard:
            return "Paste from clipboard"
        case .clearTerminal:
            return "Clear terminal screen"
        case .showUsage:
            return "Show Claude usage statistics"
        case .showContext:
            return "Show Claude context information"
        case .refreshStats:
            return "Refresh all statistics"
        }
    }
}

// MARK: - System Commands
enum SystemCommand: Codable, Equatable, Hashable {
    case switchApplication(bundleId: String)
    case openURL(url: String)
    case runAppleScript(script: String)
    case takeScreenshot
    case toggleFullscreen
    case minimizeWindow

    // Custom Codable for enum with associated values
    enum CodingKeys: String, CodingKey {
        case type
        case bundleId
        case url
        case script
    }

    enum CommandType: String, Codable {
        case switchApplication
        case openURL
        case runAppleScript
        case takeScreenshot
        case toggleFullscreen
        case minimizeWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .switchApplication:
            let bundleId = try container.decode(String.self, forKey: .bundleId)
            self = .switchApplication(bundleId: bundleId)

        case .openURL:
            let url = try container.decode(String.self, forKey: .url)
            self = .openURL(url: url)

        case .runAppleScript:
            let script = try container.decode(String.self, forKey: .script)
            self = .runAppleScript(script: script)

        case .takeScreenshot:
            self = .takeScreenshot

        case .toggleFullscreen:
            self = .toggleFullscreen

        case .minimizeWindow:
            self = .minimizeWindow
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .switchApplication(let bundleId):
            try container.encode(CommandType.switchApplication, forKey: .type)
            try container.encode(bundleId, forKey: .bundleId)

        case .openURL(let url):
            try container.encode(CommandType.openURL, forKey: .type)
            try container.encode(url, forKey: .url)

        case .runAppleScript(let script):
            try container.encode(CommandType.runAppleScript, forKey: .type)
            try container.encode(script, forKey: .script)

        case .takeScreenshot:
            try container.encode(CommandType.takeScreenshot, forKey: .type)

        case .toggleFullscreen:
            try container.encode(CommandType.toggleFullscreen, forKey: .type)

        case .minimizeWindow:
            try container.encode(CommandType.minimizeWindow, forKey: .type)
        }
    }

    var displayString: String {
        switch self {
        case .switchApplication(let bundleId):
            // Extract app name from bundle ID (e.g., com.apple.Terminal -> Terminal)
            let name = bundleId.components(separatedBy: ".").last ?? bundleId
            return "→ \(name)"

        case .openURL(let url):
            let truncated = url.count > 20 ? String(url.prefix(17)) + "..." : url
            return "🌐 \(truncated)"

        case .runAppleScript(let script):
            let truncated = script.count > 20 ? String(script.prefix(17)) + "..." : script
            return "🍎 \(truncated)"

        case .takeScreenshot:
            return "📸 Screenshot"

        case .toggleFullscreen:
            return "⛶ Fullscreen"

        case .minimizeWindow:
            return "⊟ Minimize"
        }
    }
}

// MARK: - Versioned Data Container
struct PS4ButtonMappingData: Codable {
    let version: Int
    let mappings: [PS4Button: ButtonAction]
    let repeatConfigurations: [PS4Button: RepeatConfiguration]?

    static let currentVersion = 3

    init(version: Int = currentVersion, mappings: [PS4Button: ButtonAction], repeatConfigurations: [PS4Button: RepeatConfiguration] = [:]) {
        self.version = version
        self.mappings = mappings
        self.repeatConfigurations = repeatConfigurations
    }

    // Custom decoder to handle version migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode version, default to 1 if missing (legacy data)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        switch version {
        case 1:
            // Version 1: Old format with KeyCommand only
            // Try to decode as legacy format
            do {
                // First attempt: Try to decode the entire object as legacy format
                let legacyDecoder = try decoder.singleValueContainer()
                let legacyMappings = try legacyDecoder.decode([PS4Button: KeyCommand].self)

                // Migrate to new format by wrapping each KeyCommand in ButtonAction
                self.mappings = legacyMappings.mapValues { ButtonAction.keyCommand($0) }
                self.version = Self.currentVersion
                self.repeatConfigurations = nil
            } catch {
                // Second attempt: Legacy data might be under 'mappings' key
                let oldMappings = try container.decode([PS4Button: KeyCommand].self, forKey: .mappings)
                self.mappings = oldMappings.mapValues { ButtonAction.keyCommand($0) }
                self.version = Self.currentVersion
                self.repeatConfigurations = nil
            }

        case 2:
            // Version 2: Format with ButtonAction (no repeat configs)
            self.mappings = try container.decode([PS4Button: ButtonAction].self, forKey: .mappings)
            self.version = 2
            self.repeatConfigurations = nil

        case 3:
            // Version 3: Current format with ButtonAction + repeat configurations
            self.mappings = try container.decode([PS4Button: ButtonAction].self, forKey: .mappings)
            self.repeatConfigurations = try container.decodeIfPresent([PS4Button: RepeatConfiguration].self, forKey: .repeatConfigurations)
            self.version = 3

        default:
            // Future version we don't understand yet
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported mapping version: \(version). Please update the app."
                )
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case mappings
        case repeatConfigurations
    }
}

// MARK: - Preset Macros
struct MacroPreset {
    let name: String
    let category: String
    let macro: String
    let description: String
    let autoEnter: Bool

    static let gitPresets = [
        MacroPreset(name: "Status", category: "Git", macro: "git status", description: "Show working tree status", autoEnter: true),
        MacroPreset(name: "Add All", category: "Git", macro: "git add .", description: "Stage all changes", autoEnter: true),
        MacroPreset(name: "Commit", category: "Git", macro: "git commit -m \"", description: "Start commit message", autoEnter: false),
        MacroPreset(name: "Push", category: "Git", macro: "git push", description: "Push to remote", autoEnter: true),
        MacroPreset(name: "Pull", category: "Git", macro: "git pull", description: "Pull from remote", autoEnter: true),
        MacroPreset(name: "Diff", category: "Git", macro: "git diff", description: "Show unstaged changes", autoEnter: true),
        MacroPreset(name: "Log", category: "Git", macro: "git log --oneline -10", description: "Show recent commits", autoEnter: true),
        MacroPreset(name: "Branch", category: "Git", macro: "git branch", description: "List branches", autoEnter: true),
    ]

    static let npmPresets = [
        MacroPreset(name: "Install", category: "NPM", macro: "npm install", description: "Install dependencies", autoEnter: true),
        MacroPreset(name: "Run Dev", category: "NPM", macro: "npm run dev", description: "Start development server", autoEnter: true),
        MacroPreset(name: "Test", category: "NPM", macro: "npm test", description: "Run tests", autoEnter: true),
        MacroPreset(name: "Build", category: "NPM", macro: "npm run build", description: "Build for production", autoEnter: true),
        MacroPreset(name: "Start", category: "NPM", macro: "npm start", description: "Start application", autoEnter: true),
    ]

    static let dockerPresets = [
        MacroPreset(name: "PS", category: "Docker", macro: "docker ps", description: "List running containers", autoEnter: true),
        MacroPreset(name: "Images", category: "Docker", macro: "docker images", description: "List images", autoEnter: true),
        MacroPreset(name: "Logs", category: "Docker", macro: "docker logs -f ", description: "Follow container logs", autoEnter: false),
        MacroPreset(name: "Exec", category: "Docker", macro: "docker exec -it ", description: "Execute in container", autoEnter: false),
        MacroPreset(name: "Compose Up", category: "Docker", macro: "docker-compose up -d", description: "Start services", autoEnter: true),
        MacroPreset(name: "Compose Down", category: "Docker", macro: "docker-compose down", description: "Stop services", autoEnter: true),
    ]

    static let allPresets = gitPresets + npmPresets + dockerPresets
}
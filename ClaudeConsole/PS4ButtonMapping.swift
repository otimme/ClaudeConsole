//
//  PS4ButtonMapping.swift
//  ClaudeConsole
//
//  Models for mapping PS4 controller buttons to keyboard commands
//

import Foundation
import AppKit
import os.log

// Represents a keyboard command (key + modifiers)
struct KeyCommand: Codable, Equatable, Hashable {
    let key: String
    let modifiers: KeyModifiers

    // Common key codes
    enum SpecialKey: String, CaseIterable {
        case enter = "⏎"
        case space = "␣"
        case escape = "⎋"
        case tab = "⇥"
        case delete = "⌫"
        case forwardDelete = "⌦"
        case upArrow = "↑"
        case downArrow = "↓"
        case leftArrow = "←"
        case rightArrow = "→"
        case home = "↖"
        case end = "↘"
        case pageUp = "⇞"
        case pageDown = "⇟"
        case f1 = "F1"
        case f2 = "F2"
        case f3 = "F3"
        case f4 = "F4"
        case f5 = "F5"
        case f6 = "F6"
        case f7 = "F7"
        case f8 = "F8"
        case f9 = "F9"
        case f10 = "F10"
        case f11 = "F11"
        case f12 = "F12"

        var keyCode: UInt16 {
            switch self {
            case .enter: return 36
            case .space: return 49
            case .escape: return 53
            case .tab: return 48
            case .delete: return 51
            case .forwardDelete: return 117
            case .upArrow: return 126
            case .downArrow: return 125
            case .leftArrow: return 123
            case .rightArrow: return 124
            case .home: return 115
            case .end: return 119
            case .pageUp: return 116
            case .pageDown: return 121
            case .f1: return 122
            case .f2: return 120
            case .f3: return 99
            case .f4: return 118
            case .f5: return 96
            case .f6: return 97
            case .f7: return 98
            case .f8: return 100
            case .f9: return 101
            case .f10: return 109
            case .f11: return 103
            case .f12: return 111
            }
        }
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += key
        return result
    }

    // Convert to actual key event data for terminal
    func toTerminalData() -> Data? {
        // Handle special keys
        if let specialKey = SpecialKey(rawValue: key) {
            return specialKeyToData(specialKey)
        }

        // Handle regular characters
        if modifiers.isEmpty {
            return key.data(using: .utf8)
        }

        // Handle modified characters
        return modifiedKeyToData()
    }

    private func specialKeyToData(_ specialKey: SpecialKey) -> Data? {
        switch specialKey {
        case .enter:
            return Data([0x0D]) // Carriage return
        case .space:
            return Data([0x20]) // Space
        case .escape:
            return Data([0x1B]) // Escape
        case .tab:
            return Data([0x09]) // Tab
        case .delete:
            return Data([0x7F]) // Delete
        case .forwardDelete:
            return Data([0x1B, 0x5B, 0x33, 0x7E]) // ESC[3~
        case .upArrow:
            if modifiers.isEmpty {
                return Data([0x1B, 0x5B, 0x41]) // ESC[A
            } else {
                return modifiedArrowKey("A")
            }
        case .downArrow:
            if modifiers.isEmpty {
                return Data([0x1B, 0x5B, 0x42]) // ESC[B
            } else {
                return modifiedArrowKey("B")
            }
        case .leftArrow:
            if modifiers.isEmpty {
                return Data([0x1B, 0x5B, 0x44]) // ESC[D
            } else {
                return modifiedArrowKey("D")
            }
        case .rightArrow:
            if modifiers.isEmpty {
                return Data([0x1B, 0x5B, 0x43]) // ESC[C
            } else {
                return modifiedArrowKey("C")
            }
        case .home:
            return Data([0x1B, 0x5B, 0x48]) // ESC[H
        case .end:
            return Data([0x1B, 0x5B, 0x46]) // ESC[F
        case .pageUp:
            return Data([0x1B, 0x5B, 0x35, 0x7E]) // ESC[5~
        case .pageDown:
            return Data([0x1B, 0x5B, 0x36, 0x7E]) // ESC[6~
        default:
            // Function keys
            return nil
        }
    }

    private func modifiedArrowKey(_ direction: String) -> Data? {
        // Handle modified arrow keys (e.g., Shift+Arrow for selection)
        var sequence = Data([0x1B, 0x5B, 0x31])

        var modifierCode = 1
        if modifiers.contains(.shift) { modifierCode += 1 }
        if modifiers.contains(.option) { modifierCode += 2 }
        if modifiers.contains(.control) { modifierCode += 4 }

        // Safely convert strings to ASCII data
        guard let semicolon = ";".data(using: .ascii),
              let code = "\(modifierCode)".data(using: .ascii),
              let dir = direction.data(using: .ascii) else {
            return nil
        }

        sequence.append(semicolon)
        sequence.append(code)
        sequence.append(dir)

        return sequence
    }

    private func modifiedKeyToData() -> Data? {
        guard let firstChar = key.first else { return nil }

        if modifiers.contains(.control) {
            // Control sequences
            let char = firstChar.asciiValue ?? 0
            if char >= 97 && char <= 122 { // a-z
                return Data([UInt8(char - 96)]) // Ctrl+A = 1, Ctrl+B = 2, etc.
            } else if char >= 65 && char <= 90 { // A-Z
                return Data([UInt8(char - 64)]) // Same for uppercase
            }
        }

        // For other modifier combinations, just send the character
        // Terminal apps will interpret them
        return key.data(using: .utf8)
    }
}

// Modifier keys
struct KeyModifiers: Codable, OptionSet, Hashable {
    let rawValue: Int

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)

    var isEmpty: Bool {
        return rawValue == 0
    }
}

// Main mapping class
class PS4ButtonMapping: ObservableObject, Codable {
    @Published var mappings: [PS4Button: ButtonAction]

    // Default mappings - now using ButtonAction
    static let defaultMappings: [PS4Button: ButtonAction] = [
        .cross: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: [])),
        .circle: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.escape.rawValue, modifiers: [])),
        .square: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.space.rawValue, modifiers: [])),
        .triangle: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.tab.rawValue, modifiers: [])),
        .dpadUp: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.upArrow.rawValue, modifiers: [])),
        .dpadDown: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.downArrow.rawValue, modifiers: [])),
        .dpadLeft: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.leftArrow.rawValue, modifiers: [])),
        .dpadRight: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.rightArrow.rawValue, modifiers: [])),
        .l1: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.pageUp.rawValue, modifiers: [])),
        .r1: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.pageDown.rawValue, modifiers: [])),
        .l2: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.home.rawValue, modifiers: [])),
        .r2: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.end.rawValue, modifiers: [])),
        .options: .keyCommand(KeyCommand(key: "c", modifiers: .control)),
        .share: .keyCommand(KeyCommand(key: "z", modifiers: .control)),
        .l3: .keyCommand(KeyCommand(key: "a", modifiers: .control)),
        .r3: .keyCommand(KeyCommand(key: "e", modifiers: .control)),
        // New example mappings showing different action types
        .touchpad: .applicationCommand(.showUsage),
        .psButton: .applicationCommand(.togglePS4Panel)
    ]

    init() {
        self.mappings = Self.loadMappings()
    }

    // Codable
    enum CodingKeys: String, CodingKey {
        case mappings
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMappings = try container.decode([PS4Button: ButtonAction].self, forKey: .mappings)
        // Initialize the @Published property directly to ensure proper notification
        self.mappings = decodedMappings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mappings, forKey: .mappings)
    }

    // Persistence
    private static let mappingsKey = "PS4ControllerMappings"

    static func loadMappings() -> [PS4Button: ButtonAction] {
        guard let data = UserDefaults.standard.data(forKey: mappingsKey) else {
            // No saved mappings, use defaults
            return defaultMappings
        }

        do {
            // First try to decode as versioned data (v2)
            let versionedData = try JSONDecoder().decode(PS4ButtonMappingData.self, from: data)
            print("INFO: Loaded PS4 controller mappings (version \(versionedData.version))")
            return versionedData.mappings
        } catch {
            // Fallback: Try to decode as legacy format (v1 - direct dictionary)
            do {
                let legacyMappings = try JSONDecoder().decode([PS4Button: KeyCommand].self, from: data)
                print("INFO: Migrating legacy PS4 controller mappings to version 2")

                // Migrate to new format
                let migratedMappings = legacyMappings.mapValues { ButtonAction.keyCommand($0) }

                // Save in new format for next time
                let newData = PS4ButtonMappingData(version: PS4ButtonMappingData.currentVersion, mappings: migratedMappings)
                if let encoded = try? JSONEncoder().encode(newData) {
                    UserDefaults.standard.set(encoded, forKey: mappingsKey)
                    print("INFO: Successfully migrated and saved mappings in new format")
                }

                return migratedMappings
            } catch {
                print("ERROR: Failed to load PS4 controller mappings: \(error)")
                print("INFO: Falling back to default mappings")
                return defaultMappings
            }
        }
    }

    @Published var lastSaveError: Error? = nil

    @discardableResult
    func saveMappings() -> Result<Void, Error> {
        do {
            // Save with version information
            let versionedData = PS4ButtonMappingData(
                version: PS4ButtonMappingData.currentVersion,
                mappings: mappings
            )
            let encoded = try JSONEncoder().encode(versionedData)
            UserDefaults.standard.set(encoded, forKey: Self.mappingsKey)
            lastSaveError = nil
            return .success(())
        } catch {
            os_log("ERROR: Failed to save PS4 controller mappings: %{public}@", log: .default, type: .error, error.localizedDescription)
            lastSaveError = error
            return .failure(error)
        }
    }

    func resetToDefaults() {
        // @Published property will automatically trigger objectWillChange
        mappings = Self.defaultMappings
        _ = saveMappings()
    }

    func setMapping(for button: PS4Button, action: ButtonAction) {
        // @Published property will automatically trigger objectWillChange
        mappings[button] = action
        _ = saveMappings()
    }

    func getAction(for button: PS4Button) -> ButtonAction? {
        return mappings[button]
    }

    // Legacy support - convenience method for setting key commands
    func setKeyCommand(for button: PS4Button, command: KeyCommand) {
        setMapping(for: button, action: .keyCommand(command))
    }

    // Legacy support - get KeyCommand if the action is a key command
    func getCommand(for button: PS4Button) -> KeyCommand? {
        guard let action = mappings[button] else { return nil }
        switch action {
        case .keyCommand(let command):
            return command
        default:
            return nil
        }
    }
}
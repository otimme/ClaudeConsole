//
//  PS4EnhancedConfigView.swift
//  ClaudeConsole
//
//  Enhanced configuration view supporting all ButtonAction types
//

import SwiftUI
import AppKit

struct PS4EnhancedConfigView: View {
    @ObservedObject var mapping: PS4ButtonMapping
    @ObservedObject var controller: PS4ControllerController
    @Environment(\.dismiss) var dismiss

    @State private var selectedButton: PS4Button?
    @State private var showingPresetLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("PS4 Controller Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Preset Library Button
                Button {
                    showingPresetLibrary = true
                } label: {
                    Label("Preset Library", systemImage: "books.vertical")
                }
                .buttonStyle(.accessoryBar)

                Button("Reset to Defaults") {
                    mapping.resetToDefaults()
                }
                .buttonStyle(.accessoryBarAction)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Left: Button list
                ButtonListView(
                    mapping: mapping,
                    selectedButton: $selectedButton
                )
                .frame(width: 250)

                Divider()

                // Right: Action editor
                if let button = selectedButton {
                    ActionEditorView(
                        button: button,
                        mapping: mapping
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    EmptySelectionView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 800, height: 600)
        .sheet(isPresented: $showingPresetLibrary) {
            PresetLibraryView(mapping: mapping)
        }
    }
}

// MARK: - Button List View
struct ButtonListView: View {
    @ObservedObject var mapping: PS4ButtonMapping
    @Binding var selectedButton: PS4Button?

    var buttonGroups: [(String, [PS4Button])] {
        [
            ("Face Buttons", [.cross, .circle, .square, .triangle]),
            ("D-Pad", [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
            ("Shoulders", [.l1, .r1, .l2, .r2]),
            ("Sticks", [.l3, .r3]),
            ("Center", [.options, .share, .touchpad, .psButton])
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(buttonGroups, id: \.0) { group, buttons in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)

                        ForEach(buttons, id: \.self) { button in
                            ButtonRow(
                                button: button,
                                mapping: mapping,
                                isSelected: selectedButton == button,
                                onSelect: {
                                    selectedButton = button
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ButtonRow: View {
    let button: PS4Button
    @ObservedObject var mapping: PS4ButtonMapping
    let isSelected: Bool
    let onSelect: () -> Void

    var currentAction: ButtonAction? {
        mapping.getAction(for: button)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Button icon
                ButtonIcon(button: button)
                    .frame(width: 20)

                // Button name
                Text(button.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Current mapping preview
                if let action = currentAction {
                    Text(action.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(actionTypeColor(for: action).opacity(0.2))
                        .cornerRadius(4)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func actionTypeColor(for action: ButtonAction) -> Color {
        switch action {
        case .keyCommand:
            return .blue
        case .textMacro:
            return .green
        case .applicationCommand:
            return .orange
        case .systemCommand:
            return .purple
        case .sequence:
            return .pink
        case .shellCommand:
            return .red
        }
    }
}

// MARK: - Action Editor View
struct ActionEditorView: View {
    let button: PS4Button
    @ObservedObject var mapping: PS4ButtonMapping

    @State private var selectedActionType: ActionType = .keyCommand
    @State private var keyCommand = KeyCommand(key: "", modifiers: [])
    @State private var textMacro = ""
    @State private var autoEnter = true
    @State private var selectedAppCommand: AppCommand = .showUsage
    @State private var shellCommand = ""
    @State private var savedAction: ButtonAction?
    @State private var showSaveSuccess = false
    @State private var loadedActionType: ActionType?  // Track what we loaded to prevent unwanted resets

    enum ActionType: String, CaseIterable {
        case keyCommand = "Key Press"
        case textMacro = "Text Macro"
        case applicationCommand = "App Command"
        case shellCommand = "Shell Command"

        var icon: String {
            switch self {
            case .keyCommand: return "keyboard"
            case .textMacro: return "text.cursor"
            case .applicationCommand: return "app.badge"
            case .shellCommand: return "terminal"
            }
        }
    }

    var currentAction: ButtonAction? {
        mapping.getAction(for: button)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (fixed)
            HStack {
                ButtonIcon(button: button)
                    .frame(width: 30)

                Text(button.displayName)
                    .font(.title3)
                    .fontWeight(.medium)

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Action type selector (fixed)
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Type")
                    .font(.headline)

                Picker("Action Type", selection: $selectedActionType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedActionType) { newType in
                    // Only reset if user manually changed the type
                    // Don't reset if we just loaded this type from the button's current action
                    if loadedActionType != newType {
                        resetToDefaults(for: newType)
                        showSaveSuccess = false
                        loadedActionType = nil  // Clear after manual change
                    }
                }
            }
            .padding()

            Divider()

            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Action-specific editor
                    Group {
                        switch selectedActionType {
                        case .keyCommand:
                            KeyCommandEditor(command: $keyCommand)
                            .onChange(of: keyCommand) { _ in showSaveSuccess = false }

                        case .textMacro:
                            TextMacroEditor(
                                text: $textMacro,
                                autoEnter: $autoEnter
                            )
                            .onChange(of: textMacro) { _ in showSaveSuccess = false }
                            .onChange(of: autoEnter) { _ in showSaveSuccess = false }

                        case .applicationCommand:
                            AppCommandEditor(command: $selectedAppCommand)
                            .onChange(of: selectedAppCommand) { _ in showSaveSuccess = false }

                        case .shellCommand:
                            ShellCommandEditor(command: $shellCommand)
                            .onChange(of: shellCommand) { _ in showSaveSuccess = false }
                        }
                    }
                    .padding(.top)
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            // Preview (fixed)
            ActionPreview(action: previewAction)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

            // Save button (fixed)
            HStack {
                // Success indicator
                if showSaveSuccess {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                        .transition(.opacity)
                }

                Spacer()

                Button("Cancel") {
                    loadCurrentSettings(for: button)
                }
                .buttonStyle(.accessoryBar)
                .disabled(!hasChanges)

                Button(showSaveSuccess ? "Saved" : "Save") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .foregroundColor(showSaveSuccess ? .green : nil)
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: showSaveSuccess)
        }
        .onAppear {
            loadCurrentSettings(for: button)
        }
        .onChange(of: button) { newButton in
            loadCurrentSettings(for: newButton)
        }
    }

    private var previewAction: ButtonAction {
        switch selectedActionType {
        case .keyCommand:
            return .keyCommand(keyCommand)
        case .textMacro:
            return .textMacro(text: textMacro, autoEnter: autoEnter)
        case .applicationCommand:
            return .applicationCommand(selectedAppCommand)
        case .shellCommand:
            return .shellCommand(shellCommand)
        }
    }

    private var isValidAction: Bool {
        switch selectedActionType {
        case .keyCommand:
            return !keyCommand.key.isEmpty
        case .textMacro:
            return !textMacro.isEmpty && textMacro.count <= 1000
        case .applicationCommand:
            return true // Always valid
        case .shellCommand:
            return !shellCommand.isEmpty
        }
    }

    private var hasChanges: Bool {
        // Check if the current preview action differs from the saved action
        let currentPreview = previewAction

        // If we have a saved action, compare it
        if let saved = savedAction {
            return saved != currentPreview
        }

        // If no saved action exists, check if we have valid content to save
        return isValidAction
    }

    private var canSave: Bool {
        return isValidAction && hasChanges && !showSaveSuccess
    }

    private func loadCurrentSettings(for targetButton: PS4Button) {
        // Clear the loaded action type to ensure fresh load
        loadedActionType = nil

        // Save the current action for comparison
        let action = mapping.getAction(for: targetButton)
        savedAction = action
        showSaveSuccess = false

        guard let action = action else {
            // No current action, reset to defaults for key command
            loadedActionType = .keyCommand
            selectedActionType = .keyCommand
            resetToDefaults(for: .keyCommand)
            savedAction = nil
            return
        }

        // Set loadedActionType BEFORE changing selectedActionType
        // This prevents the onChange handler from resetting fields
        switch action {
        case .keyCommand(let cmd):
            loadedActionType = .keyCommand
            keyCommand = cmd
            selectedActionType = .keyCommand

        case .textMacro(let text, let enter):
            loadedActionType = .textMacro
            textMacro = text
            autoEnter = enter
            selectedActionType = .textMacro

        case .applicationCommand(let cmd):
            loadedActionType = .applicationCommand
            selectedAppCommand = cmd
            selectedActionType = .applicationCommand

        case .shellCommand(let cmd):
            loadedActionType = .shellCommand
            shellCommand = cmd
            selectedActionType = .shellCommand

        default:
            // Default to key command for unsupported types
            loadedActionType = .keyCommand
            selectedActionType = .keyCommand
            resetToDefaults(for: .keyCommand)
        }
    }

    private func resetToDefaults(for actionType: ActionType) {
        switch actionType {
        case .keyCommand:
            keyCommand = KeyCommand(key: "", modifiers: [])
        case .textMacro:
            textMacro = ""
            autoEnter = true
        case .applicationCommand:
            selectedAppCommand = .showUsage
        case .shellCommand:
            shellCommand = ""
        }
    }

    private func saveAction() {
        let action = previewAction
        mapping.setMapping(for: button, action: action)
        savedAction = action
        showSaveSuccess = true

        // Hide success indicator after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveSuccess = false
        }
    }
}

// MARK: - Specialized Editors

struct KeyCommandEditor: View {
    @Binding var command: KeyCommand
    @State private var isCapturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Combination")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                KeyCaptureField(
                    capturedKey: .init(
                        get: { command.key },
                        set: { command = KeyCommand(key: $0, modifiers: command.modifiers) }
                    ),
                    capturedModifiers: .init(
                        get: { command.modifiers },
                        set: { command = KeyCommand(key: command.key, modifiers: $0) }
                    ),
                    isCapturing: $isCapturing
                )
                .frame(height: 36)

                Button(isCapturing ? "Stop" : "Capture") {
                    isCapturing.toggle()
                }
            }

            Text("Click 'Capture' and press any key combination")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TextMacroEditor: View {
    @Binding var text: String
    @Binding var autoEnter: Bool
    @State private var showingPresets = false

    var characterCount: Int {
        text.count
    }

    var isValid: Bool {
        !text.isEmpty && characterCount <= 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text to Send")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    showingPresets = true
                } label: {
                    Label("Browse Presets", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.accessoryBar)
            }

            // Text editor with character count
            VStack(alignment: .trailing, spacing: 4) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isValid ? Color.secondary.opacity(0.2) : Color.red.opacity(0.5), lineWidth: 1)
                    )

                Text("\(characterCount)/1000 characters")
                    .font(.caption)
                    .foregroundColor(characterCount > 1000 ? .red : .secondary)
            }

            Toggle("Add Enter key after text", isOn: $autoEnter)

            // Special character reference
            DisclosureGroup("Special Characters Reference") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([
                        ("\\n", "New line"),
                        ("\\t", "Tab"),
                        ("\\\"", "Quote"),
                        ("\\\\", "Backslash"),
                        ("$(date)", "Current date/time")
                    ], id: \.0) { char, description in
                        HStack {
                            Text(char)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 60, alignment: .leading)
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .font(.caption)
        }
        .popover(isPresented: $showingPresets) {
            MacroPresetPicker(selectedText: $text, autoEnter: $autoEnter)
                .frame(width: 400, height: 500)
        }
    }
}

struct AppCommandEditor: View {
    @Binding var command: AppCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Command")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Command", selection: $command) {
                ForEach(AppCommand.allCases, id: \.self) { cmd in
                    VStack(alignment: .leading) {
                        Text(cmd.displayString)
                        Text(cmd.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(cmd)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

struct ShellCommandEditor: View {
    @Binding var command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Command")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Enter command (e.g., ls -la)", text: $command)
                .textFieldStyle(.roundedBorder)

            Text("Command will be executed with Enter key automatically")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Supporting Views

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Select a button to configure")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Choose a button from the list to view and edit its action")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActionPreview: View {
    let action: ButtonAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            HStack {
                Image(systemName: previewIcon)
                    .foregroundColor(previewColor)

                Text(action.displayString)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Text(action.shortDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(previewColor.opacity(0.2))
                    .cornerRadius(4)
            }
        }
    }

    var previewIcon: String {
        switch action {
        case .keyCommand:
            return "keyboard"
        case .textMacro:
            return "text.cursor"
        case .applicationCommand:
            return "app.badge"
        case .systemCommand:
            return "gearshape"
        case .sequence:
            return "arrow.triangle.branch"
        case .shellCommand:
            return "terminal"
        }
    }

    var previewColor: Color {
        switch action {
        case .keyCommand:
            return .blue
        case .textMacro:
            return .green
        case .applicationCommand:
            return .orange
        case .systemCommand:
            return .purple
        case .sequence:
            return .pink
        case .shellCommand:
            return .red
        }
    }
}

// MARK: - Preset Library

struct MacroPresetPicker: View {
    @Binding var selectedText: String
    @Binding var autoEnter: Bool
    @Environment(\.dismiss) var dismiss

    @State private var selectedCategory = "All"
    @State private var searchText = ""

    var categories: [String] {
        ["All"] + Array(Set(MacroPreset.allPresets.map { $0.category })).sorted()
    }

    var filteredPresets: [MacroPreset] {
        MacroPreset.allPresets.filter { preset in
            let matchesCategory = selectedCategory == "All" || preset.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                preset.name.localizedCaseInsensitiveContains(searchText) ||
                preset.macro.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Macro Presets")
                    .font(.title3)
                    .fontWeight(.medium)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Category selector and search
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            .padding()

            // Preset list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredPresets, id: \.macro) { preset in
                        PresetRow(preset: preset) {
                            selectedText = preset.macro
                            autoEnter = preset.autoEnter
                            dismiss()
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct PresetRow: View {
    let preset: MacroPreset
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.system(.body, weight: .medium))

                    Text(preset.macro)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(preset.category)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(categoryColor(preset.category))
                        .cornerRadius(4)

                    if preset.autoEnter {
                        Label("Auto Enter", systemImage: "return")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func categoryColor(_ category: String) -> Color {
        switch category {
        case "Git": return .green
        case "NPM": return .orange
        case "Docker": return .blue
        default: return .gray
        }
    }
}

struct PresetLibraryView: View {
    @ObservedObject var mapping: PS4ButtonMapping
    @Environment(\.dismiss) var dismiss

    @State private var selectedPresetSet = "Terminal"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preset Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Preset sets
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PresetSetCard(
                        title: "Git Workflow",
                        description: "Common git commands for version control",
                        icon: "arrow.triangle.branch",
                        color: .green
                    ) {
                        applyGitPreset()
                    }

                    PresetSetCard(
                        title: "Terminal Power User",
                        description: "Essential terminal shortcuts and commands",
                        icon: "terminal",
                        color: .blue
                    ) {
                        controller.applyPreset(.terminal)
                    }

                    PresetSetCard(
                        title: "Vim Navigation",
                        description: "Navigate and edit text with Vim keybindings",
                        icon: "keyboard",
                        color: .purple
                    ) {
                        controller.applyPreset(.vim)
                    }

                    PresetSetCard(
                        title: "Docker Management",
                        description: "Control Docker containers and images",
                        icon: "shippingbox",
                        color: .orange
                    ) {
                        applyDockerPreset()
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }

    // Stub for controller reference
    var controller: PS4ControllerController {
        PS4ControllerController() // This would be injected
    }

    func applyGitPreset() {
        // Apply git-focused mappings
        mapping.setMapping(for: .cross, action: .textMacro(text: "git status", autoEnter: true))
        mapping.setMapping(for: .circle, action: .textMacro(text: "git add .", autoEnter: true))
        mapping.setMapping(for: .square, action: .textMacro(text: "git diff", autoEnter: true))
        mapping.setMapping(for: .triangle, action: .textMacro(text: "git log --oneline -10", autoEnter: true))
        mapping.setMapping(for: .l1, action: .textMacro(text: "git pull", autoEnter: true))
        mapping.setMapping(for: .r1, action: .textMacro(text: "git push", autoEnter: true))
    }

    func applyDockerPreset() {
        // Apply docker-focused mappings
        mapping.setMapping(for: .cross, action: .textMacro(text: "docker ps", autoEnter: true))
        mapping.setMapping(for: .circle, action: .textMacro(text: "docker images", autoEnter: true))
        mapping.setMapping(for: .square, action: .textMacro(text: "docker-compose up -d", autoEnter: true))
        mapping.setMapping(for: .triangle, action: .textMacro(text: "docker-compose down", autoEnter: true))
    }
}

struct PresetSetCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let onApply: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(color)
                .frame(width: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Apply") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
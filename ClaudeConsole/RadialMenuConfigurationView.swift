//
//  RadialMenuConfigurationView.swift
//  ClaudeConsole
//
//  Comprehensive radial menu configuration UI with segment editing
//

import SwiftUI
import UniformTypeIdentifiers

/// Full-featured radial menu configuration view
struct RadialMenuConfigurationView: View {
    @ObservedObject var profileManager: RadialMenuProfileManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedMenuType: MenuType = .l1
    @State private var selectedDirection: CompassDirection? = nil
    @State private var editingProfile: RadialMenuProfile?
    @State private var showingNewProfile = false
    @State private var showingImportExport = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    enum MenuType: String, CaseIterable {
        case l1 = "L1 Menu"
        case r1 = "R1 Menu"
    }

    var currentMenu: RadialMenuConfiguration {
        let profile = editingProfile ?? profileManager.activeProfile
        return selectedMenuType == .l1 ? profile.l1Menu : profile.r1Menu
    }

    var body: some View {
        HSplitView {
            // Left Panel: Profile list and menu preview
            VStack(alignment: .leading, spacing: 0) {
                // Profile selector
                profileSelectorSection

                Divider()

                // Menu type selector
                menuTypeSelectorSection

                Divider()

                // Visual menu preview
                menuPreviewSection

                Divider()

                // Segment list
                segmentListSection
            }
            .frame(minWidth: 350, idealWidth: 400)

            // Right Panel: Segment editor
            if let direction = selectedDirection {
                SegmentEditorView(
                    profile: Binding(
                        get: { editingProfile ?? profileManager.activeProfile },
                        set: { editingProfile = $0 }
                    ),
                    menuType: selectedMenuType,
                    direction: direction,
                    onSave: { saveSegmentChanges() }
                )
                .id(direction) // Force view recreation when direction changes
            } else {
                emptyStateView
            }
        }
        .frame(width: 900, height: 650)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showingImportExport.toggle()
                } label: {
                    Label("Import/Export", systemImage: "arrow.up.arrow.down.circle")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $showingImportExport) {
            ImportExportView(profileManager: profileManager)
        }
        .sheet(isPresented: $showingNewProfile) {
            NewProfileView(profileManager: profileManager)
        }
        .alert("Profile Update", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Profile Selector Section

    private var profileSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active Profile")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    showingNewProfile = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Create new profile")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Picker("", selection: Binding(
                get: { profileManager.activeProfile },
                set: { profileManager.selectProfile($0); editingProfile = nil }
            )) {
                ForEach(profileManager.profiles) { profile in
                    Text(profile.name).tag(profile)
                }
            }
            .labelsHidden()
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Button {
                    duplicateCurrentProfile()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    resetToDefaults()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if profileManager.profiles.count > 1 {
                    Button(role: .destructive) {
                        deleteCurrentProfile()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Menu Type Selector

    private var menuTypeSelectorSection: some View {
        Picker("Menu", selection: $selectedMenuType) {
            ForEach(MenuType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(12)
        .onChange(of: selectedMenuType) { _ in
            selectedDirection = nil // Clear selection when switching menus
        }
    }

    // MARK: - Menu Preview Section

    private var menuPreviewSection: some View {
        VStack {
            Text(currentMenu.name)
                .font(.headline)
                .padding(.top, 8)

            ZStack {
                // Draw 8 segments in a circle
                ForEach(CompassDirection.allCases, id: \.self) { direction in
                    let isSelected = selectedDirection == direction
                    let hasAction = currentMenu.hasAction(for: direction)

                    RadialSegmentShape(direction: direction)
                        .fill(isSelected ? SwiftUI.Color.blue.opacity(0.3) :
                              hasAction ? SwiftUI.Color.gray.opacity(0.2) :
                              SwiftUI.Color.clear)
                        .overlay(
                            RadialSegmentShape(direction: direction)
                                .stroke(SwiftUI.Color.gray.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            segmentLabel(for: direction)
                        )
                        .onTapGesture {
                            selectedDirection = direction
                        }
                }

                // Center circle
                Circle()
                    .fill(SwiftUI.Color(NSColor.controlBackgroundColor))
                    .frame(width: 60, height: 60)

                // Direction labels
                Text(selectedMenuType.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(height: 250)
            .padding()
        }
    }

    private func segmentLabel(for direction: CompassDirection) -> some View {
        let action = currentMenu.action(for: direction)
        let angle = direction.angle
        let radius: CGFloat = 75

        return VStack(spacing: 2) {
            if let action = action {
                Image(systemName: iconForAction(action))
                    .font(.system(size: 14))
                Text(direction.rawValue)
                    .font(.system(size: 10, weight: .medium))
            } else {
                Text(direction.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .offset(x: cos(angle * .pi / 180) * radius,
                y: sin(angle * .pi / 180) * radius)
    }

    // MARK: - Segment List Section

    private var segmentListSection: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(CompassDirection.allCases, id: \.self) { direction in
                    segmentRow(for: direction)
                }
            }
            .padding(8)
        }
    }

    private func segmentRow(for direction: CompassDirection) -> some View {
        let action = currentMenu.action(for: direction)
        let isSelected = selectedDirection == direction

        return Button {
            selectedDirection = direction
        } label: {
            HStack(spacing: 8) {
                Text(direction.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30)

                if let action = action {
                    Image(systemName: iconForAction(action))
                        .font(.system(size: 12))
                        .foregroundColor(.blue)

                    Text(action.displayString)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Empty")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? SwiftUI.Color.blue.opacity(0.1) : SwiftUI.Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())  // Makes entire button area clickable
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.point.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a segment to configure")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Click on a direction in the preview or list")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Functions

    private func iconForAction(_ action: ButtonAction) -> String {
        switch action {
        case .keyCommand: return "keyboard"
        case .textMacro: return "text.quote"
        case .applicationCommand: return "app.badge"
        case .systemCommand: return "gearshape"
        case .sequence: return "list.bullet"
        case .shellCommand: return "terminal"
        }
    }

    private func saveSegmentChanges() {
        if let edited = editingProfile {
            profileManager.updateProfile(edited)
            editingProfile = nil
            alertMessage = "Segment saved successfully"
            showAlert = true
        }
    }

    private func duplicateCurrentProfile() {
        let current = profileManager.activeProfile
        let duplicate = RadialMenuProfile(
            id: UUID(),
            name: "\(current.name) Copy",
            l1Menu: current.l1Menu,
            r1Menu: current.r1Menu
        )
        profileManager.addProfile(duplicate)
        profileManager.selectProfile(duplicate)
        alertMessage = "Profile duplicated"
        showAlert = true
    }

    private func deleteCurrentProfile() {
        let current = profileManager.activeProfile
        profileManager.deleteProfile(current)
        alertMessage = "Profile deleted"
        showAlert = true
    }

    private func resetToDefaults() {
        profileManager.resetToDefaults()
        editingProfile = nil
        selectedDirection = nil
        alertMessage = "Reset to default profiles"
        showAlert = true
    }
}

// MARK: - Radial Segment Shape

struct RadialSegmentShape: Shape {
    let direction: CompassDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.3

        let angle = direction.angle
        let startAngle = Angle(degrees: angle - 22.5 - 90) // -90 to rotate so North is up
        let endAngle = Angle(degrees: angle + 22.5 - 90)

        // Outer arc
        path.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: endAngle, clockwise: false)

        // Inner arc (reversed)
        path.addArc(center: center, radius: innerRadius,
                   startAngle: endAngle, endAngle: startAngle, clockwise: true)

        path.closeSubpath()

        return path
    }
}

// MARK: - Segment Editor View

struct SegmentEditorView: View {
    @Binding var profile: RadialMenuProfile
    let menuType: RadialMenuConfigurationView.MenuType
    let direction: CompassDirection
    let onSave: () -> Void

    @State private var selectedActionType: ActionType = .textMacro
    @State private var keyCommand = KeyCommand(key: "", modifiers: [])
    @State private var textMacro = ""
    @State private var autoEnter = true
    @State private var selectedAppCommand: AppCommand = .showUsage
    @State private var shellCommand = ""
    @State private var customLabel: String = ""

    enum ActionType: String, CaseIterable {
        case keyCommand = "Key Press"
        case textMacro = "Text Macro"
        case applicationCommand = "App Command"
        case shellCommand = "Shell Command"
    }

    var currentSegments: [CompassDirection: ButtonAction] {
        menuType == .l1 ? profile.l1Menu.segments : profile.r1Menu.segments
    }

    var currentAction: ButtonAction? {
        currentSegments[direction]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configure \(direction.rawValue) Segment")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(menuType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
                .id("header") // Stable ID for layout

                Divider()

                // Action type selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Type")
                        .font(.headline)

                    Picker("Action Type", selection: $selectedActionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .id("actionTypeSelector") // Stable ID for layout

                Divider()

                // Action configuration based on type
                Group {
                    switch selectedActionType {
                    case .keyCommand:
                        keyCommandEditor
                    case .textMacro:
                        textMacroEditor
                    case .applicationCommand:
                        appCommandEditor
                    case .shellCommand:
                        shellCommandEditor
                    }
                }
                .padding(.horizontal)
                .frame(minHeight: 100) // Prevent collapse

                Divider()

                // Custom label
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Label (Optional)")
                        .font(.headline)
                    TextField("Leave empty for default", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                Divider()

                // Action buttons
                HStack {
                    Button("Clear Segment") {
                        clearSegment()
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentAction == nil)

                    Spacer()

                    Button("Save") {
                        saveSegment()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(minWidth: 400)
        .onAppear {
            loadCurrentAction()
        }
        .onChange(of: direction) { _ in
            loadCurrentAction()
        }
    }

    // MARK: - Action Editors

    private var keyCommandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Command")
                .font(.headline)

            KeyCommandCapture(keyCommand: $keyCommand)
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SwiftUI.Color.gray.opacity(0.3), lineWidth: 1)
                )

            if !keyCommand.key.isEmpty {
                Text("Current: \(keyCommand.displayString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var textMacroEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Macro")
                .font(.headline)

            TextField("Enter text or command", text: $textMacro, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Toggle("Auto-send Enter key", isOn: $autoEnter)

            Text("This text will be typed into the terminal when selected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var appCommandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Command")
                .font(.headline)

            Picker("Command", selection: $selectedAppCommand) {
                ForEach(AppCommand.allCases, id: \.self) { (command: AppCommand) in
                    Text(command.displayString).tag(command)
                }
            }

            Text(selectedAppCommand.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shellCommandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Command")
                .font(.headline)

            TextField("Enter shell command", text: $shellCommand, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Text("This command will be executed in the shell when selected")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("⚠️ Be careful with shell commands - they execute with full permissions")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    // MARK: - Actions

    private func loadCurrentAction() {
        guard let action = currentAction else {
            // Empty segment - set defaults
            selectedActionType = .textMacro
            textMacro = ""
            autoEnter = true
            customLabel = ""
            return
        }

        switch action {
        case .keyCommand(let cmd):
            selectedActionType = .keyCommand
            keyCommand = cmd
        case .textMacro(let text, let enter):
            selectedActionType = .textMacro
            textMacro = text
            autoEnter = enter
        case .applicationCommand(let cmd):
            selectedActionType = .applicationCommand
            selectedAppCommand = cmd
        case .shellCommand(let command):
            selectedActionType = .shellCommand
            shellCommand = command
        case .systemCommand, .sequence:
            // Not supported in radial menu editor yet
            // Default to text macro
            selectedActionType = .textMacro
            textMacro = ""
            autoEnter = true
        }
    }

    private func saveSegment() {
        let action: ButtonAction

        switch selectedActionType {
        case .keyCommand:
            guard !keyCommand.key.isEmpty else { return }
            action = .keyCommand(keyCommand)
        case .textMacro:
            guard !textMacro.isEmpty else { return }
            action = .textMacro(text: textMacro, autoEnter: autoEnter)
        case .applicationCommand:
            action = .applicationCommand(selectedAppCommand)
        case .shellCommand:
            guard !shellCommand.isEmpty else { return }
            action = .shellCommand(shellCommand)
        }

        // Update the profile
        var updatedSegments = currentSegments
        updatedSegments[direction] = action

        if menuType == .l1 {
            profile.l1Menu = RadialMenuConfiguration(
                name: profile.l1Menu.name,
                segments: updatedSegments
            )
        } else {
            profile.r1Menu = RadialMenuConfiguration(
                name: profile.r1Menu.name,
                segments: updatedSegments
            )
        }

        onSave()
    }

    private func clearSegment() {
        var updatedSegments = currentSegments
        updatedSegments.removeValue(forKey: direction)

        if menuType == .l1 {
            profile.l1Menu = RadialMenuConfiguration(
                name: profile.l1Menu.name,
                segments: updatedSegments
            )
        } else {
            profile.r1Menu = RadialMenuConfiguration(
                name: profile.r1Menu.name,
                segments: updatedSegments
            )
        }

        onSave()
    }
}

// MARK: - Key Command Capture

struct KeyCommandCapture: NSViewRepresentable {
    @Binding var keyCommand: KeyCommand

    func makeNSView(context: Context) -> RadialMenuKeyCaptureView {
        let view = RadialMenuKeyCaptureView()
        view.onKeyCapture = { key, modifiers in
            keyCommand = KeyCommand(key: key, modifiers: modifiers)
        }
        return view
    }

    func updateNSView(_ nsView: RadialMenuKeyCaptureView, context: Context) {}
}

class RadialMenuKeyCaptureView: NSView {
    var onKeyCapture: ((String, KeyModifiers) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }

        var modifiers = KeyModifiers()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }

        onKeyCapture?(characters, modifiers)

        // Important: Don't call super.keyDown to prevent key propagation
        // This prevents Tab and other keys from affecting the UI
    }

    // Prevent Tab and other key equivalents from being processed by the responder chain
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // If we have focus, capture all key events
        if window?.firstResponder == self {
            keyDown(with: event)
            return true // We handled it
        }
        return super.performKeyEquivalent(with: event)
    }

    // Prevent interpretation of key events (like Tab for navigation)
    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        // Don't call super - we handle all keys ourselves
        for event in eventArray {
            keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let string = "Click here and press a key combination"
        let size = string.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        string.draw(at: point, withAttributes: attrs)
    }
}

// MARK: - Import/Export View

struct ImportExportView: View {
    @ObservedObject var profileManager: RadialMenuProfileManager
    @Environment(\.dismiss) var dismiss
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Import/Export Profiles")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            VStack(spacing: 16) {
                Button {
                    exportProfiles()
                } label: {
                    Label("Export All Profiles", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    importProfiles()
                } label: {
                    Label("Import Profiles", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()

            Divider()

            Text("Export saves all profiles to a JSON file.\nImport replaces all profiles with the imported file.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .alert("Import/Export", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func exportProfiles() {
        guard let jsonString = profileManager.exportAllProfiles() else {
            alertMessage = "Failed to export profiles"
            showAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "radial-menu-profiles.json"

        // Keep panel alive and ensure UI updates on main thread
        panel.begin { [weak panel] response in
            guard let strongPanel = panel else { return }

            DispatchQueue.main.async {
                if response == .OK, let url = strongPanel.url {
                    do {
                        try jsonString.write(to: url, atomically: true, encoding: .utf8)
                        alertMessage = "Profiles exported successfully"
                        showAlert = true
                    } catch {
                        alertMessage = "Failed to save file: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            }
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        // Keep panel alive and ensure UI updates on main thread
        panel.begin { [weak panel] response in
            guard let strongPanel = panel else { return }

            DispatchQueue.main.async {
                if response == .OK, let url = strongPanel.urls.first {
                    do {
                        let jsonString = try String(contentsOf: url, encoding: .utf8)
                        if profileManager.importProfiles(from: jsonString) {
                            alertMessage = "Profiles imported successfully"
                            showAlert = true
                        } else {
                            alertMessage = "Failed to parse profile data"
                            showAlert = true
                        }
                    } catch {
                        alertMessage = "Failed to read file: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            }
        }
    }
}

// MARK: - New Profile View

struct NewProfileView: View {
    @ObservedObject var profileManager: RadialMenuProfileManager
    @Environment(\.dismiss) var dismiss
    @State private var profileName: String = ""
    @State private var baseProfile: RadialMenuProfile?

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Profile")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Profile Name")
                    .font(.headline)
                TextField("Enter profile name", text: $profileName)
                    .textFieldStyle(.roundedBorder)

                Text("Base Profile")
                    .font(.headline)
                Picker("Base Profile", selection: $baseProfile) {
                    Text("Empty").tag(nil as RadialMenuProfile?)
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile as RadialMenuProfile?)
                    }
                }
            }
            .padding()

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear {
            baseProfile = profileManager.activeProfile
        }
    }

    private func createProfile() {
        let l1Menu: RadialMenuConfiguration
        let r1Menu: RadialMenuConfiguration

        if let base = baseProfile {
            l1Menu = base.l1Menu
            r1Menu = base.r1Menu
        } else {
            l1Menu = RadialMenuConfiguration(name: "L1 Menu", segments: [:])
            r1Menu = RadialMenuConfiguration(name: "R1 Menu", segments: [:])
        }

        let newProfile = RadialMenuProfile(
            id: UUID(),
            name: profileName,
            l1Menu: l1Menu,
            r1Menu: r1Menu
        )

        profileManager.addProfile(newProfile)
        profileManager.selectProfile(newProfile)
        dismiss()
    }
}

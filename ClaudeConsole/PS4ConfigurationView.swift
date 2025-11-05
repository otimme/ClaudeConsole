//
//  PS4ConfigurationView.swift
//  ClaudeConsole
//
//  Configuration panel for mapping PS4 buttons to keyboard commands
//

import SwiftUI
import AppKit

struct PS4ConfigurationView: View {
    @ObservedObject var mapping: PS4ButtonMapping
    @Environment(\.dismiss) var dismiss
    @State private var editingButton: PS4Button?
    @State private var capturedKey: String = ""
    @State private var capturedModifiers: KeyModifiers = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PS4 Controller Button Mappings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Reset to Defaults") {
                    mapping.resetToDefaults()
                }
                .buttonStyle(.link)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Button mapping list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(PS4Button.allCases, id: \.self) { button in
                        ButtonMappingRow(
                            button: button,
                            mapping: mapping,
                            isEditing: editingButton == button,
                            onEdit: {
                                editingButton = button
                                capturedKey = ""
                                capturedModifiers = []
                            },
                            onSave: { key, modifiers in
                                let command = KeyCommand(key: key, modifiers: modifiers)
                                mapping.setMapping(for: button, action: .keyCommand(command))
                                editingButton = nil
                            },
                            onCancel: {
                                editingButton = nil
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Instructions
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Click 'Edit' next to any button to change its mapping. Press the key combination you want to assign.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

struct ButtonMappingRow: View {
    let button: PS4Button
    @ObservedObject var mapping: PS4ButtonMapping
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: (String, KeyModifiers) -> Void
    let onCancel: () -> Void

    @State private var capturedKey: String = ""
    @State private var capturedModifiers: KeyModifiers = []
    @State private var isCapturing = false

    var body: some View {
        HStack(spacing: 12) {
            // Button icon/name
            HStack(spacing: 8) {
                ButtonIcon(button: button)
                Text(button.displayName)
                    .font(.system(size: 13))
                    .frame(width: 150, alignment: .leading)
            }

            Spacer()

            // Current mapping or capture field
            if isEditing {
                KeyCaptureField(
                    capturedKey: $capturedKey,
                    capturedModifiers: $capturedModifiers,
                    isCapturing: $isCapturing
                )
                .frame(width: 150)

                Button("Save") {
                    if !capturedKey.isEmpty {
                        onSave(capturedKey, capturedModifiers)
                    }
                }
                .disabled(capturedKey.isEmpty)

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.link)
            } else {
                // Show current mapping
                if let command = mapping.getCommand(for: button) {
                    Text(command.displayString)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 150)
                } else {
                    Text("Not mapped")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 150)
                }

                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isEditing ? Color.blue.opacity(0.1) : Color.clear
        )
    }
}

struct ButtonIcon: View {
    let button: PS4Button

    var body: some View {
        ZStack {
            switch button {
            case .cross, .circle, .square, .triangle:
                Circle()
                    .fill(buttonColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(button.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            case .l1, .r1, .l2, .r2:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.5))
                    .frame(width: 25, height: 16)
                    .overlay(
                        Text(button.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    )
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 20, height: 20)
                    .cornerRadius(2)
                    .overlay(
                        Text(button.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            default:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 30, height: 16)
                    .overlay(
                        Text(button.rawValue)
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    )
            }
        }
    }

    var buttonColor: Color {
        switch button {
        case .cross: return .blue
        case .circle: return .red
        case .square: return .pink
        case .triangle: return .green
        default: return .gray
        }
    }
}

struct KeyCaptureField: View {
    @Binding var capturedKey: String
    @Binding var capturedModifiers: KeyModifiers
    @Binding var isCapturing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isCapturing ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCapturing ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )

            if capturedKey.isEmpty {
                Text(isCapturing ? "Press any key..." : "Click to capture")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text(displayString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            isCapturing = true
            capturedKey = ""
            capturedModifiers = []
        }
        .focusable()
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Window became key, ready to capture
        }
        .background(KeyEventHandler(
            isCapturing: $isCapturing,
            onKeyPress: { key, modifiers in
                if isCapturing {
                    capturedKey = key
                    capturedModifiers = modifiers
                    isCapturing = false
                }
            }
        ))
    }

    var displayString: String {
        var result = ""
        if capturedModifiers.contains(.control) { result += "⌃" }
        if capturedModifiers.contains(.option) { result += "⌥" }
        if capturedModifiers.contains(.shift) { result += "⇧" }
        if capturedModifiers.contains(.command) { result += "⌘" }
        result += capturedKey
        return result
    }
}

// NSViewRepresentable to handle key events
struct KeyEventHandler: NSViewRepresentable {
    @Binding var isCapturing: Bool
    let onKeyPress: (String, KeyModifiers) -> Void

    func makeNSView(context: Context) -> PS4KeyCaptureView {
        let view = PS4KeyCaptureView()
        view.onKeyPress = onKeyPress
        view.isCapturing = isCapturing
        return view
    }

    func updateNSView(_ nsView: PS4KeyCaptureView, context: Context) {
        nsView.isCapturing = isCapturing
        if isCapturing {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

class PS4KeyCaptureView: NSView {
    var onKeyPress: ((String, KeyModifiers) -> Void)?
    var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        var modifiers = KeyModifiers(rawValue: 0)
        if event.modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if event.modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if event.modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if event.modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }

        // Get the key
        let key: String
        if let specialKey = specialKeyFromCode(event.keyCode) {
            key = specialKey
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            key = chars.uppercased()
        } else {
            return
        }

        onKeyPress?(key, modifiers)
    }

    private func specialKeyFromCode(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return KeyCommand.SpecialKey.enter.rawValue
        case 49: return KeyCommand.SpecialKey.space.rawValue
        case 53: return KeyCommand.SpecialKey.escape.rawValue
        case 48: return KeyCommand.SpecialKey.tab.rawValue
        case 51: return KeyCommand.SpecialKey.delete.rawValue
        case 117: return KeyCommand.SpecialKey.forwardDelete.rawValue
        case 126: return KeyCommand.SpecialKey.upArrow.rawValue
        case 125: return KeyCommand.SpecialKey.downArrow.rawValue
        case 123: return KeyCommand.SpecialKey.leftArrow.rawValue
        case 124: return KeyCommand.SpecialKey.rightArrow.rawValue
        case 115: return KeyCommand.SpecialKey.home.rawValue
        case 119: return KeyCommand.SpecialKey.end.rawValue
        case 116: return KeyCommand.SpecialKey.pageUp.rawValue
        case 121: return KeyCommand.SpecialKey.pageDown.rawValue
        case 122: return KeyCommand.SpecialKey.f1.rawValue
        case 120: return KeyCommand.SpecialKey.f2.rawValue
        case 99: return KeyCommand.SpecialKey.f3.rawValue
        case 118: return KeyCommand.SpecialKey.f4.rawValue
        case 96: return KeyCommand.SpecialKey.f5.rawValue
        case 97: return KeyCommand.SpecialKey.f6.rawValue
        case 98: return KeyCommand.SpecialKey.f7.rawValue
        case 100: return KeyCommand.SpecialKey.f8.rawValue
        case 101: return KeyCommand.SpecialKey.f9.rawValue
        case 109: return KeyCommand.SpecialKey.f10.rawValue
        case 103: return KeyCommand.SpecialKey.f11.rawValue
        case 111: return KeyCommand.SpecialKey.f12.rawValue
        default: return nil
        }
    }
}
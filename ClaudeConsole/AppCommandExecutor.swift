//
//  AppCommandExecutor.swift
//  ClaudeConsole
//
//  Central coordinator for executing application commands from PS4 controller
//
//  CRITICAL FIX: Provides direct access to app features without using NotificationCenter
//  Previous implementation violated this design principle by using NotificationCenter for
//  clipboard, terminal, and Claude commands. Now uses direct terminal controller access.
//
//  This eliminates hidden coupling, makes code testable, and provides single source of truth
//  for command execution logic.
//

import Foundation
import AppKit
import SwiftTerm
import UserNotifications
import os.log

class AppCommandExecutor: ObservableObject {
    // FIX: Added weak terminal controller reference for direct command execution
    // Weak references to avoid retain cycles
    weak var speechCoordinator: SpeechToTextCoordinator?
    weak var terminalController: LocalProcessTerminalView?  // Direct terminal access
    weak var contextMonitor: ContextMonitor?  // For context stats refresh

    // Published state for UI bindings
    @Published var showPS4Panel: Bool = false
    @Published var showPS4StatusBar: Bool = false

    init() {}

    /// Execute an application command
    func execute(_ command: AppCommand) {
        os_log("Executing app command: %{public}@", log: .default, type: .info, command.rawValue)

        switch command {
        case .triggerSpeechToText:
            toggleSpeechToText()

        case .stopSpeechToText:
            stopSpeechToText()

        case .pushToTalkSpeech:
            // Push-to-talk is handled by the controller via button press/release
            // This case should not be called directly
            os_log("pushToTalkSpeech called directly - should only be triggered via button press/release", log: .default, type: .error)

        case .togglePS4Panel:
            togglePS4Panel()

        case .toggleStatusBar:
            toggleStatusBar()

        case .copyToClipboard:
            copyToClipboard()

        case .pasteFromClipboard:
            pasteFromClipboard()

        case .clearTerminal:
            clearTerminal()

        case .showUsage:
            showUsage()

        case .showContext:
            showContext()

        case .refreshStats:
            refreshStats()
        }
    }

    // MARK: - Speech-to-Text Commands

    /// Toggle speech-to-text recording (start if stopped, stop if recording)
    private func toggleSpeechToText() {
        guard let speech = speechCoordinator else {
            os_log("SpeechToTextCoordinator not available", log: .default, type: .error)
            showNotification(title: "Speech-to-Text Error", body: "Speech coordinator not available")
            return
        }

        speech.toggleRecordingViaController()
    }

    /// Stop speech-to-text recording (for push-to-talk release or explicit stop)
    private func stopSpeechToText() {
        guard let speech = speechCoordinator else {
            os_log("SpeechToTextCoordinator not available", log: .default, type: .error)
            return
        }

        speech.stopRecordingViaController()
    }

    // MARK: - UI Panel Commands

    private func togglePS4Panel() {
        showPS4Panel.toggle()
        os_log("PS4 panel toggled: %{public}@", log: .default, type: .info, showPS4Panel ? "shown" : "hidden")
    }

    private func toggleStatusBar() {
        showPS4StatusBar.toggle()
        os_log("PS4 status bar toggled: %{public}@", log: .default, type: .info, showPS4StatusBar ? "shown" : "hidden")
    }

    // MARK: - Clipboard Commands
    // FIX: Replaced NotificationCenter with direct terminal access

    private func copyToClipboard() {
        guard let terminal = terminalController else {
            os_log("Terminal controller not available for copy command", log: .default, type: .error)
            return
        }

        // FIX: Direct terminal access instead of NotificationCenter.post()
        // Send Cmd+C to terminal via KeyCommand
        if let data = KeyCommand(key: "c", modifiers: .command).toTerminalData() {
            terminal.send(data: ArraySlice(data))
        }
        os_log("Copy to clipboard triggered", log: .default, type: .info)
    }

    private func pasteFromClipboard() {
        guard let terminal = terminalController else {
            os_log("Terminal controller not available for paste command", log: .default, type: .error)
            return
        }

        // Send Cmd+V to terminal
        if let data = KeyCommand(key: "v", modifiers: .command).toTerminalData() {
            terminal.send(data: ArraySlice(data))
        }
        os_log("Paste from clipboard triggered", log: .default, type: .info)
    }

    // MARK: - Terminal Commands

    private func clearTerminal() {
        guard let terminal = terminalController else {
            os_log("Terminal controller not available for clear command", log: .default, type: .error)
            return
        }

        // Send Ctrl+L to clear terminal
        if let data = KeyCommand(key: "l", modifiers: .control).toTerminalData() {
            terminal.send(data: ArraySlice(data))
        }
        os_log("Clear terminal triggered", log: .default, type: .info)
    }

    // MARK: - Claude Commands

    private func showUsage() {
        guard let terminal = terminalController else {
            os_log("Terminal controller not available for usage command", log: .default, type: .error)
            return
        }

        // Send /usage command to terminal as text macro with Enter
        var data = "/usage".data(using: .utf8) ?? Data()
        data.append(Data([0x0D])) // Carriage return
        terminal.send(data: ArraySlice(data))
        os_log("Show usage command sent", log: .default, type: .info)
    }

    private func showContext() {
        // FIX: Call contextMonitor.requestContextUpdate() to update UI stats display
        // This triggers the same functionality as the refresh button in ContextStatsView
        guard let context = contextMonitor else {
            os_log("ContextMonitor not available for context command", log: .default, type: .error)
            return
        }

        context.requestContextUpdate()
        os_log("Context stats update requested", log: .default, type: .info)
    }

    private func refreshStats() {
        // Post notification to refresh stats monitors
        // NOTE: This is one of the few cases where NotificationCenter is appropriate
        // because we're coordinating between multiple independent monitoring components
        NotificationCenter.default.post(name: Notification.Name("PS4RefreshStats"), object: nil)
        os_log("Refresh stats triggered", log: .default, type: .info)
    }

    // MARK: - Notification Helper

    private func showNotification(title: String, body: String, sound: UNNotificationSound = .default) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted, error == nil else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = sound

            let request = UNNotificationRequest(
                identifier: "app-command-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request, withCompletionHandler: nil)
        }
    }
}

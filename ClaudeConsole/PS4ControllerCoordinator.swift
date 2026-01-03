//
//  PS4ControllerCoordinator.swift
//  ClaudeConsole
//
//  Per-window PS4 controller coordinator that receives routed button events
//  from SharedResourceManager. Uses the shared PS4ControllerMonitor for state
//  observation while maintaining per-window button mapping and radial menu state.
//

import Foundation
import SwiftTerm
import Combine
import AppKit
import os.log

/// Per-window coordinator for PS4/PS5 controller functionality
/// Receives button events routed from SharedResourceManager and executes
/// actions on this window's terminal
@MainActor
final class PS4ControllerCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "PS4ControllerCoordinator")

    // MARK: - Window Identity

    let windowID: UUID

    // MARK: - Terminal Reference

    /// Terminal controller for this window (set by WindowContext)
    weak var terminalController: LocalProcessTerminalView?

    // MARK: - Per-Window Components

    /// Button mapping (per-window, can be customized per project)
    let mapping = PS4ButtonMapping()

    /// Radial menu controller (per-window state)
    let radialMenuController = RadialMenuController()

    /// Profile switcher controller (per-window state)
    let profileSwitcherController: ProfileSwitcherController

    /// App command executor (per-window, operates on this window's terminal)
    let appCommandExecutor = AppCommandExecutor()

    // MARK: - Published State

    @Published var isEnabled = true

    // MARK: - Shared Monitor Reference (read-only observation)

    /// Reference to shared PS4 monitor for state observation
    var sharedMonitor: PS4ControllerMonitor { SharedResourceManager.shared.ps4Monitor }

    // MARK: - Push-to-Talk State

    private enum PushToTalkState {
        case idle
        case recording(button: PS4Button, startedAt: Date)
        case transcribing
    }
    private var pushToTalkState: PushToTalkState = .idle

    // MARK: - Button Repeat State

    private var repeatTimers: [PS4Button: DispatchSourceTimer] = [:]
    private let repeatQueue = DispatchQueue(label: "com.claudeconsole.buttonrepeat", qos: .userInteractive)

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Speech Coordinator Reference

    weak var speechCoordinator: SpeechToTextCoordinator?

    // MARK: - Initialization

    init(windowID: UUID) {
        self.windowID = windowID
        self.profileSwitcherController = ProfileSwitcherController(profileManager: radialMenuController.profileManager)

        setupRadialMenuCallback()
        setupStateForwarding()
        setupAnalogStickObservers()

        Self.logger.info("PS4ControllerCoordinator created for window: \(windowID)")
    }

    private func setupRadialMenuCallback() {
        radialMenuController.onActionSelected = { [weak self] action in
            self?.executeButtonAction(action)
        }
    }

    // MARK: - State Forwarding

    private func setupStateForwarding() {
        // Forward radialMenuController's objectWillChange
        radialMenuController.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward profileSwitcherController's objectWillChange
        profileSwitcherController.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward mapping's objectWillChange
        mapping.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Handle controller disconnection
        sharedMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                if !isConnected {
                    self?.handleControllerDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    private func setupAnalogStickObservers() {
        // Monitor right analog stick input for radial menu (when this window is focused)
        sharedMonitor.$rightStickX
            .combineLatest(sharedMonitor.$rightStickY)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] x, y in
                guard let self = self,
                      SharedResourceManager.shared.focusedWindowID == self.windowID,
                      self.radialMenuController.isVisible else { return }
                self.radialMenuController.handleAnalogStickInput(x: x, y: y)
            }
            .store(in: &cancellables)

        // Monitor left analog stick input for profile switcher (when this window is focused)
        sharedMonitor.$leftStickX
            .combineLatest(sharedMonitor.$leftStickY)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] x, y in
                guard let self = self,
                      SharedResourceManager.shared.focusedWindowID == self.windowID,
                      self.profileSwitcherController.isVisible else { return }
                self.profileSwitcherController.handleAnalogStickInput(x: x, y: y)
            }
            .store(in: &cancellables)
    }

    // MARK: - Button Event Handling (called by WindowContext)

    /// Handle button press - called when this window receives a routed button event
    func handleButtonPressed(_ button: PS4Button) {
        guard isEnabled else { return }

        // Block normal button actions if profile switcher is visible
        guard !profileSwitcherController.isVisible else {
            return
        }

        // Block normal button actions if radial menu is visible
        guard !radialMenuController.isVisible else {
            if button == .circle {
                radialMenuController.cancelMenu()
            }
            return
        }

        // Check for touchpad button press for profile switcher
        if button == .touchpad {
            profileSwitcherController.handleTouchpadPress()
            return
        }

        // Check for L1/R1 hold for radial menu
        if button == .l1 || button == .r1 {
            radialMenuController.handleButtonPress(button)
        }

        // Get the mapped action for this button
        if let action = mapping.getAction(for: button) {
            // Check if this is a push-to-talk action
            if case .applicationCommand(.pushToTalkSpeech) = action {
                handlePushToTalkPress(button: button)
            } else if button != .l1 && button != .r1 {
                executeButtonAction(action)

                if mapping.isRepeatEnabled(for: button) {
                    startRepeatTimer(for: button, action: action)
                }
            }
        }
    }

    /// Handle button release - called when this window receives a routed button event
    func handleButtonReleased(_ button: PS4Button) {
        guard isEnabled else { return }

        stopRepeatTimer(for: button)

        if button == .touchpad {
            profileSwitcherController.handleTouchpadRelease()
            return
        }

        if button == .l1 || button == .r1 {
            radialMenuController.handleButtonRelease(button)
            return
        }

        handlePushToTalkRelease(button: button)
    }

    // MARK: - Push-to-Talk

    private func handlePushToTalkPress(button: PS4Button) {
        guard case .idle = pushToTalkState else {
            Self.logger.info("Cannot start push-to-talk: already in state \(String(describing: self.pushToTalkState))")
            return
        }

        pushToTalkState = .recording(button: button, startedAt: Date())
        speechCoordinator?.startRecordingViaController()

        Self.logger.debug("Push-to-talk started via button: \(button.rawValue)")
    }

    private func handlePushToTalkRelease(button: PS4Button) {
        guard case .recording(let recordingButton, _) = pushToTalkState,
              recordingButton == button else {
            return
        }

        pushToTalkState = .transcribing
        speechCoordinator?.stopRecordingViaController()

        // Reset to idle after a short delay to allow transcription to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if case .transcribing = self?.pushToTalkState {
                self?.pushToTalkState = .idle
            }
        }

        Self.logger.debug("Push-to-talk stopped via button: \(button.rawValue)")
    }

    private func handleControllerDisconnected() {
        // Cancel any ongoing push-to-talk
        if case .recording = pushToTalkState {
            speechCoordinator?.stopRecordingViaController()
        }
        pushToTalkState = .idle

        // Cancel all repeat timers
        for button in repeatTimers.keys {
            stopRepeatTimer(for: button)
        }

        Self.logger.info("Controller disconnected, cleaned up state")
    }

    // MARK: - Button Action Execution

    func executeButtonAction(_ action: ButtonAction) {
        switch action {
        case .keyCommand(let command):
            executeKeyCommand(command)
        case .textMacro(let text, let autoEnter):
            executeTextMacro(text, autoEnter: autoEnter)
        case .applicationCommand(let appCommand):
            appCommandExecutor.execute(appCommand)
        case .shellCommand(let command):
            executeShellCommand(command)
        case .systemCommand(let command):
            executeSystemCommand(command)
        case .sequence(let actions):
            executeSequence(actions)
        }
    }

    private func executeKeyCommand(_ command: KeyCommand) {
        guard let terminal = terminalController else { return }

        // Convert command to terminal data
        if let data = command.toTerminalData() {
            terminal.send(data: ArraySlice(data))
        }
    }

    private func executeTextMacro(_ text: String, autoEnter: Bool) {
        guard let terminal = terminalController else { return }

        let textToSend = autoEnter ? text + "\r" : text
        if let data = textToSend.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }
    }

    private func executeShellCommand(_ command: String) {
        guard let terminal = terminalController else { return }

        let fullCommand = command + "\r"
        if let data = fullCommand.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }
    }

    private func executeSystemCommand(_ command: SystemCommand) {
        switch command {
        case .switchApplication(let bundleId):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }

        case .openURL(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case .runAppleScript(let script):
            Task.detached {
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }

        case .takeScreenshot:
            // Trigger system screenshot
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-i"]
            try? task.run()

        case .toggleFullscreen:
            DispatchQueue.main.async {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }

        case .minimizeWindow:
            DispatchQueue.main.async {
                NSApp.keyWindow?.miniaturize(nil)
            }
        }
    }

    private func executeSequence(_ actions: [ButtonAction]) {
        // Execute each action in sequence with small delays
        for (index, action) in actions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) { [weak self] in
                self?.executeButtonAction(action)
            }
        }
    }

    // MARK: - Button Repeat

    private func startRepeatTimer(for button: PS4Button, action: ButtonAction) {
        stopRepeatTimer(for: button)

        let timer = DispatchSource.makeTimerSource(queue: repeatQueue)
        timer.schedule(deadline: .now() + 0.4, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.executeButtonAction(action)
            }
        }
        timer.resume()
        repeatTimers[button] = timer
    }

    private func stopRepeatTimer(for button: PS4Button) {
        if let timer = repeatTimers[button] {
            timer.cancel()
            repeatTimers.removeValue(forKey: button)
        }
    }

    deinit {
        // Cancel all repeat timers
        for timer in repeatTimers.values {
            timer.cancel()
        }
        repeatTimers.removeAll()
    }
}

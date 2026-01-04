//
//  WindowContext.swift
//  ClaudeConsole
//
//  Per-window context providing identity, terminal reference, and input event handling.
//  Each window creates its own WindowContext which registers with SharedResourceManager.
//

import Foundation
import SwiftUI
import SwiftTerm
import Combine
import os.log

/// Per-window context that coordinates hardware input routing and component wiring
@MainActor
final class WindowContext: ObservableObject, WindowCoordinatorProtocol {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "WindowContext")

    // MARK: - Window Identity

    /// Unique identifier for this window
    let windowID: UUID

    // MARK: - Focus State

    /// Whether this window currently has focus (is key window)
    @Published var isFocused: Bool = false

    // MARK: - Project State

    /// The current working directory (project folder) for this window
    @Published var workingDirectory: String?

    /// The project folder name extracted from the working directory
    var projectFolderName: String? {
        guard let path = workingDirectory else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Terminal Controller

    /// Reference to this window's terminal controller
    @Published var terminalController: LocalProcessTerminalView?

    // MARK: - Per-Window Components

    /// Callback when terminal output is received (for ContextMonitor)
    var onTerminalOutput: ((String) -> Void)?

    /// Callback when Claude Code starts (working directory detected)
    var onClaudeStarted: ((String) -> Void)?

    // MARK: - Per-Window Coordinators

    /// PS4/PS5 controller coordinator for this window
    let ps4Coordinator: PS4ControllerCoordinator

    /// Speech-to-text coordinator for this window
    let speechCoordinator: SpeechToTextCoordinator

    // MARK: - Published State (forwarded from coordinators)

    /// Whether recording is in progress
    var isRecording: Bool { speechCoordinator.isRecording }

    /// Whether transcription is in progress
    var isTranscribing: Bool { speechCoordinator.isTranscribing }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var shared: SharedResourceManager { SharedResourceManager.shared }

    // MARK: - Initialization

    init() {
        self.windowID = UUID()

        // Initialize coordinators eagerly with explicit dependency order
        self.speechCoordinator = SpeechToTextCoordinator(windowID: windowID)
        self.ps4Coordinator = PS4ControllerCoordinator(windowID: windowID)
        self.ps4Coordinator.speechCoordinator = self.speechCoordinator

        // Register with SharedResourceManager
        shared.registerWindow(id: windowID, coordinator: self)

        // Set up coordinator wiring
        setupCoordinators()

        Self.logger.info("WindowContext created: \(self.windowID)")
    }

    deinit {
        // Capture window ID for use in async block
        let id = windowID

        // Unregister from SharedResourceManager (dispatch to main thread since we're in deinit)
        Task { @MainActor in
            SharedResourceManager.shared.unregisterWindow(id: id)
        }

        Self.logger.info("WindowContext destroyed: \(id)")
    }

    // MARK: - Focus Management

    /// Call when this window becomes the key window
    func windowBecameKey() {
        shared.setFocusedWindow(id: windowID)
        isFocused = true
    }

    /// Call when this window resigns key window status
    func windowResignedKey() {
        isFocused = false
    }

    // MARK: - Coordinator Setup

    private func setupCoordinators() {
        // Wire terminal controller to coordinators when it's set
        $terminalController
            .receive(on: DispatchQueue.main)
            .sink { [weak self] terminal in
                guard let self = self else { return }
                self.ps4Coordinator.terminalController = terminal
                self.speechCoordinator.terminalController = terminal
            }
            .store(in: &cancellables)

        // Forward coordinator state changes to trigger view updates
        speechCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ps4Coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - WindowCoordinatorProtocol
    // Note: SharedResourceManager already routes events only to the focused window,
    // so focus checks here are redundant. We trust the routing layer.

    func handleSpeechRecordingStarted() {
        Self.logger.debug("Starting speech recording for window: \(self.windowID)")
        speechCoordinator.handleRecordingStarted()
    }

    func handleSpeechRecordingStopped() {
        Self.logger.debug("Stopping speech recording for window: \(self.windowID)")
        speechCoordinator.handleRecordingStopped()
    }

    func handlePS4ButtonPressed(_ button: PS4Button) {
        Self.logger.debug("PS4 button pressed: \(button.rawValue) for window: \(self.windowID)")
        ps4Coordinator.handleButtonPressed(button)
    }

    func handlePS4ButtonReleased(_ button: PS4Button) {
        Self.logger.debug("PS4 button released: \(button.rawValue) for window: \(self.windowID)")
        ps4Coordinator.handleButtonReleased(button)
    }

    func handleLeftStickChanged(x: Float, y: Float) {
        // Analog stick handled by PS4ControllerCoordinator's Combine observers
    }

    func handleRightStickChanged(x: Float, y: Float) {
        // Analog stick handled by PS4ControllerCoordinator's Combine observers
    }

    // MARK: - Terminal Integration

    /// Forward terminal output to observers (called by TerminalView)
    func receiveTerminalOutput(_ text: String) {
        onTerminalOutput?(text)
    }

    /// Forward Claude started event to observers (called by TerminalView)
    func receiveClaudeStarted(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        onClaudeStarted?(workingDirectory)
    }
}


//
//  SharedResourceManager.swift
//  ClaudeConsole
//
//  App-level singleton managing hardware resources that cannot be shared between windows.
//  Routes input events (keyboard, controller) to the focused window.
//

import Foundation
import SwiftUI
import Combine
import os.log

/// Singleton managing app-wide hardware resources and routing input to focused window
final class SharedResourceManager: ObservableObject {
    static let shared = SharedResourceManager()

    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "SharedResourceManager")

    // MARK: - Hardware Resources (single instance each)

    /// Single keyboard monitor for push-to-talk
    let keyboardMonitor: KeyboardMonitor

    /// Single audio recorder (only one recording at a time)
    let audioRecorder: AudioRecorder

    /// Single PS4/PS5 controller monitor
    let ps4Monitor: PS4ControllerMonitor

    /// Single WhisperKit speech recognition manager
    let speechRecognition: SpeechRecognitionManager

    // MARK: - Focus Tracking

    /// Currently focused window's UUID (receives hardware input)
    @Published private(set) var focusedWindowID: UUID?

    // MARK: - Window Registry

    /// Registered window coordinators, keyed by window UUID
    private var windowCoordinators: [UUID: WindowCoordinatorProtocol] = [:]
    private let lock = NSLock()

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        self.keyboardMonitor = KeyboardMonitor()
        self.audioRecorder = AudioRecorder()
        self.ps4Monitor = PS4ControllerMonitor()
        self.speechRecognition = SpeechRecognitionManager()

        setupInputRouting()

        Self.logger.info("SharedResourceManager initialized")
    }

    // MARK: - Window Registration

    /// Register a window coordinator to receive routed input events
    func registerWindow(id: UUID, coordinator: WindowCoordinatorProtocol) {
        lock.lock()
        defer { lock.unlock() }

        windowCoordinators[id] = coordinator

        // If this is the first window, make it focused
        if focusedWindowID == nil {
            DispatchQueue.main.async {
                self.focusedWindowID = id
            }
        }

        Self.logger.info("Registered window: \(id)")
    }

    /// Unregister a window coordinator when window closes
    func unregisterWindow(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        windowCoordinators.removeValue(forKey: id)

        // If this was the focused window, clear focus or pick another
        if focusedWindowID == id {
            DispatchQueue.main.async {
                self.focusedWindowID = self.windowCoordinators.keys.first
            }
        }

        Self.logger.info("Unregistered window: \(id)")
    }

    /// Set the focused window (called when window becomes key)
    func setFocusedWindow(id: UUID) {
        guard windowCoordinators[id] != nil else {
            Self.logger.warning("Attempted to focus unregistered window: \(id)")
            return
        }

        DispatchQueue.main.async {
            if self.focusedWindowID != id {
                self.focusedWindowID = id
                Self.logger.debug("Focused window changed to: \(id)")
            }
        }
    }

    /// Get the coordinator for a specific window
    func coordinator(for windowID: UUID) -> WindowCoordinatorProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return windowCoordinators[windowID]
    }

    /// Get the currently focused coordinator
    var focusedCoordinator: WindowCoordinatorProtocol? {
        lock.lock()
        defer { lock.unlock() }

        guard let focusedID = focusedWindowID else { return nil }
        return windowCoordinators[focusedID]
    }

    // MARK: - Input Routing

    private func setupInputRouting() {
        // Route keyboard push-to-talk events to focused window
        keyboardMonitor.onRecordingStarted = { [weak self] in
            self?.routeToFocusedWindow { coordinator in
                coordinator.handleSpeechRecordingStarted()
            }
        }

        keyboardMonitor.onRecordingStopped = { [weak self] in
            self?.routeToFocusedWindow { coordinator in
                coordinator.handleSpeechRecordingStopped()
            }
        }

        // Route PS4 controller button events to focused window
        ps4Monitor.onButtonPressed = { [weak self] button in
            self?.routeToFocusedWindow { coordinator in
                coordinator.handlePS4ButtonPressed(button)
            }
        }

        ps4Monitor.onButtonReleased = { [weak self] button in
            self?.routeToFocusedWindow { coordinator in
                coordinator.handlePS4ButtonReleased(button)
            }
        }

        // Route analog stick changes to focused window
        Publishers.CombineLatest(ps4Monitor.$leftStickX, ps4Monitor.$leftStickY)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] x, y in
                self?.routeToFocusedWindow { coordinator in
                    coordinator.handleLeftStickChanged(x: x, y: y)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(ps4Monitor.$rightStickX, ps4Monitor.$rightStickY)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] x, y in
                self?.routeToFocusedWindow { coordinator in
                    coordinator.handleRightStickChanged(x: x, y: y)
                }
            }
            .store(in: &cancellables)
    }

    /// Route an action to the currently focused window's coordinator
    private func routeToFocusedWindow(_ action: @escaping (WindowCoordinatorProtocol) -> Void) {
        lock.lock()
        guard let focusedID = focusedWindowID,
              let coordinator = windowCoordinators[focusedID] else {
            lock.unlock()
            Self.logger.debug("No focused window to route input to")
            return
        }
        lock.unlock()

        // Always dispatch to main thread for UI safety
        if Thread.isMainThread {
            action(coordinator)
        } else {
            DispatchQueue.main.async {
                action(coordinator)
            }
        }
    }

    // MARK: - Shared Audio Recording

    /// Start recording audio (returns success status)
    func startRecording() -> Bool {
        guard audioRecorder.hasPermission else {
            Self.logger.warning("Cannot start recording: no microphone permission")
            return false
        }

        audioRecorder.startRecording()
        return audioRecorder.isRecording
    }

    /// Stop recording and return the audio file URL
    func stopRecording() -> URL? {
        return audioRecorder.stopRecording()
    }

    /// Transcribe audio file using WhisperKit
    func transcribe(audioURL: URL) async -> String? {
        return await speechRecognition.transcribe(audioURL: audioURL)
    }

    /// Clean up a recording file
    func cleanupRecording(at url: URL) {
        audioRecorder.cleanupRecording(at: url)
    }

    // MARK: - Debug

    /// Number of registered windows
    var windowCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return windowCoordinators.count
    }
}

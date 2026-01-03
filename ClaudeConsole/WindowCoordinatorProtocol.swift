//
//  WindowCoordinatorProtocol.swift
//  ClaudeConsole
//
//  Protocol for per-window coordination with SharedResourceManager
//  Enables routing of hardware input (keyboard, controller) to the focused window
//

import Foundation
import SwiftTerm

/// Protocol that each window's coordinator implements to receive routed input events
/// from the SharedResourceManager singleton
protocol WindowCoordinatorProtocol: AnyObject {
    /// Unique identifier for this window
    var windowID: UUID { get }

    /// Reference to this window's terminal controller
    var terminalController: LocalProcessTerminalView? { get }

    // MARK: - Speech-to-Text Events

    /// Called when push-to-talk recording should start (Right Command pressed)
    func handleSpeechRecordingStarted()

    /// Called when push-to-talk recording should stop (Right Command released)
    func handleSpeechRecordingStopped()

    // MARK: - PS4 Controller Events

    /// Called when a PS4/PS5 controller button is pressed
    func handlePS4ButtonPressed(_ button: PS4Button)

    /// Called when a PS4/PS5 controller button is released
    func handlePS4ButtonReleased(_ button: PS4Button)

    // MARK: - Analog Stick Events

    /// Called when left analog stick position changes
    func handleLeftStickChanged(x: Float, y: Float)

    /// Called when right analog stick position changes
    func handleRightStickChanged(x: Float, y: Float)
}

/// Default implementations for optional handlers
extension WindowCoordinatorProtocol {
    func handleLeftStickChanged(x: Float, y: Float) {}
    func handleRightStickChanged(x: Float, y: Float) {}
}

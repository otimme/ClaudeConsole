//
//  ProfileSwitcherController.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import Foundation
import Combine

/// Controller for PS4 touchpad-triggered profile switching
class ProfileSwitcherController: ObservableObject {
    // MARK: - Published State

    /// Whether the profile switcher is currently visible
    @Published var isVisible: Bool = false

    /// Currently selected profile index (0-7, nil if in dead zone)
    @Published var selectedProfileIndex: Int? = nil

    /// Current analog stick position (for visual indicator)
    @Published var stickPosition: CGPoint = .zero

    // MARK: - Profile Manager

    let profileManager: RadialMenuProfileManager

    // MARK: - Configuration

    private let deadZoneEntry: Float = 0.2  // Must exceed to select
    private let deadZoneExit: Float = 0.15  // Can go lower without losing selection
    private let selectionDebounce: TimeInterval = 0.05  // 50ms debounce

    // MARK: - Private State

    private var selectionDebounceTimer: Timer? = nil
    private var pendingProfileIndex: Int? = nil
    private var isSwitching: Bool = false

    // MARK: - Initialization

    init(profileManager: RadialMenuProfileManager) {
        self.profileManager = profileManager
    }

    // MARK: - Public Methods

    /// Call when touchpad button is pressed
    func handleTouchpadPress() {
        guard !isVisible else { return }  // Already open
        guard !isSwitching else { return }  // Prevent during switching

        openProfileSwitcher()
    }

    /// Call when touchpad button is released
    func handleTouchpadRelease() {
        guard isVisible else { return }

        switchToSelectedProfile()
        closeProfileSwitcher()
    }

    /// Update analog stick position (call continuously while switcher is open)
    func handleAnalogStickInput(x: Float, y: Float) {
        guard isVisible else { return }

        // Update visual position (invert Y so up shows up, down shows down)
        stickPosition = CGPoint(x: CGFloat(x), y: CGFloat(-y))

        // Calculate magnitude (distance from center)
        let magnitude = sqrt(x * x + y * y)

        // Determine if we're in dead zone or selecting
        let hasExistingSelection = selectedProfileIndex != nil
        let deadZone = hasExistingSelection ? deadZoneExit : deadZoneEntry

        if magnitude < deadZone {
            // In dead zone - clear selection with debounce
            updateSelectionWithDebounce(nil)
        } else {
            // Calculate angle in degrees (0° = North/Up, clockwise)
            let angle = atan2(Double(x), Double(y)) * 180.0 / .pi
            let normalizedAngle = angle < 0 ? angle + 360 : angle

            // Map angle to profile index (0-7)
            // Each profile covers 45° (360° / 8 profiles)
            let profileIndex = compassDirectionToProfileIndex(angle: normalizedAngle)

            // Update selection with debounce
            updateSelectionWithDebounce(profileIndex)
        }
    }

    // MARK: - Private Methods

    private func openProfileSwitcher() {
        isVisible = true
        selectedProfileIndex = nil
        stickPosition = .zero

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileSwitcherOpened, object: nil)
    }

    private func closeProfileSwitcher() {
        isVisible = false
        selectedProfileIndex = nil
        stickPosition = .zero

        // Cancel any pending debounce
        selectionDebounceTimer?.invalidate()
        selectionDebounceTimer = nil
        pendingProfileIndex = nil

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileSwitcherClosed, object: nil)
    }

    private func switchToSelectedProfile() {
        guard let profileIndex = selectedProfileIndex else {
            // No profile selected - close without switching
            return
        }

        guard profileIndex >= 0 && profileIndex < profileManager.profiles.count else {
            print("Invalid profile index: \(profileIndex)")
            return
        }

        isSwitching = true

        // Get the profile at the selected index
        let profile = profileManager.profiles[profileIndex]

        // Switch to the selected profile
        profileManager.selectProfile(profile)

        print("Switched to profile: \(profile.name)")

        // Post notification with profile info
        NotificationCenter.default.post(
            name: .profileSwitched,
            object: nil,
            userInfo: ["profileName": profile.name, "profileIndex": profileIndex]
        )

        isSwitching = false
    }

    private func updateSelectionWithDebounce(_ newIndex: Int?) {
        // If same as current, no need to debounce
        if newIndex == selectedProfileIndex {
            return
        }

        // Store pending direction
        pendingProfileIndex = newIndex

        // Cancel existing timer
        selectionDebounceTimer?.invalidate()

        // Set new timer
        selectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: selectionDebounce, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // Apply the pending selection
            self.selectedProfileIndex = self.pendingProfileIndex

            // Post notification for selection change (for audio feedback, haptics, etc.)
            if let index = self.selectedProfileIndex {
                NotificationCenter.default.post(
                    name: .profileSwitcherSelectionChanged,
                    object: nil,
                    userInfo: ["profileIndex": index]
                )
            }
        }
    }

    private func compassDirectionToProfileIndex(angle: Double) -> Int {
        // Compass directions mapped to profile indices
        // North (0°) = index 0, Northeast (45°) = index 1, etc.
        let direction = CompassDirection.from(angle: angle)

        switch direction {
        case .north: return 0
        case .northeast: return 1
        case .east: return 2
        case .southeast: return 3
        case .south: return 4
        case .southwest: return 5
        case .west: return 6
        case .northwest: return 7
        case .none: return 0  // Fallback to first profile
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let profileSwitcherOpened = Notification.Name("ProfileSwitcherOpened")
    static let profileSwitcherClosed = Notification.Name("ProfileSwitcherClosed")
    static let profileSwitcherSelectionChanged = Notification.Name("ProfileSwitcherSelectionChanged")
    static let profileSwitched = Notification.Name("ProfileSwitched")
}

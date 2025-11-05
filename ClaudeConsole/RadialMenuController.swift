//
//  RadialMenuController.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import Foundation
import Combine

class RadialMenuController: ObservableObject {
    // MARK: - Published State

    /// Whether the radial menu is currently visible
    @Published var isVisible: Bool = false

    /// Which menu is currently active (L1 or R1)
    @Published var activeMenuType: MenuType? = nil

    /// Currently selected segment direction (nil if in dead zone)
    @Published var selectedDirection: CompassDirection? = nil

    /// Current analog stick position (for visual indicator)
    @Published var stickPosition: CGPoint = .zero

    // MARK: - Profile Manager

    let profileManager = RadialMenuProfileManager()

    // MARK: - Menu Types

    enum MenuType {
        case l1
        case r1

        func configuration(from profile: RadialMenuProfile) -> RadialMenuConfiguration {
            switch self {
            case .l1: return profile.l1Menu
            case .r1: return profile.r1Menu
            }
        }

        var triggerButton: PS4Button {
            switch self {
            case .l1: return .l1
            case .r1: return .r1
            }
        }
    }

    // MARK: - Configuration

    private let holdDelay: TimeInterval = 0.3  // 300ms hold to activate
    private let selectionDebounce: TimeInterval = 0.05  // 50ms debounce
    private let deadZoneEntry: Float = 0.2  // Must exceed to select
    private let deadZoneExit: Float = 0.15  // Can go lower without losing selection

    // MARK: - Private State

    private var holdTimers: [PS4Button: Timer] = [:]
    private var selectionDebounceTimer: Timer? = nil
    private var pendingDirection: CompassDirection? = nil
    private var isExecuting: Bool = false

    // MARK: - Public Methods

    /// Call when a button is pressed (L1 or R1)
    func handleButtonPress(_ button: PS4Button) {
        guard button == .l1 || button == .r1 else { return }
        guard !isVisible else { return }  // Don't open second menu
        guard !isExecuting else { return }  // Prevent during execution

        // Open menu immediately
        let menuType: MenuType = button == .l1 ? .l1 : .r1
        openMenu(type: menuType)
    }

    /// Call when a button is released (L1 or R1)
    func handleButtonRelease(_ button: PS4Button) {
        // Cancel hold timer if not yet activated
        holdTimers[button]?.invalidate()
        holdTimers[button] = nil

        // Execute and close menu if it's the active menu's button
        if isVisible, let activeType = activeMenuType, button == activeType.triggerButton {
            executeSelectedAction()
            closeMenu()
        }
    }

    /// Update analog stick position (call continuously while menu is open)
    func handleAnalogStickInput(x: Float, y: Float) {
        guard isVisible else { return }

        // Update visual position (invert Y so up shows up, down shows down)
        stickPosition = CGPoint(x: CGFloat(x), y: CGFloat(-y))

        // Calculate magnitude (distance from center)
        let magnitude = sqrt(x * x + y * y)

        // Apply dead zone with hysteresis
        let threshold = selectedDirection == nil ? deadZoneEntry : deadZoneExit

        if magnitude < threshold {
            // In dead zone - clear selection
            if selectedDirection != nil {
                selectedDirection = nil
                pendingDirection = nil
                selectionDebounceTimer?.invalidate()
            }
        } else {
            // Outside dead zone - calculate direction
            // Game controller: Y is negative when pushed up, positive when pushed down
            // We already inverted Y for visuals, so use raw Y for angle calculation
            // atan2 returns angle in radians where 0° is East
            let angleRadians = atan2(Double(y), Double(x))
            let angleDegrees = angleRadians * 180.0 / .pi

            // Convert from East=0° to North=0° and normalize to 0-360°
            let normalizedAngle = (90 - angleDegrees).truncatingRemainder(dividingBy: 360)
            let adjustedAngle = normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle

            // Determine compass direction
            if let newDirection = CompassDirection.from(angle: adjustedAngle) {
                updateSelection(to: newDirection)
            }
        }
    }

    /// Cancel the menu without executing (e.g., if Circle button pressed)
    func cancelMenu() {
        guard isVisible else { return }
        closeMenu()
    }

    // MARK: - Private Methods

    private func openMenu(type: MenuType) {
        activeMenuType = type
        isVisible = true
        selectedDirection = nil
        stickPosition = .zero
    }

    private func closeMenu() {
        isVisible = false
        activeMenuType = nil
        selectedDirection = nil
        stickPosition = .zero
        pendingDirection = nil
        selectionDebounceTimer?.invalidate()
    }

    private func updateSelection(to newDirection: CompassDirection) {
        // Debounce selection to prevent flickering on segment boundaries
        if newDirection != pendingDirection {
            pendingDirection = newDirection
            selectionDebounceTimer?.invalidate()
            selectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: selectionDebounce, repeats: false) { [weak self] _ in
                self?.selectedDirection = self?.pendingDirection
            }
        }
    }

    private func executeSelectedAction() {
        guard !isExecuting else { return }
        guard let direction = selectedDirection else { return }
        guard let menuType = activeMenuType else { return }

        let configuration = menuType.configuration(from: profileManager.activeProfile)
        guard let action = configuration.action(for: direction) else { return }

        // Set executing flag to prevent double-execution
        isExecuting = true

        // Notify delegate to execute action
        // This will be handled by PS4ControllerController
        NotificationCenter.default.post(
            name: .radialMenuActionSelected,
            object: nil,
            userInfo: ["action": action]
        )

        // Reset flag after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isExecuting = false
        }
    }

    /// Get the currently active menu configuration
    var activeConfiguration: RadialMenuConfiguration? {
        guard let menuType = activeMenuType else { return nil }
        return menuType.configuration(from: profileManager.activeProfile)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let radialMenuActionSelected = Notification.Name("radialMenuActionSelected")
}

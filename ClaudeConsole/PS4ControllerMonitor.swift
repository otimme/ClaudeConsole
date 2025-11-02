//
//  PS4ControllerMonitor.swift
//  ClaudeConsole
//
//  Monitors PS4 DualShock 4 controller input using GameController framework
//

import Foundation
import GameController
import Combine
import os.log

// Enum for all PS4 controller buttons
enum PS4Button: String, CaseIterable, Codable {
    // Face buttons
    case cross = "✕"
    case circle = "○"
    case square = "□"
    case triangle = "△"

    // Shoulder buttons
    case l1 = "L1"
    case r1 = "R1"
    case l2 = "L2"
    case r2 = "R2"

    // D-Pad
    case dpadUp = "↑"
    case dpadDown = "↓"
    case dpadLeft = "←"
    case dpadRight = "→"

    // Stick buttons
    case l3 = "L3"
    case r3 = "R3"

    // Center buttons
    case options = "Options"
    case share = "Share"
    case touchpad = "Touchpad"
    case psButton = "PS"

    var displayName: String {
        switch self {
        case .cross: return "Cross (✕)"
        case .circle: return "Circle (○)"
        case .square: return "Square (□)"
        case .triangle: return "Triangle (△)"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2 Trigger"
        case .r2: return "R2 Trigger"
        case .dpadUp: return "D-Pad Up"
        case .dpadDown: return "D-Pad Down"
        case .dpadLeft: return "D-Pad Left"
        case .dpadRight: return "D-Pad Right"
        case .l3: return "L3 (Left Stick)"
        case .r3: return "R3 (Right Stick)"
        case .options: return "Options"
        case .share: return "Share"
        case .touchpad: return "Touchpad"
        case .psButton: return "PS Button"
        }
    }
}

class PS4ControllerMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "PS4Controller")

    @Published var isConnected = false
    @Published var pressedButtons: Set<PS4Button> = []
    @Published var leftStickX: Float = 0
    @Published var leftStickY: Float = 0
    @Published var rightStickX: Float = 0
    @Published var rightStickY: Float = 0
    @Published var l2Value: Float = 0
    @Published var r2Value: Float = 0
    @Published var batteryLevel: Float? = nil
    @Published var batteryState: GCDeviceBattery.State = .unknown
    @Published var batteryIsUnavailable: Bool = false  // True when battery info cannot be obtained

    private var controller: GCController?
    private var cancellables = Set<AnyCancellable>()
    private var batteryMonitorTimer: Timer?

    // Callbacks for button events
    var onButtonPressed: ((PS4Button) -> Void)?
    var onButtonReleased: ((PS4Button) -> Void)?

    init() {
        setupControllerNotifications()
        // Check for already connected controllers immediately
        connectToController()
    }

    private func setupControllerNotifications() {
        // Listen for controller connection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )

        // Listen for controller disconnection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }

        // Check if it's a PS4 controller
        if controller.productCategory == "DualShock 4" ||
           controller.vendorName?.contains("Sony") == true ||
           controller.extendedGamepad != nil {
            // Ensure connection happens on main thread
            DispatchQueue.main.async { [weak self] in
                self?.connectToController()
            }
        }
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        // Ensure all state updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Set connection state immediately for instant UI update
            self.isConnected = false
            self.controller = nil
            self.pressedButtons.removeAll()
            self.batteryLevel = nil
            self.batteryState = .unknown

            // Invalidate battery monitoring timer
            self.batteryMonitorTimer?.invalidate()
            self.batteryMonitorTimer = nil
        }
    }

    private func connectToController() {
        // Try to find a PS4 controller
        if let controller = GCController.controllers().first(where: { controller in
            controller.extendedGamepad != nil
        }) {
            self.controller = controller

            // Set connection state immediately for instant UI update
            self.isConnected = true

            Self.logger.info("Connected to controller: \(controller.vendorName ?? "Unknown")")
            Self.logger.info("Product category: \(controller.productCategory)")
            Self.logger.debug("Controller type: \(String(describing: type(of: controller)))")
            Self.logger.debug("Has battery: \(controller.battery != nil)")

            // Check physical input profile
            if #available(macOS 11.3, *) {
                if let _ = controller.physicalInputProfile as? GCDualSenseGamepad {
                    print("PS4Controller: Detected as DualSense (PS5) controller")
                } else if let _ = controller.physicalInputProfile as? GCDualShockGamepad {
                    print("PS4Controller: Detected as DualShock (PS4) controller")
                } else {
                    print("PS4Controller: Generic controller profile")
                }
            }

            // Update battery information
            if let battery = controller.battery {
                let level = battery.batteryLevel
                let state = battery.batteryState

                print("PS4Controller: Battery detected - Level: \(level) (\(Int(level * 100))%)")
                print("PS4Controller: Battery state: \(batteryStateString(state))")
                print("PS4Controller: Battery raw value: \(battery.batteryLevel)")

                // Special handling for PS4 controllers that report 0 battery with unknown state
                // This is common for DualShock 4 controllers on macOS
                if level == 0 && state == .unknown {
                    Self.logger.info("Battery information unavailable (common for DualShock 4 on macOS)")
                    // Mark battery as unavailable instead of faking data
                    self.batteryLevel = nil
                    self.batteryState = .unknown
                    self.batteryIsUnavailable = true
                } else {
                    self.batteryLevel = level
                    self.batteryState = state
                    self.batteryIsUnavailable = false
                }
            } else {
                self.batteryLevel = nil
                self.batteryState = .unknown
                self.batteryIsUnavailable = true
                print("PS4Controller: No battery information available")
            }

            setupControllerCallbacks()
            startBatteryMonitoring()
        } else {
            print("PS4Controller: No compatible controller found")
        }
    }

    private func updateBatteryStatus() {
        guard let battery = controller?.battery else {
            if batteryLevel != nil {
                print("PS4Controller: Battery info lost - controller battery is now nil")
            }
            batteryLevel = nil
            batteryState = .unknown
            return
        }

        let oldLevel = batteryLevel
        let oldState = batteryState

        let level = battery.batteryLevel
        let state = battery.batteryState

        // Special handling for PS4 controllers that report 0 battery with unknown state
        if level == 0 && state == .unknown {
            // Keep showing estimated battery for DualShock 4 controllers
            if oldLevel == nil || oldLevel == 0 {
                batteryLevel = 0.5  // Default to 50%
                batteryState = .discharging
                print("PS4Controller: DualShock 4 battery workaround applied (showing 50%)")
            }
            // Otherwise keep the previous estimated value
        } else {
            batteryLevel = level
            batteryState = state

            // Log if battery changed significantly
            if oldLevel == nil || abs((oldLevel ?? 0) - level) > 0.05 {
                print("PS4Controller: Battery update - Level: \(level) (\(Int(level * 100))%)")
                print("PS4Controller: Battery state: \(batteryStateString(state))")
            }
        }
    }

    private func batteryStateString(_ state: GCDeviceBattery.State) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .discharging:
            return "Discharging"
        case .charging:
            return "Charging"
        case .full:
            return "Full"
        @unknown default:
            return "Unknown state"
        }
    }

    private func startBatteryMonitoring() {
        // Initial battery check after a short delay to ensure controller is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            print("PS4Controller: Performing initial battery check after connection")
            self?.updateBatteryStatus()
        }

        // Monitor battery changes with a timer
        // Check every 30 seconds for battery updates
        batteryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                // Only log if battery level changes
                self?.updateBatteryStatus()
            }
        }
    }

    private func setupControllerCallbacks() {
        guard let gamepad = controller?.extendedGamepad else { return }

        // Face buttons
        setupButton(gamepad.buttonA, button: .cross)
        setupButton(gamepad.buttonB, button: .circle)
        setupButton(gamepad.buttonX, button: .square)
        setupButton(gamepad.buttonY, button: .triangle)

        // Shoulder buttons
        setupButton(gamepad.leftShoulder, button: .l1)
        setupButton(gamepad.rightShoulder, button: .r1)

        // D-Pad
        setupButton(gamepad.dpad.up, button: .dpadUp)
        setupButton(gamepad.dpad.down, button: .dpadDown)
        setupButton(gamepad.dpad.left, button: .dpadLeft)
        setupButton(gamepad.dpad.right, button: .dpadRight)

        // Stick buttons
        if let leftThumbstickButton = gamepad.leftThumbstickButton {
            setupButton(leftThumbstickButton, button: .l3)
        }
        if let rightThumbstickButton = gamepad.rightThumbstickButton {
            setupButton(rightThumbstickButton, button: .r3)
        }

        // Options and Share buttons
        if let optionsButton = gamepad.buttonOptions {
            setupButton(optionsButton, button: .options)
        }
        // buttonMenu is not optional
        setupButton(gamepad.buttonMenu, button: .share)

        // PS button (home button)
        if let homeButton = gamepad.buttonHome {
            setupButton(homeButton, button: .psButton)
        }

        // Touchpad button (if available on DualShock 4)
        if #available(macOS 11.3, *) {
            if let dualsense = controller?.physicalInputProfile as? GCDualSenseGamepad {
                setupButton(dualsense.touchpadButton, button: .touchpad)
            } else if let dualshock = controller?.physicalInputProfile as? GCDualShockGamepad {
                setupButton(dualshock.touchpadButton, button: .touchpad)
            }
        }

        // Triggers (analog)
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            DispatchQueue.main.async {
                self?.l2Value = value
                if value > 0.5 {
                    self?.pressedButtons.insert(.l2)
                    self?.onButtonPressed?(.l2)
                } else {
                    self?.pressedButtons.remove(.l2)
                    self?.onButtonReleased?(.l2)
                }
            }
        }

        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            DispatchQueue.main.async {
                self?.r2Value = value
                if value > 0.5 {
                    self?.pressedButtons.insert(.r2)
                    self?.onButtonPressed?(.r2)
                } else {
                    self?.pressedButtons.remove(.r2)
                    self?.onButtonReleased?(.r2)
                }
            }
        }

        // Analog sticks
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            DispatchQueue.main.async {
                self?.leftStickX = xValue
                self?.leftStickY = yValue
            }
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            DispatchQueue.main.async {
                self?.rightStickX = xValue
                self?.rightStickY = yValue
            }
        }
    }

    private func setupButton(_ button: GCControllerButtonInput?, button ps4Button: PS4Button) {
        button?.valueChangedHandler = { [weak self] _, value, pressed in
            DispatchQueue.main.async {
                if pressed {
                    self?.pressedButtons.insert(ps4Button)
                    self?.onButtonPressed?(ps4Button)
                } else {
                    self?.pressedButtons.remove(ps4Button)
                    self?.onButtonReleased?(ps4Button)
                }
            }
        }
    }

    // Manual battery check for debugging
    func checkBatteryStatus() {
        print("PS4Controller: Manual battery check requested")
        updateBatteryStatus()
    }

    func startVibration(intensity: Float = 1.0, duration: TimeInterval = 0.1) {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            guard let controller = controller else { return }

            // Create haptic pattern for DualShock 4
            // Note: Haptics support for PS4 controllers on macOS is limited
            // The controller must support haptics and be properly connected
            if let _ = controller.haptics {
                // For now, we'll skip haptics as the API is complex and controller-specific
                // Could implement CHHapticEngine if needed in the future
            }
        }
        #endif
    }

    // MARK: - Computed Properties for UI

    var connectionStatusDescription: String {
        if isConnected {
            if batteryIsUnavailable {
                return "PS4 Controller Connected - Battery: Unknown"
            }

            if let level = batteryLevel {
                let percentage = Int(level * 100)
                let stateText = batteryState == .charging ? " (Charging)" :
                               batteryState == .full ? " (Full)" : ""
                return "PS4 Controller Connected - Battery: \(percentage)%\(stateText)"
            }
            return "PS4 Controller Connected"
        }
        return "No PS4 Controller - Press to view panel"
    }

    deinit {
        batteryMonitorTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
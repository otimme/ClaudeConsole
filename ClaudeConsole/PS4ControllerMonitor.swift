//
//  PS4ControllerMonitor.swift
//  ClaudeConsole
//
//  Monitors PlayStation controller input using GameController framework
//  Supports both DualShock 4 (PS4) and DualSense (PS5) controllers
//

import Foundation
import GameController
import Combine
import os.log

// Controller type identification
enum ControllerType: String, Codable {
    case dualShock4 = "DualShock 4"
    case dualSense = "DualSense"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .dualShock4: return "PlayStation 4 DualShock 4"
        case .dualSense: return "PlayStation 5 DualSense"
        case .unknown: return "Generic Controller"
        }
    }

    var shortName: String {
        switch self {
        case .dualShock4: return "PS4"
        case .dualSense: return "PS5"
        case .unknown: return "Controller"
        }
    }
}

// Enum for all PlayStation controller buttons (DualShock 4 and DualSense)
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

    // Center buttons (DualShock 4 & DualSense)
    case options = "Options"
    case share = "Share"        // DualShock 4 only
    case create = "Create"      // DualSense only (replaces Share)
    case touchpad = "Touchpad"
    case psButton = "PS"

    // DualSense-specific buttons
    case mute = "Mute"          // DualSense microphone mute button

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
        case .share: return "Share (PS4)"
        case .create: return "Create (PS5)"
        case .touchpad: return "Touchpad"
        case .psButton: return "PS Button"
        case .mute: return "Mute (PS5)"
        }
    }
}

class PS4ControllerMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "PS4Controller")

    // Configuration constants
    private static let batteryCheckInterval: TimeInterval = 30.0  // seconds
    private static let initialBatteryCheckDelay: TimeInterval = 2.0  // seconds
    private static let triggerPressThreshold: Float = 0.5  // L2/R2 trigger threshold

    @Published var isConnected = false
    @Published var controllerType: ControllerType = .unknown
    @Published var pressedButtons: Set<PS4Button> = []

    // HID battery reader for DualSense (bypasses GameController limitations)
    private var hidBatteryReader: DualSenseHIDBatteryReader?
    private var hidBatteryCancellable: AnyCancellable?
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

    // Trigger debouncing state (prevent rapid re-triggers from analog fluctuation)
    private var l2Pressed: Bool = false
    private var r2Pressed: Bool = false

    // Analog stick dead zone filtering (prevent CPU waste from tiny fluctuations)
    private var lastLeftStickX: Float = 0
    private var lastLeftStickY: Float = 0
    private var lastRightStickX: Float = 0
    private var lastRightStickY: Float = 0
    private static let analogStickThreshold: Float = 0.01  // Only update if change > 1%

    // Callbacks for button events
    var onButtonPressed: ((PS4Button) -> Void)?
    var onButtonReleased: ((PS4Button) -> Void)?

    init() {
        setupControllerNotifications()

        // Initialize HID battery reader for DualSense
        setupHIDBatteryReader()

        // Check for already connected controllers after a brief delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.connectToController()
        }
    }

    private func setupHIDBatteryReader() {
        // Create HID battery reader for DualSense
        let reader = DualSenseHIDBatteryReader()
        self.hidBatteryReader = reader

        // Subscribe to HID battery updates
        hidBatteryCancellable = reader.$batteryLevel
            .combineLatest(reader.$batteryState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level, state in
                guard let self = self else { return }

                // Only use HID battery for DualSense controllers
                if self.controllerType == .dualSense, let level = level {
                    self.batteryLevel = level

                    // Map HID battery state to GameController battery state
                    switch state {
                    case .charging:
                        self.batteryState = .charging
                    case .full:
                        self.batteryState = .full
                    case .discharging:
                        self.batteryState = .discharging
                    default:
                        self.batteryState = .unknown
                    }

                    self.batteryIsUnavailable = false
                }
            }
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
                // @Published properties will automatically trigger UI updates
            }
        }
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        // Ensure all state updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Set connection state immediately for instant UI update
            self.isConnected = false
            self.controllerType = .unknown
            self.controller = nil
            self.pressedButtons.removeAll()
            self.batteryLevel = nil
            self.batteryState = .unknown
            self.batteryIsUnavailable = false

            // Reset trigger debounce state
            self.l2Pressed = false
            self.r2Pressed = false

            // Reset analog stick dead zone state
            self.lastLeftStickX = 0
            self.lastLeftStickY = 0
            self.lastRightStickX = 0
            self.lastRightStickY = 0

            // Invalidate battery monitoring timer
            self.batteryMonitorTimer?.invalidate()
            self.batteryMonitorTimer = nil

            // @Published properties will automatically trigger UI updates
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

            // Detect controller type
            if #available(macOS 11.3, *) {
                if let _ = controller.physicalInputProfile as? GCDualSenseGamepad {
                    self.controllerType = .dualSense
                    print("PS4Controller: Detected as DualSense (PS5) controller")
                } else if let _ = controller.physicalInputProfile as? GCDualShockGamepad {
                    self.controllerType = .dualShock4
                    print("PS4Controller: Detected as DualShock (PS4) controller")
                } else {
                    self.controllerType = .unknown
                    print("PS4Controller: Generic controller profile")
                }
            } else {
                // On older macOS versions, try to detect from product category or vendor name
                if controller.productCategory == "DualShock 4" {
                    self.controllerType = .dualShock4
                } else if controller.productCategory == "DualSense" {
                    self.controllerType = .dualSense
                } else {
                    self.controllerType = .unknown
                }
            }

            // Update battery information
            if let battery = controller.battery {
                let level = battery.batteryLevel
                let state = battery.batteryState

                print("=== Battery Information ===")
                print("Controller Type: \(self.controllerType.displayName)")
                print("Battery Level: \(level) (\(Int(level * 100))%)")
                print("Battery State: \(batteryStateString(state))")
                print("Battery Raw: \(battery.batteryLevel)")
                print("==========================")

                // DualSense controllers should have better battery reporting than DualShock 4
                // Only mark as unavailable if we're certain there's no battery info
                if level == 0 && state == .unknown && self.controllerType == .dualShock4 {
                    // DualShock 4 commonly reports 0/unknown on macOS
                    Self.logger.info("Battery information unavailable (common for DualShock 4 on macOS)")
                    self.batteryLevel = nil
                    self.batteryState = .unknown
                    self.batteryIsUnavailable = true
                } else if level == 0 && state == .unknown && self.controllerType == .dualSense {
                    // DualSense reporting 0/unknown - might be charging or disconnected
                    // Show the data anyway and let the user see it
                    Self.logger.info("DualSense battery reports 0/unknown - showing as-is (may update)")
                    self.batteryLevel = level
                    self.batteryState = state
                    self.batteryIsUnavailable = false
                } else {
                    // Valid battery data - show it
                    self.batteryLevel = level
                    self.batteryState = state
                    self.batteryIsUnavailable = false
                    print("✓ Battery info available: \(Int(level * 100))% (\(batteryStateString(state)))")
                }
            } else {
                self.batteryLevel = nil
                self.batteryState = .unknown
                self.batteryIsUnavailable = true
                print("⚠ Controller battery object is nil - no battery API available")
            }

            setupControllerCallbacks()
            startBatteryMonitoring()

            // @Published properties automatically trigger UI updates
        } else {
            print("PS4Controller: No compatible controller found")
        }
    }

    private func updateBatteryStatus() {
        // For DualSense, skip GameController battery - use HID battery reader instead
        if controllerType == .dualSense {
            return
        }

        guard let battery = controller?.battery else {
            if batteryLevel != nil {
                print("PS4Controller: Battery info lost - controller battery is now nil")
            }
            batteryLevel = nil
            batteryState = .unknown
            batteryIsUnavailable = true
            return
        }

        let oldLevel = batteryLevel
        let oldState = batteryState

        let level = battery.batteryLevel
        let state = battery.batteryState

        // For DualShock 4, mark as unavailable if 0/unknown
        if level == 0 && state == .unknown {
            batteryLevel = nil
            batteryState = .unknown
            batteryIsUnavailable = true
        } else {
            // Show battery data for valid readings
            batteryLevel = level
            batteryState = state
            batteryIsUnavailable = false
        }

        // Log battery changes with detailed info
        if oldLevel == nil || abs((oldLevel ?? 0) - level) > 0.05 || oldState != state {
            print("🔋 Battery Update [\(controllerType.shortName)]:")
            print("   Level: \(Int(level * 100))% (raw: \(level))")
            print("   State: \(batteryStateString(state))")
            if let old = oldLevel {
                print("   Previous: \(Int(old * 100))%")
            }
            os_log("Battery: %{public}@ %d%% (%{public}@)", log: .default, type: .info,
                   controllerType.shortName, Int(level * 100), batteryStateString(state))
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
        // Ensure timer is scheduled on main RunLoop for thread safety
        DispatchQueue.main.async { [weak self] in
            self?.batteryMonitorTimer = Timer.scheduledTimer(withTimeInterval: Self.batteryCheckInterval, repeats: true) { [weak self] _ in
                // Already on main queue since timer is on main RunLoop
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

        // PS button (home button)
        if let homeButton = gamepad.buttonHome {
            setupButton(homeButton, button: .psButton)
        }

        // Controller-specific buttons (DualShock 4 vs DualSense)
        if #available(macOS 11.3, *) {
            if let dualsense = controller?.physicalInputProfile as? GCDualSenseGamepad {
                // DualSense (PS5) specific buttons
                // On DualSense: buttonOptions = left (Create), buttonMenu = right (Options)
                if let optionsButton = gamepad.buttonOptions {
                    setupButton(optionsButton, button: .create)  // Left button = Create
                }
                setupButton(gamepad.buttonMenu, button: .options)  // Right button = Options
                setupButton(dualsense.touchpadButton, button: .touchpad)

                // Mute button (if available - check if the API exposes it)
                // Note: As of macOS 14, the mute button might not be exposed via GameController framework
                // We'll handle it when Apple adds API support
                print("PS4Controller: DualSense buttons configured (Create, Options, Touchpad)")
            } else if let dualshock = controller?.physicalInputProfile as? GCDualShockGamepad {
                // DualShock 4 (PS4) specific buttons
                // On DualShock 4: buttonOptions = left (Share), buttonMenu = right (Options)
                if let optionsButton = gamepad.buttonOptions {
                    setupButton(optionsButton, button: .share)  // Left button = Share
                }
                setupButton(gamepad.buttonMenu, button: .options)  // Right button = Options
                setupButton(dualshock.touchpadButton, button: .touchpad)
                print("PS4Controller: DualShock 4 buttons configured (Share, Options, Touchpad)")
            } else {
                // Generic controller - map buttons generically
                if let optionsButton = gamepad.buttonOptions {
                    setupButton(optionsButton, button: .share)
                }
                setupButton(gamepad.buttonMenu, button: .options)
            }
        } else {
            // Fallback for older macOS versions
            if let optionsButton = gamepad.buttonOptions {
                setupButton(optionsButton, button: .share)
            }
            setupButton(gamepad.buttonMenu, button: .options)
        }

        // Triggers (analog) with debouncing to prevent rapid re-triggers
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.l2Value = value

                let shouldBePressed = value > Self.triggerPressThreshold

                // Only fire callbacks when state actually changes
                if shouldBePressed && !self.l2Pressed {
                    self.l2Pressed = true
                    self.pressedButtons.insert(.l2)
                    self.onButtonPressed?(.l2)
                } else if !shouldBePressed && self.l2Pressed {
                    self.l2Pressed = false
                    self.pressedButtons.remove(.l2)
                    self.onButtonReleased?(.l2)
                }
            }
        }

        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.r2Value = value

                let shouldBePressed = value > Self.triggerPressThreshold

                // Only fire callbacks when state actually changes
                if shouldBePressed && !self.r2Pressed {
                    self.r2Pressed = true
                    self.pressedButtons.insert(.r2)
                    self.onButtonPressed?(.r2)
                } else if !shouldBePressed && self.r2Pressed {
                    self.r2Pressed = false
                    self.pressedButtons.remove(.r2)
                    self.onButtonReleased?(.r2)
                }
            }
        }

        // Analog sticks (with dead zone filtering to reduce CPU usage)
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }

            // Only update if change exceeds threshold (prevents CPU waste from tiny fluctuations)
            let xChanged = abs(xValue - self.lastLeftStickX) > Self.analogStickThreshold
            let yChanged = abs(yValue - self.lastLeftStickY) > Self.analogStickThreshold

            if xChanged || yChanged {
                self.lastLeftStickX = xValue
                self.lastLeftStickY = yValue

                DispatchQueue.main.async {
                    self.leftStickX = xValue
                    self.leftStickY = yValue
                }
            }
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }

            // Only update if change exceeds threshold (prevents CPU waste from tiny fluctuations)
            let xChanged = abs(xValue - self.lastRightStickX) > Self.analogStickThreshold
            let yChanged = abs(yValue - self.lastRightStickY) > Self.analogStickThreshold

            if xChanged || yChanged {
                self.lastRightStickX = xValue
                self.lastRightStickY = yValue

                DispatchQueue.main.async {
                    self.rightStickX = xValue
                    self.rightStickY = yValue
                }
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
            let controllerName = controllerType.shortName + " Controller"

            if batteryIsUnavailable {
                return "\(controllerName) Connected - Battery: Unknown"
            }

            if let level = batteryLevel {
                let percentage = Int(level * 100)

                // Special message for DualSense reporting 0%/Unknown (macOS limitation)
                if percentage == 0 && batteryState == .unknown && controllerType == .dualSense {
                    return "\(controllerName) Connected - Battery: Unavailable (macOS limitation)"
                }

                let stateText = batteryState == .charging ? " (Charging)" :
                               batteryState == .full ? " (Full)" : ""
                return "\(controllerName) Connected - Battery: \(percentage)%\(stateText)"
            }
            return "\(controllerName) Connected"
        }
        return "No Controller - Press to view panel"
    }

    deinit {
        batteryMonitorTimer?.invalidate()
        hidBatteryCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
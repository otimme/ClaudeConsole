//
//  DualSenseHIDBatteryReader.swift
//  ClaudeConsole
//
//  Reads DualSense battery information directly from HID reports
//  This bypasses GameController framework limitations
//

import Foundation
import IOKit.hid
import Combine
import os.log

class DualSenseHIDBatteryReader: ObservableObject {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "DualSenseHID")

    // Published battery information
    @Published var batteryLevel: Float? = nil
    @Published var batteryState: BatteryChargingState = .unknown
    @Published var isConnected = false

    // HID Manager
    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?

    // Report buffer (needs manual deallocation)
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var reportBufferSize: Int = 0

    // DualSense VID/PID
    private static let sonyVendorID = 0x054C
    private static let dualSenseProductID = 0x0CE6  // DualSense controller

    // Report IDs
    private static let reportIDUSB: UInt8 = 0x01
    private static let reportIDBluetooth: UInt8 = 0x31

    // Connection mode (immutable after detection to avoid race conditions)
    private var connectionMode: ConnectionMode = .unknown

    // Logging control flags
    private var hasReceivedFirstReport = false
    private var hasShownBatteryOffsetError = false

    enum ConnectionMode {
        case usb
        case bluetooth
        case unknown
    }

    enum BatteryChargingState: Int {
        case unknown = -1
        case discharging = 0
        case charging = 1
        case full = 2
        case voltageError = 0xA
        case temperatureError = 0xB
        case chargingError = 0xF

        var description: String {
            switch self {
            case .unknown: return "Unknown"
            case .discharging: return "Discharging"
            case .charging: return "Charging"
            case .full: return "Full"
            case .voltageError: return "Voltage Error"
            case .temperatureError: return "Temperature Error"
            case .chargingError: return "Charging Error"
            }
        }
    }

    init() {
        setupHIDManager()
    }

    private func setupHIDManager() {
        // Create HID Manager
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Set up device matching for DualSense controller
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: Self.sonyVendorID,
            kIOHIDProductIDKey: Self.dualSenseProductID
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Register callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let reader = Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let reader = Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceDisconnected(device)
        }, context)

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            Self.logger.error("Failed to open HID Manager: \(openResult)")
        } else {
            Self.logger.info("HID Manager opened successfully")
        }
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        Self.logger.info("DualSense HID device connected")

        // Detect connection mode BEFORE async dispatch to avoid race
        detectConnectionMode(device)

        DispatchQueue.main.async {
            self.device = device
            self.isConnected = true
            self.setupInputReportCallback(device)
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        Self.logger.info("DualSense HID device disconnected")

        DispatchQueue.main.async {
            self.device = nil
            self.isConnected = false
            self.batteryLevel = nil
            self.batteryState = .unknown
            self.connectionMode = .unknown
        }
    }

    private func detectConnectionMode(_ device: IOHIDDevice) {
        // Check transport property to determine USB vs Bluetooth
        if let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String {
            if transport.contains("USB") {
                connectionMode = .usb
                Self.logger.info("DualSense connected via USB")
            } else if transport.contains("Bluetooth") {
                connectionMode = .bluetooth
                Self.logger.info("DualSense connected via Bluetooth")
            } else {
                connectionMode = .unknown
                Self.logger.warning("Unknown transport type: \(transport)")
            }
        } else {
            connectionMode = .unknown
            Self.logger.warning("Could not determine connection mode")
        }
    }

    private func setupInputReportCallback(_ device: IOHIDDevice) {
        let reportSize = connectionMode == .usb ? 64 : 78

        // Clean up old buffer if it exists
        if let oldBuffer = reportBuffer {
            oldBuffer.deallocate()
        }

        // Allocate new buffer
        reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        reportBufferSize = reportSize

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer!,
            reportSize,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let reader = Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue()
                reader.handleInputReport(report: report, length: reportLength, reportID: reportID)
            },
            context
        )

        Self.logger.info("Input report callback registered")
    }

    private func handleInputReport(report: UnsafeMutablePointer<UInt8>, length: Int, reportID: UInt32) {
        if !hasReceivedFirstReport {
            hasReceivedFirstReport = true
        }

        // Determine battery offset and validate report length
        // Report 0x01 (USB/simple format):
        //   - Full USB: 64 bytes, battery at offset 53
        //   - Bluetooth simplified: 10 bytes, battery at offset 5
        // Report 0x31 (Bluetooth full): 78 bytes, battery at offset 54
        var batteryOffset: Int?
        var expectedMinLength: Int?

        if reportID == Self.reportIDUSB {
            if length >= 64 {
                // Full USB report: battery at offset 53
                batteryOffset = 53
                expectedMinLength = 64
            } else if length >= 10 {
                // Simplified Bluetooth report: battery at offset 5
                batteryOffset = 5
                expectedMinLength = 10
            }
        } else if reportID == Self.reportIDBluetooth {
            if length >= 78 {
                // Bluetooth full mode: battery at offset 54
                batteryOffset = 54
                expectedMinLength = 78
            }
        }

        // Validate offset and length to prevent buffer overflow
        guard let offset = batteryOffset,
              let minLength = expectedMinLength,
              length >= minLength,
              offset < length else {
            if !hasShownBatteryOffsetError {
                Self.logger.warning("Invalid report - ID: 0x\(String(reportID, radix: 16)), Length: \(length), Expected: \(expectedMinLength ?? 0)")
                hasShownBatteryOffsetError = true
            }
            return
        }

        // Extract battery byte safely
        let batteryByte = report[offset]

        // Parse battery capacity (lower 4 bits)
        let capacity = batteryByte & 0x0F  // Bits 0-3

        // Validate capacity is in expected range (0-10)
        guard capacity <= 10 else {
            Self.logger.warning("Invalid battery capacity: \(capacity)")
            return
        }

        // Parse charging status (upper 4 bits)
        let chargingStatus = (batteryByte & 0xF0) >> 4  // Bits 4-7

        // Calculate battery percentage (0.0-1.0)
        // Each unit represents ~10%, centered in range: 0→5%, 1→15%, ..., 10→100%
        let percentage = min(Float(capacity) * 10.0 + 5.0, 100.0) / 100.0

        // Update published properties on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let oldLevel = self.batteryLevel
            self.batteryLevel = percentage
            self.batteryState = BatteryChargingState(rawValue: Int(chargingStatus)) ?? .unknown

            // Log significant changes (5% threshold)
            if oldLevel == nil || abs((oldLevel ?? 0) - percentage) > 0.05 {
                Self.logger.info("DualSense Battery: \(Int(percentage * 100))% - \(self.batteryState.description)")
            }
        }
    }

    deinit {
        // Clean up HID manager
        if let manager = hidManager {
            // Unregister callbacks explicitly
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)

            // Unschedule from run loop
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            // Close manager
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        // Unregister device input callback
        if let device = device, let buffer = reportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 0, nil, nil)
        }

        // Deallocate report buffer
        if let buffer = reportBuffer {
            buffer.deallocate()
        }
    }
}

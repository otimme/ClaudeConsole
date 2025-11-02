#!/usr/bin/env swift

import GameController
import Foundation

print("PS4 Controller Test")
print("===================")
print("Waiting for controllers...")

// Set up notification observers
NotificationCenter.default.addObserver(
    forName: .GCControllerDidConnect,
    object: nil,
    queue: .main
) { notification in
    if let controller = notification.object as? GCController {
        print("\n✅ Controller Connected!")
        print("Vendor: \(controller.vendorName ?? "Unknown")")
        print("Product: \(controller.productCategory)")

        if let gamepad = controller.extendedGamepad {
            print("\nPress buttons to test (Ctrl+C to exit):")

            // Set up button handlers
            gamepad.buttonA.valueChangedHandler = { _, _, pressed in
                if pressed { print("✕ Cross pressed") }
            }
            gamepad.buttonB.valueChangedHandler = { _, _, pressed in
                if pressed { print("○ Circle pressed") }
            }
            gamepad.buttonX.valueChangedHandler = { _, _, pressed in
                if pressed { print("□ Square pressed") }
            }
            gamepad.buttonY.valueChangedHandler = { _, _, pressed in
                if pressed { print("△ Triangle pressed") }
            }
            gamepad.dpad.up.valueChangedHandler = { _, _, pressed in
                if pressed { print("↑ D-Pad Up pressed") }
            }
            gamepad.dpad.down.valueChangedHandler = { _, _, pressed in
                if pressed { print("↓ D-Pad Down pressed") }
            }
            gamepad.leftShoulder.valueChangedHandler = { _, _, pressed in
                if pressed { print("L1 pressed") }
            }
            gamepad.rightShoulder.valueChangedHandler = { _, _, pressed in
                if pressed { print("R1 pressed") }
            }
        }
    }
}

NotificationCenter.default.addObserver(
    forName: .GCControllerDidDisconnect,
    object: nil,
    queue: .main
) { notification in
    print("\n❌ Controller Disconnected")
}

// Check for already connected controllers
let controllers = GCController.controllers()
if controllers.count > 0 {
    print("\nFound \(controllers.count) controller(s) already connected")
    for controller in controllers {
        print("- \(controller.vendorName ?? "Unknown")")
    }
} else {
    print("\nNo controllers currently connected")
    print("\nTroubleshooting:")
    print("1. Make sure controller is in pairing mode (PS+Share)")
    print("2. Check Bluetooth settings")
    print("3. Try USB connection instead")
}

// Keep the script running
RunLoop.main.run()
//
//  ClaudeConsoleApp.swift
//  ClaudeConsole
//
//  Created by Olaf Timme on 31/10/2025.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "App")

// Application delegate to handle termination
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating, cleaning up sessions...")

        // Notify components to cleanup (non-blocking)
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)

        // Terminate tracked processes immediately (no blocking wait)
        // ProcessTracker validates PIDs and uses process groups
        ProcessTracker.shared.cleanupAllTrackedProcesses()

        logger.info("Cleanup complete")
    }
}

@main
struct ClaudeConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Notification for app termination
extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
//
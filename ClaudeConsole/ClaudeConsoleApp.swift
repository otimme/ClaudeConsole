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

    // Initialize SharedResourceManager early to set up hardware monitoring
    // This ensures keyboard, audio, and controller resources are ready
    // before any windows are created
    private let sharedResources = SharedResourceManager.shared

    init() {
        logger.info("ClaudeConsoleApp initializing with SharedResourceManager")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Add Window menu commands for multi-window support
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }

    private func openNewWindow() {
        // Open a new window using the default WindowGroup behavior
        if let url = URL(string: "claudeconsole://new") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Notification for app termination
extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
//
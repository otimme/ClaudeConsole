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
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window restoration to prevent duplicate windows on launch
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

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
        // Use NSApp's newWindowForTab action to open a new window
        // This works with WindowGroup and respects the system's window management
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
    }
}

// Notification for app termination
extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
//
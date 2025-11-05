//
//  ContentView.swift
//  ClaudeConsole
//
//  Created by Olaf Timme on 31/10/2025.
//

import SwiftUI
import SwiftTerm
import GameController
import Combine

struct ContentView: View {
    @StateObject private var usageMonitor = UsageMonitor()
    @StateObject private var contextMonitor = ContextMonitor()
    @StateObject private var speechToText = SpeechToTextController()
    @StateObject private var ps4Controller = PS4ControllerController()
    @State private var terminalController: LocalProcessTerminalView?
    @State private var showPS4Controller = false
    @State private var useCompactStatusBar = false
    @AppStorage("showPS4StatusBar") private var showPS4StatusBar = true

    // CRITICAL FIX: Thread-safe subscription management
    // Using @State with Set<AnyCancellable> directly causes race conditions and crashes
    // because @State is not thread-safe for reference types.
    // This helper class wraps the cancellables in a reference type that @State can safely hold.
    private class SubscriptionManager {
        var cancellables = Set<AnyCancellable>()
    }
    @State private var subscriptionManager = SubscriptionManager()

    init() {
        // Wire up dependencies after initialization
        _usageMonitor = StateObject(wrappedValue: UsageMonitor())
        _contextMonitor = StateObject(wrappedValue: ContextMonitor())
        _speechToText = StateObject(wrappedValue: SpeechToTextController())
        _ps4Controller = StateObject(wrappedValue: PS4ControllerController())
    }

    var body: some View {
        VStack(spacing: 0) {
            // PS4 Controller status bar at the very top (only when connected)
            if showPS4StatusBar && ps4Controller.monitor.isConnected {
                Group {
                    if useCompactStatusBar {
                        PS4ControllerMiniBar(
                            monitor: ps4Controller.monitor,
                            mapping: ps4Controller.mapping
                        )
                    } else {
                        PS4ControllerStatusBar(
                            monitor: ps4Controller.monitor,
                            mapping: ps4Controller.mapping
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .contextMenu {
                    Button(useCompactStatusBar ? "Show Full Status Bar" : "Show Compact Status Bar") {
                        useCompactStatusBar.toggle()
                    }
                    Divider()
                    Button("Hide PS4 Status Bar") {
                        showPS4StatusBar = false
                    }
                }
            }

            // Real usage stats from /usage command
            RealUsageStatsView(usageMonitor: usageMonitor)
                .frame(height: 70)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content area with terminal and optional PS4 controller panel
            HStack(spacing: 0) {
                // Terminal in the middle with speech-to-text overlay
                ZStack(alignment: .top) {
                    TerminalView(terminalController: $terminalController)
                        .frame(minWidth: 600, minHeight: 400)

                // Model download indicator (center)
                if speechToText.speechRecognition.isDownloadingModel {
                    ModelDownloadIndicator(
                        progress: speechToText.speechRecognition.downloadProgress
                    )
                }

                // Model warmup indicator (center)
                if speechToText.speechRecognition.isWarmingUp {
                    ModelWarmupIndicator()
                }

                // Error banner (top)
                if let error = speechToText.currentError {
                    ErrorBanner(
                        error: error,
                        onDismiss: {
                            speechToText.clearError()
                        },
                        onRetry: error.canRetry ? {
                            speechToText.retryAfterError()
                        } : nil
                    )
                    .zIndex(100) // Ensure it appears above other content
                }

                // Speech-to-text status indicator (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if speechToText.isRecording || speechToText.isTranscribing {
                            SpeechStatusIndicator(
                                isRecording: speechToText.isRecording,
                                isTranscribing: speechToText.isTranscribing
                            )
                            .padding(16)
                        }
                    }
                }

                // Radial menu overlay (full screen)
                if ps4Controller.radialMenuController.isVisible {
                    RadialMenuView(controller: ps4Controller.radialMenuController)
                        .zIndex(50) // Below error banner, above terminal
                }
            }

                // PS4 Controller panel (collapsible)
                if showPS4Controller {
                    Divider()

                    PS4ControllerView(
                        monitor: ps4Controller.monitor,
                        mapping: ps4Controller.mapping,
                        controller: ps4Controller
                    )
                    .frame(width: 400)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }

            Divider()

            // Context usage statistics with PS4 toggle button
            HStack(spacing: 0) {
                ContextStatsView(contextMonitor: contextMonitor)

                Divider()
                    .frame(height: 40)

                // PS4 Controller toggle button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showPS4Controller.toggle()
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: ps4Controller.monitor.isConnected ? "gamecontroller.fill" : "gamecontroller")
                            .font(.system(size: 22))
                            .foregroundColor(ps4Controller.monitor.isConnected ? .green : .gray)
                            .opacity(ps4Controller.monitor.isConnected ? 1.0 : 0.4)

                        // Battery indicator - always show, but disabled when not connected
                        PS4BatteryIndicator(
                            level: ps4Controller.monitor.batteryLevel ?? 0,
                            state: ps4Controller.monitor.batteryState,
                            isConnected: ps4Controller.monitor.isConnected,
                            batteryIsUnavailable: ps4Controller.monitor.batteryIsUnavailable
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 60)
                .animation(.easeInOut(duration: 0.3), value: ps4Controller.monitor.isConnected)
                .help(batteryTooltip)
                .onTapGesture(count: 2) {
                    // Double-tap to force battery check (for debugging)
                    print("ContentView: Manual battery check requested")
                    if let level = ps4Controller.monitor.batteryLevel {
                        print("ContentView: Current battery level: \(level) (\(Int(level * 100))%)")
                        print("ContentView: Current battery state: \(ps4Controller.monitor.batteryState)")
                    } else {
                        print("ContentView: Battery level is nil")
                    }
                }
                .contextMenu {
                    Button("Toggle Controller Panel") {
                        withAnimation {
                            showPS4Controller.toggle()
                        }
                    }
                    Divider()
                    Toggle("Show Status Bar", isOn: $showPS4StatusBar)
                    Toggle("Compact Mode", isOn: $useCompactStatusBar)
                        .disabled(!showPS4StatusBar)
                    Divider()
                    Button("Check Battery Status") {
                        ps4Controller.monitor.checkBatteryStatus()
                    }
                    .disabled(!ps4Controller.monitor.isConnected)
                }
            }
            .frame(height: 60)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: showPS4Controller ? 1000 : 800, minHeight: 600)
        .onAppear {
            // CRITICAL FIX: Prevent duplicate subscriptions on multiple onAppear calls
            // onAppear can fire multiple times (view recreation, navigation), so we guard
            // against creating duplicate Combine subscriptions which cause memory leaks.
            guard subscriptionManager.cancellables.isEmpty else { return }

            // FIX: Wire up AppCommandExecutor dependencies for direct access
            // This replaces the previous NotificationCenter-based approach with direct references,
            // making the code more testable and eliminating hidden coupling.
            ps4Controller.appCommandExecutor.speechController = speechToText
            ps4Controller.appCommandExecutor.ps4Controller = ps4Controller
            ps4Controller.appCommandExecutor.terminalController = terminalController
            ps4Controller.appCommandExecutor.contextMonitor = contextMonitor

            // Sync UI state with AppCommandExecutor
            ps4Controller.appCommandExecutor.showPS4Panel = showPS4Controller
            ps4Controller.appCommandExecutor.showPS4StatusBar = showPS4StatusBar

            // FIX: Bidirectional binding with weak captures to prevent retain cycles
            // Observe AppCommandExecutor state changes and update local @State
            ps4Controller.appCommandExecutor.$showPS4Panel
                .receive(on: DispatchQueue.main)
                .sink { [weak subscriptionManager] newValue in
                    guard subscriptionManager != nil else { return }
                    showPS4Controller = newValue
                }
                .store(in: &subscriptionManager.cancellables)

            ps4Controller.appCommandExecutor.$showPS4StatusBar
                .receive(on: DispatchQueue.main)
                .sink { [weak subscriptionManager] newValue in
                    guard subscriptionManager != nil else { return }
                    showPS4StatusBar = newValue
                }
                .store(in: &subscriptionManager.cancellables)
        }
        .onChange(of: terminalController) { _, newController in
            // FIX: Update AppCommandExecutor's terminal controller when it becomes available
            // Terminal controller is set asynchronously after view initialization via binding
            ps4Controller.appCommandExecutor.terminalController = newController
        }
    }

    var batteryTooltip: String {
        return ps4Controller.monitor.connectionStatusDescription
    }
}

// Battery indicator view for PS4 controller
struct PS4BatteryIndicator: View {
    let level: Float
    let state: GCDeviceBattery.State
    let isConnected: Bool
    let batteryIsUnavailable: Bool

    var body: some View {
        HStack(spacing: 1) {
            // Battery body
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(batteryColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 22, height: 8)

                // Show question mark if battery is unavailable
                if isConnected && batteryIsUnavailable {
                    Text("?")
                        .font(.system(size: 7))
                        .foregroundColor(batteryColor.opacity(0.7))
                        .frame(width: 20, height: 6)
                } else if isConnected && (level > 0 || state == .full) {
                    // Battery fill (show when connected and has level OR is full)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(batteryColor)
                        // If full but level is 0, show as full
                        .frame(width: max(2, 20 * CGFloat(state == .full && level == 0 ? 1.0 : level)), height: 6)
                        .padding(.horizontal, 1)
                }
            }

            // Battery tip
            RoundedRectangle(cornerRadius: 0.5)
                .fill(batteryColor.opacity(0.5))
                .frame(width: 2, height: 4)

            // Charging indicator
            if isConnected && state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.yellow)
                    .offset(x: -1)
            }
        }
        .frame(width: 30, height: 8)
        .opacity(isConnected ? 1.0 : 0.4)
    }

    var batteryColor: SwiftUI.Color {
        if !isConnected {
            return .gray
        }
        if batteryIsUnavailable {
            return .gray  // Show gray for unknown battery
        }
        if state == .charging {
            return .yellow
        }
        if level > 0.5 {
            return .green
        } else if level > 0.2 {
            return .orange
        } else if level > 0 {
            return .red
        } else {
            return .gray
        }
    }
}

// Model download indicator (center of terminal)
struct ModelDownloadIndicator: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

            Text("Downloading Whisper Model...")
                .font(.headline)
                .foregroundColor(.white)

            if progress > 0 {
                ProgressView(value: progress, total: 1.0)
                    .frame(width: 200)
                    .tint(.blue)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Text("~500MB • First run only")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
    }
}

// Model warmup indicator
struct ModelWarmupIndicator: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

            Text("Optimizing for Neural Engine...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Compiling model for your Mac")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

            Text("~10 seconds • First run only")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
    }
}

// Visual indicator for speech-to-text status
struct SpeechStatusIndicator: View {
    let isRecording: Bool
    let isTranscribing: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.red, lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    )

                Text("Recording...")
                    .font(.caption)
                    .foregroundColor(.white)
            } else if isTranscribing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)

                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.75))
        .cornerRadius(20)
    }
}

#Preview {
    ContentView()
}

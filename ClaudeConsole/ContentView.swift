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
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "ContentView")

struct ContentView: View {
    // MARK: - Window Context (Multi-Instance Support)
    /// Per-window context for identity and input routing
    @StateObject private var windowContext = WindowContext()

    @StateObject private var usageMonitor = UsageMonitor()
    @StateObject private var contextMonitor = ContextMonitor()
    @StateObject private var gitMonitor = GitMonitor()

    // MARK: - Shared Resources (read from SharedResourceManager)
    private var sharedMonitor: PS4ControllerMonitor { SharedResourceManager.shared.ps4Monitor }
    private var sharedSpeechRecognition: SpeechRecognitionManager { SharedResourceManager.shared.speechRecognition }

    // MARK: - Per-Window Coordinators (accessed through WindowContext)
    private var speechCoordinator: SpeechToTextCoordinator { windowContext.speechCoordinator }
    private var ps4Coordinator: PS4ControllerCoordinator { windowContext.ps4Coordinator }
    @State private var terminalController: LocalProcessTerminalView?
    @State private var showPS4Controller = false
    @State private var useCompactStatusBar = false
    @State private var showPS4StatusBar = false  // Always starts hidden, no persistence
    @State private var isStreaming = false
    @State private var streamingDebounceTimer: Timer?

    // Project Launcher
    @State private var showProjectLauncher = false
    @State private var selectedProject: Project?
    @State private var hasLaunchedProject = false

    // CRITICAL FIX: Thread-safe subscription management
    // Using @State with Set<AnyCancellable> directly causes race conditions and crashes
    // because @State is not thread-safe for reference types.
    // This helper class wraps the cancellables with proper thread synchronization.
    private class SubscriptionManager {
        private let lock = NSLock()
        private var _cancellables = Set<AnyCancellable>()
        private var _notificationObservers: [NSObjectProtocol] = []

        var cancellables: Set<AnyCancellable> {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _cancellables
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _cancellables = newValue
            }
        }

        func insert(_ cancellable: AnyCancellable) {
            lock.lock()
            defer { lock.unlock() }
            _cancellables.insert(cancellable)
        }

        func addObserver(_ observer: NSObjectProtocol) {
            lock.lock()
            defer { lock.unlock() }
            _notificationObservers.append(observer)
        }

        func removeAll() {
            lock.lock()
            let observers = _notificationObservers
            _notificationObservers.removeAll()
            _cancellables.removeAll()
            lock.unlock()

            // Remove notification observers outside the lock
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    @State private var subscriptionManager = SubscriptionManager()

    init() {
        // Wire up dependencies after initialization
        _windowContext = StateObject(wrappedValue: WindowContext())
        _usageMonitor = StateObject(wrappedValue: UsageMonitor())
        _contextMonitor = StateObject(wrappedValue: ContextMonitor())
    }

    var body: some View {
        ZStack {
            // Fallout background
            Color.Fallout.background
                .ignoresSafeArea()

            // Window focus monitor for multi-instance input routing
            WindowFocusMonitor(windowContext: windowContext)
                .frame(width: 0, height: 0)

            VStack(spacing: 0) {
                // Fallout-style status bar at the very top
                FalloutStatusBar(
                    title: statusBarTitle,
                    modelTier: usageMonitor.modelTier,
                    gitBranch: gitMonitor.branchName,
                    gitIsDirty: gitMonitor.isDirty,
                    isGitRepo: gitMonitor.isGitRepo,
                    isStreaming: isStreaming
                )

                // PS4 Controller status bar (only when connected)
                if showPS4StatusBar && sharedMonitor.isConnected {
                    Group {
                        if useCompactStatusBar {
                            PS4ControllerMiniBar(
                                monitor: sharedMonitor,
                                mapping: ps4Coordinator.mapping
                            )
                        } else {
                            PS4ControllerStatusBar(
                                monitor: sharedMonitor,
                                mapping: ps4Coordinator.mapping
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
                    .frame(height: 50)
                    .background(Color.Fallout.backgroundAlt)

                Rectangle()
                    .fill(Color.Fallout.border)
                    .frame(height: 1)

                // Main content area with terminal and optional PS4 controller panel
                HStack(spacing: 0) {
                    // Terminal in the middle with speech-to-text overlay
                    ZStack(alignment: .top) {
                        TerminalView(
                            terminalController: $terminalController,
                            onOutput: { [weak contextMonitor] text in
                                // Forward terminal output directly to this window's ContextMonitor
                                contextMonitor?.receiveTerminalOutput(text)

                                // Streaming detection: strip ANSI codes then check length
                                // Keystroke echoes are 1-2 visible chars but padded with ANSI sequences
                                let stripped = text.replacingOccurrences(
                                    of: "\u{001B}\\[[0-9;?]*[a-zA-Z]",
                                    with: "",
                                    options: .regularExpression
                                )
                                if stripped.count > 10 {
                                    DispatchQueue.main.async {
                                        isStreaming = true
                                        streamingDebounceTimer?.invalidate()
                                        streamingDebounceTimer = Timer.scheduledTimer(
                                            withTimeInterval: 0.5,
                                            repeats: false
                                        ) { _ in
                                            isStreaming = false
                                        }
                                    }
                                }
                            },
                            onClaudeStarted: { [weak windowContext, weak usageMonitor] workingDir in
                                logger.info("onClaudeStarted fired with workingDir: \(workingDir)")
                                // Forward Claude started event to this window's context
                                windowContext?.receiveClaudeStarted(workingDirectory: workingDir)
                                // Detect model from session JSONL (delayed to let session file be created)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    let projectPath = selectedProject?.path.path
                                    usageMonitor?.detectModelFromSession(projectPath: projectPath)
                                    // If no project was selected via launcher, use workingDir as fallback for git
                                    if selectedProject == nil {
                                        logger.info("No project selected, using workingDir for git: \(workingDir)")
                                        gitMonitor.setWorkingDirectory(workingDir)
                                    }
                                }
                            }
                        )
                        .frame(minWidth: 600, minHeight: 400)

                    // Model preparation indicator (center)
                    if let step = sharedSpeechRecognition.preparationStep {
                        ModelPreparationIndicator(
                            currentStep: step,
                            downloadProgress: sharedSpeechRecognition.downloadProgress,
                            showDownloadStep: sharedSpeechRecognition.needsDownload
                        )
                    }

                    // Error banner (top)
                    if let error = speechCoordinator.currentError {
                        ErrorBanner(
                            error: error,
                            onDismiss: {
                                speechCoordinator.clearError()
                            },
                            onRetry: error.canRetry ? {
                                speechCoordinator.retryAfterError()
                            } : nil
                        )
                        .zIndex(100) // Ensure it appears above other content
                    }

                    // Speech-to-text status indicator (bottom-right) - Fallout style
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if speechCoordinator.isRecording || speechCoordinator.isTranscribing {
                                FalloutRecordingOverlay(
                                    isRecording: speechCoordinator.isRecording,
                                    isTranscribing: speechCoordinator.isTranscribing
                                )
                                .padding(16)
                            }
                        }
                    }
                    .allowsHitTesting(false)

                    // Radial menu overlay (full screen)
                    if ps4Coordinator.radialMenuController.isVisible {
                        RadialMenuView(controller: ps4Coordinator.radialMenuController)
                            .zIndex(50) // Below error banner, above terminal
                    }

                    // Profile switcher overlay (full screen)
                    if ps4Coordinator.profileSwitcherController.isVisible {
                        ProfileSwitcherView(controller: ps4Coordinator.profileSwitcherController)
                            .zIndex(51) // Above radial menu
                    }
                }

                    // PS4 Controller panel (collapsible)
                    if showPS4Controller {
                        Rectangle()
                            .fill(Color.Fallout.border)
                            .frame(width: 1)

                        PS4ControllerView(
                            monitor: sharedMonitor,
                            mapping: ps4Coordinator.mapping,
                            profileManager: ps4Coordinator.radialMenuController.profileManager
                        )
                        .frame(width: 400)
                        .background(Color.Fallout.backgroundPanel)
                    }
                }

                Rectangle()
                    .fill(Color.Fallout.border)
                    .frame(height: 1)

                // Context usage statistics with language toggle and PS4 toggle button
                HStack(spacing: 0) {
                    ContextStatsView(contextMonitor: contextMonitor)

                    Rectangle()
                        .fill(Color.Fallout.borderDim)
                        .frame(width: 1, height: 50)

                    // Speech language toggle buttons (per-window)
                    SpeechLanguageToggle(speechCoordinator: speechCoordinator)

                    Rectangle()
                        .fill(Color.Fallout.borderDim)
                        .frame(width: 1, height: 50)

                    // PS4 Controller toggle button - Fallout styled
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showPS4Controller.toggle()
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: sharedMonitor.isConnected ? "gamecontroller.fill" : "gamecontroller")
                                .font(.system(size: 22))
                                .foregroundColor(sharedMonitor.isConnected ? Color.Fallout.primary : Color.Fallout.tertiary)
                                .opacity(sharedMonitor.isConnected ? 1.0 : 0.4)
                                .falloutGlow(radius: sharedMonitor.isConnected ? 3 : 0)

                            // Battery indicator - always show, but disabled when not connected
                            PS4BatteryIndicator(
                                level: sharedMonitor.batteryLevel ?? 0,
                                state: sharedMonitor.batteryState,
                                isConnected: sharedMonitor.isConnected,
                                batteryIsUnavailable: sharedMonitor.batteryIsUnavailable
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 60)
                    .animation(.easeInOut(duration: 0.3), value: sharedMonitor.isConnected)
                    .help(batteryTooltip)
                    .onTapGesture(count: 2) {
                        // Double-tap to force battery check (for debugging)
                        print("ContentView: Manual battery check requested")
                        if let level = sharedMonitor.batteryLevel {
                            print("ContentView: Current battery level: \(level) (\(Int(level * 100))%)")
                            print("ContentView: Current battery state: \(sharedMonitor.batteryState)")
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
                            sharedMonitor.checkBatteryStatus()
                        }
                        .disabled(!sharedMonitor.isConnected)
                    }
                }
                .frame(height: 50)
                .background(Color.Fallout.backgroundAlt)
            }

            // CRT effects overlay
            CRTEffectsOverlay()
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: showPS4Controller ? 1000 : 800, minHeight: 600)
        .navigationTitle(windowTitle)
        .overlay {
            if showProjectLauncher {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    ProjectLauncherView(
                        ps4Monitor: sharedMonitor,
                        onProjectSelected: { project in
                            selectedProject = project
                            launchProject(project)
                            showProjectLauncher = false
                            // Focus the terminal so user can type immediately
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if let terminal = terminalController {
                                    terminal.window?.makeFirstResponder(terminal)
                                }
                            }
                        },
                        onSkip: {
                            selectedProject = nil
                            showProjectLauncher = false
                            // Focus the terminal after skipping launcher too
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if let terminal = terminalController {
                                    terminal.window?.makeFirstResponder(terminal)
                                }
                            }
                        }
                    )
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            // Show project launcher on first launch if enabled
            let settings = ProjectLauncherSettings.load()
            if settings.enableAutoLaunch && !hasLaunchedProject {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showProjectLauncher = true
                }
            }

            // CRITICAL FIX: Prevent duplicate subscriptions on multiple onAppear calls
            // onAppear can fire multiple times (view recreation, navigation), so we guard
            // against creating duplicate Combine subscriptions which cause memory leaks.
            guard subscriptionManager.cancellables.isEmpty else { return }

            // Note: Window focus detection is handled by WindowFocusMonitor background view

            // Wire up WindowContext terminal reference
            windowContext.terminalController = terminalController

            // Wire up ContextMonitor terminal reference for direct access
            contextMonitor.terminalController = terminalController

            // FIX: Wire up AppCommandExecutor dependencies for direct access
            // This replaces the previous NotificationCenter-based approach with direct references,
            // making the code more testable and eliminating hidden coupling.
            ps4Coordinator.appCommandExecutor.speechCoordinator = speechCoordinator
            ps4Coordinator.appCommandExecutor.terminalController = terminalController
            ps4Coordinator.appCommandExecutor.contextMonitor = contextMonitor

            // CRITICAL FIX: Sync UI state with AppCommandExecutor
            // ContentView @State is the source of truth - always starts hidden (no persistence)
            // AppCommandExecutor should mirror these values, not override them
            ps4Coordinator.appCommandExecutor.showPS4Panel = showPS4Controller
            ps4Coordinator.appCommandExecutor.showPS4StatusBar = showPS4StatusBar

            // FIX: Bidirectional binding with weak captures to prevent retain cycles
            // Observe AppCommandExecutor state changes and update local @State
            // Skip the first emission to avoid overriding initial @State values
            ps4Coordinator.appCommandExecutor.$showPS4Panel
                .dropFirst() // Skip initial value to preserve @State
                .receive(on: DispatchQueue.main)
                .sink { [weak subscriptionManager] newValue in
                    guard subscriptionManager != nil else { return }
                    showPS4Controller = newValue
                }
                .store(in: &subscriptionManager.cancellables)

            ps4Coordinator.appCommandExecutor.$showPS4StatusBar
                .dropFirst() // Skip initial value to preserve @State
                .receive(on: DispatchQueue.main)
                .sink { [weak subscriptionManager] newValue in
                    guard subscriptionManager != nil else { return }
                    showPS4StatusBar = newValue
                }
                .store(in: &subscriptionManager.cancellables)

            // Listen for app termination to cleanup sessions
            // Store observer token to prevent memory leaks
            let terminationObserver = NotificationCenter.default.addObserver(
                forName: .appWillTerminate,
                object: nil,
                queue: .main
            ) { [terminalController, usageMonitor, gitMonitor] _ in
                Self.performCleanup(terminal: terminalController, usageMonitor: usageMonitor, gitMonitor: gitMonitor)
            }
            subscriptionManager.addObserver(terminationObserver)
        }
        .onDisappear {
            // Clean up all subscriptions and observers when view disappears
            subscriptionManager.removeAll()
            streamingDebounceTimer?.invalidate()
            streamingDebounceTimer = nil
            gitMonitor.cleanup()
        }
        .onChange(of: terminalController) { _, newController in
            // FIX: Update AppCommandExecutor's terminal controller when it becomes available
            // Terminal controller is set asynchronously after view initialization via binding
            ps4Coordinator.appCommandExecutor.terminalController = newController

            // Update WindowContext's terminal controller for multi-instance support
            windowContext.terminalController = newController

            // Update ContextMonitor's terminal controller for direct access
            contextMonitor.terminalController = newController
        }
    }

    static func performCleanup(terminal: LocalProcessTerminalView?, usageMonitor: UsageMonitor, gitMonitor: GitMonitor? = nil) {
        logger.info("Cleaning up sessions...")

        // Send exit command to terminal if Claude is likely running
        // Note: This may fail if terminal is running a different program
        if let terminal = terminal {
            let exitCommand = "/exit \r"
            if let data = exitCommand.data(using: .utf8) {
                terminal.send(data: ArraySlice(data))
            }
        }

        // Cleanup monitors
        usageMonitor.cleanup()
        gitMonitor?.cleanup()

        logger.info("Session cleanup complete")
    }

    var batteryTooltip: String {
        return sharedMonitor.connectionStatusDescription
    }

    var projectName: String? {
        // First try selected project from launcher
        if let project = selectedProject {
            return project.path.lastPathComponent
        }
        // Fall back to detected working directory
        if let name = windowContext.projectFolderName, name != "/" {
            return name
        }
        return nil
    }

    var windowTitle: String {
        if let name = projectName {
            return "ClaudeConsole - \(name)"
        }
        return "ClaudeConsole"
    }

    var statusBarTitle: String {
        if let name = projectName {
            return "CLAUDE CONSOLE - \(name.uppercased())"
        }
        return "CLAUDE CONSOLE"
    }

    // MARK: - Project Launcher

    private func launchProject(_ project: Project) {
        hasLaunchedProject = true

        // Set git working directory immediately from the known project path
        let projectDir = project.path.path
        logger.info("Project selected: \(project.name) at \(projectDir)")
        gitMonitor.setWorkingDirectory(projectDir)

        // Wait for terminal to be ready
        guard let terminal = terminalController else {
            // Terminal not ready yet, schedule retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.launchProject(project)
            }
            return
        }

        // Navigate to project directory, clear screen, then launch claude in one command.
        // The clear wipes the cd + command text so the terminal starts clean like Terminal.app.
        // Leading space prevents the command from being saved in shell history.
        let command = " cd \"\(projectDir)\" && clear && claude\n"
        if let data = command.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }
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

// MARK: - Pip-Boy Spinner (replaces system ProgressView)

struct PipBoySpinner: View {
    let segmentCount: Int
    let size: CGFloat

    @State private var rotation: Double = 0
    @State private var glowPulse: Double = 0.5

    init(segmentCount: Int = 8, size: CGFloat = 40) {
        self.segmentCount = segmentCount
        self.size = size
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(Color.Fallout.primary.opacity(0.15 * glowPulse), lineWidth: size * 0.08)
                .frame(width: size * 1.2, height: size * 1.2)

            // Segmented spinner
            ForEach(0..<segmentCount, id: \.self) { index in
                let segmentAngle = 360.0 / Double(segmentCount)
                let opacity = Double(index + 1) / Double(segmentCount)

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.Fallout.primary.opacity(opacity))
                    .frame(width: size * 0.12, height: size * 0.32)
                    .offset(y: -size * 0.34)
                    .rotationEffect(.degrees(segmentAngle * Double(index)))
                    .shadow(color: Color.Fallout.glow.opacity(opacity * 0.6), radius: 2)
            }
            .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
        }
    }
}

// Model download indicator (center of terminal)
// Unified model preparation indicator with step-by-step progress
struct ModelPreparationIndicator: View {
    let currentStep: ModelPreparationStep
    let downloadProgress: Double
    let showDownloadStep: Bool

    @State private var dotCount = 0
    @State private var timer: Timer?

    private var paddedDots: String {
        let d = String(repeating: ".", count: dotCount)
        return d.padding(toLength: 3, withPad: " ", startingAt: 0)
    }

    private var visibleSteps: [ModelPreparationStep] {
        if showDownloadStep {
            return ModelPreparationStep.allCases
        } else {
            return ModelPreparationStep.allCases.filter { $0 != .downloading }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            PipBoySpinner(size: 44)

            Text("PREPARING WHISPER MODEL")
                .font(.Fallout.heading)
                .foregroundColor(Color.Fallout.primary)
                .tracking(2)
                .falloutGlow(radius: 4)

            FalloutDivider()
                .frame(width: 300)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleSteps, id: \.rawValue) { step in
                    stepRow(step)
                }
            }
            .frame(width: 320, alignment: .leading)

            // Show download progress bar when downloading
            if currentStep == .downloading && downloadProgress > 0 {
                FalloutProgressBar(
                    value: downloadProgress,
                    segments: 20,
                    showPercentage: true,
                    style: .normal
                )
                .frame(width: 300)
            }
        }
        .padding(32)
        .background(Color.Fallout.background.opacity(0.95))
        .overlay(
            BeveledRectangle(cornerSize: 12)
                .stroke(Color.Fallout.primary, lineWidth: 2)
        )
        .clipShape(BeveledRectangle(cornerSize: 12))
        .shadow(color: Color.Fallout.glow.opacity(0.3), radius: 20)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount % 3) + 1
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    @ViewBuilder
    private func stepRow(_ step: ModelPreparationStep) -> some View {
        let isActive = step == currentStep
        let isComplete = step.rawValue < currentStep.rawValue
        let isPending = step.rawValue > currentStep.rawValue

        HStack(spacing: 10) {
            // Status indicator
            if isComplete {
                Text("[OK]")
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.primary)
                    .frame(width: 50, alignment: .leading)
            } else if isActive {
                Text(">>\(paddedDots)")
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.primary)
                    .frame(width: 50, alignment: .leading)
            } else {
                Text("[  ]")
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.tertiary.opacity(0.5))
                    .frame(width: 50, alignment: .leading)
            }

            // Step info
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.Fallout.caption)
                    .foregroundColor(isActive ? Color.Fallout.primary : isComplete ? Color.Fallout.secondary : Color.Fallout.tertiary.opacity(0.5))
                    .tracking(1)
                    .falloutGlow(radius: isActive ? 3 : 0)

                Text(step.detail)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? Color.Fallout.secondary : isComplete ? Color.Fallout.tertiary : Color.Fallout.tertiary.opacity(0.3))
                    .tracking(0.5)
            }
        }
        .opacity(isPending ? 0.5 : 1.0)
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

// MARK: - Speech Language Toggle

/// Fallout-styled language toggle buttons for speech recognition (per-window)
struct SpeechLanguageToggle: View {
    @ObservedObject var speechCoordinator: SpeechToTextCoordinator

    var body: some View {
        HStack(spacing: 0) {
            // English button
            LanguageButton(
                language: .english,
                isSelected: speechCoordinator.speechLanguage == .english
            ) {
                speechCoordinator.speechLanguage = .english
            }

            // Divider between buttons
            Rectangle()
                .fill(Color.Fallout.borderDim)
                .frame(width: 1, height: 30)

            // Dutch button
            LanguageButton(
                language: .dutch,
                isSelected: speechCoordinator.speechLanguage == .dutch
            ) {
                speechCoordinator.speechLanguage = .dutch
            }
        }
        .frame(width: 100)
        .help("Speech recognition language (per window)")
    }
}

/// Individual language button
struct LanguageButton: View {
    let language: SpeechLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(language.flag)
                    .font(.system(size: 16))

                Text(language.shortName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .foregroundColor(isSelected ? Color.Fallout.primary : Color.Fallout.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isSelected ? Color.Fallout.primary.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .falloutGlow(radius: isSelected ? 2 : 0)
    }
}

// MARK: - Window Focus Monitor

/// NSViewRepresentable that monitors window focus changes for a specific window
/// Used for multi-instance support to route hardware input to the correct window
struct WindowFocusMonitor: NSViewRepresentable {
    let windowContext: WindowContext

    func makeNSView(context: Context) -> NSView {
        let view = WindowFocusMonitorView()
        view.windowContext = windowContext
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowFocusMonitorView {
            view.windowContext = windowContext
        }
    }

    class WindowFocusMonitorView: NSView {
        weak var windowContext: WindowContext?
        private var becameKeyObserver: NSObjectProtocol?
        private var resignedKeyObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            // Clean up old observers
            if let observer = becameKeyObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = resignedKeyObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            guard let window = self.window else { return }

            // Observe this specific window becoming key
            becameKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.windowContext?.windowBecameKey()
            }

            // Observe this specific window resigning key
            resignedKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.windowContext?.windowResignedKey()
            }

            // If this window is already key, notify immediately
            if window.isKeyWindow {
                windowContext?.windowBecameKey()
            }
        }

        deinit {
            if let observer = becameKeyObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = resignedKeyObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

#Preview {
    ContentView()
}

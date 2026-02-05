//
//  ProjectLauncherView.swift
//  ClaudeConsole
//
//  Fallout Pip-Boy themed project selector modal
//

import SwiftUI
import GameController
import Combine

struct ProjectLauncherView: View {
    @StateObject private var controller = ProjectLauncherController()
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @ObservedObject var ps4Monitor: PS4ControllerMonitor
    @State private var lastAnalogValue: Float = 0
    @State private var canNavigate = true
    @State private var cancellables = Set<AnyCancellable>()
    @State private var originalButtonHandler: ((PS4Button) -> Void)?

    // CRT power-on animation
    @State private var crtPowerOn = false

    // Title glow pulse
    @State private var titleGlowRadius: CGFloat = 2

    let onProjectSelected: (Project) -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // Full background
            Color.Fallout.background
                .ignoresSafeArea()

            // Main content wrapped in fallout frame
            VStack(spacing: 0) {
                // Header
                headerSection

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Search bar
                searchBarSection

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Project list
                projectListSection

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Footer
                footerSection
            }
            .falloutFrame(title: "PROJECT DIRECTORY", corners: .beveled)

            // CRT effects overlay (lighter for modal)
            ZStack {
                ScanlineOverlay(lineOpacity: 0.15)
                VignetteOverlay(intensity: 0.4)
            }
            .allowsHitTesting(false)
        }
        .frame(width: 700, height: 600)
        // CRT power-on animation
        .scaleEffect(x: 1.0, y: crtPowerOn ? 1.0 : 0.02)
        .opacity(crtPowerOn ? 1.0 : 0.5)
        .task {
            if controller.projects.isEmpty {
                await controller.scanProjects()
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsView(settings: $controller.settings)
        }
        .onKeyPress(.return) {
            if let project = controller.selectedProject {
                controller.selectProject(project)
                onProjectSelected(project)
                dismiss()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            navigateUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateDown()
            return .handled
        }
        .onChange(of: controller.searchText) { _, _ in
            // Auto-select top result when search text changes
            controller.selectedProject = controller.filteredProjects.first
        }
        .onAppear {
            setupPS4Controller()
            // Trigger CRT power-on animation
            withAnimation(.easeOut(duration: 0.3)) {
                crtPowerOn = true
            }
            // Start title glow pulse
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                titleGlowRadius = 5
            }
        }
        .onDisappear {
            cleanupPS4Controller()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROBCO INDUSTRIES (TM) PROJECT SELECTOR")
                        .font(.Fallout.subheading)
                        .foregroundColor(Color.Fallout.primary)
                        .tracking(2)
                        .falloutGlow(radius: titleGlowRadius)

                    Text("SELECT TARGET DIRECTORY")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.secondary)
                        .tracking(3)
                }

                Spacer()

                Button(action: { showSettings = true }) {
                    Text("[CONFIG]")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search Bar Section

    private var searchBarSection: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.Fallout.body)
                .foregroundColor(Color.Fallout.primary)
                .falloutGlow(radius: 2)

            TextField("ENTER SEARCH QUERY...", text: $controller.searchText)
                .textFieldStyle(.plain)
                .font(.Fallout.body)
                .foregroundColor(Color.Fallout.primary)
                .tint(Color.Fallout.primary)

            if !controller.searchText.isEmpty {
                Button(action: { controller.searchText = "" }) {
                    Text("[CLR]")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.Fallout.background)
        .clipShape(BeveledRectangle(cornerSize: 4))
        .overlay(
            BeveledRectangle(cornerSize: 4)
                .stroke(Color.Fallout.borderDim, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Project List Section

    private var projectListSection: some View {
        Group {
            if controller.isScanning {
                VStack(spacing: 16) {
                    ProcessingIndicator()

                    Text("SCANNING DIRECTORIES...")
                        .font(.Fallout.body)
                        .foregroundColor(Color.Fallout.primary)
                        .tracking(2)
                        .falloutGlow(radius: 2)

                    Text("LOCATING CLAUDE.MD FILES")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.filteredProjects.isEmpty {
                VStack(spacing: 16) {
                    Text("[!]")
                        .font(.Fallout.title)
                        .foregroundColor(Color.Fallout.warning)
                        .falloutGlow(color: Color.Fallout.warning, radius: 4)

                    Text("NO ENTRIES FOUND")
                        .font(.Fallout.heading)
                        .foregroundColor(Color.Fallout.warning)
                        .tracking(2)

                    Text("DIRECTORIES MUST CONTAIN CLAUDE.MD")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)

                    FalloutDivider()
                        .frame(width: 200)

                    Button("RESCAN") {
                        Task {
                            await controller.refreshProjects()
                        }
                    }
                    .buttonStyle(.fallout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Entry count
                    HStack {
                        if controller.searchText.isEmpty {
                            Text("FOUND \(controller.filteredProjects.count) ENTRIES")
                                .font(.Fallout.caption)
                                .foregroundColor(Color.Fallout.tertiary)
                                .tracking(2)
                        } else {
                            Text("SHOWING \(controller.filteredProjects.count) OF \(controller.projects.count) ENTRIES")
                                .font(.Fallout.caption)
                                .foregroundColor(Color.Fallout.tertiary)
                                .tracking(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(controller.filteredProjects.enumerated()), id: \.element.id) { index, project in
                                    ProjectRow(
                                        project: project,
                                        isSelected: controller.selectedProject?.id == project.id,
                                        index: index
                                    )
                                    .id(project.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        controller.selectProject(project)
                                        onProjectSelected(project)
                                        dismiss()
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: controller.selectedProject?.id) { _, newId in
                            if let id = newId {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            Button("RESCAN") {
                Task {
                    await controller.refreshProjects()
                }
            }
            .buttonStyle(.fallout)
            .disabled(controller.isScanning)

            Spacer()

            if ps4Monitor.isConnected {
                Text("D-PAD: NAVIGATE | R2: SELECT | ESC: SKIP")
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.tertiary)
                    .tracking(1)
            } else {
                Text("ARROWS: NAVIGATE | ENTER: SELECT | ESC: SKIP")
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.tertiary)
                    .tracking(1)
            }

            Spacer()

            Button("SKIP") {
                controller.skipLauncher()
                onSkip()
                dismiss()
            }
            .buttonStyle(.fallout)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - PS4 Controller Support

    private func setupPS4Controller() {
        // Save the original button handler
        originalButtonHandler = ps4Monitor.onButtonPressed

        // Temporarily override with launcher-specific behavior
        ps4Monitor.onButtonPressed = { [originalButtonHandler] button in
            switch button {
            case .r2:
                // R2 trigger launches the selected project
                launchSelectedProject()
            case .dpadUp:
                // D-pad up navigates up in the project list
                navigateUp()
            case .dpadDown:
                // D-pad down navigates down in the project list
                navigateDown()
            case .dpadLeft, .dpadRight:
                // D-pad left/right could be used for page navigation in future
                break
            default:
                // Pass through other buttons to original handler
                originalButtonHandler?(button)
            }
        }

        // Observe left analog stick Y-axis for up/down navigation
        ps4Monitor.$leftStickY
            .removeDuplicates()
            .sink { [self] yValue in
                handleAnalogNavigation(yValue: yValue)
            }
            .store(in: &cancellables)
    }

    private func cleanupPS4Controller() {
        // Restore the original button press handler
        ps4Monitor.onButtonPressed = originalButtonHandler

        // Cancel all subscriptions
        cancellables.removeAll()
    }

    private func handleAnalogNavigation(yValue: Float) {
        let deadzone: Float = 0.3

        // Debounce navigation to prevent too-rapid scrolling
        guard canNavigate else { return }

        // Check if stick moved past deadzone
        if abs(yValue) > deadzone {
            // Determine direction (negative Y = down in list, positive Y = up in list)
            // Inverted to match natural stick movement
            if yValue < -deadzone && lastAnalogValue >= -deadzone {
                // Stick pushed down -> navigate down
                navigateDown()
                canNavigate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    canNavigate = true
                }
            } else if yValue > deadzone && lastAnalogValue <= deadzone {
                // Stick pushed up -> navigate up
                navigateUp()
                canNavigate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    canNavigate = true
                }
            }
        }

        lastAnalogValue = yValue
    }

    private func navigateUp() {
        let projects = controller.filteredProjects
        guard !projects.isEmpty else { return }

        if let currentProject = controller.selectedProject,
           let currentIndex = projects.firstIndex(where: { $0.id == currentProject.id }) {
            // Move to previous project
            if currentIndex > 0 {
                controller.selectedProject = projects[currentIndex - 1]
            }
        } else {
            // No selection, select first
            controller.selectedProject = projects.first
        }
    }

    private func navigateDown() {
        let projects = controller.filteredProjects
        guard !projects.isEmpty else { return }

        if let currentProject = controller.selectedProject,
           let currentIndex = projects.firstIndex(where: { $0.id == currentProject.id }) {
            // Move to next project
            if currentIndex < projects.count - 1 {
                controller.selectedProject = projects[currentIndex + 1]
            }
        } else {
            // No selection, select first
            controller.selectedProject = projects.first
        }
    }

    private func launchSelectedProject() {
        if let project = controller.selectedProject {
            controller.selectProject(project)
            onProjectSelected(project)
            dismiss()
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    let index: Int

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Index number
            Text(String(format: "%02d.", index + 1))
                .font(.Fallout.caption)
                .foregroundColor(Color.Fallout.tertiary)
                .frame(width: 28, alignment: .leading)

            // Folder icon
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? Color.Fallout.primary : Color.Fallout.secondary)
                .frame(width: 20)

            // Project name and path
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(project.name.uppercased())
                        .font(.Fallout.body)
                        .foregroundColor(isSelected ? Color.Fallout.primary : Color.Fallout.secondary)
                        .tracking(0.5)

                    if let branch = project.gitBranch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.branch")
                                .font(.system(size: 10))
                            Text(branch)
                                .font(.Fallout.caption)
                        }
                        .foregroundColor(Color.Fallout.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.Fallout.primary.opacity(0.08)
                        )
                        .clipShape(BeveledRectangle(cornerSize: 3))
                        .overlay(
                            BeveledRectangle(cornerSize: 3)
                                .stroke(Color.Fallout.borderDim, lineWidth: 0.5)
                        )
                    }
                }

                Text(project.path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Modified date
            Text(formatDate(project.lastModified).uppercased())
                .font(.Fallout.caption)
                .foregroundColor(Color.Fallout.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                // Selection / hover background
                if isSelected {
                    Color.Fallout.primary.opacity(0.15)
                } else if isHovered {
                    Color.Fallout.primary.opacity(0.05)
                } else {
                    Color.clear
                }

                // Left green selection bar
                if isSelected {
                    Rectangle()
                        .fill(Color.Fallout.primary)
                        .frame(width: 3)
                        .falloutGlow(radius: 3)
                }
            }
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Settings View

struct ProjectSettingsView: View {
    @Binding var settings: ProjectLauncherSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.Fallout.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("SYSTEM CONFIGURATION")
                    .font(.Fallout.heading)
                    .foregroundColor(Color.Fallout.primary)
                    .tracking(2)
                    .falloutGlow(radius: 3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Search Paths Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("SEARCH PATHS")
                        .font(.Fallout.subheading)
                        .foregroundColor(Color.Fallout.secondary)
                        .tracking(2)

                    Text("DIRECTORIES TO SCAN FOR CLAUDE.MD FILES")
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.tertiary)

                    ForEach(Array(settings.searchPaths.enumerated()), id: \.offset) { index, _ in
                        HStack(spacing: 8) {
                            Text(">")
                                .font(.Fallout.body)
                                .foregroundColor(Color.Fallout.primary)
                                .falloutGlow(radius: 2)

                            TextField("PATH", text: Binding(
                                get: { settings.searchPaths[index] },
                                set: { settings.searchPaths[index] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.Fallout.body)
                            .foregroundColor(Color.Fallout.primary)
                            .tint(Color.Fallout.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.Fallout.background)
                        .clipShape(BeveledRectangle(cornerSize: 4))
                        .overlay(
                            BeveledRectangle(cornerSize: 4)
                                .stroke(Color.Fallout.borderDim, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("PARAMETERS")
                        .font(.Fallout.subheading)
                        .foregroundColor(Color.Fallout.secondary)
                        .tracking(2)

                    HStack {
                        Text("MAX DEPTH")
                            .font(.Fallout.body)
                            .foregroundColor(Color.Fallout.secondary)

                        Spacer()

                        HStack(spacing: 8) {
                            Text("\(settings.maxDepth)")
                                .font(.Fallout.stats)
                                .foregroundColor(Color.Fallout.primary)

                            Stepper("", value: $settings.maxDepth, in: 1...10)
                                .labelsHidden()
                        }
                    }

                    HStack {
                        Text("CACHE EXPIRATION")
                            .font(.Fallout.body)
                            .foregroundColor(Color.Fallout.secondary)

                        Spacer()

                        HStack(spacing: 8) {
                            Text("\(settings.cacheExpirationMinutes) MIN")
                                .font(.Fallout.stats)
                                .foregroundColor(Color.Fallout.primary)

                            Stepper("", value: $settings.cacheExpirationMinutes, in: 1...60)
                                .labelsHidden()
                        }
                    }

                    HStack {
                        Text("ENABLE AUTO-LAUNCH")
                            .font(.Fallout.body)
                            .foregroundColor(Color.Fallout.secondary)

                        Spacer()

                        Toggle("", isOn: $settings.enableAutoLaunch)
                            .labelsHidden()
                            .tint(Color.Fallout.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer()

                FalloutDivider()
                    .padding(.horizontal, 16)

                // Footer buttons
                HStack {
                    Spacer()

                    Button("CANCEL") {
                        dismiss()
                    }
                    .buttonStyle(.fallout)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button("SAVE") {
                        settings.save()
                        dismiss()
                    }
                    .buttonStyle(.fallout)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .falloutFrame(title: "CONFIGURATION", corners: .beveled)

            // CRT effects overlay
            ZStack {
                ScanlineOverlay(lineOpacity: 0.15)
                VignetteOverlay(intensity: 0.4)
            }
            .allowsHitTesting(false)
        }
        .frame(width: 500, height: 580)
    }
}

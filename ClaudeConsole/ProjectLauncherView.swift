//
//  ProjectLauncherView.swift
//  ClaudeConsole
//
//  SwiftUI modal for selecting Claude projects
//

import SwiftUI
import GameController
import Combine

struct ProjectLauncherView: View {
    @StateObject private var controller = ProjectLauncherController()
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @StateObject private var ps4Monitor = PS4ControllerMonitor()
    @State private var lastAnalogValue: Float = 0
    @State private var canNavigate = true
    @State private var cancellables = Set<AnyCancellable>()

    let onProjectSelected: (Project) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Claude Project")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search projects...", text: $controller.searchText)
                    .textFieldStyle(.plain)

                if !controller.searchText.isEmpty {
                    Button(action: { controller.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            // Project list
            if controller.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Scanning for projects...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.filteredProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No projects found")
                        .font(.title3)

                    Text("Projects must contain a CLAUDE.md file")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Refresh") {
                        Task {
                            await controller.refreshProjects()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.filteredProjects) { project in
                            ProjectRow(
                                project: project,
                                isSelected: controller.selectedProject?.id == project.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Clicking a project launches it immediately
                                controller.selectProject(project)
                                onProjectSelected(project)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Refresh") {
                    Task {
                        await controller.refreshProjects()
                    }
                }
                .disabled(controller.isScanning)

                Spacer()

                Button("Skip") {
                    controller.skipLauncher()
                    onSkip()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
        }
        .frame(width: 700, height: 600)
        .task {
            if controller.projects.isEmpty {
                await controller.scanProjects()
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsView(settings: $controller.settings)
        }
        .onKeyPress(.return) {
            // Enter key launches selected project
            if let project = controller.selectedProject {
                controller.selectProject(project)
                onProjectSelected(project)
                dismiss()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            setupPS4Controller()
        }
    }

    // MARK: - PS4 Controller Support

    private func setupPS4Controller() {
        // Handle R2 trigger (launch project)
        ps4Monitor.onButtonPressed = { button in
            if button == .r2 {
                launchSelectedProject()
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

    private func handleAnalogNavigation(yValue: Float) {
        let deadzone: Float = 0.3

        // Debounce navigation to prevent too-rapid scrolling
        guard canNavigate else { return }

        // Check if stick moved past deadzone
        if abs(yValue) > deadzone {
            // Determine direction (negative Y = up, positive Y = down)
            if yValue < -deadzone && lastAnalogValue >= -deadzone {
                // Moving up
                navigateUp()
                canNavigate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    canNavigate = true
                }
            } else if yValue > deadzone && lastAnalogValue <= deadzone {
                // Moving down
                navigateDown()
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

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.headline)

                    if let branch = project.gitBranch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.branch")
                                .font(.caption)
                            Text(branch)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Text(project.path.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(formatDate(project.lastModified))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Modified " + formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ProjectSettingsView: View {
    @Binding var settings: ProjectLauncherSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Project Launcher Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Search Paths") {
                    Text("Directories to scan for CLAUDE.md files")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(settings.searchPaths.enumerated()), id: \.offset) { index, path in
                        TextField("Path", text: Binding(
                            get: { settings.searchPaths[index] },
                            set: { settings.searchPaths[index] = $0 }
                        ))
                    }
                }

                Section("Settings") {
                    HStack {
                        Text("Max Depth")
                        Spacer()
                        Stepper("\(settings.maxDepth)", value: $settings.maxDepth, in: 1...10)
                    }

                    HStack {
                        Text("Cache Expiration")
                        Spacer()
                        Stepper("\(settings.cacheExpirationMinutes) min", value: $settings.cacheExpirationMinutes, in: 1...60)
                    }

                    Toggle("Enable Auto-Launch", isOn: $settings.enableAutoLaunch)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    settings.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
}

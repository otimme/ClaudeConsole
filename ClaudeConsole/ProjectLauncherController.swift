//
//  ProjectLauncherController.swift
//  ClaudeConsole
//
//  State management for project launcher
//

import Foundation
import Combine

@MainActor
class ProjectLauncherController: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isScanning: Bool = false
    @Published var searchText: String = ""
    @Published var selectedProject: Project?
    @Published var settings: ProjectLauncherSettings

    private let scanner: ProjectScanner
    private let cache = ProjectCache.self

    init() {
        let loadedSettings = ProjectLauncherSettings.load()
        self.settings = loadedSettings
        self.scanner = ProjectScanner(settings: loadedSettings)

        // Try to load from cache first
        if let cachedProjects = cache.load(expirationMinutes: settings.cacheExpirationMinutes) {
            self.projects = cachedProjects

            // Pre-select the most recently modified project (first in filtered list)
            if let firstProject = filteredProjects.first {
                selectedProject = firstProject
            }
        }
    }

    /// Filtered projects based on search text, sorted by latest modified date
    var filteredProjects: [Project] {
        let filtered: [Project]

        if searchText.isEmpty {
            filtered = projects
        } else {
            filtered = projects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText) ||
                project.path.path.localizedCaseInsensitiveContains(searchText) ||
                project.parentPath.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by modified date, newest first
        return filtered.sorted { $0.lastModified > $1.lastModified }
    }

    /// Scans for projects (or loads from cache)
    func scanProjects() async {
        isScanning = true

        let scannedProjects = await scanner.scanForProjects()
        projects = scannedProjects

        // Save to cache
        cache.save(projects: scannedProjects)

        // Pre-select the most recently modified project (first in filtered list)
        if let firstProject = filteredProjects.first {
            selectedProject = firstProject
        }

        isScanning = false
    }

    /// Forces a rescan, ignoring cache
    func refreshProjects() async {
        cache.clear()
        await scanProjects()
    }

    /// Selects a project and saves preference
    func selectProject(_ project: Project) {
        selectedProject = project
        settings.lastSelectedProjectId = project.id
        settings.save()
    }

    /// Clears selection
    func skipLauncher() {
        selectedProject = nil
        settings.lastSelectedProjectId = nil
        settings.save()
    }
}

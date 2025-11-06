//
//  ProjectScanner.swift
//  ClaudeConsole
//
//  Scans directories for CLAUDE.md files to detect Claude-enabled projects
//

import Foundation

class ProjectScanner {
    private let fileManager = FileManager.default
    private let settings: ProjectLauncherSettings

    init(settings: ProjectLauncherSettings = .load()) {
        self.settings = settings
    }

    /// Scans for projects asynchronously
    func scanForProjects() async -> [Project] {
        var allProjects: [Project] = []

        for pathString in settings.searchPaths {
            // Expand tilde to home directory
            let expandedPath = NSString(string: pathString).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)

            // Check if directory exists
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let projects = await scanDirectory(url, currentDepth: 0, maxDepth: settings.maxDepth)
            allProjects.append(contentsOf: projects)
        }

        // Sort by parent path, then by modified date (newest first)
        return allProjects.sorted { p1, p2 in
            if p1.parentPath != p2.parentPath {
                return p1.parentPath < p2.parentPath
            }
            return p1.lastModified > p2.lastModified
        }
    }

    /// Recursively scans a directory for CLAUDE.md files
    private func scanDirectory(_ url: URL, currentDepth: Int, maxDepth: Int) async -> [Project] {
        guard currentDepth <= maxDepth else {
            return []
        }

        var projects: [Project] = []

        // Check if this directory should be excluded
        let directoryName = url.lastPathComponent
        if settings.excludePatterns.contains(directoryName) {
            return []
        }

        // Check if this directory contains CLAUDE.md
        let claudeMdPath = url.appendingPathComponent("CLAUDE.md")
        if fileManager.fileExists(atPath: claudeMdPath.path) {
            if let project = createProject(from: url, claudeMdPath: claudeMdPath) {
                projects.append(project)
            }
        }

        // Scan subdirectories
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                // Check if it's a directory
                guard let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    continue
                }

                // Recursively scan subdirectory
                let subProjects = await scanDirectory(item, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                projects.append(contentsOf: subProjects)
            }
        } catch {
            // Ignore permission errors or other issues
            return projects
        }

        return projects
    }

    /// Creates a Project from a directory containing CLAUDE.md
    private func createProject(from url: URL, claudeMdPath: URL) -> Project? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: claudeMdPath.path)
            let modifiedDate = attributes[.modificationDate] as? Date ?? Date()

            let name = url.lastPathComponent
            let parentPath = url.deletingLastPathComponent().path

            // Try to get git branch if in a git repository
            let gitBranch = getGitBranch(for: url)

            return Project(
                name: name,
                path: url,
                claudeMdPath: claudeMdPath,
                lastModified: modifiedDate,
                parentPath: parentPath,
                gitBranch: gitBranch
            )
        } catch {
            return nil
        }
    }

    /// Gets the current git branch for a directory (if it's a git repo)
    private func getGitBranch(for url: URL) -> String? {
        let gitHeadPath = url.appendingPathComponent(".git/HEAD")

        guard fileManager.fileExists(atPath: gitHeadPath.path),
              let headContent = try? String(contentsOf: gitHeadPath, encoding: .utf8) else {
            return nil
        }

        // Parse "ref: refs/heads/main" format
        if headContent.hasPrefix("ref: refs/heads/") {
            let branch = headContent
                .replacingOccurrences(of: "ref: refs/heads/", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return branch
        }

        return nil
    }
}

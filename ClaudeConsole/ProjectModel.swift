//
//  ProjectModel.swift
//  ClaudeConsole
//
//  Data model for Claude-enabled projects
//

import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let claudeMdPath: URL
    let lastModified: Date
    let parentPath: String
    var gitBranch: String?

    init(name: String, path: URL, claudeMdPath: URL, lastModified: Date, parentPath: String, gitBranch: String? = nil) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.claudeMdPath = claudeMdPath
        self.lastModified = lastModified
        self.parentPath = parentPath
        self.gitBranch = gitBranch
    }

    // Custom coding keys to handle URL encoding
    enum CodingKeys: String, CodingKey {
        case id, name, lastModified, parentPath, gitBranch
        case pathString, claudeMdPathString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        parentPath = try container.decode(String.self, forKey: .parentPath)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)

        let pathString = try container.decode(String.self, forKey: .pathString)
        let claudeMdPathString = try container.decode(String.self, forKey: .claudeMdPathString)

        path = URL(fileURLWithPath: pathString)
        claudeMdPath = URL(fileURLWithPath: claudeMdPathString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(parentPath, forKey: .parentPath)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encode(path.path, forKey: .pathString)
        try container.encode(claudeMdPath.path, forKey: .claudeMdPathString)
    }
}

struct ProjectLauncherSettings: Codable {
    var searchPaths: [String] = [
        "~/Documents/Projects",
        "~/Code",
        "~/Development"
    ]
    var maxDepth: Int = 3
    var enableAutoLaunch: Bool = true
    var excludePatterns: [String] = [
        "node_modules",
        ".git",
        "venv",
        "__pycache__",
        ".build",
        "build",
        "Pods"
    ]
    var cacheExpirationMinutes: Int = 5
    var lastSelectedProjectId: UUID?

    static let userDefaultsKey = "projectLauncherSettings"

    static func load() -> ProjectLauncherSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(ProjectLauncherSettings.self, from: data) else {
            return ProjectLauncherSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ProjectLauncherSettings.userDefaultsKey)
        }
    }
}

//
//  ProjectCache.swift
//  ClaudeConsole
//
//  Caching for project scan results with expiration
//

import Foundation

class ProjectCache {
    private static let cacheKey = "cachedProjects"
    private static let timestampKey = "cachedProjectsTimestamp"

    /// Saves projects to cache
    static func save(projects: [Project]) {
        if let encoded = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: timestampKey)
        }
    }

    /// Loads projects from cache if not expired
    static func load(expirationMinutes: Int = 5) -> [Project]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let timestamp = UserDefaults.standard.object(forKey: timestampKey) as? Date else {
            return nil
        }

        // Check if cache is expired
        let expirationInterval = TimeInterval(expirationMinutes * 60)
        if Date().timeIntervalSince(timestamp) > expirationInterval {
            return nil
        }

        // Decode projects
        return try? JSONDecoder().decode([Project].self, from: data)
    }

    /// Clears the cache
    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
    }
}

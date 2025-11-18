//
//  RadialMenuProfileManager.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import Foundation
import Combine

/// Manages radial menu profiles with UserDefaults persistence
class RadialMenuProfileManager: ObservableObject {
    // MARK: - Published Properties

    /// Currently active profile
    @Published var activeProfile: RadialMenuProfile {
        didSet {
            saveActiveProfile()
        }
    }

    /// All available profiles (defaults + custom)
    @Published var profiles: [RadialMenuProfile] {
        didSet {
            saveProfiles()
        }
    }

    // MARK: - UserDefaults Keys

    private let profilesKey = "radialMenuProfiles"
    private let activeProfileIDKey = "radialMenuActiveProfileID"

    // MARK: - Initialization

    init() {
        // Load saved profiles or use defaults
        let loadedProfiles: [RadialMenuProfile]
        if let savedProfiles = Self.loadProfilesFromUserDefaults(), !savedProfiles.isEmpty {
            loadedProfiles = savedProfiles
        } else {
            loadedProfiles = RadialMenuProfile.allDefaults
        }
        self.profiles = loadedProfiles

        // Load active profile or use first default
        let activeID = UserDefaults.standard.string(forKey: activeProfileIDKey)
        if let activeID = activeID,
           let profile = loadedProfiles.first(where: { $0.id.uuidString == activeID }) {
            self.activeProfile = profile
        } else {
            self.activeProfile = loadedProfiles.first ?? .defaultProfile
        }
    }

    // MARK: - Profile Management

    /// Switch to a different profile
    func selectProfile(_ profile: RadialMenuProfile) {
        // Update in profiles array if it exists
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
        activeProfile = profile
    }

    /// Add a new custom profile
    func addProfile(_ profile: RadialMenuProfile) {
        profiles.append(profile)
    }

    /// Update an existing profile
    func updateProfile(_ profile: RadialMenuProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            // If this is the active profile, update it too
            if activeProfile.id == profile.id {
                activeProfile = profile
            }
        }
    }

    /// Delete a profile
    func deleteProfile(_ profile: RadialMenuProfile) {
        profiles.removeAll { $0.id == profile.id }
        // If we deleted the active profile, switch to first available
        if activeProfile.id == profile.id, let first = profiles.first {
            activeProfile = first
        }
    }

    /// Reset to default profiles
    func resetToDefaults() {
        profiles = RadialMenuProfile.allDefaults
        activeProfile = .defaultProfile
    }

    // MARK: - Persistence

    private func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: profilesKey)
            // Force synchronization for release builds
            UserDefaults.standard.synchronize()
        } catch {
            print("RadialMenuProfileManager: Failed to save profiles: \(error)")
        }
    }

    private func saveActiveProfile() {
        UserDefaults.standard.set(activeProfile.id.uuidString, forKey: activeProfileIDKey)
        // Force synchronization for release builds
        UserDefaults.standard.synchronize()
    }

    private static func loadProfilesFromUserDefaults() -> [RadialMenuProfile]? {
        guard let data = UserDefaults.standard.data(forKey: "radialMenuProfiles") else { return nil }
        return try? JSONDecoder().decode([RadialMenuProfile].self, from: data)
    }

    // MARK: - Import/Export

    /// Export profile to JSON string
    func exportProfile(_ profile: RadialMenuProfile) -> String? {
        guard let data = try? JSONEncoder().encode(profile) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import profile from JSON string
    func importProfile(from jsonString: String) -> RadialMenuProfile? {
        guard let data = jsonString.data(using: .utf8),
              let profile = try? JSONDecoder().decode(RadialMenuProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    /// Export all profiles to JSON
    func exportAllProfiles() -> String? {
        guard let data = try? JSONEncoder().encode(profiles) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import profiles from JSON (replaces all)
    func importProfiles(from jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let importedProfiles = try? JSONDecoder().decode([RadialMenuProfile].self, from: data),
              !importedProfiles.isEmpty else {
            return false
        }
        profiles = importedProfiles
        activeProfile = importedProfiles.first ?? .defaultProfile
        // Persist the imported profiles immediately
        saveProfiles()
        saveActiveProfile()
        return true
    }
}

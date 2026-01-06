//
//  SpeechLanguageSettings.swift
//  ClaudeConsole
//
//  Language settings for WhisperKit speech-to-text
//

import Foundation
import SwiftUI

// MARK: - Speech Language

/// Supported languages for speech recognition
enum SpeechLanguage: String, CaseIterable, Codable {
    case english = "en"
    case dutch = "nl"

    /// Display name for the language
    var displayName: String {
        switch self {
        case .english: return "English"
        case .dutch: return "Nederlands"
        }
    }

    /// Short display name for compact UI
    var shortName: String {
        switch self {
        case .english: return "EN"
        case .dutch: return "NL"
        }
    }

    /// Flag emoji for visual identification
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .dutch: return "🇳🇱"
        }
    }
}

// MARK: - Speech Language Settings Manager

/// Manages speech language settings with UserDefaults persistence
class SpeechLanguageManager: ObservableObject {
    static let shared = SpeechLanguageManager()

    private let languageKey = "speechRecognitionLanguage"

    @Published var currentLanguage: SpeechLanguage {
        didSet {
            saveLanguage()
            NotificationCenter.default.post(
                name: .speechLanguageDidChange,
                object: nil,
                userInfo: ["language": currentLanguage]
            )
        }
    }

    private init() {
        // Load saved language or default to English
        if let savedValue = UserDefaults.standard.string(forKey: languageKey),
           let language = SpeechLanguage(rawValue: savedValue) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .english
        }
    }

    private func saveLanguage() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
    }

    /// Toggle between available languages
    func toggleLanguage() {
        switch currentLanguage {
        case .english:
            currentLanguage = .dutch
        case .dutch:
            currentLanguage = .english
        }
    }

    /// Set a specific language
    func setLanguage(_ language: SpeechLanguage) {
        currentLanguage = language
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let speechLanguageDidChange = Notification.Name("speechLanguageDidChange")
}

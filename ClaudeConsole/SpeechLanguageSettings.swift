//
//  SpeechLanguageSettings.swift
//  ClaudeConsole
//
//  Language settings for WhisperKit speech-to-text
//

import Foundation

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

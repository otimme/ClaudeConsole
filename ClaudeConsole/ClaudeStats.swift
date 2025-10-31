//
//  ClaudeStats.swift
//  ClaudeConsole
//
//  Model for Claude Code statistics
//

import Foundation

struct ClaudeStats: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cost: Double = 0.0
    var duration: Int = 0
    var linesAdded: Int = 0
    var linesRemoved: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    var formattedCost: String {
        String(format: "$%.4f", cost / 100.0) // Convert cents to dollars
    }

    var formattedDuration: String {
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes % 60)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds % 60)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

class ClaudeStatsMonitor: ObservableObject {
    @Published var stats = ClaudeStats()

    private var fileMonitor: DispatchSourceFileSystemObject?
    private let claudeJSONPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")

    init() {
        loadStats()
        startMonitoring()
    }

    func loadStats() {
        guard let data = try? Data(contentsOf: claudeJSONPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: [String: Any]] else {
            return
        }

        // Find the most recent project stats
        var latestStats = ClaudeStats()
        var latestDate: Date?

        for (_, projectData) in projects {
            if let inputTokens = projectData["lastTotalInputTokens"] as? Int,
               let outputTokens = projectData["lastTotalOutputTokens"] as? Int {

                // Try to determine if this is the most recent
                let tempStats = ClaudeStats(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationTokens: projectData["lastTotalCacheCreationInputTokens"] as? Int ?? 0,
                    cacheReadTokens: projectData["lastTotalCacheReadInputTokens"] as? Int ?? 0,
                    cost: projectData["lastCost"] as? Double ?? 0.0,
                    duration: projectData["lastDuration"] as? Int ?? 0,
                    linesAdded: projectData["lastLinesAdded"] as? Int ?? 0,
                    linesRemoved: projectData["lastLinesRemoved"] as? Int ?? 0
                )

                // Use the project with the highest token count as "latest"
                if tempStats.totalTokens > latestStats.totalTokens {
                    latestStats = tempStats
                }
            }
        }

        DispatchQueue.main.async {
            self.stats = latestStats
        }
    }

    func startMonitoring() {
        guard FileManager.default.fileExists(atPath: claudeJSONPath.path) else {
            print("Claude JSON file not found at: \(claudeJSONPath.path)")
            return
        }

        let fileDescriptor = open(claudeJSONPath.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open file for monitoring")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.loadStats()
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        fileMonitor = source
    }

    deinit {
        fileMonitor?.cancel()
    }
}

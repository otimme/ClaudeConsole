//
//  JSONLUsageMonitor.swift
//  ClaudeConsole
//
//  Monitors Claude Code usage by parsing JSONL session files
//

import Foundation
import Combine

struct MessageUsage: Codable {
    var input_tokens: Int?
    var output_tokens: Int?
    var cache_creation_input_tokens: Int?
    var cache_read_input_tokens: Int?
}

struct Message: Codable {
    var usage: MessageUsage?
}

struct JSONLEntry: Codable {
    var message: Message?
    var timestamp: String?
    var sessionId: String?
}

struct SessionUsage {
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheCreation: Int = 0
    var totalCacheRead: Int = 0

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }
}

class JSONLUsageMonitor: ObservableObject {
    @Published var currentSessionUsage = SessionUsage()
    @Published var dailyPercentage: Double = 0.0
    @Published var weeklyPercentage: Double = 0.0

    private var currentProject: String?
    private var currentSessionId: String?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var sessionFilePath: URL?

    init() {
        startMonitoring()

        // Update every 2 seconds
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateUsage()
        }
    }

    private func startMonitoring() {
        let fileManager = FileManager.default
        let claudeDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let projectsDir = claudeDir.appendingPathComponent("projects")

        print("JSONLUsageMonitor: Scanning all projects in: \(projectsDir.path)")

        // Find the most recently modified JSONL file across ALL projects
        do {
            let projectDirs = try fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil, options: [])

            var allJsonlFiles: [URL] = []

            for projectDir in projectDirs {
                let files = try fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
                let jsonlFiles = files.filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.contains("agent") }
                allJsonlFiles.append(contentsOf: jsonlFiles)
            }

            // Get the most recently modified file
            if let mostRecent = allJsonlFiles.max(by: { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 < date2
            }) {
                self.sessionFilePath = mostRecent
                print("JSONLUsageMonitor: Monitoring most recent session: \(mostRecent.lastPathComponent)")
                print("JSONLUsageMonitor: From project: \(mostRecent.deletingLastPathComponent().lastPathComponent)")
                monitorFile(at: mostRecent)
                updateUsage()
            }
        } catch {
            print("JSONLUsageMonitor: Error scanning projects: \(error)")
        }
    }

    private func monitorFile(at url: URL) {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("JSONLUsageMonitor: Failed to open file for monitoring")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.updateUsage()
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        fileMonitor = source
    }

    private func updateUsage() {
        guard let filePath = sessionFilePath else { return }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            do {
                let content = try String(contentsOf: filePath, encoding: .utf8)
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

                var sessionUsage = SessionUsage()

                for line in lines {
                    if let data = line.data(using: .utf8),
                       let entry = try? JSONDecoder().decode(JSONLEntry.self, from: data),
                       let usage = entry.message?.usage {
                        sessionUsage.totalInputTokens += usage.input_tokens ?? 0
                        sessionUsage.totalOutputTokens += usage.output_tokens ?? 0
                        sessionUsage.totalCacheCreation += usage.cache_creation_input_tokens ?? 0
                        sessionUsage.totalCacheRead += usage.cache_read_input_tokens ?? 0
                    }
                }

                DispatchQueue.main.async {
                    self.currentSessionUsage = sessionUsage
                    // Calculate rough percentage (you'd need actual limits from Anthropic API for accurate numbers)
                    // For now, assuming rough limits
                    self.dailyPercentage = min(100, Double(sessionUsage.totalTokens) / 500000 * 100)
                    self.weeklyPercentage = min(100, Double(sessionUsage.totalTokens) / 2000000 * 100)
                }
            } catch {
                print("JSONLUsageMonitor: Error reading session file: \(error)")
            }
        }
    }

    deinit {
        fileMonitor?.cancel()
    }
}

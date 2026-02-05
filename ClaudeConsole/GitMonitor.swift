//
//  GitMonitor.swift
//  ClaudeConsole
//
//  Monitors git repository status (branch name, dirty/clean) with periodic polling.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "GitMonitor")

class GitMonitor: ObservableObject {
    @Published var branchName: String = ""
    @Published var isDirty: Bool = false
    @Published var isGitRepo: Bool = false

    private var workingDirectory: String?
    private var pollTimer: Timer?
    /// Git status polling interval — balances responsiveness with git command overhead
    private let pollInterval: TimeInterval = 30.0
    /// Timeout for individual git commands to prevent hangs on slow/network filesystems
    private let commandTimeout: TimeInterval = 5.0

    init() {}

    /// Set or update the working directory and trigger immediate refresh
    func setWorkingDirectory(_ path: String?) {
        logger.info("setWorkingDirectory called with: \(path ?? "nil") (current: \(self.workingDirectory ?? "nil"))")
        // Must be called on main thread (called from onClaudeStarted which is main)
        guard workingDirectory != path else {
            logger.info("Working directory unchanged, skipping")
            return
        }
        workingDirectory = path

        pollTimer?.invalidate()
        pollTimer = nil

        guard let path = path else {
            branchName = ""
            isDirty = false
            isGitRepo = false
            return
        }

        // Validate directory exists before starting
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("Working directory does not exist: \(path)")
            branchName = ""
            isDirty = false
            isGitRepo = false
            return
        }

        fetchGitStatus()
        startPolling()
    }

    private func startPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer = Timer.scheduledTimer(
                withTimeInterval: self.pollInterval,
                repeats: true
            ) { [weak self] _ in
                self?.fetchGitStatus()
            }
        }
    }

    func fetchGitStatus() {
        guard let dir = workingDirectory else {
            logger.debug("fetchGitStatus: no working directory set")
            return
        }
        logger.info("fetchGitStatus: checking \(dir)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let branch = self.runGitCommand(
                ["branch", "--show-current"],
                in: dir
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let porcelain = self.runGitCommand(
                ["status", "--porcelain"],
                in: dir
            ) ?? ""
            let dirty = !porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isRepo = !branch.isEmpty

            logger.info("fetchGitStatus result: branch='\(branch)', dirty=\(dirty), isRepo=\(isRepo)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.branchName = branch
                self.isDirty = dirty
                self.isGitRepo = isRepo
            }
        }
    }

    private func runGitCommand(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        // Merge with system environment to preserve PATH, HOME, etc.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Use semaphore with timeout to prevent blocking on slow/network repos
            let semaphore = DispatchSemaphore(value: 0)
            var result: String?

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    result = String(data: data, encoding: .utf8)
                }
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + commandTimeout) == .timedOut {
                process.terminate()
                logger.warning("Git command timed out: git \(arguments.joined(separator: " "))")
                return nil
            }

            return result
        } catch {
            logger.debug("Git command failed: \(error.localizedDescription)")
            return nil
        }
    }

    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        cleanup()
    }
}

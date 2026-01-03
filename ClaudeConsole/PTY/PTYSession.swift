//
//  PTYSession.swift
//  ClaudeConsole
//
//  Thread-safe PTY session manager with proper lifecycle management
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "PTYSession")

/// Thread-safe PTY session manager with proper lifecycle management
final class PTYSession {
    // MARK: - Properties

    /// Serial queue for buffer operations - ALL buffer access must go through this queue
    private let bufferQueue = DispatchQueue(label: "com.claudeconsole.ptysession.buffer")

    /// Lock for state access
    private let stateLock = NSLock()

    /// Current session state (protected by stateLock)
    private var _state: PTYSessionState = .uninitialized
    var state: PTYSessionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    /// Output buffer (only access from bufferQueue)
    private var _outputBuffer: String = ""

    /// Dispatch sources (protected by stateLock)
    private var readSource: DispatchSourceRead?
    private var processMonitorSource: DispatchSourceProcess?

    /// Debounce work item for buffer processing (only access from bufferQueue)
    private var bufferCheckWorkItem: DispatchWorkItem?

    /// Callback for processed output - called on main thread
    var onOutput: ((String) -> Void)?

    /// Callback for state changes - called on main thread
    var onStateChange: ((PTYSessionState) -> Void)?

    /// Callback for raw data received - called on bufferQueue
    var onDataReceived: ((String) -> Void)?

    /// Configuration
    private let maxBufferSize: Int
    private let debounceInterval: TimeInterval

    // MARK: - Initialization

    init(maxBufferSize: Int = 50000, debounceInterval: TimeInterval = 0.3) {
        self.maxBufferSize = maxBufferSize
        self.debounceInterval = debounceInterval
    }

    deinit {
        // Synchronous cleanup - must complete before dealloc
        cleanupSync()
    }

    // MARK: - Public API

    /// Start a PTY session with the given executable
    /// - Parameters:
    ///   - executablePath: Path to the executable (e.g., node)
    ///   - arguments: Command line arguments
    ///   - environment: Environment variables
    func start(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) async throws {
        // Verify executable exists
        guard FileManager.default.fileExists(atPath: executablePath) else {
            let error = PTYError.executableNotFound(path: executablePath)
            try transitionState(to: .failed(error))
            throw error
        }

        // Transition to starting state
        try transitionState(to: .starting)

        // Create PTY pair
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            let error = PTYError.ptyCreationFailed
            try transitionState(to: .failed(error))
            throw error
        }

        // Set up file actions for child process
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, masterFD)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)

        // Prepare arguments
        var args: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        args.append(nil)

        // Prepare environment
        var env: [UnsafeMutablePointer<CChar>?] = environment.map {
            strdup("\($0.key)=\($0.value)")
        }
        env.append(nil)

        // Spawn process
        var pid: pid_t = 0
        let result = posix_spawn(&pid, executablePath, &fileActions, nil, args, env)

        // Clean up spawn resources
        posix_spawn_file_actions_destroy(&fileActions)
        args.forEach { free($0) }
        env.forEach { free($0) }

        // Close slave FD in parent (always - child has its own copy)
        close(slaveFD)

        if result != 0 {
            close(masterFD)
            let error = PTYError.spawnFailed(errno: result)
            try transitionState(to: .failed(error))
            throw error
        }

        // Set non-blocking
        fcntl(masterFD, F_SETFL, O_NONBLOCK)

        // Transition to running state
        try transitionState(to: .running(pid: pid, masterFD: masterFD))

        // Register with process tracker
        ProcessTracker.shared.registerProcess(pid)

        // Start reading and monitoring
        startReading(masterFD: masterFD)
        startProcessMonitoring(pid: pid)

        logger.info("PTY session started: PID=\(pid), FD=\(masterFD)")
    }

    /// Write data to the PTY
    /// - Parameter data: Data to write
    /// - Returns: Number of bytes written, or -1 on error
    @discardableResult
    func write(_ data: Data) -> Int {
        stateLock.lock()
        guard case .running(_, let masterFD) = _state else {
            stateLock.unlock()
            logger.warning("Cannot write: session not running")
            return -1
        }
        stateLock.unlock()

        return data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return Darwin.write(masterFD, baseAddress, data.count)
        }
    }

    /// Write a string to the PTY
    /// - Parameter string: String to write
    /// - Returns: Number of bytes written, or -1 on error
    @discardableResult
    func write(_ string: String) -> Int {
        guard let data = string.data(using: .utf8) else { return -1 }
        return write(data)
    }

    /// Terminate the PTY session gracefully
    func terminate() {
        cleanupSync()
    }

    /// Get the current output buffer contents (thread-safe)
    func getBuffer() -> String {
        var result = ""
        bufferQueue.sync {
            result = self._outputBuffer
        }
        return result
    }

    /// Clear the output buffer (thread-safe)
    func clearBuffer() {
        bufferQueue.async { [weak self] in
            self?._outputBuffer = ""
        }
    }

    /// Check if buffer contains specific text (thread-safe)
    func bufferContains(_ text: String) -> Bool {
        var result = false
        bufferQueue.sync {
            result = self._outputBuffer.contains(text)
        }
        return result
    }

    // MARK: - Private Methods

    private func transitionState(to newState: PTYSessionState) throws {
        stateLock.lock()

        // Validate state transition
        let validTransition: Bool
        switch (_state, newState) {
        case (.uninitialized, .starting),
             (.starting, .running),
             (.starting, .failed),
             (.running, .terminating),
             (.running, .failed),
             (.terminating, .terminated),
             (.failed, .uninitialized),     // Allow reset
             (.terminated, .uninitialized): // Allow restart
            validTransition = true
        default:
            validTransition = false
        }

        guard validTransition else {
            let error = PTYError.invalidStateTransition(
                from: _state.description,
                to: newState.description
            )
            stateLock.unlock()
            throw error
        }

        let oldState = _state
        _state = newState
        stateLock.unlock()

        logger.debug("State transition: \(oldState.description) → \(newState.description)")

        // Notify on main thread
        let handler = onStateChange
        DispatchQueue.main.async {
            handler?(newState)
        }
    }

    private func startReading(masterFD: Int32) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            // Verify still in running state with this FD
            self.stateLock.lock()
            guard case .running(_, let currentFD) = self._state, currentFD == masterFD else {
                self.stateLock.unlock()
                return
            }
            self.stateLock.unlock()

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(masterFD, &buffer, buffer.count)

            guard bytesRead > 0 else { return }

            let data = Data(buffer[0..<bytesRead])
            guard let text = String(data: data, encoding: .utf8) else { return }

            self.handleOutput(text)
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            // Only close if we still own this FD
            self.stateLock.lock()
            if case .running(_, let fd) = self._state, fd == masterFD {
                // FD will be closed during cleanup
            } else if case .terminating = self._state {
                // FD will be closed during cleanup
            } else {
                // Safe to close here
                close(masterFD)
            }
            self.stateLock.unlock()
        }

        stateLock.lock()
        readSource = source
        stateLock.unlock()

        source.resume()
    }

    private func startProcessMonitoring(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            logger.warning("PTY process \(pid) terminated")
            self?.handleProcessTermination()
        }

        stateLock.lock()
        processMonitorSource = source
        stateLock.unlock()

        source.resume()
    }

    private func handleOutput(_ text: String) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            self._outputBuffer += text

            // Limit buffer size
            if self._outputBuffer.count > self.maxBufferSize {
                self._outputBuffer = String(self._outputBuffer.suffix(self.maxBufferSize / 2))
            }

            // Call raw data handler
            let dataHandler = self.onDataReceived
            dataHandler?(text)

            // Debounce output callback
            self.bufferCheckWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let buffer = self._outputBuffer

                // Call output handler on main thread
                let outputHandler = self.onOutput
                DispatchQueue.main.async {
                    outputHandler?(buffer)
                }
            }

            self.bufferCheckWorkItem = workItem
            self.bufferQueue.asyncAfter(
                deadline: .now() + self.debounceInterval,
                execute: workItem
            )
        }
    }

    private func handleProcessTermination() {
        cleanupSync()
    }

    private func cleanupSync() {
        stateLock.lock()

        // Already cleaned up?
        if case .terminated = _state {
            stateLock.unlock()
            return
        }
        if case .uninitialized = _state {
            stateLock.unlock()
            return
        }

        // Get current state info before transition
        var pidToKill: pid_t? = nil
        var fdToClose: Int32? = nil

        if case .running(let pid, let fd) = _state {
            pidToKill = pid
            fdToClose = fd
        }

        // Capture sources before clearing
        let readSrc = readSource
        let processSrc = processMonitorSource
        readSource = nil
        processMonitorSource = nil

        _state = .terminating
        stateLock.unlock()

        logger.info("Starting PTY session cleanup")

        // Cancel buffer work item synchronously
        bufferQueue.sync {
            bufferCheckWorkItem?.cancel()
            bufferCheckWorkItem = nil
            _outputBuffer = ""
        }

        // Cancel dispatch sources
        readSrc?.cancel()
        processSrc?.cancel()

        // Close file descriptor if we have one
        if let fd = fdToClose {
            close(fd)
            logger.debug("Closed FD \(fd)")
        }

        // Terminate process
        if let pid = pidToKill {
            if kill(pid, 0) == 0 {
                // Try graceful termination first
                kill(pid, SIGTERM)
                logger.info("Sent SIGTERM to PID \(pid)")

                // Give it a moment to exit
                usleep(100000) // 100ms

                // Force kill if still running
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                    logger.warning("Sent SIGKILL to PID \(pid)")
                }
            }
            ProcessTracker.shared.unregisterProcess(pid)
        }

        // Final state transition
        stateLock.lock()
        _state = .terminated
        stateLock.unlock()

        logger.info("PTY session cleanup complete")

        // Notify on main thread
        let handler = onStateChange
        DispatchQueue.main.async {
            handler?(.terminated)
        }
    }
}

// MARK: - Async Helpers

extension PTYSession {
    /// Run a shell command and return output with timeout
    static func runCommand(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 5.0
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments

            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            // Non-blocking timeout using DispatchQueue
            let timeoutItem = DispatchWorkItem {
                if task.isRunning {
                    task.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            DispatchQueue.global().async {
                task.waitUntilExit()
                timeoutItem.cancel()

                guard task.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)
                continuation.resume(returning: result)
            }
        }
    }

    /// Find claude executable path
    static func findClaudePath() async -> String? {
        // Try using 'which' command
        if let path = await runCommand("/bin/zsh", arguments: ["-l", "-c", "which claude"]) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("not found") {
                logger.info("Found claude at \(trimmed)")
                return trimmed
            }
        }

        // Fallback: search nvm directories
        let nvmDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for version in nodeVersions.sorted().reversed() {
                let claudePath = "\(nvmDir)/\(version)/bin/claude"
                if FileManager.default.fileExists(atPath: claudePath) {
                    logger.info("Found claude at \(claudePath) (nvm fallback)")
                    return claudePath
                }
            }
        }

        logger.warning("Could not find claude executable")
        return nil
    }

    /// Get PATH from login shell
    static func getLoginShellPath() async -> String {
        if let path = await runCommand("/bin/zsh", arguments: ["-l", "-c", "echo $PATH"]) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "/usr/bin:/bin:/usr/sbin:/sbin"
    }
}

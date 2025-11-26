import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "ProcessTracker")

struct TrackedProcess {
    let pid: pid_t
    let pgid: pid_t
    let commandName: String
    let registrationTime: Date
}

class ProcessTracker {
    static let shared = ProcessTracker()

    private var trackedProcesses: [pid_t: TrackedProcess] = [:]
    private let lock = NSLock()

    private init() {}

    func registerProcess(_ pid: pid_t) {
        // Verify process exists before registering
        guard kill(pid, 0) == 0 else {
            logger.warning("Cannot register PID \(pid): process does not exist")
            return
        }

        // Get process group ID
        let pgid = getpgid(pid)

        // Get command name for validation later
        let commandName = getProcessCommandName(pid) ?? "unknown"

        let tracked = TrackedProcess(
            pid: pid,
            pgid: pgid,
            commandName: commandName,
            registrationTime: Date()
        )

        lock.lock()
        trackedProcesses[pid] = tracked
        lock.unlock()

        logger.info("Registered PID: \(pid), PGID: \(pgid), command: \(commandName)")
    }

    func unregisterProcess(_ pid: pid_t) {
        lock.lock()
        let removed = trackedProcesses.removeValue(forKey: pid)
        lock.unlock()

        if removed != nil {
            logger.info("Unregistered PID: \(pid)")
        }
    }

    func cleanupAllTrackedProcesses() {
        lock.lock()
        let processes = Array(trackedProcesses.values)
        lock.unlock()

        logger.info("Cleaning up \(processes.count) tracked processes")

        for process in processes {
            terminateProcess(process)
        }

        // Clear all tracked processes
        lock.lock()
        trackedProcesses.removeAll()
        lock.unlock()

        logger.info("Cleanup complete")
    }

    private func terminateProcess(_ process: TrackedProcess) {
        let pid = process.pid

        // Validate process still exists and matches what we registered
        guard kill(pid, 0) == 0 else {
            logger.info("PID \(pid) already exited")
            return
        }

        // Verify command name still matches to prevent PID reuse attacks
        if let currentCommand = getProcessCommandName(pid) {
            if !commandNamesMatch(process.commandName, currentCommand) {
                logger.warning("PID \(pid) command changed from '\(process.commandName)' to '\(currentCommand)' - skipping kill (PID reuse detected)")
                return
            }
        }

        // Try to kill the entire process group first (catches child processes)
        if process.pgid > 0 {
            let pgidResult = kill(-process.pgid, SIGTERM)
            if pgidResult == 0 {
                logger.info("Sent SIGTERM to process group \(process.pgid)")
            }
        }

        // Also send SIGTERM directly to the process
        let result = kill(pid, SIGTERM)
        if result == 0 {
            logger.info("Sent SIGTERM to PID \(pid)")
        } else {
            logger.warning("Failed to SIGTERM PID \(pid): \(String(cString: strerror(errno)))")
        }
    }

    private func getProcessCommandName(_ pid: pid_t) -> String? {
        // Use sysctl to get process info - more reliable than parsing ps
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return nil }

        // Extract command name from kp_proc.p_comm
        // p_comm is a fixed-size C array (typically 16 chars on macOS)
        let comm = info.kp_proc.p_comm
        return withUnsafePointer(to: comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 16) { cString in
                String(cString: cString)
            }
        }
    }

    private func commandNamesMatch(_ original: String, _ current: String) -> Bool {
        // Allow for truncation in process names (MAXCOMM is typically 16 chars)
        let normalizedOriginal = original.prefix(15).lowercased()
        let normalizedCurrent = current.prefix(15).lowercased()
        return normalizedOriginal == normalizedCurrent
    }

    func getTrackedPIDCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return trackedProcesses.count
    }
}

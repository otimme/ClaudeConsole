import Foundation

/// Represents the lifecycle states of a PTY session
enum PTYSessionState: Equatable, CustomStringConvertible {
    case uninitialized
    case starting
    case running(pid: pid_t, masterFD: Int32)
    case terminating
    case terminated
    case failed(PTYError)

    static func == (lhs: PTYSessionState, rhs: PTYSessionState) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
             (.starting, .starting),
             (.terminating, .terminating),
             (.terminated, .terminated):
            return true
        case let (.running(lPid, lFD), .running(rPid, rFD)):
            return lPid == rPid && lFD == rFD
        case (.failed, .failed):
            return true  // Don't compare errors for equality
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .uninitialized:
            return "uninitialized"
        case .starting:
            return "starting"
        case .running(let pid, let fd):
            return "running(pid: \(pid), fd: \(fd))"
        case .terminating:
            return "terminating"
        case .terminated:
            return "terminated"
        case .failed(let error):
            return "failed(\(error.localizedDescription))"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isTerminal: Bool {
        switch self {
        case .terminated, .failed:
            return true
        default:
            return false
        }
    }
}

/// Errors that can occur during PTY session management
enum PTYError: Error, LocalizedError, Equatable {
    case ptyCreationFailed
    case spawnFailed(errno: Int32)
    case invalidStateTransition(from: String, to: String)
    case notRunning
    case writeFailedSessionNotRunning
    case executableNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .ptyCreationFailed:
            return "Failed to create PTY pair"
        case .spawnFailed(let errno):
            return "posix_spawn failed with error \(errno): \(String(cString: strerror(errno)))"
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from) to \(to)"
        case .notRunning:
            return "PTY session is not running"
        case .writeFailedSessionNotRunning:
            return "Cannot write: PTY session is not running"
        case .executableNotFound(let path):
            return "Executable not found at path: \(path)"
        }
    }

    static func == (lhs: PTYError, rhs: PTYError) -> Bool {
        switch (lhs, rhs) {
        case (.ptyCreationFailed, .ptyCreationFailed),
             (.notRunning, .notRunning),
             (.writeFailedSessionNotRunning, .writeFailedSessionNotRunning):
            return true
        case (.spawnFailed(let l), .spawnFailed(let r)):
            return l == r
        case (.invalidStateTransition(let lf, let lt), .invalidStateTransition(let rf, let rt)):
            return lf == rf && lt == rt
        case (.executableNotFound(let l), .executableNotFound(let r)):
            return l == r
        default:
            return false
        }
    }
}

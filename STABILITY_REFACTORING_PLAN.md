# ClaudeConsole Stability Refactoring Plan

## Summary

Comprehensive refactoring to fix race conditions, memory management issues, and threading problems in the PTY management layer. The solution introduces a thread-safe `PTYSession` class and modernizes existing monitors with proper synchronization.

---

## Architecture Overview

### New Component Structure

```
ClaudeConsole/
  PTY/
    PTYSession.swift          (NEW: Thread-safe PTY wrapper)
    PTYSessionState.swift     (NEW: State machine for PTY lifecycle)
  UsageMonitor.swift          (MODIFIED: Uses PTYSession)
  TerminalView.swift          (MODIFIED: Thread-safe buffer handling)
  ContextMonitor.swift        (MODIFIED: Proper timer cleanup)
```

---

## Phase 1: Create Thread-Safe PTY Management Layer

### 1.1 New File: `PTYSessionState.swift`

**Location**: `ClaudeConsole/PTY/PTYSessionState.swift`

Define a clean state machine for PTY lifecycle:
- `.uninitialized` → `.starting` → `.running(pid, masterFD)` → `.terminating` → `.terminated`
- Error state: `.failed(Error)`

### 1.2 New File: `PTYSession.swift`

**Location**: `ClaudeConsole/PTY/PTYSession.swift`

Thread-safe PTY session manager with:
- `NSLock` for state synchronization (consistent with `ProcessTracker.swift` pattern)
- Serial `bufferQueue` for all buffer operations
- Async/await for non-blocking initialization
- Proper FD lifecycle management (cancel handler closes FD once)
- Debounced output callbacks

**Key APIs**:
```swift
func start(executablePath:arguments:environment:) async throws
func write(_ data: Data) -> Int
func terminate()
var onOutput: ((String) -> Void)?
var onStateChange: ((PTYSessionState) -> Void)?
```

---

## Phase 2: Refactor UsageMonitor.swift

**File**: `ClaudeConsole/UsageMonitor.swift`

### Changes:

1. **Replace manual PTY management with `PTYSession`**
   - Remove: `masterFD`, `childPID`, `outputSource`, `processMonitorSource`, `outputBuffer`, `bufferCheckWorkItem`, `bufferQueue`
   - Add: `private var ptySession: PTYSession?`

2. **Replace blocking `Thread.sleep` with async/await**
   - Current: Lines 98-111 use `Thread.sleep(forTimeInterval: 0.1)` in while loop
   - New: Use `Task.sleep()` or `withCheckedContinuation` with timeout work item

3. **Fix weak self capture in nested closures**
   - Current: Line 553-556 has inner `DispatchQueue.main.async` that can crash
   - New: Capture values before closure, use `[weak self]` in inner closure

4. **Use async initialization**
   ```swift
   init() {
       Task.detached(priority: .background) { [weak self] in
           self?.claudePath = await self?.findClaudePath()
           if self?.claudePath != nil {
               await self?.startBackgroundSession()
           }
       }
   }
   ```

5. **Simplify cleanup**
   ```swift
   func cleanup() {
       pollTimer?.invalidate()
       ptySession?.terminate()  // PTYSession handles all FD cleanup
       ptySession = nil
   }
   ```

---

## Phase 3: Fix TerminalView.swift Race Conditions

**File**: `ClaudeConsole/TerminalView.swift`

### Changes:

1. **Add thread-safe buffer access with NSLock**
   - Current: Lines 28-47 have unprotected `outputBuffer`, `isPWDCapture`, `pwdBuffer`
   - New: Add `bufferLock` and computed properties with lock/unlock

   ```swift
   private let bufferLock = NSLock()
   private var _outputBuffer = ""
   private var _isPWDCapture = false
   private var _pwdBuffer = ""

   private var outputBuffer: String {
       get { bufferLock.lock(); defer { bufferLock.unlock() }; return _outputBuffer }
       set { bufferLock.lock(); defer { bufferLock.unlock() }; _outputBuffer = newValue }
   }
   // Similar for isPWDCapture, pwdBuffer
   ```

2. **Refactor `dataReceived` callback**
   - Current: Lines 322-424 read/write shared state without synchronization
   - New: Use atomic operations with lock, extract processing to separate methods

---

## Phase 4: Fix ContextMonitor.swift Timer Issues

**File**: `ClaudeConsole/ContextMonitor.swift`

### Changes:

1. **Properly invalidate timer in deinit**
   - Current: Timer invalidated but may be on wrong thread
   - New: Check `Thread.isMainThread`, use `DispatchQueue.main.sync` if needed

2. **Add thread safety for buffer access**
   - Add `bufferLock` and synchronized accessors for `outputBuffer`, `isCapturingContext`

---

## Implementation Order

| Phase | Component | Dependencies | Est. Time |
|-------|-----------|--------------|-----------|
| 1a | `PTYSessionState.swift` | None | 30 min |
| 1b | `PTYSession.swift` | PTYSessionState, ProcessTracker | 2-3 hours |
| 2 | `UsageMonitor.swift` refactor | PTYSession | 2-3 hours |
| 3 | `TerminalView.swift` fixes | None | 1-2 hours |
| 4 | `ContextMonitor.swift` fixes | None | 30 min |

---

## Critical Files

| File | Issue | Severity |
|------|-------|----------|
| `UsageMonitor.swift:345-391` | Buffer debounce race condition | High |
| `UsageMonitor.swift:428-450` | Unsynchronized masterFD access | High |
| `UsageMonitor.swift:98-111` | Blocking Thread.sleep | Medium |
| `UsageMonitor.swift:140-154` | FD cleanup gap on spawn failure | Medium |
| `TerminalView.swift:28-47` | Unprotected buffer properties | High |
| `TerminalView.swift:336-375` | Unsynchronized dataReceived | High |
| `ContextMonitor.swift:96-102` | Timer not invalidated properly | Low |

---

## Testing Strategy

### Manual Testing Checklist
- [ ] App launches without crash
- [ ] Usage stats update every 60 seconds
- [ ] Context stats update on refresh click
- [ ] No memory leaks (Instruments → Leaks)
- [ ] No FD leaks (`lsof -p <pid> | wc -l` stable)
- [ ] No zombie processes after quit
- [ ] Thread Sanitizer shows no races

### Stress Tests
- Rapid start/stop of UsageMonitor instances
- Large terminal output during /context command
- Multiple concurrent Claude command invocations
- App termination during PTY initialization


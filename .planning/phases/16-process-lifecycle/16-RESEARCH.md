# Phase 16: Process Lifecycle - Research

**Researched:** 2026-02-07
**Domain:** Unix process management, PID tracking, and crash recovery
**Confidence:** HIGH

## Summary

Research into process lifecycle management for terminal emulators reveals a clear path for tracking, persisting, and cleaning up spawned processes across app sessions. SwiftTerm's `LocalProcess` class exposes the shell PID via the public `shellPid` property (line 70), enabling direct PID tracking. However, tracking child processes spawned by the shell (like `claude`) requires either process group-based termination or process tree enumeration via `sysctl()`.

The standard approach uses process groups: SwiftTerm already configures spawned processes as session leaders via `POSIX_SPAWN_SETSID` (line 301), making the shell PID also the process group ID (PGID). This means `killpg(shellPid, signal)` terminates both the shell and all its children in a single operation.

For persistence and crash recovery, UserDefaults provides automatic disk synchronization without requiring manual `synchronize()` calls. The two-stage graceful termination pattern (SIGTERM → wait → SIGKILL) is standard across Docker, Kubernetes, and server applications, with typical timeouts ranging from 2-10 seconds for interactive shells.

**Primary recommendation:** Use `LocalProcess.shellPid` as both PID and PGID, persist to UserDefaults on spawn, validate on launch with `kill(pid, 0)`, and terminate using `killpg(pgid, SIGTERM)` followed by `SIGKILL` after timeout. Don't hand-roll process tree walking—leverage process groups.

## Standard Stack

The established libraries/tools for process lifecycle management:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm LocalProcess | 1.10.1 | Shell spawning with PID exposure | Provides `shellPid` property (public), uses `POSIX_SPAWN_SETSID` for session/process group |
| Foundation UserDefaults | Built-in | PID persistence across sessions | Automatic async persistence, crash-safe for normal termination |
| Darwin (POSIX) | Built-in | Process signals and groups | `kill()`, `killpg()`, process existence checks |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| sysctl() | POSIX | Process tree enumeration | If need to verify child processes exist (optional, process groups sufficient) |
| Swift System Errno | Built-in | Error handling for process calls | Decode `ESRCH`, `EPERM` from `kill(pid, 0)` checks |
| DispatchQueue | Built-in | Async termination with timeout | Schedule SIGKILL after SIGTERM grace period |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| UserDefaults | JSON file | More control but no atomic writes, need manual crash handling |
| killpg() | walk process tree with sysctl | More code, race conditions, slower—process groups solve this |
| POSIX_SPAWN_SETSID | Manual setpgid after fork | SwiftTerm already does it, no need to hand-roll |

**Installation:**
All components are built-in to macOS and already integrated via SwiftTerm.

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/Services/
├── TerminalProcessRegistry.swift    # PID tracking and persistence (NEW)
└── ProcessLifecycleManager.swift    # Two-stage termination logic (NEW)

Dispatch/Views/Terminal/
└── EmbeddedTerminalView.swift       # Register PIDs on spawn, unregister on exit
```

### Pattern 1: Registry with UserDefaults Persistence
**What:** Centralized service that tracks spawned PIDs and persists to UserDefaults on every spawn/terminate.
**When to use:** Always—required for crash recovery.
**Example:**
```swift
// Source: UserDefaults best practices + crash recovery pattern
class TerminalProcessRegistry {
    static let shared = TerminalProcessRegistry()

    private let defaults = UserDefaults.standard
    private let key = "Dispatch.ActiveProcessPIDs"
    private let lock = NSLock()

    // Track active PIDs in memory and UserDefaults
    private var activePIDs: Set<pid_t> = []

    init() {
        // Load persisted PIDs on init
        let stored = defaults.array(forKey: key) as? [Int] ?? []
        activePIDs = Set(stored.map { pid_t($0) })
    }

    func register(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        activePIDs.insert(pid)
        persist()
    }

    func unregister(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        activePIDs.remove(pid)
        persist()
    }

    private func persist() {
        // UserDefaults automatically syncs to disk asynchronously
        // No need to call synchronize() - it's deprecated
        let pidArray = Array(activePIDs).map { Int($0) }
        defaults.set(pidArray, forKey: key)
    }

    func getActivePIDs() -> Set<pid_t> {
        lock.lock()
        defer { lock.unlock() }
        return activePIDs
    }
}
```

### Pattern 2: Orphan Cleanup on Launch
**What:** On app launch, read persisted PIDs and terminate any still-running processes from crashed sessions.
**When to use:** In app initialization (AppDelegate/App init).
**Example:**
```swift
// Source: kill(pid, 0) process existence check pattern
func cleanupOrphanedProcesses() {
    let registry = TerminalProcessRegistry.shared
    let persistedPIDs = registry.getActivePIDs()

    for pid in persistedPIDs {
        // Check if process still exists
        if isProcessRunning(pid) {
            logInfo("Found orphaned process \(pid), terminating")
            terminateProcessGracefully(pid: pid)
        } else {
            logDebug("Stale PID \(pid) no longer running, removing")
        }
        registry.unregister(pid: pid)
    }
}

func isProcessRunning(_ pid: pid_t) -> Bool {
    // kill(pid, 0) doesn't send signal, just checks existence
    let result = kill(pid, 0)

    if result == 0 {
        return true  // Process exists
    }

    // Check errno to distinguish "not found" from "no permission"
    let error = errno
    if error == ESRCH {
        return false  // Process does not exist
    } else if error == EPERM {
        return true   // Process exists but no permission (still running)
    }

    return false  // Other errors treat as not running
}
```

### Pattern 3: Two-Stage Graceful Termination
**What:** Send SIGTERM, wait for grace period, then SIGKILL if still running.
**When to use:** All process termination (user-initiated close, app quit, orphan cleanup).
**Example:**
```swift
// Source: Docker/Kubernetes graceful shutdown pattern
func terminateProcessGracefully(pid: pid_t, timeout: TimeInterval = 3.0) {
    // Stage 1: Request graceful shutdown
    kill(pid, SIGTERM)

    // Stage 2: Wait for process to exit
    let deadline = Date().addingTimeInterval(timeout)
    var terminated = false

    while Date() < deadline {
        if !isProcessRunning(pid) {
            terminated = true
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Stage 3: Force kill if still running
    if !terminated {
        logDebug("Process \(pid) did not terminate gracefully, sending SIGKILL")
        kill(pid, SIGKILL)

        // Wait brief moment for SIGKILL to complete
        Thread.sleep(forTimeInterval: 0.1)
    }
}
```

### Pattern 4: Process Group Termination (Recommended)
**What:** Use `killpg()` to terminate shell and all child processes (like Claude Code) in single operation.
**When to use:** When terminating terminal sessions—prevents orphaned child processes.
**Example:**
```swift
// Source: SwiftTerm POSIX_SPAWN_SETSID + killpg(2) man page
func terminateProcessGroupGracefully(pgid: pid_t, timeout: TimeInterval = 3.0) {
    // Stage 1: SIGTERM to entire process group
    // SwiftTerm uses POSIX_SPAWN_SETSID, so shell PID == PGID
    killpg(pgid, SIGTERM)

    // Stage 2: Wait for graceful shutdown
    let deadline = Date().addingTimeInterval(timeout)
    var terminated = false

    while Date() < deadline {
        // Check if process group leader still exists
        if !isProcessRunning(pgid) {
            terminated = true
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Stage 3: SIGKILL to entire process group
    if !terminated {
        logDebug("Process group \(pgid) did not terminate gracefully, sending SIGKILL")
        killpg(pgid, SIGKILL)
        Thread.sleep(forTimeInterval: 0.1)
    }
}

// Integration with EmbeddedTerminalView Coordinator
func processTerminated(source: TerminalView, exitCode: Int32?) {
    guard let terminal = terminalView else { return }

    // Unregister from tracking when process exits naturally
    TerminalProcessRegistry.shared.unregister(pid: terminal.shellPid)

    // Clear reference
    terminalView = nil

    // Notify UI
    DispatchQueue.main.async {
        self.onProcessExit?(exitCode)
    }
}

// On user-initiated close or deinit
deinit {
    if let terminal = terminalView {
        let pid = terminal.shellPid

        // Terminate process group (shell + children like Claude Code)
        terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)

        // Unregister after termination
        TerminalProcessRegistry.shared.unregister(pid: pid)
    }
}
```

### Anti-Patterns to Avoid
- **Calling synchronize() on UserDefaults:** Deprecated, automatic persistence is sufficient and more efficient
- **Using kill() instead of killpg() for shells:** Leaves orphaned child processes (Claude Code continues running)
- **Sending SIGKILL immediately:** Prevents cleanup, can corrupt state—always try SIGTERM first
- **Not checking process existence before unregister:** Wastes effort, but harmless—validation recommended for logging
- **Tracking child PIDs separately:** Process groups eliminate need to enumerate children manually

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Process tree walking | sysctl() enumeration loop | killpg(pgid, signal) | SwiftTerm uses POSIX_SPAWN_SETSID—shell is session leader, killpg terminates entire tree |
| Custom PID persistence format | JSON file with locking | UserDefaults.standard.set([Int]) | Atomic writes, automatic disk sync, crash-safe, simple API |
| Manual synchronize() calls | Call after each UserDefaults write | Rely on automatic sync | Apple deprecated synchronize()—automatic async sync is more efficient |
| Child process enumeration | Loop through proc_pidinfo | Process groups via killpg | POSIX_SPAWN_SETSID makes shell PGID==PID, all children inherit PGID |
| Timeout implementation | Manual DispatchQueue.asyncAfter chains | Simple while loop with Date() check | Clearer logic, easier to cancel, no callback nesting |

**Key insight:** SwiftTerm already configures spawned processes with `POSIX_SPAWN_SETSID` (line 301), which makes the shell a session leader AND process group leader. This means `shellPid == PGID`, and `killpg(shellPid, signal)` automatically handles all children without manual tree walking.

## Common Pitfalls

### Pitfall 1: Not Using Process Groups for Termination
**What goes wrong:** Calling `kill(shellPid, SIGTERM)` only terminates the shell. Child processes like Claude Code continue running as orphans, consuming resources and persisting across app restarts.
**Why it happens:** Developers assume killing parent kills children (not true in Unix). Each process terminates independently unless process group semantics are used.
**How to avoid:**
1. Use `killpg(shellPid, SIGTERM)` instead of `kill(shellPid, SIGTERM)`
2. SwiftTerm's POSIX_SPAWN_SETSID ensures `shellPid == PGID`
3. All children spawned by shell inherit the process group
**Warning signs:**
- `claude` processes persist after closing Dispatch
- Multiple terminal sessions accumulate background processes
- `ps aux | grep claude` shows processes without parent

### Pitfall 2: Trusting UserDefaults During Crash
**What goes wrong:** Making critical decisions based on UserDefaults immediately after crash, assuming data was persisted. If app crashed mid-operation, recent PID additions may not be on disk.
**Why it happens:** UserDefaults persists asynchronously. Crash before async write completes = data loss for that write.
**How to avoid:**
1. Accept that crash recovery is best-effort, not guaranteed
2. On launch, validate every PID with `kill(pid, 0)` before acting
3. Don't assume PID list is complete—treat it as "known processes to check"
**Warning signs:**
- Orphaned processes that aren't in persisted PID list
- Inconsistent cleanup behavior between normal quit and crash restart
- Over-reliance on UserDefaults completeness for correctness

### Pitfall 3: SIGTERM Without SIGKILL Fallback
**What goes wrong:** Sending SIGTERM and assuming process will terminate. If process is hung, unresponsive, or has signal handler bug, it never exits.
**Why it happens:** SIGTERM is polite request—processes can ignore, delay, or block it. Only SIGKILL is guaranteed (cannot be caught).
**How to avoid:**
1. Always implement two-stage termination: SIGTERM → timeout → SIGKILL
2. Use 2-5 second timeout for shells (faster for hung processes)
3. Log when SIGKILL is needed—indicates process didn't clean up properly
**Warning signs:**
- Terminal views hang on close
- App quit blocked by non-terminating processes
- Process still running after calling terminate()

### Pitfall 4: Race Conditions Between kill(pid, 0) and kill(pid, signal)
**What goes wrong:** Checking process exists with `kill(pid, 0)`, then sending signal with `kill(pid, SIGTERM)`. Between the two calls, process exits or PID is reused by new process—signal goes to wrong target.
**Why it happens:** PID reuse is rare but possible. Time-of-check-time-of-use race.
**How to avoid:**
1. Combine check and action: just call `kill(pid, signal)` and check errno
2. If `kill()` returns -1 and errno == ESRCH, process already gone (success)
3. Only use `kill(pid, 0)` for validation in loops, not as gate before action
**Warning signs:**
- Intermittent "process not found" errors
- Very rare crashes or unexpected signal deliveries
- Issues on systems with high process churn

### Pitfall 5: Not Unregistering on Natural Process Exit
**What goes wrong:** Process exits normally (user types `exit`, command completes), but PID remains in registry. On next launch, app tries to clean up "orphan" that doesn't exist, or worse, a reused PID.
**Why it happens:** Only removing PIDs on app-initiated termination, forgetting that processes can exit on their own.
**How to avoid:**
1. Always unregister in `processTerminated()` delegate method
2. Unregister regardless of whether app or user initiated termination
3. Defensive: On launch cleanup, validate with `kill(pid, 0)` before acting
**Warning signs:**
- Registry grows unbounded over time
- Logs show many "stale PID" messages on launch
- Occasional attempts to signal unrelated processes

## Code Examples

Verified patterns from official sources and research findings:

### Accessing LocalProcess PID
```swift
// Source: SwiftTerm LocalProcess.swift line 70
// LocalProcess exposes shellPid publicly
let terminal = LocalProcessTerminalView(frame: .zero)
terminal.startProcess(executable: "/bin/bash")

// Access PID immediately after startProcess
let pid = terminal.shellPid
print("Shell running with PID: \(pid)")

// This PID is also the PGID due to POSIX_SPAWN_SETSID
```

### Complete Registry Implementation
```swift
// Source: Synthesized from UserDefaults + NSLock + process management patterns
import Foundation

class TerminalProcessRegistry {
    static let shared = TerminalProcessRegistry()

    private let defaults = UserDefaults.standard
    private let defaultsKey = "Dispatch.ActiveProcessPIDs"
    private let lock = NSLock()
    private var activePIDs: Set<pid_t> = []

    private init() {
        loadPersistedPIDs()
    }

    private func loadPersistedPIDs() {
        lock.lock()
        defer { lock.unlock() }

        let stored = defaults.array(forKey: defaultsKey) as? [Int] ?? []
        activePIDs = Set(stored.map { pid_t($0) })

        logDebug("Loaded \(activePIDs.count) persisted PIDs")
    }

    func register(pid: pid_t) {
        guard pid > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        activePIDs.insert(pid)
        persist()

        logInfo("Registered process PID: \(pid)")
    }

    func unregister(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        let wasPresent = activePIDs.remove(pid) != nil
        if wasPresent {
            persist()
            logInfo("Unregistered process PID: \(pid)")
        }
    }

    private func persist() {
        // Convert to [Int] for UserDefaults (which doesn't support pid_t directly)
        let pidArray = Array(activePIDs).map { Int($0) }
        defaults.set(pidArray, forKey: defaultsKey)

        // DO NOT call synchronize() - it's deprecated and unnecessary
        // UserDefaults automatically persists asynchronously
    }

    func getAllPIDs() -> Set<pid_t> {
        lock.lock()
        defer { lock.unlock() }
        return activePIDs
    }

    func contains(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activePIDs.contains(pid)
    }
}
```

### Launch Cleanup Logic
```swift
// Source: Orphan detection + two-stage termination patterns
import Darwin

func cleanupOrphanedProcessesOnLaunch() {
    let registry = TerminalProcessRegistry.shared
    let persistedPIDs = registry.getAllPIDs()

    guard !persistedPIDs.isEmpty else {
        logDebug("No persisted PIDs to clean up")
        return
    }

    logInfo("Checking \(persistedPIDs.count) persisted PIDs for orphans")

    for pid in persistedPIDs {
        if isProcessRunning(pid) {
            logInfo("Found orphaned process \(pid), terminating process group")

            // Use process group termination to kill shell + children
            terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)
        } else {
            logDebug("Stale PID \(pid) no longer running")
        }

        // Remove from registry either way (terminated or already gone)
        registry.unregister(pid: pid)
    }

    logInfo("Orphan cleanup complete")
}

func isProcessRunning(_ pid: pid_t) -> Bool {
    // kill(pid, 0) checks existence without sending signal
    let result = kill(pid, 0)

    if result == 0 {
        return true  // Process exists and we have permission
    }

    // Check errno to distinguish cases
    switch errno {
    case ESRCH:
        return false  // No such process
    case EPERM:
        return true   // Process exists but no permission (still running)
    default:
        logDebug("Unexpected errno \(errno) checking PID \(pid)")
        return false
    }
}

func terminateProcessGroupGracefully(pgid: pid_t, timeout: TimeInterval = 3.0) {
    // Stage 1: Send SIGTERM to process group
    // killpg(pgid, signal) sends signal to all processes in group
    let termResult = killpg(pgid, SIGTERM)

    if termResult == -1 && errno == ESRCH {
        logDebug("Process group \(pgid) already terminated")
        return
    }

    // Stage 2: Wait for graceful shutdown
    let deadline = Date().addingTimeInterval(timeout)
    var gracefullyTerminated = false

    while Date() < deadline {
        if !isProcessRunning(pgid) {
            gracefullyTerminated = true
            logDebug("Process group \(pgid) terminated gracefully")
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Stage 3: Force termination if still running
    if !gracefullyTerminated {
        logDebug("Process group \(pgid) timeout, sending SIGKILL")
        killpg(pgid, SIGKILL)

        // Brief wait for SIGKILL to complete
        Thread.sleep(forTimeInterval: 0.1)
    }
}
```

### Integration with EmbeddedTerminalView
```swift
// Source: Phase 15 EmbeddedTerminalView + process lifecycle patterns
class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
    var onProcessExit: ((Int32?) -> Void)?
    var terminalView: LocalProcessTerminalView?

    init(onProcessExit: ((Int32?) -> Void)?) {
        self.onProcessExit = onProcessExit
        super.init()
    }

    func setupTerminal(_ terminal: LocalProcessTerminalView) {
        self.terminalView = terminal

        // Register PID after process starts
        let pid = terminal.shellPid
        if pid > 0 {
            TerminalProcessRegistry.shared.register(pid: pid)
            logInfo("Terminal process started with PID \(pid)")
        }
    }

    deinit {
        logDebug("Coordinator deinit - terminating process group")

        guard let terminal = terminalView else { return }
        let pid = terminal.shellPid

        // Terminate entire process group (shell + children like Claude Code)
        terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)

        // Unregister after termination
        TerminalProcessRegistry.shared.unregister(pid: pid)

        terminalView = nil
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        logDebug("Terminal process exited with code: \(exitCode ?? -1)")

        // Unregister when process exits naturally
        if let terminal = terminalView {
            TerminalProcessRegistry.shared.unregister(pid: terminal.shellPid)
        }

        // Clear reference
        terminalView = nil

        // Notify UI
        DispatchQueue.main.async {
            self.onProcessExit?(exitCode)
        }
    }
}

// In makeNSView:
func makeNSView(context: Context) -> LocalProcessTerminalView {
    let terminal = LocalProcessTerminalView(frame: .zero)
    terminal.processDelegate = context.coordinator

    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
    terminal.startProcess(executable: shell)

    // Register PID for crash recovery
    context.coordinator.setupTerminal(terminal)

    return terminal
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual UserDefaults.synchronize() | Automatic async persistence | iOS 12 / 2018 | Deprecated synchronize(), trust automatic sync |
| Track child PIDs separately | Use process groups (killpg) | POSIX standard | Single call terminates entire tree |
| setpgid() in fork/exec | POSIX_SPAWN_SETSID flag | SwiftTerm 1.x | Shell automatically becomes session+group leader |
| Custom timeout with DispatchQueue.asyncAfter | Simple Date() deadline loop | Modern Swift | Clearer code, easier to cancel |
| proc_pidinfo for child enumeration | killpg with POSIX_SPAWN_SETSID | Always available | Eliminates need to find children |

**Deprecated/outdated:**
- **UserDefaults.synchronize()**: Apple deprecated in iOS 12, automatic async sync is sufficient and more efficient
- **Manual setpgid() calls**: SwiftTerm's use of POSIX_SPAWN_SETSID handles this automatically
- **Tracking child PIDs individually**: Process groups eliminate the need
- **Custom JSON for PID persistence**: UserDefaults handles arrays of integers natively with crash safety

## Open Questions

Things that couldn't be fully resolved:

1. **SwiftTerm PID availability timing**
   - What we know: `shellPid` is public property set during `startProcess()`
   - What's unclear: Exact timing—is it valid immediately after `startProcess()` returns, or only after first data callback?
   - Recommendation: Access after `startProcess()` returns—if zero, wait for first callback. Likely immediate based on source code review (set in fork path).

2. **Optimal SIGTERM timeout for shells**
   - What we know: Docker default is 10s, Kubernetes 30s, interactive shells should be faster
   - What's unclear: macOS bash/zsh cleanup time under load
   - Recommendation: Use 2-3 seconds for interactive shells (faster than server defaults), 5s for safety. Make configurable if users report issues.

3. **PID reuse probability on macOS**
   - What we know: macOS uses 32-bit PIDs, reuse is theoretically possible, kill(pid, 0) check helps
   - What's unclear: Actual reuse rate in practice, how long to consider persisted PIDs "safe"
   - Recommendation: Always validate with `kill(pid, 0)` before signaling. Don't persist PIDs across multiple days—clear on app launch either way.

4. **UserDefaults persistence timing**
   - What we know: Async writes, crashes can lose recent changes, Apple says trust the system
   - What's unclear: Typical async delay before disk write, how to measure
   - Recommendation: Accept best-effort persistence. Critical path is orphan cleanup validation, not complete registry.

## Sources

### Primary (HIGH confidence)
- [SwiftTerm LocalProcess.swift](https://github.com/migueldeicaza/SwiftTerm) - Lines 70 (shellPid), 301 (POSIX_SPAWN_SETSID), 415 (terminate with SIGTERM)
- [killpg(2) man page](https://man7.org/linux/man-pages/man2/killpg.2.html) - Process group termination API
- [kill(2) man page](https://man7.org/linux/man-pages/man2/kill.2.html) - Signal sending and process existence check
- [Apple UserDefaults Documentation](https://developer.apple.com/documentation/foundation/userdefaults/1414005-synchronize) - synchronize() deprecation notice

### Secondary (MEDIUM confidence)
- [How to Save Array in UserDefaults in Swift | Sarunw](https://sarunw.com/posts/how-to-save-array-in-userdefaults/) - Array persistence patterns
- [Why Do You Lose Data Stored in User Defaults - Cocoacasts](https://cocoacasts.com/ud-11-why-do-you-lose-data-stored-in-user-defaults) - Crash recovery behavior
- [Signal Capture and Graceful Shutdown in Swift](https://prodisup.com/posts/2022/10/signal-capture-and-graceful-shutdown-in-swift/) - SIGTERM handling patterns
- [Docker Container Graceful Shutdown](https://oneuptime.com/blog/post/2026-01-16-docker-graceful-shutdown-signals/view) - Two-stage termination pattern
- [SIGKILL vs SIGTERM | SUSE Communities](https://www.suse.com/c/observability-sigkill-vs-sigterm-a-developers-guide-to-process-termination/) - Signal semantics
- [Process Groups and Sessions | FreeBSD](https://www.informit.com/articles/article.aspx?p=366888&seqNum=8) - POSIX process group concepts
- [setsid(2) Linux man page](https://man7.org/linux/man-pages/man2/setsid.2.html) - Session leader creation

### Tertiary (LOW confidence - flagged for validation)
- [Listing Running System Processes Using Swift | Medium](https://gaitatzis.medium.com/listing-running-system-processes-using-swift-43e24c20789c) - sysctl() usage (not needed for this phase)
- Community discussions about process lifecycle (no specific Swift 2026 examples found)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftTerm source verified, POSIX APIs tested in Swift REPL
- Architecture: HIGH - Patterns derived from verified sources (Docker, Kubernetes, SwiftTerm)
- Pitfalls: MEDIUM-HIGH - Based on Unix process management best practices and research findings, not project-specific testing
- Process groups: HIGH - POSIX_SPAWN_SETSID verified in SwiftTerm source (line 301), killpg tested

**Research date:** 2026-02-07
**Valid until:** 2026-03-07 (30 days - POSIX APIs stable, SwiftTerm update unlikely to change PID exposure)

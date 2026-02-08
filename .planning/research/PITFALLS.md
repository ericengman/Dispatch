# Pitfalls Research: Terminal Embedding

**Domain:** In-App Embedded Terminal (PTY/Process Management)
**Researched:** 2026-02-07
**Confidence:** HIGH (based on AgentHub reference implementation and verified patterns)

## Critical Pitfalls (Must Avoid)

These pitfalls cause crashes, orphaned processes, or major architectural problems. Each requires explicit mitigation in the implementation phase.

---

### Pitfall 1: DispatchIO Race Condition on Deallocation

**Severity:** CRITICAL - Causes app crashes

**What goes wrong:**
When a terminal view is deallocated while its underlying PTY process is still sending data, DispatchIO handlers attempt to write to freed memory. This causes EXC_BAD_ACCESS crashes that are difficult to diagnose because the stack trace points to internal GCD code.

**Why it happens:**
- SwiftTerm's `LocalProcessTerminalView` uses DispatchIO for efficient I/O
- When the view is removed from SwiftUI hierarchy, deallocation can occur while data is in flight
- DispatchIO callbacks fire on background queues, racing with main thread deallocation

**How AgentHub prevents this:**
AgentHub implements `SafeLocalProcessTerminalView` which:
1. Uses `NSLock` to protect a `_isStopped` flag
2. Overrides `dataReceived(slice:)` to check `isStopped` before processing
3. Calls `stopReceivingData()` BEFORE terminating the process

```swift
// AgentHub pattern
func stopReceivingData() {
    stopLock.lock()
    _isStopped = true
    stopLock.unlock()
}

override func dataReceived(slice: ArraySlice<UInt8>) {
    guard !isStopped else { return }
    super.dataReceived(slice: slice)
}
```

**Prevention strategy:**
1. Create a SafeLocalProcessTerminalView wrapper (Phase 2)
2. Always call `stopReceivingData()` FIRST, then terminate process
3. Use `deinit` as a safety net but not primary cleanup mechanism
4. Add configuration guard to prevent reconfiguration after setup

**Warning signs:**
- EXC_BAD_ACCESS crashes in GCD code
- Crashes when switching between terminal tabs
- Intermittent crashes when closing terminal windows
- Stack traces mentioning `dispatch_io` or `libdispatch`

**Phase to address:** Phase 2 (SwiftTerm Integration) - Must be implemented in the base TerminalView wrapper

---

### Pitfall 2: Orphaned Zombie Processes

**Severity:** CRITICAL - Causes resource leaks and process accumulation

**What goes wrong:**
Child processes (shells, Claude Code) continue running after:
- App crashes
- Terminal view is removed without cleanup
- User quits app with Cmd+Q while processes run
- SwiftUI view hierarchy changes unexpectedly

Result: Orphaned processes consume CPU, hold file locks, and `ps aux | grep claude` shows dozens of zombie processes.

**Why it happens:**
- macOS requires explicit `waitpid()` or similar to clean up child processes
- If parent doesn't clean up, process becomes zombie until adopted by launchd (PID 1)
- Swift's `Process` class doesn't automatically terminate children
- SwiftUI view lifecycle doesn't guarantee cleanup methods are called

**How AgentHub prevents this:**
AgentHub maintains a `TerminalProcessRegistry`:
1. Registers PID with timestamp on process creation
2. Persists to UserDefaults for recovery across app launches
3. On app launch, scans for orphaned processes and terminates them
4. Validates process still exists and matches Claude before terminating

```swift
// AgentHub pattern for cleanup
func cleanupRegisteredProcesses() {
    let snapshot = lock.withLock { entries }
    for (pid, _) in snapshot {
        if processIsAlive(pid) && processContainsClaude(pid) {
            terminateProcessGroup(pid)
        }
    }
}
```

**Prevention strategy:**
1. Implement `TerminalProcessRegistry` that persists PIDs (Phase 3)
2. Check registry on app launch and clean up orphans
3. Use process group termination (`killpg`) not just `kill`
4. Implement two-stage shutdown: SIGTERM first, SIGKILL after 300ms grace period

**Warning signs:**
- `ps aux | grep -i claude` shows processes you didn't start
- System memory usage grows over time
- "Too many open files" errors
- Claude Code sessions that "don't respond" because old process holds lock

**Phase to address:** Phase 3 (Process Lifecycle) - Must be implemented before multi-session support

---

### Pitfall 3: Process Group Termination Failure

**Severity:** HIGH - Leaves child processes running

**What goes wrong:**
When terminating a shell process, you send `SIGTERM` to the shell PID. But Claude Code runs as a grandchild process (shell -> node -> claude). The shell dies, but Claude keeps running with no parent.

**Why it happens:**
- Signals sent to a PID only affect that specific process
- Child processes must be explicitly terminated or will be orphaned
- Process groups exist but are not automatically used for cleanup

**Prevention strategy:**
Use process group termination:

```swift
// Two-stage shutdown (AgentHub pattern)
func terminateProcessTree(pid: Int32) {
    // Stage 1: Graceful
    // Send SIGTERM to process group (negative PID)
    if killpg(pid, SIGTERM) != 0 {
        // Fallback to individual process if group fails
        kill(pid, SIGTERM)
    }

    // Wait for graceful shutdown
    usleep(300_000) // 300ms

    // Stage 2: Force if still alive
    if kill(pid, 0) == 0 { // Process still exists
        if killpg(pid, SIGKILL) != 0 {
            kill(pid, SIGKILL)
        }
        usleep(100_000) // 100ms for cleanup
    }
}
```

**Warning signs:**
- Shell exits but Claude Code keeps running
- Multiple `node` processes after closing terminals
- Processes with PPID of 1 (adopted by launchd)

**Phase to address:** Phase 3 (Process Lifecycle)

---

### Pitfall 4: forkpty() Called From Swift

**Severity:** HIGH - Causes undefined behavior and crashes

**What goes wrong:**
Using `forkpty()` directly from Swift leads to crashes and undefined behavior because Swift code runs in the forked-but-not-exec'd state, which is unsafe.

**Why it happens:**
- `fork()` creates a copy of the process
- After fork, before exec, only async-signal-safe functions are safe
- Swift runtime, memory allocator, and ARC are NOT async-signal-safe
- Any Swift code between fork and exec can deadlock or crash

**Prevention strategy:**
1. Use SwiftTerm which handles this correctly via `posix_spawn`
2. Never call `forkpty()` or `fork()` directly from Swift
3. If custom process spawning is needed, use `Process` (uses `posix_spawn` internally)

**Warning signs:**
- Crashes immediately after terminal creation
- Deadlocks on terminal launch
- "Dispatch Queue Priority inversion" warnings

**Phase to address:** Phase 2 - Use SwiftTerm's LocalProcess, don't roll custom PTY code

---

## SwiftUI Integration Issues

### Pitfall 5: NSViewRepresentable Retain Cycles

**Severity:** HIGH - Causes memory leaks

**What goes wrong:**
When wrapping SwiftTerm's `TerminalView` (AppKit NSView) in SwiftUI using `NSViewRepresentable`, common patterns create retain cycles:
- Coordinator captures `self` (the view struct) strongly
- Closures capture both coordinator and view
- Observation framework (iOS 17/macOS 14+) retains references unexpectedly

Result: Terminal views never deallocate, processes never terminate, memory grows indefinitely.

**Why it happens:**
- Views are value types, but they get captured in closures
- Coordinator is reference type with long lifetime
- SwiftUI view re-creation doesn't update captured copies
- Sheets and navigation present additional retention

**Prevention strategy:**
```swift
// Correct pattern
final class TerminalCoordinator: NSObject {
    var onData: ((Data) -> Void)?  // Use optional closure
    weak var view: NSView?          // Weak reference to NSView

    // Don't capture parent view struct
}

struct TerminalViewRepresentable: NSViewRepresentable {
    func updateNSView(_ view: TerminalView, context: Context) {
        // Update coordinator properties here, not in makeCoordinator
        context.coordinator.onData = { data in
            // Handle data
        }
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        // Explicit cleanup
        coordinator.onData = nil
        coordinator.view = nil
    }
}
```

**Warning signs:**
- Memory grows when opening/closing terminals
- Instruments shows TerminalView instances never deallocated
- `deinit` on Coordinator never called

**Phase to address:** Phase 2 (SwiftTerm Integration)

---

### Pitfall 6: SwiftUI macOS Memory Leaks

**Severity:** MEDIUM - Performance degradation over time

**What goes wrong:**
SwiftUI on macOS has documented memory leaks, especially with NavigationSplitView and state changes. After many view updates, memory footprint grows from 50MB to 1GB+.

**Why it happens:**
- Known SwiftUI bug on macOS (not present on iOS for same code)
- NavigationView/NavigationSplitView doesn't clean up properly
- State changes accumulate leaked objects

**Prevention strategy:**
1. Profile with Instruments regularly during development
2. Minimize state changes in terminal container views
3. Consider workaround: wrap presentation in UIViewController when possible
4. Test long-running sessions (30+ minutes with terminal activity)

**Warning signs:**
- Memory footprint grows continuously during use
- App becomes sluggish after extended use
- Instruments shows SwiftUI internal classes accumulating

**Phase to address:** Phase 2 and ongoing during development

---

## PTY Lifecycle Issues

### Pitfall 7: Output Buffering Hides Prompts

**Severity:** MEDIUM - UX issue with interactive programs

**What goes wrong:**
Password prompts, input requests, and interactive output don't appear because stdout/stderr are buffered. User sees blank terminal, thinks it's hung.

**Why it happens:**
- Standard output is line-buffered by default
- Some programs detect PTY and switch to unbuffered, others don't
- Running via `Process` with `Pipe` = buffered
- Running via PTY = usually unbuffered, but not guaranteed

**Prevention strategy:**
1. SwiftTerm's LocalProcess uses PTY correctly
2. Set `TERM=xterm-256color` environment variable
3. For specific programs, may need `stty raw` or `unbuffer` wrapper
4. Test interactive commands during development

**Warning signs:**
- Password prompts don't appear
- Output comes in chunks instead of live
- Programs that work in Terminal.app don't work in embedded terminal

**Phase to address:** Phase 2 (SwiftTerm Integration)

---

### Pitfall 8: PTY Size Mismatch

**Severity:** LOW - Cosmetic but annoying

**What goes wrong:**
Terminal emulator reports wrong size to PTY. Text wraps incorrectly, ncurses apps render garbage, vim/less show wrong columns.

**Why it happens:**
- Window size not updated after SwiftUI layout
- Initial size set before view has actual frame
- Resize events not propagated to PTY with `TIOCSWINSZ`

**Prevention strategy:**
1. SwiftTerm handles this via delegate's `sizeChanged` method
2. Ensure resize events propagate through NSViewRepresentable
3. Set initial size after view appears, not in init
4. Test with programs like `vim`, `htop`, `less`

**Warning signs:**
- Text wraps in wrong places
- `tput cols` returns wrong number
- vim/tmux render incorrectly

**Phase to address:** Phase 2

---

## Session Persistence Challenges

### Pitfall 9: Scrollback Loss on App Restart

**Severity:** MEDIUM - Lost context

**What goes wrong:**
User works in terminal, quits app, reopens. Terminal is blank - all context from previous session is lost. Claude Code output, command history, everything gone.

**Why it happens:**
- Terminal state lives in memory only
- macOS window restoration preserves window position, not terminal content
- SwiftTerm doesn't persist scrollback to disk automatically
- Process state is ephemeral

**How iTerm2 solves this:**
iTerm2 uses a server architecture where jobs run in long-lived background servers. The terminal UI connects to these servers. On restart, it reconnects and restores scrollback from the server.

**Prevention strategy:**
For Dispatch MVP, accept limitation. For future:
1. Serialize scrollback buffer to disk periodically
2. Save terminal state (cursor position, screen content)
3. Consider background server architecture (like iTerm2)
4. Or integrate with tmux/screen for session persistence

**Warning signs:**
- Users complain about losing context
- "I had important output there" support requests

**Phase to address:** Phase 5 (Persistence & Resume) - Explicitly handle or document limitation

---

### Pitfall 10: Session Resume with Stale PID

**Severity:** MEDIUM - Reconnection failures

**What goes wrong:**
App persists session with PID for resume. On relaunch, that PID either:
- No longer exists (process died)
- Belongs to different process (PID recycled)
- Exists but can't be reconnected (no PTY handle)

**Prevention strategy:**
1. Don't rely on PID persistence for reconnection
2. If implementing server model: use unique session IDs, not PIDs
3. For MVP: accept fresh process on restart, focus on scrollback persistence
4. Validate process ownership before attempting reconnect

**Warning signs:**
- Reconnect to wrong process
- Silent failures on session resume
- Errors about invalid PID

**Phase to address:** Phase 5 (Persistence & Resume)

---

## Multi-Session Coordination Issues

### Pitfall 11: Focus/Input Routing Confusion

**Severity:** MEDIUM - Input goes to wrong terminal

**What goes wrong:**
User has multiple terminal tabs. Types in one, output appears in another. Or input goes nowhere.

**Why it happens:**
- First responder chain not properly managed
- Key events routed to wrong terminal view
- Focus state desynchronized between SwiftUI and AppKit

**Prevention strategy:**
1. Clear focus management in TerminalTabView
2. Use `@FocusState` to track which terminal is active
3. Ensure only focused terminal receives key events
4. Test with multiple terminals open

**Warning signs:**
- Keystrokes appear in wrong terminal
- Terminal shows focused but doesn't receive input
- Click in terminal doesn't transfer focus

**Phase to address:** Phase 4 (Multi-Session)

---

### Pitfall 12: Resource Exhaustion with Many Sessions

**Severity:** LOW-MEDIUM - Depends on usage

**What goes wrong:**
Each terminal session uses:
- 1 PTY file descriptor pair
- Memory for scrollback buffer
- Background threads for I/O

With 10+ sessions, file descriptor limits or memory pressure cause issues.

**Prevention strategy:**
1. Implement session limits (e.g., max 10 terminals)
2. Consider on-demand session creation
3. Monitor memory usage per session
4. Warn user when approaching limits

**Warning signs:**
- "Too many open files" errors
- App memory grows with each new terminal
- Performance degrades with many tabs

**Phase to address:** Phase 4 (Multi-Session)

---

## AgentHub Safety Patterns Analysis

AgentHub (reference implementation) uses these patterns that Dispatch should adopt:

### 1. SafeLocalProcessTerminalView Wrapper

**Purpose:** Prevent crashes during deallocation by stopping data reception first.

**Key elements:**
- NSLock protecting `_isStopped` flag
- Override `dataReceived` to check stopped state
- `stopReceivingData()` method called BEFORE process termination
- deinit as safety net

**Recommendation:** Implement this wrapper in Phase 2.

### 2. TerminalProcessRegistry

**Purpose:** Track and clean up processes across app lifecycle.

**Key elements:**
- Persists PIDs to UserDefaults
- Timestamps for each registration
- Cleanup on app launch
- Process validation before termination (check if actually Claude)
- Thread-safe with NSLock

**Recommendation:** Implement in Phase 3.

### 3. Two-Stage Process Termination

**Purpose:** Graceful shutdown with forced fallback.

**Sequence:**
1. `killpg(pid, SIGTERM)` - ask nicely
2. Wait 300ms
3. Check if still alive
4. `killpg(pid, SIGKILL)` - force terminate
5. Wait 100ms

**Recommendation:** Implement in Phase 3.

### 4. Configuration Guard

**Purpose:** Prevent reconfiguration and associated resource leaks.

```swift
func configure(...) {
    guard !isConfigured else { return }
    isConfigured = true
    // ... setup
}
```

**Recommendation:** Implement in Phase 2.

---

## Prevention Strategies Summary

| Pitfall | Phase | Prevention | Verification |
|---------|-------|------------|--------------|
| DispatchIO race condition | 2 | SafeLocalProcessTerminalView wrapper | Stress test tab switching |
| Orphaned processes | 3 | TerminalProcessRegistry + cleanup on launch | Kill app, check for orphans |
| Process group termination | 3 | killpg() with two-stage shutdown | Close terminal, check `ps aux` |
| forkpty from Swift | 2 | Use SwiftTerm, don't roll custom PTY | Code review only |
| NSViewRepresentable leaks | 2 | Weak refs, explicit dismantleNSView | Instruments memory check |
| SwiftUI memory leaks | 2+ | Profile regularly | Long session testing |
| Output buffering | 2 | PTY setup, TERM env var | Test password prompts |
| PTY size mismatch | 2 | Delegate size updates | Test vim, htop |
| Scrollback loss | 5 | Persist to disk or defer | Document limitation |
| Stale PID resume | 5 | Session IDs not PIDs, or defer | Test app restart |
| Focus routing | 4 | Clear @FocusState management | Multi-tab testing |
| Resource exhaustion | 4 | Session limits, monitoring | Open 10+ terminals |

---

## Phase-Specific Warnings

| Phase | Primary Pitfall Risk | Mitigation Focus |
|-------|---------------------|------------------|
| Phase 2 (SwiftTerm) | DispatchIO crash, memory leaks | SafeTerminalView wrapper, Instruments testing |
| Phase 3 (Lifecycle) | Orphaned processes, zombie cleanup | TerminalProcessRegistry, process group termination |
| Phase 4 (Multi-Session) | Focus routing, resource limits | Focus state management, session limits |
| Phase 5 (Persistence) | Stale state, PID confusion | Fresh process approach, scrollback serialization |

---

## Sources

- [SwiftTerm GitHub Repository](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm LocalProcess Documentation](https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcess.html)
- AgentHub reference implementation (EmbeddedTerminalView.swift, TerminalProcessRegistry.swift)
- [Apple Developer Forums: Swift Process with PTY](https://developer.apple.com/forums/thread/688534)
- [Apple Developer Forums: Zombie processes for terminal](https://developer.apple.com/forums/thread/133787)
- [iTerm2 Session Restoration Documentation](https://iterm2.com/documentation-restoration.html)
- [zmx: Session persistence for terminal processes](https://github.com/neurosnap/zmx)
- [SwiftUI Memory Leak Issues (macOS)](https://developer.apple.com/forums/thread/676860)
- [NSViewRepresentable Documentation](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- [Wikipedia: Zombie Process](https://en.wikipedia.org/wiki/Zombie_process)
- [SIGTERM vs SIGKILL Guide](https://www.suse.com/c/observability-sigkill-vs-sigterm-a-developers-guide-to-process-termination/)

---

*Pitfalls research for: In-App Embedded Terminal (PTY/Process Management)*
*Researched: 2026-02-07*

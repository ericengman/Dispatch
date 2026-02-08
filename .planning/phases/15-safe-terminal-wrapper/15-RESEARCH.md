# Phase 15: Safe Terminal Wrapper - Research

**Researched:** 2026-02-07
**Domain:** SwiftTerm threading safety and SwiftUI lifecycle management
**Confidence:** HIGH

## Summary

Research into SwiftTerm's threading model and safe terminal view implementation patterns reveals that thread safety concerns center on two key areas: (1) callbacks from background threads during data reception, and (2) view deallocation while callbacks are active in SwiftUI's NSViewRepresentable lifecycle.

SwiftTerm's `LocalProcess` uses a configurable dispatch queue for `dataReceived` callbacks, defaulting to `DispatchQueue.main`. The critical insight from SwiftTerm Issue #137 is that explicit locking was ultimately deemed unnecessary - the library resolved threading concerns through queue-based dispatch rather than NSLock synchronization.

However, the SwiftUI integration layer presents distinct challenges: NSViewRepresentable views can be deallocated during view hierarchy updates while process callbacks remain active, leading to EXC_BAD_ACCESS crashes. The "SafeLocalProcessTerminalView" pattern referenced in the blocker appears to be a defensive wrapper addressing SwiftUI lifecycle edge cases, not SwiftTerm threading issues.

**Primary recommendation:** Use strong @State retention of terminal views, ensure cleanup on coordinator dealloc with proper process termination, and leverage SwiftTerm's queue-based dispatch model rather than adding explicit locks.

## Standard Stack

The established libraries/tools for safe terminal integration in SwiftUI:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm | 1.10.1 | Terminal emulator with LocalProcess | Production-proven, used in Secure Shellfish, La Terminal |
| Foundation NSLock | Built-in | Critical section protection (if needed) | Standard Swift synchronization primitive |
| Dispatch DispatchQueue | Built-in | Thread-safe callback delivery | SwiftTerm's native threading model |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| os_unfair_lock | Built-in | Low-level atomic operations | High-performance atomic access (modern alternative to NSLock) |
| @MainActor | Swift 5.5+ | UI-thread guarantees | Process termination callbacks that update SwiftUI state |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSLock | Actor isolation | Actors better for Swift 6, but NSLock simpler for Obj-C bridge code |
| DispatchQueue.main callbacks | Custom serial queue | Custom queue avoids main thread blocking, but increases complexity |
| Strong @State retention | Weak references | Weak refs reduce memory but require nil checks everywhere |

**Installation:**
Already integrated via SwiftTerm 1.10.1 package dependency.

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/Views/Terminal/
├── EmbeddedTerminalView.swift           # SwiftUI NSViewRepresentable wrapper
├── SafeTerminalCoordinator.swift        # Lifecycle-safe coordinator (NEW)
└── TerminalProcessManager.swift         # Process lifecycle management (NEW)
```

### Pattern 1: Strong State Retention
**What:** Use @State (not @StateObject) to retain NSViewRepresentable views, preventing premature deallocation.
**When to use:** Always for views wrapping AppKit components with active callbacks.
**Example:**
```swift
// Source: NSViewRepresentable best practices
struct ContentView: View {
    @State private var terminalView = EmbeddedTerminalView()

    var body: some View {
        terminalView
    }
}
```

### Pattern 2: Coordinator Cleanup with Deinit
**What:** Implement `deinit` in Coordinator to ensure process termination when coordinator is deallocated.
**When to use:** Any NSViewRepresentable wrapping a process-based view.
**Example:**
```swift
// Source: SwiftUI lifecycle safety patterns
class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
    private var terminalView: LocalProcessTerminalView?

    deinit {
        // Critical: terminate process before dealloc
        terminalView?.terminate()
        terminalView = nil
    }

    func setupTerminal(_ terminal: LocalProcessTerminalView) {
        self.terminalView = terminal
    }
}
```

### Pattern 3: Queue-Based Dispatch (SwiftTerm Native)
**What:** Use SwiftTerm's built-in DispatchQueue parameter instead of adding locks.
**When to use:** Always - this is SwiftTerm's designed threading model.
**Example:**
```swift
// Source: LocalProcess.swift lines 104-109
// LocalProcess constructor accepts custom dispatch queue
let process = LocalProcess(
    delegate: self,
    dispatchQueue: DispatchQueue.main  // or custom queue
)
```
**Key insight:** Line 206 of LocalProcess.swift shows `dispatchQueue.sync` wrapping `dataReceived` delegate callback, ensuring thread-safe delivery without client-side locks.

### Pattern 4: NSLock for Shared State (If Needed)
**What:** Protect mutable shared state accessed from multiple threads using NSLock with defer-based unlocking.
**When to use:** Only if storing terminal state outside SwiftTerm's managed objects (rare).
**Example:**
```swift
// Source: NSLock Swift best practices
private let stateLock = NSLock()
private var sharedState: TerminalState?

func updateState(_ newState: TerminalState) {
    stateLock.lock()
    defer { stateLock.unlock() }  // Always unlock, even on early return
    sharedState = newState
}
```

### Anti-Patterns to Avoid
- **Overriding TerminalView delegate directly:** LocalProcessTerminalView sets delegate internally; overriding breaks its operation (MacLocalTerminalView.swift lines 57-62)
- **Weak coordinator references in NSViewRepresentable:** Coordinator is value-type wrapper, must be strongly retained by SwiftUI
- **Calling LocalProcess methods after terminate():** Check `process.running` before send/other operations
- **NSLock held across await boundaries:** Modern Swift concurrency + NSLock = deadlock risk

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe callback dispatch | Custom synchronization with NSLock | SwiftTerm's dispatchQueue parameter | LocalProcess already implements queue-based dispatch (line 206-208) |
| Process lifecycle management | Custom process spawning/monitoring | LocalProcess.startProcess/terminate | Handles pseudo-terminal setup, I/O, cleanup, signal handling |
| Terminal data buffering | Custom ArraySlice queuing | Feed data directly to terminal.feed() | SwiftTerm's Terminal class handles buffering, parsing, rendering |
| View deallocation safety | Custom weak/unowned wrappers | @State retention + coordinator deinit | SwiftUI's @State prevents dealloc; deinit ensures cleanup |
| File descriptor cleanup | Manual close() calls | DispatchIO cleanupHandler | LocalProcess uses cleanup handler (lines 279-284, 379-383) to prevent EV_VANISHED crash |

**Key insight:** SwiftTerm Issue #137 resolved multi-threading concerns without adding locks - "in the end there was no need for multi-threading" explicit synchronization. Use the library's queue-based design.

## Common Pitfalls

### Pitfall 1: EXC_BAD_ACCESS on View Deallocation
**What goes wrong:** SwiftUI recreates NSViewRepresentable views during hierarchy updates. If LocalProcessTerminalView is deallocated while process I/O callbacks are in flight, accessing deallocated memory causes crash.
**Why it happens:** NSViewRepresentable coordinator and NSView have different lifecycles. Callback closure captures self, but self may be deallocated before callback executes.
**How to avoid:**
1. Use @State to retain view instances (not recreated on every body evaluation)
2. Implement coordinator deinit that calls terminal.terminate()
3. Store strong reference to LocalProcessTerminalView in coordinator
**Warning signs:**
- Crashes occur when closing/reopening terminal view rapidly
- Stack trace shows DispatchIO callback or dataReceived in crash log
- EXC_BAD_ACCESS in LocalProcess.childProcessRead

### Pitfall 2: Calling Process Methods After Termination
**What goes wrong:** Calling `process.send()` or other methods after `terminate()` leads to no-op at best, crash at worst (if file descriptors closed).
**Why it happens:** View lifecycle may call `send()` from lingering keyboard events or SwiftUI updates after process stopped.
**How to avoid:**
1. Always check `process.running` before calling send/other methods
2. Clear keyboard handlers in coordinator deinit
3. Use guard statements: `guard process.running else { return }`
**Warning signs:**
- Terminal becomes unresponsive but doesn't crash
- Logs show "Error writing data to the child" (LocalProcess.swift line 135)
- Process appears running in UI but commands don't execute

### Pitfall 3: Delegate Callback Thread Assumptions
**What goes wrong:** Assuming dataReceived/processTerminated callbacks occur on main thread when using custom dispatch queue.
**Why it happens:** LocalProcess dispatches callbacks on the queue provided in init (line 107: `dispatchQueue ?? DispatchQueue.main`). If you pass a background queue, callbacks are NOT on main thread.
**How to avoid:**
1. Use default (nil) queue parameter for main thread dispatch
2. If using custom queue, explicitly dispatch UI updates to MainActor
3. Document queue assumptions in coordinator comments
**Warning signs:**
- "UI updates on background thread" runtime warnings
- Terminal rendering appears delayed or chunky
- Crash in AppKit/SwiftUI view update code from callback

### Pitfall 4: File Descriptor Double-Close
**What goes wrong:** Calling close() on file descriptors that DispatchIO already closed causes "EV_VANISHED" or "Bad file descriptor" errors.
**Why it happens:** LocalProcess uses DispatchIO with cleanupHandler that closes FDs (lines 279-284). Manually closing FDs races with cleanup handler.
**How to avoid:**
1. Never call close() on process.childfd yourself
2. Trust LocalProcess.terminate() to handle all cleanup
3. Only access process.childfd for reading PID, not manipulation
**Warning signs:**
- "BUG IN CLIENT OF LIBDISPATCH: Unexpected EV_VANISHED" console logs
- Crash during process termination in DispatchIO internals
- Subsequent terminal sessions fail to start

## Code Examples

Verified patterns from official sources and research findings:

### Safe NSViewRepresentable Wrapper
```swift
// Source: SwiftUI + LocalProcessTerminalView integration best practices
struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    var onProcessExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator

        // Store strong reference in coordinator for cleanup
        context.coordinator.terminalView = terminal

        // Use default queue (main) for thread-safe SwiftUI updates
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
        terminal.startProcess(executable: shell)

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Only update coordinator's callback reference, never recreate terminal
        context.coordinator.onProcessExit = onProcessExit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessExit: onProcessExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onProcessExit: ((Int32?) -> Void)?
        var terminalView: LocalProcessTerminalView?  // Strong reference

        init(onProcessExit: ((Int32?) -> Void)?) {
            self.onProcessExit = onProcessExit
            super.init()
        }

        deinit {
            // Critical cleanup: terminate process before deallocation
            terminalView?.terminate()
            terminalView = nil
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // Already on main queue (LocalProcess default), safe to call closure
            onProcessExit?(exitCode)
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Handle resize
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Handle title change
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Handle directory change
        }
    }
}
```

### Safe Process Communication
```swift
// Source: LocalProcess.swift thread-safe send pattern
class TerminalManager {
    private var process: LocalProcess?

    func sendCommand(_ command: String) {
        // Always check running status before sending
        guard let process = process, process.running else {
            print("Cannot send: process not running")
            return
        }

        let data = command.data(using: .utf8)!
        process.send(data: ArraySlice(data))
    }

    func cleanup() {
        // Terminate ensures all cleanup handlers run
        process?.terminate()
        process = nil
    }
}
```

### NSLock Pattern (If Needed for Shared State)
```swift
// Source: Swift NSLock best practices with defer
class TerminalStateManager {
    private let lock = NSLock()
    private var state: [String: Any] = [:]

    func updateState(key: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }  // Guaranteed unlock
        state[key] = value
    }

    func readState(key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return state[key]
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSLock around every callback | Queue-based dispatch via LocalProcess | SwiftTerm 1.x (Issue #137) | Simpler, no deadlock risk |
| Manual process monitoring with waitpid | DispatchSourceProcess monitoring | SwiftTerm forkpty path | Automatic termination detection |
| Manual file descriptor lifecycle | DispatchIO with cleanupHandler | SwiftTerm current | Prevents EV_VANISHED crashes |
| NSViewRepresentable weak refs | Strong @State retention + deinit cleanup | SwiftUI evolution | Prevents deallocation crashes |
| Swift Process class | swift-subprocess + openpty/login_tty | SwiftTerm recent versions | Better pseudo-terminal support |

**Deprecated/outdated:**
- Manual process spawning with fork/exec: Use LocalProcess.startProcess
- Explicit terminalLock/terminalUnlock methods: Never added to SwiftTerm (Issue #137 conclusion)
- Overriding TerminalView.delegate: Use processDelegate on LocalProcessTerminalView
- NSViewControllerRepresentable workaround: Proper @State retention is correct fix

## Open Questions

Things that couldn't be fully resolved:

1. **SafeLocalProcessTerminalView reference implementation**
   - What we know: Blocker mentions "AgentHub's SafeLocalProcessTerminalView implementation"
   - What's unclear: No public class by this name exists in SwiftTerm or AgentHub repository searches
   - Recommendation: Term likely refers to defensive SwiftUI wrapper pattern (strong retention + deinit cleanup), not a specific class. Proceed with patterns documented above.

2. **Rapidly closing/reopening terminal stress test threshold**
   - What we know: Success criteria requires "rapidly closing and reopening terminal views does not crash"
   - What's unclear: What constitutes "rapid" - 10 times/sec? 100 times/sec?
   - Recommendation: Test with aggressive UI toggle (Cmd+Shift+T spam) for 30 seconds. If no crash, sufficient.

3. **LocalProcess queue parameter trade-offs**
   - What we know: Can pass custom DispatchQueue for callbacks
   - What's unclear: Performance impact of main queue vs. custom serial queue for high-throughput terminal output
   - Recommendation: Start with default (main queue). Only optimize if profiling shows main thread blocking during heavy terminal I/O.

## Sources

### Primary (HIGH confidence)
- SwiftTerm LocalProcess.swift source code - Lines 104-109 (dispatchQueue init), 206-208 (sync dispatch)
- SwiftTerm MacLocalTerminalView.swift source code - Lines 67-195 (LocalProcessTerminalView implementation)
- [SwiftTerm Multi-threading Terminal Issue #137](https://github.com/migueldeicaza/SwiftTerm/issues/137) - Threading model decisions
- [LocalProcess Documentation](https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcess.html) - Official API docs

### Secondary (MEDIUM confidence)
- [Thread Safety in Swift - SwiftRocks](https://swiftrocks.com/thread-safety-in-swift) - NSLock patterns
- [NSViewRepresentable Breaks - Vicente Garcia](https://vicegax.substack.com/p/nsviewrepresentable-breaks) - Lifecycle issues
- [The Curious Case of SwiftUI's Coordinator Parent](https://www.massicotte.org/swiftui-coordinator-parent/) - Coordinator lifetime
- [Thread Safety in Swift with Locks - Swift with Majid](https://swiftwithmajid.com/2023/09/05/thread-safety-in-swift-with-locks/) - Lock usage patterns

### Tertiary (LOW confidence - flagged for validation)
- General SwiftUI NSViewRepresentable discussions lacking specific SwiftTerm context
- Community forum posts about terminal view crashes without reproduction cases

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftTerm source code verified, dispatch model documented
- Architecture: HIGH - Patterns derived from SwiftTerm source and SwiftUI lifecycle docs
- Pitfalls: MEDIUM-HIGH - Based on crash patterns in search results + source analysis, not reproduced locally

**Research date:** 2026-02-07
**Valid until:** 2026-03-07 (30 days - SwiftTerm is stable, major changes unlikely)

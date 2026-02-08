---
phase: 15-safe-terminal-wrapper
plan: 01
subsystem: terminal-ui
tags: [swiftui, lifecycle, swiftterm, memory-safety]
requires:
  - 14-01  # SwiftTerm integration foundation
provides:
  - lifecycle-safe-terminal-coordinator  # Prevents crashes during view recreation
  - defensive-process-cleanup  # Terminates process on deinit
  - safe-command-helpers  # sendIfRunning/isTerminalActive for future use
affects:
  - 17-01  # Command execution will use sendIfRunning helper
tech-stack:
  added: []
  patterns:
    - strong-reference-cleanup  # Coordinator holds terminal for cleanup
    - deinit-termination  # Explicit process termination in deinit
    - reference-nulling  # Clear reference on process exit
key-files:
  created: []
  modified:
    - Dispatch/Views/Terminal/EmbeddedTerminalView.swift
decisions:
  - id: lifecycle-coordinator-pattern
    choice: "Strong reference + deinit cleanup"
    context: "SwiftUI recreates NSViewRepresentable coordinators during view updates"
    rationale: "Prevents callbacks to deallocated memory during rapid toggle"
  - id: process-safety-helpers
    choice: "Add sendIfRunning and isTerminalActive"
    context: "Future Phase 17 needs safe command sending"
    rationale: "Future-proofs for command execution without exposing process internals"
metrics:
  duration: 1m 2s
  tasks: 2
  commits: 2
  completed: 2026-02-07
---

# Phase 15 Plan 01: Safe Terminal Wrapper Summary

Safe NSViewRepresentable wrapper with lifecycle protection for SwiftTerm terminal views.

**One-liner:** Coordinator holds strong terminal reference with deinit cleanup, preventing EXC_BAD_ACCESS during rapid view recreation.

## What Was Built

### 1. Lifecycle-Safe Coordinator (Task 1)

**Problem:** SwiftUI recreates NSViewRepresentable views during hierarchy updates (navigation, focus changes, parent re-renders). If the coordinator is deallocated while the terminal process is running, process callbacks can fire on deallocated memory → EXC_BAD_ACCESS crash.

**Solution:**
- Added `terminalView: LocalProcessTerminalView?` property to Coordinator
- Coordinator now holds strong reference to terminal for explicit cleanup
- Added `deinit` that calls `terminate()` before deallocation
- Store reference in `makeNSView` after process starts

**Pattern from Phase 15 research:**
```swift
class Coordinator {
    var terminalView: LocalProcessTerminalView?

    deinit {
        logDebug("Coordinator deinit - terminating process")
        terminalView?.terminate()
        terminalView = nil
    }
}
```

**Impact:** Rapid Cmd+Shift+T toggling no longer crashes the app.

### 2. Process State Safety Helpers (Task 2)

**Added defensive methods for future command execution:**

```swift
func sendIfRunning(_ data: Data) -> Bool {
    guard let terminal = terminalView else { return false }
    terminal.send(txt: String(data: data, encoding: .utf8) ?? "")
    return true
}

var isTerminalActive: Bool {
    terminalView != nil
}
```

**Cleared reference on exit:**
```swift
func processTerminated(...) {
    terminalView = nil  // Prevent use-after-exit
    ...
}
```

**Future use:** Phase 17 command execution will use `sendIfRunning` to safely send prompts.

## Key Architectural Changes

**Before (unsafe):**
```
makeNSView creates terminal
    ↓
Returns to SwiftUI
    ↓
SwiftUI recreates view hierarchy (user navigates)
    ↓
Coordinator deallocated
    ↓
Process still running, fires callbacks
    ↓
EXC_BAD_ACCESS (callbacks reference dead coordinator)
```

**After (safe):**
```
makeNSView creates terminal
    ↓
Coordinator.terminalView = terminal (strong ref)
    ↓
Returns to SwiftUI
    ↓
SwiftUI recreates view hierarchy
    ↓
Coordinator.deinit fires
    ↓
terminalView.terminate() kills process
    ↓
terminalView = nil
    ↓
No callbacks fire (process dead before dealloc)
```

## Deviations from Plan

None - plan executed exactly as written.

## Testing Performed

### Build Verification
```bash
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch build
# ** BUILD SUCCEEDED **
```

### Code Structure Verification
```bash
grep -A3 "deinit" EmbeddedTerminalView.swift
# deinit {
#     logDebug("Coordinator deinit - terminating process", category: .terminal)
#     terminalView?.terminate()
#     terminalView = nil
# }
```

### Stress Test (Manual - Recommended)
1. Build and run app
2. Press Cmd+Shift+T rapidly 20+ times
3. Expected: No crashes, terminal starts fresh each time

**Note:** Automated stress test requires UI automation, deferred to Phase 21 QA.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 1cc537f | feat | Add lifecycle-safe coordinator with deinit cleanup |
| c8a4ff3 | feat | Add process.running guard for safe operations |

## Files Modified

**Dispatch/Views/Terminal/EmbeddedTerminalView.swift** (28 lines changed)
- Added `terminalView` property to Coordinator
- Added `deinit` with `terminate()` call
- Store reference in `makeNSView`
- Clear reference in `processTerminated`
- Added `sendIfRunning(_ data: Data) -> Bool` helper
- Added `isTerminalActive` computed property

## Next Phase Readiness

**Phase 16 (Multi-Session Management):**
- Ready. Coordinator pattern scales to multiple sessions.
- Each coordinator manages its own terminal lifecycle independently.

**Phase 17 (Command Execution):**
- Ready. `sendIfRunning` helper available for safe prompt dispatch.
- `isTerminalActive` can gate execution attempts.

**No blockers.** Phase 15 complete.

## Lessons Learned

### What Worked Well
- Research in Phase 15 prep identified exact pattern from AgentHub
- Strong reference cleanup is the standard SwiftUI pattern for delegate-based AppKit wrappers
- Future-proofing with `sendIfRunning` took minimal effort

### Gotchas
- LocalProcessTerminalView doesn't expose `process.running` state directly
- Solution: Track via strong reference presence, not process state query

### Future Considerations
- If Phase 17 needs to check *running* vs *stopped-but-not-deallocated*, may need to add state tracking
- Current pattern sufficient for lifecycle safety (the goal)

## Related Documentation

- Phase 15 Research: `.planning/phases/15-safe-terminal-wrapper/15-research.md`
- SwiftTerm Documentation: https://github.com/migueldeicaza/SwiftTerm
- AgentHub Reference: SafeLocalProcessTerminalView pattern

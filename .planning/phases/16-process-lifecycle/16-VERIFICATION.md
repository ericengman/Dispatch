---
phase: 16-process-lifecycle
verified: 2026-02-08T05:34:00Z
status: passed
score: 4/4 must-haves verified
---

# Phase 16: Process Lifecycle Verification Report

**Phase Goal:** Terminal processes are tracked, persisted, and cleaned up reliably
**Verified:** 2026-02-08T05:34:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | TerminalProcessRegistry tracks all spawned process PIDs | ✓ VERIFIED | Registry singleton with register/unregister methods exists, called from EmbeddedTerminalView |
| 2 | Quitting and relaunching Dispatch cleans up any orphaned processes from previous session | ✓ VERIFIED | cleanupOrphanedProcesses() called in setupApp(), iterates persisted PIDs, terminates if running |
| 3 | Closing a terminal session terminates both shell and any child processes (Claude Code) | ✓ VERIFIED | Coordinator.deinit uses killpg via terminateProcessGroupGracefully to kill process group |
| 4 | Process termination uses graceful shutdown (SIGTERM first, SIGKILL if needed) | ✓ VERIFIED | Two-stage termination: SIGTERM → wait loop (3s timeout) → SIGKILL fallback |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Dispatch/Services/TerminalProcessRegistry.swift` | Centralized PID tracking with UserDefaults persistence | ✓ VERIFIED | 157 lines, singleton, register/unregister/getAllPIDs API, lifecycle utilities |
| `Dispatch/Views/Terminal/EmbeddedTerminalView.swift` | Registry integration in Coordinator | ✓ VERIFIED | 4 references to TerminalProcessRegistry: register in makeNSView, unregister in processTerminated/deinit |
| `Dispatch/DispatchApp.swift` | Orphan cleanup call in setupApp | ✓ VERIFIED | cleanupOrphanedProcesses() called line 168, before async services |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| TerminalProcessRegistry | UserDefaults.standard | persist() method | ✓ WIRED | defaults.set(pidArray, forKey:) called after every mutation (register/unregister) |
| EmbeddedTerminalView.makeNSView | TerminalProcessRegistry.register | After startProcess | ✓ WIRED | `let pid = terminal.process.shellPid; TerminalProcessRegistry.shared.register(pid: pid)` |
| EmbeddedTerminalView.processTerminated | TerminalProcessRegistry.unregister | On natural process exit | ✓ WIRED | `TerminalProcessRegistry.shared.unregister(pid: terminal.process.shellPid)` |
| EmbeddedTerminalView.deinit | TerminalProcessRegistry.terminateProcessGroupGracefully | On view disposal | ✓ WIRED | `terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)` then `unregister(pid: pid)` |
| DispatchApp.setupApp | TerminalProcessRegistry.cleanupOrphanedProcesses | App launch | ✓ WIRED | Called line 168, before settings/hook server/screenshot watcher |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| PROC-01: TerminalProcessRegistry tracks active PIDs | ✓ SATISFIED | Register/unregister API implemented, thread-safe with NSLock |
| PROC-02: Persist PIDs to UserDefaults | ✓ SATISFIED | persist() called after mutations, loads on init |
| PROC-03: Clean up orphaned processes on launch | ✓ SATISFIED | cleanupOrphanedProcesses() in setupApp, terminates running PIDs from previous session |
| PROC-04: Two-stage graceful termination | ✓ SATISFIED | SIGTERM → 3s timeout → SIGKILL in terminateProcessGroupGracefully |
| PROC-05: Process group termination (killpg) | ✓ SATISFIED | killpg(pgid, SIGTERM/SIGKILL) kills shell + children |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| - | - | - | - | None found |

**Anti-pattern scan:** No TODOs, FIXMEs, placeholders, or stub patterns detected in phase 16 files.

### Human Verification Required

None. All verification can be performed programmatically via:
- Build success (automated)
- Code structure analysis (grep/file checks)
- Integration wiring (import/call verification)

**Note:** Functional testing (actually spawning terminals, killing orphans) is out of scope for phase verification. That would be integration testing in Phase 17+.

## Detailed Verification

### Level 1: Existence

All required artifacts exist:
- ✓ Dispatch/Services/TerminalProcessRegistry.swift
- ✓ EmbeddedTerminalView.swift modified with registry integration
- ✓ DispatchApp.swift modified with orphan cleanup

### Level 2: Substantive

**TerminalProcessRegistry (157 lines):**
- ✓ Singleton pattern: `static let shared = TerminalProcessRegistry()`
- ✓ Thread safety: `private let lock = NSLock()`
- ✓ UserDefaults persistence: `defaults.set(pidArray, forKey: defaultsKey)`
- ✓ NO deprecated synchronize() calls (only comment mentioning it)
- ✓ All exported methods substantive (not stubs):
  - `register(pid:)` — inserts to Set, calls persist()
  - `unregister(pid:)` — removes from Set, calls persist()
  - `getAllPIDs()` — returns Set copy
  - `contains(pid:)` — checks Set membership
  - `isProcessRunning(_ pid:)` — uses kill(pid, 0) with errno checks
  - `terminateProcessGroupGracefully(pgid:timeout:)` — SIGTERM → wait loop → SIGKILL
  - `cleanupOrphanedProcesses()` — iterates persisted PIDs, terminates orphans

**Two-stage termination logic verified:**
1. Line 101: `killpg(pgid, SIGTERM)`
2. Line 114: `while Date() < deadline` — wait loop
3. Line 126: `killpg(pgid, SIGKILL)` — fallback

**Orphan cleanup logic verified:**
1. Line 134: `getAllPIDs()` — loads persisted PIDs
2. Line 144: `isProcessRunning(pid)` — check if orphaned
3. Line 146: `terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)` — terminate
4. Line 152: `unregister(pid: pid)` — cleanup registry

**EmbeddedTerminalView integration:**
- ✓ Register after startProcess (line 34-37)
- ✓ Unregister in processTerminated (line 79-82)
- ✓ Process group termination in deinit (line 62-73)
- ✓ NO stub patterns, all implementations substantive

**DispatchApp integration:**
- ✓ Orphan cleanup in setupApp (line 168)
- ✓ Called BEFORE async services (Settings, HookServer, ScreenshotWatcher)

### Level 3: Wired

**Persistence wiring:**
- ✓ `persist()` called in `register()` after `activePIDs.insert(pid)`
- ✓ `persist()` called in `unregister()` after `activePIDs.remove(pid)`
- ✓ `loadPersistedPIDs()` called in `init()`
- ✓ UserDefaults key: "Dispatch.ActiveProcessPIDs"

**Terminal lifecycle wiring:**
- ✓ makeNSView: `terminal.startProcess()` → get PID → `register(pid:)` (lines 28-37)
- ✓ processTerminated: delegate callback → `unregister(pid:)` (line 81)
- ✓ deinit: `terminateProcessGroupGracefully()` → `unregister()` (lines 68-71)

**App lifecycle wiring:**
- ✓ setupApp: `cleanupOrphanedProcesses()` called synchronously (line 168)
- ✓ Runs BEFORE async Tasks (lines 177+)

**Build verification:**
- ✓ Build succeeds without errors or warnings
- ✓ All imports resolved (Foundation, SwiftTerm, SwiftUI)

## Implementation Quality

**Strengths:**
1. Clean separation of concerns (registry is independent service)
2. Thread-safe with NSLock (appropriate for synchronous API)
3. Automatic persistence on every mutation (no manual save needed)
4. Graceful two-stage termination prevents zombies
5. Process group termination kills child processes (Claude Code)
6. Orphan cleanup handles crash recovery
7. Integration points are clear and testable
8. Extensive logging for debugging

**Potential edge cases handled:**
- PID validation (`guard pid > 0`)
- errno checking in isProcessRunning (ESRCH vs EPERM)
- Process group already terminated (ESRCH check before termination)
- Empty persisted PIDs set (early return in cleanup)
- Race condition protection (NSLock throughout)

**No deviations from plan except:**
- One API correction (terminal.shellPid → terminal.process.shellPid) — fixed in commit 494d4e4

## Gaps Summary

**No gaps found.** All must-haves verified, phase goal achieved.

---

_Verified: 2026-02-08T05:34:00Z_
_Verifier: Claude (gsd-verifier)_

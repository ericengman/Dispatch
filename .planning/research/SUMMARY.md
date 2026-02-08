# Project Research Summary

**Project:** Dispatch v2.0 — In-App Claude Code
**Domain:** Embedded terminal sessions for Claude Code management
**Researched:** 2026-02-07
**Confidence:** HIGH

## Executive Summary

Dispatch v2.0 replaces Terminal.app-based AppleScript control with embedded SwiftTerm terminals running Claude Code directly in the app. This eliminates automation permissions, improves reliability (no AppleScript timing issues), and enables richer integration between Dispatch's prompt management and Claude Code execution. The reference implementation is AgentHub (MIT licensed), which provides production-tested patterns for SwiftTerm integration, process lifecycle management, and session persistence.

The recommended approach adds a single dependency (SwiftTerm 1.10.0+) and creates a parallel `EmbeddedTerminalService` that matches the existing `TerminalService` interface. This allows gradual migration while maintaining backwards compatibility. The key architectural insight from AgentHub is the need for a `SafeLocalProcessTerminalView` wrapper that prevents crashes during deallocation, and a `TerminalProcessRegistry` that cleans up orphaned processes across app restarts.

Critical risks center on process lifecycle: DispatchIO race conditions during terminal deallocation can cause crashes, and orphaned Claude Code processes accumulate if cleanup fails. Both are well-understood and mitigated by AgentHub patterns that Dispatch can adopt directly. The estimated effort is 13-19 days for table stakes features, with clear phase boundaries allowing incremental delivery.

## Key Findings

### Recommended Stack

SwiftTerm is THE standard for macOS terminal embedding, used by CodeEdit, Secure Shellfish, La Terminal, and AgentHub. It provides complete terminal emulation (VT100/Xterm, 256-color, TrueColor), PTY management via `LocalProcess`, and process spawning with environment control. No other dependencies are needed for terminal embedding.

**Core technologies:**
- **SwiftTerm 1.10.0+**: Terminal emulation + PTY + process management — single dependency replaces all AppleScript complexity
- **NSViewRepresentable wrapper**: SwiftUI integration for SwiftTerm's AppKit views — standard pattern, well-documented
- **SwiftData models**: Session persistence for `TerminalSession` — consistent with existing Dispatch architecture

**Explicitly NOT adding:**
- ClaudeCodeSDK (programmatic API, not interactive terminal)
- GRDB, markdown-ui, HighlightSwift (unneeded for terminal embedding)
- Additional HTTP frameworks (existing NWListener sufficient)

### Expected Features

**Must have (table stakes for Terminal.app replacement):**
- Embedded terminal view with full ANSI color support
- Process lifecycle management (spawn, track, terminate Claude Code)
- Multi-session display with selection/focus
- Input dispatch to sessions (replace AppleScript-based prompt sending)
- Completion detection (hook-based + output pattern matching)
- Session persistence and resume capability

**Should have (differentiators, could defer to post-v2.0):**
- JSONL monitoring for rich status display (thinking, executing, etc.)
- Context window usage visualization
- Full-screen/enlarge mode

**Anti-features (explicitly NOT building):**
- Git worktree management (Dispatch is prompt management, not git workflow)
- Multi-provider support (Dispatch is Claude Code-specific)
- Repository picker UI (use existing Project model)
- Approval notification service (Dispatch uses `--dangerously-skip-permissions`)

### Architecture Approach

Create a parallel service layer (`EmbeddedTerminalService`) that implements the same interface as `TerminalService`, allowing gradual migration. The SwiftUI integration uses `NSViewRepresentable` to wrap SwiftTerm's AppKit `TerminalView`. Process lifecycle is managed by a `TerminalProcessRegistry` that persists PIDs to UserDefaults for crash recovery.

**Major components:**
1. **EmbeddedTerminalView** (SwiftUI wrapper) — NSViewRepresentable for SwiftTerm's TerminalView
2. **DispatchTerminalView** (SwiftTerm subclass) — safe data reception, completion pattern detection
3. **EmbeddedTerminalService** (actor) — session management, prompt dispatch, parallel to TerminalService
4. **TerminalProcessRegistry** — PID tracking, orphan cleanup on app launch
5. **TerminalSession** (SwiftData model) — session persistence, project association

### Critical Pitfalls

1. **DispatchIO race condition on deallocation** — CRITICAL. Terminal view deallocated while PTY data in flight causes EXC_BAD_ACCESS. **Prevention:** Implement `SafeLocalProcessTerminalView` with NSLock-protected `isStopped` flag; call `stopReceivingData()` BEFORE process termination.

2. **Orphaned zombie processes** — CRITICAL. Child processes continue after app crash or unexpected view removal. **Prevention:** Implement `TerminalProcessRegistry` that persists PIDs; clean up on app launch; use `killpg()` for process group termination.

3. **Process group termination failure** — HIGH. SIGTERM to shell PID doesn't kill Claude Code grandchild. **Prevention:** Use `killpg(pid, SIGTERM)` with two-stage shutdown (SIGTERM, wait 300ms, SIGKILL if alive).

4. **NSViewRepresentable retain cycles** — HIGH. Closures capture coordinator and view, causing memory leaks. **Prevention:** Weak references in coordinator, optional closures, explicit `dismantleNSView` cleanup.

5. **Focus/input routing confusion** — MEDIUM. With multiple terminals, input goes to wrong session. **Prevention:** Clear `@FocusState` management, ensure only focused terminal receives key events.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: SwiftTerm Integration
**Rationale:** Core dependency must work before building on it. Validates SwiftTerm compatibility with Dispatch's macOS 14 target.
**Delivers:** SwiftTerm package added, basic `EmbeddedTerminalView` showing bash shell
**Addresses:** None yet — pure infrastructure
**Avoids:** Pitfall 4 (forkpty from Swift) by using SwiftTerm's safe implementation

### Phase 2: Safe Terminal Wrapper
**Rationale:** Safety patterns must be in place before process lifecycle. AgentHub's crashes during development came from skipping this.
**Delivers:** `DispatchTerminalView` with safe data reception, configuration guard
**Uses:** SwiftTerm `LocalProcessTerminalView` as base class
**Avoids:** Pitfall 1 (DispatchIO race condition), Pitfall 4 (retain cycles)

### Phase 3: Process Lifecycle
**Rationale:** Cleanup must work before multi-session. Orphaned processes compound without registry.
**Delivers:** `TerminalProcessRegistry`, graceful termination, crash recovery cleanup
**Implements:** Two-stage shutdown (SIGTERM then SIGKILL), process group termination
**Avoids:** Pitfall 2 (orphaned processes), Pitfall 3 (process group failure)

### Phase 4: Claude Code Integration
**Rationale:** With terminal and process management stable, integrate Claude Code specifically.
**Delivers:** Claude Code launch, prompt dispatch via PTY, completion detection
**Uses:** Existing `HookServer` for completion (unchanged), output pattern matching as backup
**Implements:** `EmbeddedTerminalService` with `dispatchPrompt()` matching existing interface

### Phase 5: Multi-Session UI
**Rationale:** Single session must work before managing multiple. Focus/routing complexity increases with sessions.
**Delivers:** Session tabs, split view, session selection, session limits
**Addresses:** Full-screen toggle, multi-terminal display
**Avoids:** Pitfall 5 (focus routing), resource exhaustion

### Phase 6: Session Persistence
**Rationale:** Persistence comes after core functionality is stable. SwiftData integration builds on existing patterns.
**Delivers:** `TerminalSession` SwiftData model, project-session association, session resume
**Uses:** SwiftData (existing), `-r` flag for Claude Code session resume
**Implements:** Architecture component from ARCHITECTURE.md

### Phase 7: Migration & Polish
**Rationale:** Only after embedded terminals are fully working, deprecate AppleScript path.
**Delivers:** Deprecated `TerminalService` methods, settings toggle for terminal mode, dual-mode UI
**Implements:** Smooth transition for users with Terminal.app workflows

### Phase Ordering Rationale

- **SwiftTerm first:** Everything builds on the terminal emulator. Must validate compatibility.
- **Safety before features:** Phases 2-3 establish safety patterns before adding complexity.
- **Single session before multi:** Each phase validates before the next adds scope.
- **Claude Code integration mid-sequence:** By Phase 4, infrastructure is stable enough for business logic.
- **Persistence late:** Session data only matters after sessions work correctly.
- **Migration last:** Don't break existing workflows until new path is proven.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Safe Terminal Wrapper):** Review AgentHub's `SafeLocalProcessTerminalView` implementation in detail before coding
- **Phase 6 (Session Persistence):** Claude Code's `-r` session resume behavior needs verification

Phases with standard patterns (skip research-phase):
- **Phase 1 (SwiftTerm Integration):** Well-documented, SPM integration is straightforward
- **Phase 3 (Process Lifecycle):** POSIX signals, patterns from AgentHub are clear
- **Phase 5 (Multi-Session UI):** Standard SwiftUI patterns
- **Phase 7 (Migration):** Internal refactoring, no external research needed

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | SwiftTerm verified via GitHub, version confirmed, API reviewed |
| Features | HIGH | Direct analysis of AgentHub source code, table stakes clearly identified |
| Architecture | HIGH | Based on AgentHub patterns and existing Dispatch codebase |
| Pitfalls | HIGH | Derived from AgentHub implementation, Apple Developer Forums, verified patterns |

**Overall confidence:** HIGH

### Gaps to Address

- **Scrollback persistence:** PTY state cannot be serialized. Accept fresh terminals on restart, or implement background server (like iTerm2) — defer decision to Phase 6 planning.
- **Sandbox compatibility:** SwiftTerm uses `forkpty()` which works in non-sandboxed apps. Mac App Store distribution would require rethinking. Currently not a concern (direct distribution).
- **Session resume reliability:** Claude Code's `-r` flag behavior with stale session IDs needs testing during Phase 6.

## Sources

### Primary (HIGH confidence)
- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm) — terminal emulation, LocalProcess API
- [AgentHub GitHub](https://github.com/jamesrochabrun/AgentHub) — production patterns for embedded Claude Code terminals
- AgentHub source files: `EmbeddedTerminalView.swift`, `TerminalProcessRegistry.swift`, `SafeLocalProcessTerminalView` pattern

### Secondary (MEDIUM confidence)
- [Apple Developer Forums](https://developer.apple.com/forums/thread/133787) — zombie process handling
- SwiftTerm LocalProcess documentation — process spawning patterns

### Tertiary (LOW confidence)
- iTerm2 Session Restoration documentation — background server pattern (deferred consideration)

---
*Research completed: 2026-02-07*
*Ready for roadmap: yes*

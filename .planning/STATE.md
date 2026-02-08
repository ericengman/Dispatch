# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Users can dispatch prompts to Claude Code with zero friction via embedded terminal sessions
**Current focus:** Phase 17 - Claude Code Integration

## Current Position

Phase: 17 of 22 (Claude Code Integration)
Plan: 1 of 3 in current phase
Status: In progress
Last activity: 2026-02-08 — Completed 17-01-PLAN.md

Progress: [#################░░░] 90% (17/19 phases complete across milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 17 (12 v1.1, 5 v2.0)
- Average duration: 3.1m
- Total execution time: 53m

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 8 | 1 | 3m | 3m |
| 9 | 1 | 3m | 3m |
| 10 | 1 | 4m | 4m |
| 11 | 3 | 7m | 2.3m |
| 12 | 4 | 15m | 3.8m |
| 13 | 2 | 7m | 3.5m |
| 14 | 1 | 5m | 5m |
| 15 | 1 | 1m | 1m |
| 16 | 2 | 4m | 2m |
| 17 | 1 | 3m | 3m |

**Recent Trend:**
- Last 5 plans: 15-01 (1m), 16-01 (1m), 16-02 (3m), 17-01 (3m)
- Trend: Service extensions consistently fast (1-3m)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0]: Full Terminal.app replacement (no hybrid mode)
- [v2.0]: SwiftTerm + LocalProcess pattern (proven in AgentHub)
- [v2.0]: Multi-session split panes (matches AgentHub UX)
- [14-01]: SwiftTerm 1.10.1 via upToNextMinorVersion
- [14-01]: HSplitView terminal placement with Cmd+Shift+T toggle
- [14-01]: Respect user's $SHELL environment variable
- [15-01]: Strong reference cleanup pattern for Coordinator lifecycle
- [15-01]: sendIfRunning helper for safe command execution
- [16-01]: UserDefaults for PID persistence (simple, sufficient for crash recovery)
- [16-01]: NSLock over actor isolation for PID registry (synchronous API)
- [16-01]: Set<pid_t> in-memory structure for fast lookup
- [16-02]: Two-stage termination with 3s timeout (2s for deinit) prevents zombies while allowing graceful shutdown
- [16-02]: killpg sends signal to entire process group (shell + Claude Code children)
- [16-02]: kill(pid, 0) syscall for lightweight process existence check
- [17-01]: ClaudeCodeLauncher singleton for consistent process configuration
- [17-01]: TerminalLaunchMode enum in EmbeddedTerminalView for shell/Claude Code selection
- [17-01]: PATH prepending (~/.claude/local/bin, /usr/local/bin, /opt/homebrew/bin) for CLI discovery
- [17-01]: Terminal.getEnvironmentVariables() baseline ensures TERM=xterm-256color and COLORTERM=truecolor
- [17-01]: --dangerously-skip-permissions default true for embedded usage

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 19]: Claude Code's `-r` session resume behavior needs verification

### Known Gaps (Future Work)

- 20 skills still use hardcoded `/tmp` paths instead of Dispatch library
- Phase 11 migrated only 4 skills; remaining skills need migration for complete integration

## Session Continuity

Last session: 2026-02-08 05:20
Stopped at: Completed 17-01-PLAN.md (Claude Code Launcher)
Resume file: None

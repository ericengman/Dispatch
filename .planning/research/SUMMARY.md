# Project Research Summary

**Project:** Dispatch Screenshot Routing Fix
**Domain:** CLI-to-macOS-app integration for iOS simulator screenshot management
**Researched:** 2026-02-03
**Confidence:** HIGH

## Executive Summary

This project addresses a straightforward but pervasive problem: Claude Code skills save iOS simulator screenshots to temporary directories instead of routing them through Dispatch for user review. The root cause is duplicated, inconsistent integration code scattered across 39 skills, where many skills skip integration entirely. The Dispatch API endpoints already exist and work correctly; the problem is on the skill side.

The recommended solution is a **shared bash library** (`~/.claude/lib/dispatch.sh`) that encapsulates all Dispatch integration logic. Skills source this library and call simple functions (`dispatch_init`, `dispatch_finalize`) instead of reimplementing the integration themselves. This eliminates duplication, ensures consistency, and provides graceful fallback when Dispatch is not running. The Dispatch app's HookInstaller should be extended to install this library automatically.

The primary risks are shell state management (variables lost between bash calls) and race conditions (screenshots not flushed to disk before completion scan). Both are well-understood and mitigable with temp file persistence and a small delay before completion. With the shared library pattern, these mitigations are implemented once and benefit all skills.

## Key Findings

### Recommended Stack

The existing stack requires no changes. Dispatch is a Swift/SwiftUI macOS app with SwiftData persistence, and skills are bash-based markdown files. The solution adds a single bash library file.

**Core technologies:**
- **Bash library** (`~/.claude/lib/dispatch.sh`): Shared integration code — eliminates duplication across 39 skills
- **Temp file persistence** (`/tmp/dispatch-*.txt`): State storage between bash calls — works around Claude Code's shell reset behavior
- **Existing HookServer API**: No new endpoints needed — `/health`, `/screenshots/run`, `/screenshots/complete` already work

No new dependencies. The solution uses curl, grep, and bash features already present in all skills.

### Expected Features

**Must have (table stakes):**
- Health check detects Dispatch availability — skills check before calling APIs
- Create run returns usable path immediately — directory pre-created by Dispatch
- Complete run triggers filesystem scan — screenshots appear in Dispatch UI
- Graceful fallback to temp directory — skills work without Dispatch

**Should have (v1.x after validation):**
- Screenshot labels via API — add context during capture
- Bulk screenshot registration — reduce race conditions on large runs
- Run status query — verify completion, debug missing screenshots

**Defer (v2+):**
- WebSocket notifications — overkill for current scale
- Automatic screenshot capture — too noisy, skills know when to capture
- In-app screenshot editing — macOS Preview handles this well

### Architecture Approach

The architecture follows a **shared library + SessionStart hook** pattern. Skills source the library at execution time to get integration functions. A SessionStart hook detects Dispatch availability at session start and sets environment variables. The library handles all API calls, error handling, and fallback logic.

**Major components:**
1. **Shared Library** (`~/.claude/lib/dispatch.sh`) — encapsulates health check, run creation, completion, path management
2. **SessionStart Hook** (`~/.claude/hooks/session-start.sh`) — detects Dispatch at session start, sets environment
3. **HookInstaller Enhancement** — Dispatch app installs/updates library automatically
4. **Skill Updates** — change ~30 lines of duplicated code to 3 lines sourcing the library

### Critical Pitfalls

1. **State lost between bash calls** — use temp files (`/tmp/dispatch-run-id`, `/tmp/dispatch-screenshot-path`) instead of environment variables
2. **Silent Dispatch fallback** — make fallback explicit with clear output: "Dispatch not running - screenshots at /tmp/..."
3. **Race condition on completion** — add 1-second sleep before calling `/screenshots/complete` to let filesystem flush
4. **Project name mismatch** — use `git rev-parse --show-toplevel` instead of `pwd` for project name derivation
5. **API version drift** — document API version in library, return clear errors for malformed requests

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation
**Rationale:** The shared library is the foundation everything else builds on. Must be correct before updating skills.
**Delivers:** `~/.claude/lib/dispatch.sh` with all integration functions, tested independently
**Addresses:** Core routing problem, consistent API usage
**Avoids:** Pitfalls 1 (state loss) and 2 (silent fallback) by implementing correct patterns once

### Phase 2: Hook Integration
**Rationale:** SessionStart hook provides environment context before skills run. Depends on library existing.
**Delivers:** `~/.claude/hooks/session-start.sh`, updated `~/.claude/settings.json`
**Uses:** Library functions for health check
**Implements:** Early Dispatch detection for session-wide awareness

### Phase 3: Dispatch App Updates
**Rationale:** HookInstaller should auto-install the library so users don't need manual setup. Depends on library and hook being finalized.
**Delivers:** `installSharedLibrary()` method in HookInstaller, Settings UI status indicator
**Implements:** Zero-config installation for Dispatch users

### Phase 4: Skill Migration
**Rationale:** Update all skills to use the library. Largest phase but safest to do after infrastructure is stable.
**Delivers:** All 39 skills reviewed and updated (4 heavily using Dispatch, others may need minimal changes)
**Avoids:** Pitfall 3 (inconsistent paths) by standardizing on library usage

### Phase 5: Verification
**Rationale:** End-to-end validation that the full chain works: skill -> screenshot -> Dispatch UI
**Delivers:** Tested workflows, documentation updates
**Avoids:** Pitfall 4 (race conditions) and 5 (API drift) through explicit testing

### Phase Ordering Rationale

- **Library first:** Everything depends on the library being correct. Test it in isolation before integrating.
- **Hook before app updates:** The hook works independently of HookInstaller; app updates are convenience, not critical path.
- **App updates before skill migration:** Ensures library is installed when skills try to source it.
- **Skills last:** Largest scope, most tedious, but safest when infrastructure is proven stable.
- **Verification throughout:** Each phase should have verification, but Phase 5 is dedicated E2E validation.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (Skill Migration):** Need to audit all 39 skills for screenshot usage patterns. Some may not take screenshots at all.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Foundation):** Bash library patterns well-understood
- **Phase 2 (Hook Integration):** Claude Code hooks documented
- **Phase 3 (Dispatch App Updates):** Extends existing HookInstaller pattern
- **Phase 5 (Verification):** Standard testing, no new patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new technologies; extending existing patterns |
| Features | HIGH | API endpoints already exist and work; features are validation, not implementation |
| Architecture | HIGH | Shared library pattern is well-established; verified against Claude Code docs |
| Pitfalls | HIGH | Based on direct analysis of existing code and skill execution model |

**Overall confidence:** HIGH

### Gaps to Address

- **Skill audit completeness:** 39 skills exist, but not all take screenshots. Need to identify which ones during Phase 4 planning.
- **SessionStart hook environment persistence:** `CLAUDE_ENV_FILE` behavior should be verified in real execution. May need alternative approach if it doesn't persist as expected.
- **Multi-instance scenarios:** Current design assumes single Dispatch instance. If users run multiple, port configuration becomes relevant.

## Sources

### Primary (HIGH confidence)
- `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift` — existing API implementation, endpoint definitions
- `/Users/eric/Dispatch/Dispatch/Services/ScreenshotWatcherService.swift` — screenshot processing, directory monitoring
- `/Users/eric/.claude/skills/test-feature/SKILL.md` — current integration pattern
- `/Users/eric/.claude/skills/explore-app/SKILL.md` — current integration pattern
- `/Users/eric/.claude/skills/test-dynamic-type/SKILL.md` — current integration pattern

### Secondary (MEDIUM confidence)
- Claude Code Hooks Reference — SessionStart hook behavior, CLAUDE_ENV_FILE
- Bash library best practices — shell sourcing patterns

### Tertiary (LOW confidence)
- Skill count (39) from grep — needs validation during Phase 4 planning

---
*Research completed: 2026-02-03*
*Ready for roadmap: yes*

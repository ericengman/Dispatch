# Dispatch

## What This Is

Dispatch is a native macOS application that manages, queues, and sends prompts to Claude Code running in Terminal.app. It enables prompt composition while Claude Code executes, prompt reuse with modifications, and automated prompt sequences (chains). The app includes a Simulator Screenshot Review feature for reviewing and annotating iOS simulator screenshots captured during Claude Code testing sessions.

## Core Value

Users can dispatch prompts (including annotated simulator screenshots) to Claude Code with zero friction, enabling rapid iterative development.

## Current Milestone: v1.1 Screenshot Integration Fix

**Goal:** Ensure simulator screenshots captured by Claude Code skills are properly routed to Dispatch for review, and complete polish items for the screenshot feature.

**Target features:**
- Fix screenshot path routing so all skills save to Dispatch-monitored location
- Update multiple skills to use Dispatch screenshot API
- Add deferred polish: Settings UI, tooltips, error display
- End-to-end testing of screenshot flow

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- v1.0 Core dispatch functionality
- v1.0 Queue management
- v1.0 Chain execution
- v1.0 Simulator screenshot annotation (mostly complete - phases 1-7)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Screenshot path routing fix across all skills
- [ ] Settings UI for screenshot configuration
- [ ] Tooltip hints for annotation tools
- [ ] Error display when dispatch fails
- [ ] End-to-end testing

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Drag to reorder in send queue — adds complexity, not blocking usage
- Auto-focus prompt field — minor UX, not worth the effort
- PromptHistory with images — requires schema changes, defer to v1.2
- Image auto-resize — only needed if we hit size limits in practice
- Comparison mode (side-by-side diff) — future enhancement
- Video recording of simulator — high complexity, out of scope

## Context

The Dispatch app has a working Simulator Screenshot Review feature (PRD in `Docs/PRD_SimulatorScreenshots.md`). The implementation is mostly complete per `Docs/TODO_SimulatorScreenshots.md`, but the end-to-end flow is broken because:

1. Skills capture screenshots but save to temp folders instead of Dispatch-monitored location
2. The `HookServer` has endpoints for screenshot runs (`/screenshots/run`, `/screenshots/complete`)
3. Skills need to call these endpoints to get the correct save path
4. Many skills (5+) across `~/.claude/skills/` capture screenshots and need updating

Technical environment:
- macOS 14.0+ (Sonoma)
- Swift 6, SwiftUI, SwiftData
- Terminal.app integration via AppleScript
- HookServer runs on port 19847 by default

## Constraints

- **Architecture**: Must work with existing HookServer API
- **Skills**: Many skills to update, need centralized approach
- **Compatibility**: Don't break existing skills that don't use screenshots

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Copy-paste to Terminal for images | Simpler than file references, works with Claude | — Pending |
| Max 5 images per dispatch | Claude vision limit | ✓ Good |
| 10 runs per project max | Storage management | — Pending |

---
*Last updated: 2026-02-03 after milestone v1.1 started*

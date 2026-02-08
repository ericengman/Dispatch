# Dispatch

## What This Is

Dispatch is a native macOS application that manages, queues, and sends prompts to Claude Code. It enables prompt composition while Claude Code executes, prompt reuse with modifications, and automated prompt sequences (chains). The app includes a Simulator Screenshot Review feature for reviewing and annotating iOS simulator screenshots captured during Claude Code testing sessions.

## Core Value

Users can dispatch prompts (including annotated simulator screenshots) to Claude Code with zero friction, enabling rapid iterative development.

## Current Milestone: v2.0 In-App Claude Code

**Goal:** Replace Terminal.app dependency with embedded terminal sessions, enabling full Claude Code management within Dispatch.

**Target features:**
- Embedded terminal via SwiftTerm with PTY support
- Full replacement of Terminal.app (remove AppleScript dependency)
- Multi-session support with split panes and focus mode (AgentHub pattern)
- Session persistence across app restarts with resume capability
- Integration with existing queue/chain execution

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- v1.0 Core dispatch functionality
- v1.0 Queue management
- v1.0 Chain execution
- v1.0 Simulator screenshot annotation
- v1.1 Screenshot path routing via shared library
- v1.1 SessionStart hook for Dispatch detection
- v1.1 Auto-install library and hooks
- v1.1 Settings UI for screenshots
- v1.1 Annotation tooltips and error handling

### Active

<!-- Current scope. Building toward these. -->

- [ ] SwiftTerm integration for embedded terminal
- [ ] PTY-based process management (LocalProcess)
- [ ] Multi-session UI with split panes
- [ ] Session focus/enlarge mode
- [ ] Session persistence and resume
- [ ] Remove TerminalService AppleScript dependency
- [ ] Wire to existing queue/chain execution

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Drag to reorder in send queue — adds complexity, not blocking usage
- PromptHistory with images — requires schema changes, defer to v2.1
- Image auto-resize — only needed if we hit size limits in practice
- Video recording of simulator — high complexity, out of scope
- Hybrid mode (in-app + Terminal.app) — full replacement is cleaner

## Context

v2.0 replaces Terminal.app dependency with embedded terminals using SwiftTerm. Reference implementation: [AgentHub](https://github.com/jamesrochabrun/AgentHub) (MIT licensed).

**AgentHub architecture pattern:**
```
SwiftUI View (EmbeddedTerminalView)
    └── NSView Container (TerminalContainerView)
        └── SwiftTerm TerminalView + LocalProcess (PTY)
            └── Claude CLI spawned via bash -c
```

**Key dependencies to add:**
- SwiftTerm (v1.2.0+) — Terminal emulation with PTY support
- Optionally: ClaudeCodeSDK for programmatic API access

Technical environment:
- macOS 14.0+ (Sonoma)
- Swift 6, SwiftUI, SwiftData
- SwiftTerm for terminal emulation (replacing AppleScript)
- HookServer runs on port 19847 by default

## Constraints

- **Architecture**: Follow AgentHub's proven pattern for terminal embedding
- **Compatibility**: Existing queue/chain logic must work with new terminal backend
- **License**: AgentHub is MIT licensed — can reference patterns freely

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Copy-paste to Terminal for images | Simpler than file references, works with Claude | ✓ Good |
| Max 5 images per dispatch | Claude vision limit | ✓ Good |
| 10 runs per project max | Storage management | ✓ Good |
| Full Terminal.app replacement (v2.0) | Cleaner than hybrid mode | — Pending |
| SwiftTerm + LocalProcess pattern | Proven in AgentHub, MIT licensed | — Pending |
| Multi-session split panes | User preference, matches AgentHub UX | — Pending |

---
*Last updated: 2026-02-07 after milestone v2.0 started*

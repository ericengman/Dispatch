# Dispatch

## What This Is

Dispatch is a native macOS application that manages, queues, and sends prompts to Claude Code via embedded terminal sessions. It enables prompt composition while Claude Code executes, prompt reuse with modifications, and automated prompt sequences (chains). The app includes a Simulator Screenshot Review feature for reviewing and annotating iOS simulator screenshots captured during Claude Code testing sessions.

## Core Value

Users can dispatch prompts (including annotated simulator screenshots) to Claude Code with zero friction, enabling rapid iterative development.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

**v1.0:**
- Core dispatch functionality
- Queue management
- Chain execution
- Simulator screenshot annotation

**v1.1:**
- Screenshot path routing via shared library
- SessionStart hook for Dispatch detection
- Auto-install library and hooks
- Settings UI for screenshots
- Annotation tooltips and error handling

**v2.0:**
- ✓ SwiftTerm integration for embedded terminal — v2.0
- ✓ PTY-based process management (LocalProcess) — v2.0
- ✓ Thread-safe terminal data reception — v2.0
- ✓ Claude Code process spawning with environment config — v2.0
- ✓ PTY-based prompt dispatch — v2.0
- ✓ Output pattern completion detection — v2.0
- ✓ JSONL status parsing and display — v2.0
- ✓ Context window visualization — v2.0
- ✓ Process registry with PID tracking and persistence — v2.0
- ✓ Orphan process cleanup on launch — v2.0
- ✓ Graceful two-stage termination — v2.0
- ✓ Multi-session UI with split panes — v2.0
- ✓ Session focus/enlarge mode — v2.0
- ✓ Session persistence and resume — v2.0
- ✓ Project-session relationship — v2.0
- ✓ Queue/chain execution wired to embedded terminals — v2.0
- ✓ HookServer + pattern dual completion detection — v2.0
- ✓ TerminalService deprecated (AppleScript removed) — v2.0
- ✓ Terminal.app Automation permission removed — v2.0

**v3.0:**
- ✓ Cross-hair region capture via native screencapture CLI — v3.0
- ✓ Window capture with interactive hover-highlight UX — v3.0
- ✓ iOS Simulator windows prominently visible (system UI filtered) — v3.0
- ✓ Annotation UI reuse with QuickCapture multi-window support — v3.0
- ✓ Session picker for targeted dispatch — v3.0
- ✓ Quick Capture sidebar section with MRU thumbnails — v3.0
- ✓ Global keyboard shortcuts (Ctrl+Cmd+1/2) — v3.0
- ✓ Re-capture from MRU list — v3.0

### Active

<!-- Current scope. Building toward these. -->

(No active requirements — awaiting next milestone definition)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Drag to reorder in send queue — adds complexity, not blocking usage
- PromptHistory with images — requires schema changes, defer to v2.1+
- Image auto-resize — only needed if we hit size limits in practice
- Video recording of simulator — high complexity, out of scope
- Hybrid mode (in-app + Terminal.app) — full replacement is cleaner
- Mac App Store distribution — sandbox incompatible with forkpty()

## Context

**Current State (v3.0):**
- macOS 14.0+ (Sonoma)
- Swift 6, SwiftUI, SwiftData
- SwiftTerm 1.10.1 for embedded terminal emulation
- HookServer runs on port 19847 by default
- 23,676 lines of Swift across 114 files

**Architecture:**
```
MainView (NavigationSplitView)
├── SidebarView (Library, Projects, Chains, Quick Capture)
├── Content area (Prompts, History, Chains)
└── MultiSessionTerminalView (embedded Claude Code)
    ├── SessionTabBar
    └── SessionPaneView(s) with EmbeddedTerminalView

QuickCaptureAnnotationView (separate WindowGroup per capture)
├── AnnotationCanvasView (reused from Screenshot Runs)
├── AnnotationToolbar
└── SessionPickerView + Dispatch button
```

**Tech Debt (Non-Blocking):**
- 20 skills still use hardcoded `/tmp` paths instead of Dispatch library
- Status monitoring only starts for resumed sessions (not new sessions)
- 40 actor isolation warnings in pre-v3.0 code

## Constraints

- **No Sandbox**: forkpty() incompatible with App Sandbox (no Mac App Store)
- **Multi-session limit**: 4 concurrent sessions max (resource management)
- **Session retention**: 7-day window for persisted sessions

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Copy-paste to Terminal for images | Simpler than file references, works with Claude | ✓ Good |
| Max 5 images per dispatch | Claude vision limit | ✓ Good |
| 10 runs per project max | Storage management | ✓ Good |
| Full Terminal.app replacement (v2.0) | Cleaner than hybrid mode | ✓ Good |
| SwiftTerm + LocalProcess pattern | Proven in AgentHub, MIT licensed | ✓ Good |
| Multi-session split panes | User preference, matches AgentHub UX | ✓ Good |
| UUID-based session registry | Cross-component lookup | ✓ Good |
| Dual completion detection | HookServer primary, pattern fallback | ✓ Good |
| Deprecate over delete | Rollback safety, removal in v3.0 | ✓ Good |
| Native screencapture CLI (v3.0) | Zero custom UI, perfect cross-hair UX | ✓ Good |
| Custom WindowCaptureSession (v3.0) | Better than system picker, hover-highlight UX | ✓ Good |
| Static cache for QuickCapture images (v3.0) | Avoid SwiftData for transient screenshots | ✓ Good |
| Value-based WindowGroup (v3.0) | Multiple annotation windows simultaneously | ✓ Good |
| UserDefaults for MRU (v3.0) | Lightweight, no SwiftData needed | ✓ Good |
| Global shortcuts Ctrl+Cmd+1/2 (v3.0) | Avoid system/menu conflicts | ✓ Good |

## Most Recent Milestone: v3.0 Screenshot Capture (Shipped)

**Delivered:** Quick screenshot capture from anywhere with annotation and dispatch to Claude sessions.

**Shipped features:**
- Cross-hair region selection via native screencapture CLI
- Window capture with interactive hover-highlight UX
- iOS Simulator windows prominently visible
- Annotation UI reuse with multi-window support
- Session picker for targeted dispatch
- Quick Capture sidebar section with MRU thumbnails
- Global keyboard shortcuts (Ctrl+Cmd+1/2)

See `.planning/MILESTONES.md` for full history.

---
*Last updated: 2026-02-10 after v3.0 milestone shipped*

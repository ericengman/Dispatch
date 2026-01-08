# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## User Preferences

- **Build & Run**: When building the app, always build AND run it, then notify the user once it's running. Use this sequence:
  1. Build: `xcodebuild -scheme Dispatch -destination 'platform=macOS' build`
  2. Kill with SIGKILL: `pkill -9 -x "Dispatch" 2>/dev/null || true`
  3. Launch fresh: `open -F /path/to/Dispatch.app`
- **Logging**: Use extensive debug logging with the LoggingService for all new code.
- **Threading**: UI on main thread, everything else on background.

## Project Overview

Dispatch is a native macOS application that manages, queues, and sends prompts to Claude Code running in Terminal.app. It enables prompt composition while Claude Code executes, prompt reuse with modifications, and automated prompt sequences (chains).

## Technical Stack

- **Language:** Swift 6
- **UI Framework:** SwiftUI
- **Data Persistence:** SwiftData
- **Minimum macOS:** 14.0 (Sonoma)
- **Terminal Integration:** AppleScript via NSAppleScript
- **Global Hotkey:** HotKey package via SPM
- **Architecture:** MVVM

## Build Commands

```bash
# Build the app
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug build

# Run tests
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug test

# Run a specific test
xcodebuild -project Dispatch.xcodeproj -scheme DispatchTests -only-testing:DispatchTests/TestClassName/testMethodName test

# Clean build
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch clean
```

## Architecture

### Data Models (SwiftData)

All models use the `@Model` macro and are defined in `Dispatch/Models/`:

- **Prompt**: Core entity with title, content, starred status, project relationship, and usage tracking. Supports `{{placeholder}}` template syntax.
- **Project**: Organizes prompts with name, color (hex), and sort order. Has inverse relationships to Prompt and PromptChain.
- **PromptHistory**: Immutable snapshot of sent prompts with timestamp and terminal target info.
- **PromptChain**: Named sequence of ChainItems for automated multi-step execution.
- **ChainItem**: References a library Prompt OR contains inline content, with configurable delay.
- **QueueItem**: Pending prompts to execute, with ordering and optional terminal target.
- **AppSettings**: Singleton for hotkey config, menu bar toggle, hook server port, etc.

### Services Layer

Located in `Dispatch/Services/`:

- **TerminalService**: AppleScript execution for enumerating windows, detecting active window, and sending prompts. Must escape special characters (quotes, backslashes).
- **HookServer**: Local HTTP server (default port 19847) that receives POST requests from Claude Code's stop hook to detect completion.
- **ExecutionStateMachine**: Manages states IDLE → SENDING → EXECUTING → COMPLETED with transitions triggered by hook callbacks or polling fallback.
- **PlaceholderResolver**: Parses `{{placeholder_name}}` syntax, auto-fills built-ins (clipboard, date, time), prompts for custom values.
- **HookInstaller**: Creates/updates `~/.claude/hooks/stop.sh` to notify Dispatch on completion.
- **HotkeyManager**: Registers global hotkey (default ⌘⇧D) using HotKey package.

### View Structure

Views follow the navigation hierarchy:

```
MainView (NavigationSplitView)
├── SidebarView
│   ├── Library section (Starred, History, All Prompts)
│   ├── Projects section (user-created)
│   └── Chains section
├── Content area (PromptListView, HistoryListView, etc.)
└── QueuePanelView (collapsible bottom panel)
```

### Key Integration Points

**Terminal Communication:**
```applescript
tell application "Terminal"
    do script "{{PROMPT_TEXT}}" in window id {{WINDOW_ID}}
end tell
```

**Completion Detection (Primary):** Hook-based via local HTTP server receiving POST to `/hook/complete`

**Completion Detection (Fallback):** Poll terminal content every 2s looking for Claude Code prompt pattern (`╭─`)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New Prompt |
| ⌘⇧N | New Chain |
| ⌘⏎ | Send Selected Prompt |
| ⌘⇧Q | Add to Queue |
| ⌘R | Run Next in Queue |
| ⌘⇧R | Run All in Queue |

## Permissions Required

- **Accessibility**: For global hotkey registration
- **Automation (Terminal.app)**: For AppleScript control of Terminal

## Dependencies

```swift
// Package.swift or Xcode SPM
.package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
```

Optional for full HTTP server: Vapor, or use built-in NWListener from Network framework.

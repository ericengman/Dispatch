# Dispatch — macOS Prompt Manager for Claude Code

## Overview

Dispatch is a native macOS application that manages, queues, and sends prompts to Claude Code running in Terminal.app. It solves the workflow friction of composing prompts while Claude Code is executing, enables prompt reuse with modifications, and automates prompt sequences.

---

## Technical Stack

- **Language:** Swift 6
- **UI Framework:** SwiftUI
- **Data Persistence:** SwiftData
- **Minimum macOS:** 14.0 (Sonoma)
- **Terminal Integration:** AppleScript via NSAppleScript
- **Global Hotkey:** Carbon (RegisterEventHotKey) or HotKey package via SPM
- **Architecture:** MVVM

---

## App Structure

### Window Configuration

- **Primary Window:** Standard macOS window (NSWindow), resizable, minimum size 600x500
- **Menu Bar Icon:** Optional toggle in settings—when enabled, app lives in menu bar with popover for quick actions
- **Window Restoration:** Remember window position and size between launches

### Navigation Structure

Sidebar navigation with three sections:

```
┌─────────────────────────────────────────────────────┐
│ [Sidebar]              │ [Main Content Area]        │
│                        │                            │
│ LIBRARY                │                            │
│   ★ Starred            │                            │
│   ⏱ History            │                            │
│   📋 All Prompts       │                            │
│                        │                            │
│ PROJECTS               │                            │
│   + Add Project        │                            │
│   ◉ RayRise            │                            │
│   ◉ Forge              │                            │
│   ◉ General            │                            │
│                        │                            │
│ CHAINS                 │                            │
│   + Add Chain          │                            │
│   ⛓ Setup New Feature  │                            │
│   ⛓ Code Review Flow   │                            │
│                        │                            │
├────────────────────────┼────────────────────────────┤
│ [Queue Panel - Collapsible, Bottom]                 │
│ Queue (3) ▼  [▶ Run Next] [▶▶ Run All] [Clear]     │
│ 1. Initialize SwiftData models                      │
│ 2. Create main view hierarchy                       │
│ 3. Implement terminal integration                   │
└─────────────────────────────────────────────────────┘
```

---

## Data Models

### Prompt

```swift
@Model
final class Prompt {
    var id: UUID
    var title: String                    // User-provided title, auto-generated if empty
    var content: String                  // The actual prompt text
    var isStarred: Bool
    var createdAt: Date
    var updatedAt: Date
    var project: Project?                // Optional relationship
    var usageCount: Int                  // Track how often used
    
    // Computed: Extract first line or first 50 chars for auto-title
}
```

### Project

```swift
@Model
final class Project {
    var id: UUID
    var name: String
    var colorHex: String                 // Store as hex, convert to Color
    var createdAt: Date
    var prompts: [Prompt]                // Inverse relationship
    var chains: [PromptChain]            // Inverse relationship
    var sortOrder: Int                   // For manual ordering
}
```

### PromptHistory

```swift
@Model
final class PromptHistory {
    var id: UUID
    var content: String                  // Snapshot of what was sent
    var sentAt: Date
    var projectName: String?             // Denormalized for history persistence
    var terminalWindowName: String?      // Which window it was sent to
    var wasFromChain: Bool               // Part of automated chain?
    var chainName: String?               // If from chain, which one
}
```

### PromptChain

```swift
@Model
final class PromptChain {
    var id: UUID
    var name: String
    var chainItems: [ChainItem]          // Ordered list
    var project: Project?
    var createdAt: Date
}

@Model
final class ChainItem {
    var id: UUID
    var prompt: Prompt?                  // Reference to library prompt
    var inlineContent: String?           // OR inline prompt text
    var order: Int
    var chain: PromptChain?
    var delaySeconds: Int                // Optional delay after completion before next
    
    // Use either prompt reference or inlineContent, not both
}
```

### QueueItem

```swift
@Model
final class QueueItem {
    var id: UUID
    var prompt: Prompt?                  // Reference to library prompt
    var inlineContent: String?           // OR one-off prompt not in library
    var order: Int
    var addedAt: Date
    var targetTerminalId: String?        // Specific terminal, nil = active window
}
```

### AppSettings

```swift
@Model
final class AppSettings {
    var id: UUID
    var globalHotkeyKeyCode: Int?
    var globalHotkeyModifiers: Int?
    var showInMenuBar: Bool
    var autoDetectActiveTerminal: Bool
    var defaultProjectId: UUID?
    var sendDelay: Double                // Milliseconds to wait after focusing terminal
    var enableClaudeHooks: Bool          // Whether to use hook-based completion detection
    var hookServerPort: Int              // Port for local hook communication
}
```

---

## Features Specification

### 1. Prompt Library

#### 1.1 Prompt List View

- Display prompts in a List with selection
- Each row shows: Star icon (toggleable), title, project badge (colored dot + name), last used date
- Support multi-select for bulk operations (delete, move to project)
- Right-click context menu: Edit, Duplicate, Delete, Add to Queue, Move to Project, Copy to Clipboard

#### 1.2 Prompt Editor

- Opens in main content area or sheet
- **Fields:**
  - Title (TextField, placeholder: "Auto-generated from content")
  - Content (TextEditor, monospace font, syntax-aware if possible)
  - Project (Picker, optional)
  - Starred (Toggle)
- **Template Placeholders:**
  - Support `{{placeholder_name}}` syntax
  - When sending, show popover to fill in placeholders before execution
  - Common placeholders button: `{{filename}}`, `{{path}}`, `{{selection}}`, `{{clipboard}}`
- **Actions:**
  - Save (⌘S)
  - Save & Send (⌘⏎)
  - Save & Queue (⌘⇧Q)

#### 1.3 Search & Filter

- Search bar at top of prompt list
- Searches title and content
- Filter pills: All, Starred, by Project
- Sort options: Recently Used, Recently Created, Alphabetical, Most Used

---

### 2. Queue System

#### 2.1 Queue Panel

- Collapsible panel at bottom of window (drag handle to resize)
- Shows ordered list of queued prompts
- Drag-to-reorder support
- Each item shows: Order number, prompt title/preview, target terminal badge, remove button (X)

#### 2.2 Queue Operations

- **Add to Queue:** From prompt list, context menu, or keyboard shortcut
- **Run Next:** Execute first item in queue, remove from queue on success
- **Run All:** Execute sequentially, waiting for each to complete
- **Clear Queue:** Remove all items with confirmation
- **Reorder:** Drag and drop
- **Edit Target:** Click terminal badge to change target window

#### 2.3 Queue Persistence

- Queue persists across app restarts
- Option to auto-clear queue on app quit (in settings)

---

### 3. Terminal Integration

#### 3.1 Terminal Window Detection

AppleScript to enumerate Terminal windows:

```applescript
tell application "Terminal"
    set windowList to {}
    repeat with w in windows
        set windowInfo to {id of w as string, name of w}
        set end of windowList to windowInfo
    end repeat
    return windowList
end tell
```

#### 3.2 Active Window Detection

```applescript
tell application "Terminal"
    if frontmost then
        return {id of front window as string, name of front window}
    end if
end tell
```

#### 3.3 Send Prompt to Terminal

```applescript
tell application "Terminal"
    activate
    set targetWindow to window id {{WINDOW_ID}}
    do script "{{PROMPT_TEXT}}" in targetWindow
end tell
```

**Implementation Notes:**
- Escape special characters in prompt text (quotes, backslashes)
- Use `do script` without `in` clause to use frontmost window
- Add configurable delay after activation before sending (default 100ms)

#### 3.4 Terminal Picker UI

- Dropdown/picker showing all open Terminal windows
- Format: "Window Name — Tab Title" 
- Option: "Active Window (Auto-detect)"
- Refresh button to update list
- Visual indicator for currently targeted window

---

### 4. Claude Code Completion Detection

#### 4.1 Hook-Based Detection (Primary Method)

Claude Code supports hooks at `~/.claude/hooks/`. Create a `Stop` hook that notifies Dispatch.

**Setup Flow:**
1. On first launch, prompt user to install hook
2. Create/update `~/.claude/hooks/stop.sh`:

```bash
#!/bin/bash
# Dispatch completion notification hook
curl -s -X POST "http://localhost:{{PORT}}/hook/complete" \
  -H "Content-Type: application/json" \
  -d "{\"session\": \"$CLAUDE_SESSION_ID\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  2>/dev/null || true
```

3. Dispatch runs a local HTTP server (Vapor or raw NIO) on configurable port (default 19847)
4. When POST received, mark current execution as complete, trigger next in chain/queue

**Hook Configuration UI:**
- Settings panel to install/uninstall hook
- Status indicator: Hook Installed ✓ / Not Installed
- Custom port configuration
- Test hook button

#### 4.2 Fallback: Polling-Based Detection

If hooks disabled or unavailable:
- Poll Terminal window content via AppleScript every 2 seconds
- Detect Claude Code prompt pattern: `╭─` or the input prompt character
- Less reliable but works without hook setup

```applescript
tell application "Terminal"
    set windowContent to contents of front window
    -- Check last 500 characters for prompt pattern
end tell
```

#### 4.3 Execution State Machine

```
States:
- IDLE: No active execution
- SENDING: Prompt being sent to terminal
- EXECUTING: Waiting for completion signal
- COMPLETED: Ready for next action

Transitions:
- IDLE → SENDING: User triggers send
- SENDING → EXECUTING: AppleScript confirms sent
- EXECUTING → COMPLETED: Hook received or prompt detected
- COMPLETED → IDLE: Auto-transition after 1 second
- COMPLETED → SENDING: If chain/queue has more items
```

---

### 5. Prompt Chains

#### 5.1 Chain Editor

- Create named sequences of prompts
- Add prompts from library OR write inline prompts
- Drag-to-reorder steps
- Per-step delay configuration (0-60 seconds)
- Assign to project (optional)

#### 5.2 Chain Execution

- Start chain: Sends first prompt
- On completion detected: Wait configured delay, send next
- Visual progress indicator showing current step
- **Pause button:** Stop after current prompt completes
- **Cancel button:** Stop immediately (doesn't interrupt running Claude Code)
- Completion notification when chain finishes

#### 5.3 Chain List View

- Shows all chains, filterable by project
- Each row: Name, step count, project badge
- Right-click: Edit, Duplicate, Delete, Run Chain
- Double-click to edit

---

### 6. History

#### 6.1 History View

- Chronological list (newest first) of all sent prompts
- Each row: Timestamp, prompt preview (first 100 chars), project badge, terminal target
- Click to expand full prompt content
- Search bar to filter history

#### 6.2 History Actions

- **Copy:** Copy prompt text to clipboard
- **Save to Library:** Create new Prompt from history item
- **Resend:** Send same prompt again
- **Add to Queue:** Add to queue for later

#### 6.3 History Retention

- Setting: Keep history for X days (default 30)
- Manual clear all history option
- History items are immutable (snapshots)

---

### 7. Global Hotkey

#### 7.1 Hotkey Configuration

- Settings panel with hotkey recorder
- Default: ⌘⇧D (Command+Shift+D)
- Conflict detection with system shortcuts

#### 7.2 Hotkey Actions

When triggered:
1. If app is hidden/background: Bring to front, focus search bar
2. If app is frontmost: Hide app
3. Optional (configurable): Send clipboard contents as prompt immediately

#### 7.3 Implementation

Use the `HotKey` Swift package or implement via Carbon:

```swift
// Using HotKey package (recommended)
import HotKey

let hotKey = HotKey(key: .d, modifiers: [.command, .shift])
hotKey.keyDownHandler = {
    // Toggle app visibility or trigger action
}
```

---

### 8. Project Organization

#### 8.1 Project Management

- Create project: Name + Color picker (preset palette of 8 colors)
- Edit project: Change name or color
- Delete project: Prompts become unassigned (not deleted)
- Reorder projects: Drag in sidebar

#### 8.2 Project Colors

Preset palette:
- Red: #FF6B6B
- Orange: #FFA94D  
- Yellow: #FFE066
- Green: #69DB7C
- Teal: #38D9A9
- Blue: #4DABF7
- Purple: #9775FA
- Pink: #F06595

#### 8.3 Project Filtering

- Click project in sidebar to filter all views to that project
- Badge shows count of prompts in project
- "All" view shows prompts from all projects

---

## UI Components

### Prompt Row Component

```
┌─────────────────────────────────────────────────────────────┐
│ ★  Implement SwiftData models for...    ◉ RayRise   2h ago │
│    "Create the following SwiftData models: Prompt..."       │
└─────────────────────────────────────────────────────────────┘
```

- Star icon: Yellow filled if starred, gray outline if not (clickable)
- Title: Bold, truncated with ellipsis
- Project badge: Colored dot + name
- Timestamp: Relative time
- Subtitle: First line of content, gray, smaller font

### Queue Item Component

```
┌─────────────────────────────────────────────────────────────┐
│ 1. ≡  Create view hierarchy            [Terminal 1] ✕      │
└─────────────────────────────────────────────────────────────┘
```

- Order number
- Drag handle (≡)
- Title/preview
- Terminal target badge (clickable to change)
- Remove button

### Chain Step Component

```
┌─────────────────────────────────────────────────────────────┐
│ 2. ≡  Setup project structure          [5s delay]    ✕     │
│      ↳ From library: "Initialize new feature"               │
└─────────────────────────────────────────────────────────────┘
```

- Step number with connecting line to next
- Title
- Delay indicator
- Source indicator (library reference or "Inline prompt")

### Terminal Picker Component

```
┌──────────────────────────────────────┐
│ Target Terminal              ▼  ↻    │
├──────────────────────────────────────┤
│ ● Active Window (Auto-detect)        │
│ ○ Terminal — claude-code             │
│ ○ Terminal — zsh                     │
│ ○ Terminal 2 — node server           │
└──────────────────────────────────────┘
```

- Radio selection
- Refresh button
- Auto-detect option at top

---

## Keyboard Shortcuts

### Global (when app is frontmost)

| Shortcut | Action |
|----------|--------|
| ⌘N | New Prompt |
| ⌘⇧N | New Chain |
| ⌘F | Focus Search |
| ⌘1 | Show All Prompts |
| ⌘2 | Show Starred |
| ⌘3 | Show History |
| ⌘⇧Q | Add Selected to Queue |
| ⌘⏎ | Send Selected Prompt |
| ⌘R | Run Next in Queue |
| ⌘⇧R | Run All in Queue |
| ⌘, | Open Settings |
| ⌘W | Close Window |
| ⌘Q | Quit App |

### In Prompt Editor

| Shortcut | Action |
|----------|--------|
| ⌘S | Save Prompt |
| ⌘⏎ | Save & Send |
| ⌘⇧Q | Save & Add to Queue |
| ⎋ (Escape) | Cancel Edit |

---

## Settings Panel

### General Tab

- [ ] Launch at login
- [ ] Show in menu bar
- [ ] Show dock icon
- Default project: [Picker]
- History retention: [X] days

### Hotkey Tab

- Global hotkey: [Recorder] (Current: ⌘⇧D)
- [ ] Send clipboard as prompt on hotkey (when modifier held)

### Terminal Tab

- Send delay: [Slider 0-500ms] (Time to wait after focusing Terminal)
- Default target: [Active Window / Specific Window]
- [ ] Auto-refresh terminal list

### Claude Hooks Tab

- Hook status: [Installed ✓ / Not Installed]
- [Install Hook] / [Uninstall Hook] button
- Server port: [Number field] (Default: 19847)
- [Test Hook] button
- [ ] Use polling fallback when hooks unavailable

### Appearance Tab

- [ ] Use compact row height
- Sidebar width: [Slider]
- Editor font size: [Picker 12-18pt]

---

## Menu Bar Mode

When enabled, app shows in menu bar with icon (paper airplane or terminal icon).

### Menu Bar Popover

```
┌─────────────────────────────────────┐
│ [Search prompts...]            ⌘F   │
├─────────────────────────────────────┤
│ ★ Recent Starred                    │
│   • Implement models                │
│   • Setup CloudKit                  │
│   • Code review checklist           │
├─────────────────────────────────────┤
│ Queue (2)                           │
│   [▶ Run Next]  [▶▶ Run All]       │
├─────────────────────────────────────┤
│ [Open Dispatch]              ⌘O     │
│ [Settings...]                ⌘,     │
│ [Quit]                       ⌘Q     │
└─────────────────────────────────────┘
```

- Quick search
- Recent starred prompts (click to send immediately)
- Queue status with action buttons
- Open main window

---

## Placeholder System

### Syntax

`{{placeholder_name}}` — Case-insensitive, alphanumeric + underscores

### Built-in Placeholders

| Placeholder | Description | Auto-filled |
|-------------|-------------|-------------|
| `{{clipboard}}` | Current clipboard text | Yes |
| `{{date}}` | Current date (YYYY-MM-DD) | Yes |
| `{{time}}` | Current time (HH:MM) | Yes |
| `{{filename}}` | Prompt user | No |
| `{{path}}` | Prompt user (with file picker) | No |
| `{{selection}}` | Prompt user | No |

### Placeholder Resolution UI

When sending a prompt with unfilled placeholders:

```
┌─────────────────────────────────────────────────────────────┐
│ Fill Placeholders                                      ✕    │
├─────────────────────────────────────────────────────────────┤
│ This prompt has placeholders that need values:              │
│                                                             │
│ filename                                                    │
│ [____________________________________] [Browse...]          │
│                                                             │
│ component_name                                              │
│ [____________________________________]                      │
│                                                             │
│                            [Cancel]  [Send]                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Error Handling

### Terminal Not Running

- Show alert: "Terminal.app is not running. Would you like to launch it?"
- Option to auto-launch Terminal when sending

### No Terminal Windows

- Show alert: "No Terminal windows found. Please open a Terminal window first."
- Button to open new Terminal window

### Hook Server Port Conflict

- Detect port in use on launch
- Offer to use different port or kill conflicting process
- Show in settings as warning

### AppleScript Permissions

- On first Terminal interaction, macOS will prompt for permissions
- If denied, show settings deep-link to re-enable
- Graceful fallback messaging

---

## File Structure

```
Dispatch/
├── DispatchApp.swift                    # App entry point, scene configuration
├── Models/
│   ├── Prompt.swift
│   ├── Project.swift
│   ├── PromptHistory.swift
│   ├── PromptChain.swift
│   ├── ChainItem.swift
│   ├── QueueItem.swift
│   └── AppSettings.swift
├── Views/
│   ├── MainView.swift                   # Split view container
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── ProjectListView.swift
│   │   └── ChainListView.swift
│   ├── Prompts/
│   │   ├── PromptListView.swift
│   │   ├── PromptRowView.swift
│   │   ├── PromptEditorView.swift
│   │   └── PromptDetailView.swift
│   ├── Queue/
│   │   ├── QueuePanelView.swift
│   │   ├── QueueItemView.swift
│   │   └── QueueControlsView.swift
│   ├── Chains/
│   │   ├── ChainEditorView.swift
│   │   ├── ChainStepView.swift
│   │   └── ChainExecutionView.swift
│   ├── History/
│   │   ├── HistoryListView.swift
│   │   └── HistoryRowView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── GeneralSettingsView.swift
│   │   ├── HotkeySettingsView.swift
│   │   ├── TerminalSettingsView.swift
│   │   └── HookSettingsView.swift
│   ├── Components/
│   │   ├── TerminalPickerView.swift
│   │   ├── ProjectBadgeView.swift
│   │   ├── PlaceholderEditorView.swift
│   │   ├── HotkeyRecorderView.swift
│   │   └── SearchBarView.swift
│   └── MenuBar/
│       ├── MenuBarView.swift
│       └── MenuBarPopoverView.swift
├── ViewModels/
│   ├── PromptViewModel.swift
│   ├── QueueViewModel.swift
│   ├── ChainViewModel.swift
│   ├── HistoryViewModel.swift
│   ├── TerminalViewModel.swift
│   └── SettingsViewModel.swift
├── Services/
│   ├── TerminalService.swift            # AppleScript execution
│   ├── HookServer.swift                 # Local HTTP server for hooks
│   ├── HotkeyManager.swift              # Global hotkey registration
│   ├── PlaceholderResolver.swift        # Parse and fill placeholders
│   ├── ExecutionStateMachine.swift      # Manage execution state
│   └── HookInstaller.swift              # Install/uninstall Claude hooks
├── Utilities/
│   ├── AppleScriptRunner.swift
│   ├── ColorExtensions.swift
│   ├── DateExtensions.swift
│   └── StringExtensions.swift
├── Resources/
│   ├── Assets.xcassets
│   └── Scripts/
│       └── stop-hook-template.sh
└── Info.plist
```

---

## Dependencies (Swift Package Manager)

```swift
dependencies: [
    .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
]
```

Optional (if implementing full HTTP server for hooks):
```swift
    .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
```

Alternative: Use lightweight NWListener from Network framework (built-in, no dependency).

---

## Launch Checklist

On first launch:

1. Request Accessibility permissions (for global hotkey)
2. Request Automation permissions (for Terminal control) - happens automatically on first AppleScript
3. Create default "General" project
4. Show onboarding: Brief feature overview
5. Prompt to install Claude hook (optional, can skip)
6. Set up default hotkey

---

## Edge Cases to Handle

1. **Prompt sent but Terminal closed:** Detect failure, show error, keep prompt in queue
2. **Multiple rapid sends:** Debounce, queue automatically if executing
3. **Very long prompts:** No explicit limit, but warn if >10,000 characters
4. **Special characters in prompts:** Escape for AppleScript (quotes, backslashes)
5. **Hook server crash:** Auto-restart, fall back to polling
6. **Chain interrupted by app quit:** Save state, offer to resume on next launch
7. **Terminal permission denied:** Clear guidance to System Settings > Privacy > Automation
8. **Placeholder with no value:** Require all placeholders filled before send, or allow empty

---

## Testing Scenarios

1. Create prompt, star it, verify in Starred view
2. Create project, assign prompts, verify filtering
3. Queue 3 prompts, reorder, run all sequentially
4. Create chain, run, verify completion detection triggers next step
5. Global hotkey from different app, verify focus and behavior
6. Placeholder resolution with mixed auto/manual placeholders
7. History search finds old prompt, resend works
8. Menu bar mode quick send from recent starred
9. Hook failure, verify fallback polling works
10. App quit and relaunch, verify queue and chain state persist

---

## App Icon Concept

Simple, recognizable:
- Paper airplane emerging from terminal cursor
- Or: Queue/stack of cards with send arrow
- Colors: Deep blue (#2563EB) primary, white accent
- macOS Big Sur+ rounded rectangle style

---

## Summary

Dispatch is a productivity tool for Claude Code power users. Core value: Never lose a prompt, never wait to compose one, and automate repetitive sequences. The implementation should prioritize reliability of terminal communication and seamless queue/chain execution over feature breadth.

Build priority order:
1. Prompt CRUD + Library view
2. Terminal integration (send to Terminal)
3. Queue system
4. History
5. Projects
6. Global hotkey
7. Chains
8. Hook-based completion detection
9. Menu bar mode
10. Placeholder system

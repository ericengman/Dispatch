# Stack Research: Embedded Terminal Sessions for Dispatch v2.0

**Researched:** 2026-02-07
**Confidence:** HIGH (verified with official repositories)
**Reference Implementation:** AgentHub (MIT, uses SwiftTerm + ClaudeCodeSDK)

## Executive Summary

Dispatch v2.0 replaces Terminal.app AppleScript integration with embedded terminal sessions using SwiftTerm. This is a single-dependency addition - SwiftTerm handles PTY management, terminal emulation, and process spawning. ClaudeCodeSDK is NOT required for terminal embedding; it is a separate programmatic API wrapper.

---

## Required Dependencies

### SwiftTerm
| Attribute | Value |
|-----------|-------|
| Repository | https://github.com/migueldeicaza/SwiftTerm |
| Version | 1.10.1 (latest as of Feb 3, 2026) |
| Recommended | `from: "1.10.0"` |
| License | MIT |
| Swift Tools | 5.9 |
| Minimum macOS | 13 |

**What it provides:**
- VT100/Xterm terminal emulation (full ANSI, 256-color, TrueColor)
- PTY (pseudo-terminal) management via `LocalProcess` class
- AppKit-based `TerminalView` (NSView subclass)
- Process spawning with environment and working directory control
- Unicode/emoji support with proper grapheme cluster handling
- Graphics protocols: Sixel, iTerm2-style, Kitty
- Production-tested in Secure Shellfish, La Terminal, CodeEdit

**Key API for Dispatch:**
```swift
// LocalProcess class - spawns shell with PTY
public func startProcess(
    executable: String = "/bin/bash",
    args: [String] = [],
    environment: [String]? = nil,
    execName: String? = nil,
    currentDirectory: String? = nil
)

// Send data to process
public func send(data: ArraySlice<UInt8>)

// Delegate receives process output and termination
protocol LocalProcessDelegate {
    func processTerminated(_ source: LocalProcess, exitCode: Int32?)
    func dataReceived(slice: ArraySlice<UInt8>)
    func getWindowSize() -> (cols: Int, rows: Int)
}
```

**SPM Integration:**
```swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.10.0")

// Target dependency
.product(name: "SwiftTerm", package: "SwiftTerm")
```

**Rationale:**
- SwiftTerm is THE standard for macOS terminal embedding (used by CodeEdit, AgentHub, etc.)
- Actively maintained (v1.10.1 released Feb 2026)
- Provides everything needed: terminal emulation + PTY + process management
- MIT license allows commercial use
- macOS 13 minimum is compatible with Dispatch's macOS 14 target

---

## Optional Dependencies

### ClaudeCodeSDK

| Attribute | Value |
|-----------|-------|
| Repository | https://github.com/jamesrochabrun/ClaudeCodeSDK |
| Version | 2.0.0 |
| License | MIT |
| Required? | NO - Optional enhancement |

**What it provides:**
- Programmatic API for Claude Code (not terminal embedding)
- Single-prompt execution via `runSinglePrompt()`
- Multi-turn conversations via `continueConversation()`
- JSON/streaming output modes
- MCP (Model Context Protocol) integration
- Tool allowlisting/blocklisting

**When to include:**
- If you want to run Claude Code programmatically WITHOUT a terminal UI
- If you need structured JSON responses from Claude Code
- If you want headless/background Claude Code execution

**When NOT to include (Dispatch v2.0):**
- Dispatch embeds interactive terminal sessions where users SEE Claude Code running
- ClaudeCodeSDK spawns subprocesses and captures output - no terminal UI
- Users need to see streaming output, tool calls, file edits in real-time
- The visual terminal experience IS the product

**Verdict for Dispatch v2.0:** DO NOT ADD. ClaudeCodeSDK solves a different problem (programmatic API access) than what Dispatch needs (interactive terminal embedding).

---

### Other Libraries from AgentHub (NOT needed)

| Library | AgentHub Use | Dispatch Status |
|---------|--------------|-----------------|
| GRDB.swift | Database | Dispatch uses SwiftData - no need |
| swift-markdown-ui | Markdown rendering | Not needed for terminal embedding |
| HighlightSwift | Syntax highlighting | Not needed for terminal embedding |
| PierreDiffsSwift | Diff processing | Not needed for terminal embedding |

---

## Integration Points with Existing Dispatch Stack

### SwiftTerm + SwiftUI

SwiftTerm provides AppKit views (`TerminalView` is an NSView). For SwiftUI integration:

```swift
import SwiftUI
import SwiftTerm

struct EmbeddedTerminalView: NSViewRepresentable {
    let process: LocalProcess

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        // Configure and start process
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Handle updates
    }
}
```

**Note:** SwiftTerm does NOT have native SwiftUI views. You MUST wrap with `NSViewRepresentable`. This is standard practice and works well.

### SwiftTerm + SwiftData

Terminal session state can be persisted in SwiftData:

```swift
@Model
class TerminalSession {
    var id: UUID
    var projectId: UUID?
    var workingDirectory: String
    var createdAt: Date
    var lastActiveAt: Date
    var isClaudeCodeSession: Bool

    // Process state is NOT persisted - recreate on app launch
}
```

**Key insight:** PTY state cannot be serialized. On app restart, you can:
1. Store working directory and recreate sessions
2. Or show "session ended" state with option to restart

### Replacing TerminalService

Current `TerminalService` uses AppleScript to control Terminal.app:
- `sendPrompt()` - types text via AppleScript
- `getWindowContent()` - reads terminal buffer
- `typeText()` - clipboard + paste workaround

With SwiftTerm:
- `LocalProcess.send(data:)` - direct PTY write
- `LocalProcessDelegate.dataReceived()` - direct buffer access
- No AppleScript, no clipboard manipulation, no System Events

**Migration path:**
1. Create `EmbeddedTerminalService` with SwiftTerm
2. Keep `TerminalService` for v1.x compatibility period (optional)
3. Replace callers incrementally

### HookServer Integration

Current `HookServer` receives POST from Claude Code's stop hook. This STILL WORKS with embedded terminals because:
- Claude Code writes to `~/.claude/hooks/stop.sh`
- Hook executes regardless of terminal type
- HTTP POST to localhost works from any process

**No changes needed to HookServer.**

### ExecutionStateMachine

Current states: IDLE -> SENDING -> EXECUTING -> COMPLETED

With embedded terminals, state detection becomes MORE reliable:
- SENDING: Direct PTY write (instant, no AppleScript delay)
- EXECUTING: Process is running (known from PTY)
- COMPLETED: Hook fires OR detect prompt pattern in buffer

**Enhancement:** Can now detect Claude Code prompt pattern directly from terminal buffer instead of polling via AppleScript.

---

## What NOT to Add

### ClaudeCodeSDK
**Reason:** Solves programmatic API access, not interactive terminal embedding. Dispatch needs users to see Claude Code running in real-time.

### Vapor / Hummingbird (HTTP frameworks)
**Reason:** Dispatch already uses `NWListener` for HookServer. No need to add heavyweight HTTP framework for a simple webhook endpoint.

### GRDB.swift
**Reason:** Dispatch uses SwiftData. No benefit to switching database layer for terminal embedding.

### Any UI component libraries (swift-markdown-ui, HighlightSwift)
**Reason:** Not needed for terminal embedding. If markdown rendering is needed later, it is a separate feature.

### iTerm2 integration / other terminal apps
**Reason:** Embedded terminals mean Dispatch IS the terminal. No external app integration needed.

---

## Platform Considerations

### Minimum macOS Version

| Component | Minimum |
|-----------|---------|
| SwiftTerm | macOS 13 |
| Dispatch current | macOS 14 |
| **Result** | macOS 14 (unchanged) |

SwiftTerm's macOS 13 minimum is compatible with Dispatch's macOS 14 target.

### Sandboxing

SwiftTerm uses `forkpty()` and `Process` APIs to spawn subprocesses. These work in non-sandboxed macOS apps.

**If Dispatch ever moves to Mac App Store (sandboxed):**
- Subprocess spawning is heavily restricted
- Would need to rethink architecture
- Currently NOT a concern (Dispatch is direct distribution)

### Permissions

**Removed with v2.0:**
- Automation permission for Terminal.app (no longer needed)
- Accessibility permission for System Events keystrokes (no longer needed)

**Still needed:**
- Accessibility for global hotkey (HotKey package)

This is a significant UX improvement - fewer permission prompts.

---

## Implementation Recommendations

### Phase 1: Basic Terminal Embedding
1. Add SwiftTerm dependency
2. Create `EmbeddedTerminalView` (NSViewRepresentable wrapper)
3. Create `EmbeddedTerminalService` using `LocalProcess`
4. Test: spawn bash, run simple commands

### Phase 2: Claude Code Integration
1. Start Claude Code process in terminal (`claude` command)
2. Integrate with existing HookServer for completion detection
3. Implement prompt sending via PTY write
4. Test: full prompt dispatch cycle

### Phase 3: Session Management
1. Create SwiftData model for terminal sessions
2. Implement session persistence (working directory, project association)
3. Handle session restart on app launch
4. Multi-session UI (tabs or split view)

### Phase 4: Migration & Cleanup
1. Migrate callers from `TerminalService` to `EmbeddedTerminalService`
2. Remove AppleScript-based `TerminalService`
3. Remove Terminal.app automation permission request
4. Update CLAUDE.md documentation

---

## Sources

| Source | Confidence | URL |
|--------|------------|-----|
| SwiftTerm GitHub | HIGH | https://github.com/migueldeicaza/SwiftTerm |
| SwiftTerm Package.swift | HIGH | https://raw.githubusercontent.com/migueldeicaza/SwiftTerm/main/Package.swift |
| SwiftTerm Releases | HIGH | https://github.com/migueldeicaza/SwiftTerm/releases |
| SwiftTerm LocalProcess.swift | HIGH | https://raw.githubusercontent.com/migueldeicaza/SwiftTerm/main/Sources/SwiftTerm/LocalProcess.swift |
| ClaudeCodeSDK README | HIGH | https://raw.githubusercontent.com/jamesrochabrun/ClaudeCodeSDK/main/README.md |
| AgentHub Package.swift | HIGH | https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Package.swift |

---

## Summary

**Add:**
- SwiftTerm 1.10.0+ (terminal emulation + PTY + process management)

**Keep:**
- HotKey (existing, for global hotkey)
- SwiftData (existing, for persistence)
- HookServer (existing, for completion detection)

**Do NOT add:**
- ClaudeCodeSDK (different problem domain)
- GRDB, markdown-ui, HighlightSwift (not needed)
- Additional HTTP frameworks (NWListener sufficient)

**Net result:** One new dependency (SwiftTerm) replaces AppleScript-based Terminal.app control with native embedded terminals.

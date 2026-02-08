# Phase 14: SwiftTerm Integration - Research

**Researched:** 2026-02-07
**Domain:** Terminal emulation, SwiftUI/AppKit integration, pseudo-terminal process management
**Confidence:** HIGH

## Summary

SwiftTerm is a mature, actively-maintained VT100/Xterm terminal emulator library for Swift that provides both AppKit (macOS) and UIKit (iOS) implementations. The library has been in active development for 6 years with 893 commits and supports comprehensive terminal emulation including Unicode, ANSI colors, TrueColor (24-bit), and modern terminal features.

For Phase 14, the standard approach is to use SwiftTerm's `LocalProcessTerminalView` (an NSView) wrapped in an `NSViewRepresentable` for SwiftUI integration. This provides a bash shell with full terminal capabilities including ANSI escape sequences, color support, and interactive command execution. The library requires disabling App Sandbox to allow the shell full filesystem and command access.

**Primary recommendation:** Use SwiftTerm v1.10+ with `LocalProcessTerminalView` wrapped in `NSViewRepresentable`, disable App Sandbox, and leverage the delegate pattern for shell lifecycle management.

## Standard Stack

The established libraries/tools for terminal emulation in Swift macOS apps:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm | 1.10.1+ | VT100/Xterm terminal emulator | Mature (6 years), proven in commercial apps (Secure Shellfish, La Terminal, CodeEdit), comprehensive VT100/Xterm support |
| LocalProcessTerminalView | (SwiftTerm) | NSView for local shell processes | Built-in integration of TerminalView with pseudo-terminal management |
| NSViewRepresentable | (SwiftUI) | AppKit-to-SwiftUI bridge | Apple's standard pattern for embedding NSView in SwiftUI |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation.Process | (stdlib) | Process spawning | NOT for interactive shells - lacks PTY support |
| Darwin (posix_spawn) | (stdlib) | Low-level process control | Advanced PTY management (SwiftTerm handles this) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftTerm | Custom NSTextView + Process | Massive complexity - PTY management, ANSI parsing, cursor control all require manual implementation |
| LocalProcessTerminalView | TerminalView + custom LocalProcess | More control but requires delegate implementation for PTY setup |
| NSViewRepresentable | NSHostingController | Inverted architecture - use when embedding SwiftUI IN AppKit, not AppKit in SwiftUI |

**Installation:**
```swift
// Package.swift or Xcode SPM
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.10.0")
]
```

**Note:** SwiftTerm does not use semantic versioning with tags. Use `.upToNextMinor(from: "1.10.0")` or reference the `main` branch for latest.

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/
├── Views/
│   ├── Terminal/
│   │   ├── EmbeddedTerminalView.swift      # NSViewRepresentable wrapper
│   │   └── TerminalCoordinator.swift       # Coordinator for lifecycle/delegates
├── Services/
│   └── TerminalService.swift                # Shell management, command sending
└── Models/
    └── TerminalSession.swift                # Session state (if multi-session)
```

### Pattern 1: NSViewRepresentable Wrapper
**What:** SwiftUI wrapper that creates and manages LocalProcessTerminalView lifecycle
**When to use:** Embedding terminal in SwiftUI view hierarchy (this phase)
**Example:**
```swift
// Source: Apple NSViewRepresentable documentation + SwiftTerm patterns
struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)

        // Set delegate via coordinator
        terminalView.terminalDelegate = context.coordinator

        // Start bash shell (default: /bin/bash)
        terminalView.startProcess()

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Update if configuration changes (sizing handled by layout)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        // Implement delegate methods for process lifecycle
        func processTerminated(_ source: TerminalView, exitCode: Int32?) {
            print("Process exited with code: \(exitCode ?? -1)")
        }
    }
}
```

### Pattern 2: Coordinator-Based Lifecycle Management
**What:** Use NSViewRepresentable's Coordinator to manage terminal delegates and state
**When to use:** Need to react to shell events or capture output
**Example:**
```swift
// Source: SwiftTerm Discussion #308 - subclassing pattern
class TerminalCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    // Capture shell output for monitoring
    func dataReceived(slice: ArraySlice<UInt8>) {
        // Process output data (e.g., detect prompt patterns)
        let output = String(bytes: slice, encoding: .utf8)
        // Handle in background to avoid blocking terminal
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Terminal resized - may need to notify shell
        print("Terminal resized to \(newCols)x\(newRows)")
    }

    func processTerminated(_ source: TerminalView, exitCode: Int32?) {
        // Handle shell exit (restart, notify user, etc.)
    }
}
```

### Pattern 3: Terminal Sizing in SwiftUI
**What:** Let SwiftUI control frame, terminal auto-calculates cols/rows based on font
**When to use:** Standard responsive layout
**Example:**
```swift
// SwiftUI view with proper sizing
EmbeddedTerminalView()
    .frame(minWidth: 400, minHeight: 300)
    .frame(maxWidth: .infinity, maxHeight: .infinity)

// Terminal automatically calculates cols/rows from:
// - Available frame size
// - Font metrics (terminal.font)
// Result accessible via: terminal.cols, terminal.rows
```

### Anti-Patterns to Avoid
- **Using Foundation.Process for interactive shells:** Process doesn't support PTY, so interactive features (colors, escape sequences, input echoing) won't work. Use LocalProcessTerminalView instead.
- **Trying to manually manage PTY file handles:** SwiftTerm handles PTY setup/teardown. Don't spawn processes separately and try to connect them.
- **Keeping App Sandbox enabled:** LocalProcessTerminalView requires full filesystem/command access. Sandbox restrictions will break basic commands like `ls`, `cd`, etc.
- **Creating terminal in updateNSView:** Terminal and shell process should only be created once in `makeNSView`. Recreating on updates causes shell restarts.
- **Blocking main thread in delegates:** Delegate methods like `dataReceived` are called frequently. Process data on background queue.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ANSI escape sequence parsing | Custom regex parser | SwiftTerm's built-in rendering | Hundreds of edge cases: colors, cursor movement, clearing, modes, character sets. SwiftTerm handles VT100/xterm spec. |
| Pseudo-terminal (PTY) management | posix_spawn + pty.h + file handles | LocalProcessTerminalView | PTY setup is "a royal pain in any language" - master/slave FDs, terminal attributes, window size signaling (TIOCSWINSZ), cleanup on termination. |
| Terminal text rendering | NSTextView with attributed strings | TerminalView | Proper character-level rendering, cursor positioning, scrollback buffer, selection, and Unicode grapheme cluster handling. |
| Shell process lifecycle | Process + pipes | LocalProcessTerminalView.startProcess() | PTY requires proper fork/exec, session ID setup, controlling terminal assignment, and signal handling. |
| Terminal resize signaling | Manual SIGWINCH | SwiftTerm automatic resize | Shell needs TIOCSWINSZ ioctl on window size change. SwiftTerm handles this internally. |
| Unicode/Emoji rendering | Character-by-character NSAttributedString | SwiftTerm's grapheme cluster handling | Combining characters, emoji with skin tones, zero-width joiners, double-width CJK - all require proper wcwidth and grapheme boundary detection. |

**Key insight:** Terminal emulation is deceptively complex. What looks like "text with colors" involves PTY semantics, terminal state machines, escape sequence parsing, and character width calculations. SwiftTerm has 6 years of edge case fixes - don't rebuild it.

## Common Pitfalls

### Pitfall 1: App Sandbox Prevents Shell Access
**What goes wrong:** Terminal renders but commands fail with "command not found" or permission errors. Shell can't access basic utilities in `/bin`, `/usr/bin`, or user files.
**Why it happens:** macOS App Sandbox restricts filesystem and subprocess access by default. The `com.apple.security.app-sandbox` entitlement blocks PTY shells from accessing most of the system.
**How to avoid:**
- Remove or set to `false` the App Sandbox entitlement in your `.entitlements` file
- For Xcode: Target → Signing & Capabilities → Remove "App Sandbox" capability
- Note: This makes Mac App Store distribution impossible (requires sandbox)
**Warning signs:**
- Commands like `ls`, `cd`, `git` return "command not found"
- Shell prompt appears but no commands work
- Console logs show "Operation not permitted" errors

### Pitfall 2: Terminal Recreated on SwiftUI Updates
**What goes wrong:** Shell restarts every time parent view updates, losing state and interrupting running commands.
**Why it happens:** If terminal creation happens in `updateNSView` or if the view identity changes, SwiftUI recreates the entire NSViewRepresentable, including the underlying LocalProcessTerminalView and its shell process.
**How to avoid:**
- Only create LocalProcessTerminalView in `makeNSView`
- Keep `updateNSView` minimal - only update configuration, never recreate views
- Use stable view identity (avoid dynamic IDs or conditional creation that changes)
- Consider `@State` for configuration that should persist across updates
**Warning signs:**
- Shell prompt reappears unexpectedly
- Running commands (like `vim` or `top`) suddenly restart
- Terminal history disappears

### Pitfall 3: Delegate Methods Block Main Thread
**What goes wrong:** Terminal becomes unresponsive during heavy output (compilation logs, large file reads). UI freezes or stutters.
**Why it happens:** `dataReceived(slice:)` is called on the main thread for every chunk of output. Processing synchronously blocks the terminal renderer and SwiftUI updates.
**How to avoid:**
- Dispatch heavy processing to background queue: `DispatchQueue.global().async { ... }`
- Call `super.dataReceived(slice: slice)` immediately, then process asynchronously
- Keep delegate methods fast (<1ms) - defer logging, parsing, or state updates
**Warning signs:**
- Terminal stops scrolling during command output
- Cursor position updates lag behind typing
- Main thread CPU spikes to 100% during shell output

### Pitfall 4: Terminal Size Not Set at Creation
**What goes wrong:** Terminal appears with wrong dimensions (often 80x25 default) until first resize, causing text wrapping issues or truncated output.
**Why it happens:** LocalProcessTerminalView initializes with default size before SwiftUI layout runs. If shell starts before proper size is set, commands see wrong `$COLUMNS` and `$LINES`.
**How to avoid:**
- Let SwiftUI frame propagate naturally - terminal recalculates on first layout
- Don't manually set initial cols/rows unless you have specific requirements
- Terminal auto-adjusts from frame size + font metrics
- For custom sizing, set `TerminalOptions` before calling `startProcess()`
**Warning signs:**
- Initial shell prompt wraps oddly
- `echo $COLUMNS` shows 80 when window is larger
- TUI apps (vim, top) have wrong dimensions on first launch

### Pitfall 5: Hardcoding `/bin/bash` Instead of User Shell
**What goes wrong:** User expects their default shell (zsh on modern macOS) but gets bash. Shell configuration (.zshrc, custom prompt) doesn't load.
**Why it happens:** `LocalProcessTerminalView.startProcess()` defaults to `/bin/bash`. Many macOS users have zsh as default (since Catalina 2019).
**How to avoid:**
- Read user's default shell: `ProcessInfo.processInfo.environment["SHELL"]` or parse `/etc/passwd`
- Pass to startProcess: `terminalView.startProcess(executable: userShell)`
- Provide preference for shell selection if users want alternatives (fish, bash, zsh)
**Warning signs:**
- User complains "my aliases don't work"
- Prompt looks different than system Terminal.app
- Custom shell configuration not loading

### Pitfall 6: Memory Leaks in NSViewRepresentable Lifecycle
**What goes wrong:** Memory usage grows over time, especially with repeated terminal view creation/destruction (navigation, sheets).
**Why it happens:** SwiftUI has known memory leak issues with NSViewRepresentable in sheets/navigation (iOS 17/macOS 14 range), and incorrect Coordinator lifecycle management can cause retain cycles.
**How to avoid:**
- Ensure Coordinator uses `weak` references to avoid cycles
- Clean up terminal resources in `dismantleNSView` (if implemented)
- Be cautious with closures capturing `self` in delegates
- Test with Instruments (Leaks, Allocations) during navigation flows
**Warning signs:**
- Memory usage increases with each terminal open/close
- Terminal views not deallocated after dismissal
- Instruments shows leaked LocalProcessTerminalView instances

## Code Examples

Verified patterns from official sources:

### Basic LocalProcessTerminalView Setup
```swift
// Source: SwiftTerm README + LocalProcessTerminalView API
let terminalView = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

// Optional: Configure terminal options before starting
// (Usually not needed - defaults are sensible)
// terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

// Start shell process (defaults to /bin/bash)
terminalView.startProcess()

// Or specify shell explicitly
let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
terminalView.startProcess(executable: userShell, args: [], environment: nil)
```

### NSViewRepresentable Implementation
```swift
// Source: Apple NSViewRepresentable documentation patterns
struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    // Optional: Pass configuration from SwiftUI
    var onExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator

        // Start user's default shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
        terminal.startProcess(executable: shell)

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Update coordinator's closure if it changed
        context.coordinator.onExit = onExit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onExit: ((Int32?) -> Void)?

        init(onExit: ((Int32?) -> Void)?) {
            self.onExit = onExit
        }

        func processTerminated(_ source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async {
                self.onExit?(exitCode)
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            print("Terminal resized: \(newCols)x\(newRows)")
        }
    }
}
```

### Accessing Terminal Dimensions
```swift
// Source: SwiftTerm Terminal class API documentation
let terminal = terminalView.getTerminal()
let cols = terminal.cols  // Current column count
let rows = terminal.rows  // Current row count

// Terminal auto-calculates these from:
// 1. Available frame size (from SwiftUI/AppKit layout)
// 2. Font metrics (character width/height)
print("Terminal size: \(cols)x\(rows)")
```

### Capturing Shell Output (Advanced)
```swift
// Source: SwiftTerm Discussion #308 - subclassing for output capture
class OutputCapturingTerminalView: LocalProcessTerminalView {
    var outputHandler: ((String) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Call super first to ensure normal rendering
        super.dataReceived(slice: slice)

        // Process output asynchronously
        if let handler = outputHandler {
            DispatchQueue.global(qos: .utility).async {
                if let output = String(bytes: slice, encoding: .utf8) {
                    handler(output)
                }
            }
        }
    }
}
```

### Sending Commands to Shell
```swift
// Source: SwiftTerm TerminalView API
// Note: Send via getTerminal().feed() for programmatic input
let terminal = terminalView.getTerminal()

// Send command with newline to execute
let command = "ls -la\n"
terminal.feed(text: command)

// For byte-level control (e.g., Ctrl+C)
terminal.feed(byteArray: [0x03])  // Ctrl+C = 0x03
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom Process + pipes | LocalProcessTerminalView with PTY | Always (since SwiftTerm v1.0) | PTY provides full interactivity: colors, escape sequences, terminal control |
| Manual ANSI parsing | SwiftTerm built-in VT100/xterm emulation | Always | Comprehensive escape sequence support, tested against esctest suite |
| 16-color ANSI only | TrueColor (24-bit) support | SwiftTerm v1.x+ | Modern CLI tools (bat, delta, ripgrep) use 16M colors for syntax highlighting |
| UIKit on iOS / AppKit on macOS | Shared "Apple" common code | SwiftTerm architecture | Single implementation for terminal logic, platform views are thin wrappers |
| XCTest | Swift Testing | SwiftTerm v1.8.0 (Jan 2025) | Modern Swift testing framework with better concurrency support |
| Manual test cases | esctest suite integration | SwiftTerm v1.9.0 (Jan 2025) | Comprehensive VT100/xterm conformance testing (FreeDesktop standard) |
| Basic Kitty graphics | Full Kitty protocol + memory limits | SwiftTerm v1.8.0 | Graphics in terminal (images) with performance/memory controls |

**Deprecated/outdated:**
- **Foundation.Process for terminals**: Never worked for interactive use due to lack of PTY support. Use LocalProcessTerminalView.
- **Term.xcodeproj separate projects**: SwiftTerm now uses SwiftPM exclusively (as of v1.6+). Don't expect Xcode project files.
- **SwiftTermApp standalone repo**: Reference implementation moved to main SwiftTerm repo under `TerminalApp/` directory.

## Open Questions

Things that couldn't be fully resolved:

1. **Version Requirement Specification**
   - What we know: Latest stable is v1.10.1 (Feb 2025). Requirement says "v1.10.0+" is reasonable.
   - What's unclear: SwiftTerm doesn't use tagged releases consistently. Some users report SPM issues with version resolution.
   - Recommendation: Use `.branch("main")` or `.upToNextMinor(from: "1.10.0")` in Package.swift. Test that Xcode resolves correctly.

2. **Multi-Session Architecture**
   - What we know: v2.0 milestone mentions "multi-session split panes" inspired by AgentHub
   - What's unclear: AgentHub reference not publicly documented. Unknown whether tabs, splits, or both are intended.
   - Recommendation: Start with single embedded terminal for Phase 14. Defer multi-session architecture to later phase.

3. **Terminal Font Configuration**
   - What we know: TerminalView has a `font` property (NSFont/UIFont)
   - What's unclear: Whether Dispatch should allow user font preferences or use system monospace
   - Recommendation: Start with system monospace (`NSFont.monospacedSystemFont()`). Add preference if users request.

4. **Window Restoration / Session Persistence**
   - What we know: SwiftTerm provides terminal state but not shell session persistence
   - What's unclear: Should Dispatch restore terminal content on app restart, or start fresh shell?
   - Recommendation: Start fresh each launch (simpler). Consider tmux integration for session persistence in future phase.

5. **Focus Management Between SwiftUI and Terminal**
   - What we know: NSViewRepresentable can handle focus but requires explicit management
   - What's unclear: How focus integrates with Dispatch's existing keyboard shortcuts (Cmd+N, etc.) and whether terminal steals focus from prompt editing
   - Recommendation: Test focus behavior in Phase 14. May need focus state coordination between terminal view and prompt composer.

## Sources

### Primary (HIGH confidence)
- [SwiftTerm GitHub Repository](https://github.com/migueldeicaza/SwiftTerm) - Main repository, README, architecture
- [SwiftTerm Releases](https://github.com/migueldeicaza/SwiftTerm/releases) - v1.10.1 (Feb 2025) latest stable
- [SwiftTerm README](https://github.com/migueldeicaza/SwiftTerm/blob/main/README.md) - Features, capabilities, installation
- [SwiftTerm Discussion #308](https://github.com/migueldeicaza/SwiftTerm/discussions/308) - Output capture pattern, subclassing guidance
- [Apple NSViewRepresentable Documentation](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) - Official SwiftUI-AppKit bridge pattern
- [Apple WWDC22: Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/) - Best practices, lifecycle, data flow

### Secondary (MEDIUM confidence)
- [Swift Forums: Process with PTY](https://forums.swift.org/t/swift-process-with-psuedo-terminal/51457) - PTY complexity discussion
- [Apple Developer Forums: Swift Process with PTY](https://developer.apple.com/forums/thread/688534) - PTY setup challenges
- [Medium: How macOS PTY Works](https://medium.com/@rajeshbolloju1/how-macos-pty-works-92334ab1ef99) - Recent (Dec 2025) deep dive into PTY behavior
- [SwiftUI Lab: Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/) - Advanced NSViewRepresentable patterns
- [SwiftUI Lab: UIViewControllerRepresentable Memory Leak](https://swiftui-lab.com/uiviewcontrollerrepresentable-memory-leak/) - Known SwiftUI memory issues

### Tertiary (LOW confidence)
- [LocalProcessTerminalView Class Reference](https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcessTerminalView.html) - API docs (404'd during research, may be outdated URL)
- [Terminal Class Reference](https://migueldeicaza.github.io/SwiftTerm/Classes/Terminal.html) - API docs (404'd during research, may be outdated URL)
- WebSearch results about terminal emulation, ANSI escape codes, VT100 specs - general knowledge, not SwiftTerm-specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftTerm is proven, well-documented, and used in commercial apps
- Architecture: HIGH - NSViewRepresentable pattern is Apple's official approach, verified in WWDC
- Don't hand-roll: HIGH - PTY and terminal emulation complexity well-documented across sources
- Pitfalls: MEDIUM - Based on general SwiftUI/AppKit patterns and inferred from forum discussions, not specific to SwiftTerm integration
- Code examples: HIGH - Synthesized from official APIs and verified discussion patterns

**Research date:** 2026-02-07
**Valid until:** ~30 days (stable domain - terminal emulation standards don't change rapidly)

**Note on AgentHub reference:** The requirement mentions "SwiftTerm + LocalProcess pattern (proven in AgentHub)" but AgentHub appears to be internal/private reference. Research proceeded without accessing AgentHub codebase, relying on public SwiftTerm documentation and patterns.

# Phase 17: Claude Code Integration - Research

**Researched:** 2026-02-07
**Domain:** Claude Code CLI process management, PTY-based prompt dispatch, completion detection
**Confidence:** HIGH

## Summary

Phase 17 integrates Claude Code into the embedded terminal established in Phases 14-16. The core challenge is threefold: (1) spawning Claude Code with the correct environment for color output and PATH resolution, (2) dispatching prompts via PTY write instead of AppleScript, and (3) detecting completion through output pattern matching as a complement to the existing HookServer.

Research confirms that SwiftTerm's `LocalProcessTerminalView.startProcess()` accepts an `environment` parameter as `[String]?`, which allows passing custom environment variables. SwiftTerm's `Terminal.getEnvironmentVariables()` helper provides baseline terminal variables (TERM, COLORTERM, LANG). For Claude Code specifically, the PATH must include the `claude` CLI location (typically `~/.claude/local/bin` or similar).

For prompt dispatch, the existing `EmbeddedTerminalView.Coordinator.sendIfRunning()` method uses `terminal.send(txt:)` which writes directly to the PTY. This is the correct approach - no new APIs needed, just proper integration with the existing infrastructure.

For completion detection, Claude Code's idle prompt displays a distinctive box-drawing character pattern (`╭─`) that can be detected in terminal output. The existing `TerminalService.isClaudeCodePromptVisible()` logic identifies patterns including `╭─`, `│`, `╰─`. This same pattern matching can be applied to the terminal buffer content.

**Primary recommendation:** Create a `ClaudeCodeLauncher` service that extends the current `EmbeddedTerminalView` with environment configuration for Claude Code, use the existing `send(txt:)` API for prompt dispatch with proper newline termination, and implement a `TerminalOutputMonitor` that watches the buffer for completion patterns as a fallback/complement to HookServer.

## Standard Stack

The established libraries/tools for this phase:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm LocalProcessTerminalView | 1.10.1 | Terminal emulation with PTY | Already integrated in Phase 14, `startProcess(environment:)` accepts custom env vars |
| SwiftTerm Terminal | 1.10.1 | Environment variable helpers | `getEnvironmentVariables(termName:trueColor:)` provides baseline TERM/COLORTERM/LANG |
| EmbeddedTerminalView | (Dispatch) | NSViewRepresentable wrapper | Existing wrapper from Phase 14, has `send(txt:)` via Coordinator |
| HookServer | (Dispatch) | Completion detection (primary) | Existing HTTP server on port 19847, receives POST from Claude Code stop hook |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ProcessInfo.processInfo.environment | (Foundation) | Access current environment | Get PATH, SHELL, HOME for inheritance |
| FileManager | (Foundation) | Check claude CLI existence | Validate `~/.claude/local/bin/claude` or locate via `which` |
| TerminalProcessRegistry | (Dispatch) | PID tracking | Already integrated in Phase 16, register Claude Code process |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| startProcess(environment:) | Spawn Process separately | Loses PTY integration, would need manual PTY management |
| send(txt:) for prompts | Process stdin write | send(txt:) goes through PTY, proper for interactive input |
| Pattern matching completion | Polling terminal content | Pattern matching is event-driven vs polling, more efficient |

**Installation:**
All components already integrated. No new dependencies required.

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/Services/
├── ClaudeCodeLauncher.swift        # Spawn Claude Code with proper environment (NEW)
├── TerminalOutputMonitor.swift     # Watch terminal buffer for patterns (NEW)
├── TerminalProcessRegistry.swift   # Existing from Phase 16
└── HookServer.swift                # Existing, primary completion detection

Dispatch/Views/Terminal/
└── EmbeddedTerminalView.swift      # Existing, extend for Claude Code mode
```

### Pattern 1: Environment Configuration for Claude Code
**What:** Build environment array with TERM, COLORTERM, LANG, and PATH including claude CLI location.
**When to use:** When spawning Claude Code (vs plain shell).
**Example:**
```swift
// Source: SwiftTerm Terminal.getEnvironmentVariables() + Claude Code requirements
func buildClaudeCodeEnvironment() -> [String] {
    // Start with SwiftTerm's baseline terminal environment
    var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
    // Returns: ["TERM=xterm-256color", "COLORTERM=truecolor", "LANG=en_US.UTF-8", ...]

    // Inherit essential variables from current process
    let processEnv = ProcessInfo.processInfo.environment

    // PATH must include claude CLI location
    if var path = processEnv["PATH"] {
        // Add Claude CLI paths if not already present
        let claudePaths = [
            "\(NSHomeDirectory())/.claude/local/bin",
            "/usr/local/bin"  // Common install location
        ]
        for claudePath in claudePaths {
            if !path.contains(claudePath) {
                path = "\(claudePath):\(path)"
            }
        }
        env.append("PATH=\(path)")
    }

    // Inherit HOME, USER, LOGNAME (SwiftTerm's helper may already include these)
    for key in ["HOME", "USER", "LOGNAME", "SHELL"] {
        if let value = processEnv[key] {
            // Only add if not already present
            if !env.contains(where: { $0.hasPrefix("\(key)=") }) {
                env.append("\(key)=\(value)")
            }
        }
    }

    return env
}
```

### Pattern 2: Claude Code Process Launch
**What:** Start Claude Code directly via `startProcess()` instead of spawning shell first.
**When to use:** When opening a new Claude Code session.
**Example:**
```swift
// Source: SwiftTerm LocalProcessTerminalView + existing EmbeddedTerminalView patterns
class ClaudeCodeLauncher {
    func launchClaudeCode(
        in terminal: LocalProcessTerminalView,
        workingDirectory: String,
        dangerouslySkipPermissions: Bool = false
    ) {
        let claudePath = findClaudeCLI()  // ~/.claude/local/bin/claude or from PATH
        let environment = buildClaudeCodeEnvironment()

        var args: [String] = []
        if dangerouslySkipPermissions {
            args.append("--dangerously-skip-permissions")
        }

        // Set working directory before launch
        terminal.startProcess(
            executable: claudePath,
            args: args,
            environment: environment,
            execName: "claude"
        )

        // Register PID for lifecycle management
        let pid = terminal.process.shellPid
        if pid > 0 {
            TerminalProcessRegistry.shared.register(pid: pid)
        }
    }

    private func findClaudeCLI() -> String {
        // Check common locations
        let candidates = [
            "\(NSHomeDirectory())/.claude/local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback to PATH resolution (let shell find it)
        return "claude"
    }
}
```

### Pattern 3: Prompt Dispatch via PTY
**What:** Send prompt text to Claude Code through the terminal's `send(txt:)` method.
**When to use:** Dispatching prompts from the queue or direct send.
**Example:**
```swift
// Source: Existing EmbeddedTerminalView.Coordinator.sendIfRunning()
extension EmbeddedTerminalView.Coordinator {
    /// Dispatch a prompt to Claude Code
    func dispatchPrompt(_ prompt: String) -> Bool {
        guard let terminal = terminalView else {
            logDebug("Cannot dispatch: no terminal view", category: .terminal)
            return false
        }

        // Prompts need newline to submit to Claude Code
        let fullPrompt = prompt.hasSuffix("\n") ? prompt : prompt + "\n"

        logInfo("Dispatching prompt (\(fullPrompt.count) chars)", category: .terminal)
        terminal.send(txt: fullPrompt)

        return true
    }

    /// Send raw text (for partial input, control characters, etc.)
    func sendRaw(_ text: String) -> Bool {
        guard let terminal = terminalView else { return false }
        terminal.send(txt: text)
        return true
    }
}
```

### Pattern 4: Output Pattern Monitoring for Completion Detection
**What:** Monitor terminal output for Claude Code idle prompt patterns.
**When to use:** As fallback/complement to HookServer for completion detection.
**Example:**
```swift
// Source: Existing TerminalService.isClaudeCodePromptVisible() patterns
class TerminalOutputMonitor {
    // Claude Code prompt patterns indicating idle state
    private static let completionPatterns = ["╭─", "│", "╰─"]

    private weak var terminalView: LocalProcessTerminalView?
    private var isMonitoring = false

    func startMonitoring(_ terminal: LocalProcessTerminalView) {
        self.terminalView = terminal
        self.isMonitoring = true
    }

    func stopMonitoring() {
        self.isMonitoring = false
    }

    /// Check if Claude Code appears to be idle (showing prompt)
    func isClaudeCodeIdle() -> Bool {
        guard let terminal = terminalView else { return false }

        // Get recent terminal content (last ~200 chars)
        let buffer = terminal.getTerminal().getScrollInvariantText()
        let recentContent = String(buffer.suffix(200))

        // Check for prompt patterns near the end
        for pattern in Self.completionPatterns {
            if let range = recentContent.range(of: pattern, options: .backwards) {
                let distance = recentContent.distance(from: range.lowerBound, to: recentContent.endIndex)
                if distance < 100 {
                    logDebug("Claude Code idle detected (pattern: \(pattern))", category: .terminal)
                    return true
                }
            }
        }

        return false
    }
}
```

### Pattern 5: Integration with ExecutionStateMachine
**What:** Connect embedded terminal completion detection with existing state machine.
**When to use:** Replacing/complementing Terminal.app-based polling.
**Example:**
```swift
// Source: Existing ExecutionStateMachine integration patterns
extension ExecutionStateMachine {
    /// Start completion monitoring for embedded terminal
    func startEmbeddedTerminalMonitoring(monitor: TerminalOutputMonitor, interval: TimeInterval = 1.0) {
        guard state == .executing else { return }

        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while !Task.isCancelled && state == .executing {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                    guard !Task.isCancelled else { break }

                    if monitor.isClaudeCodeIdle() {
                        logInfo("Completion detected via terminal pattern", category: .execution)
                        markCompleted(result: .success)
                        break
                    }
                } catch {
                    // Task cancelled or sleep interrupted
                    break
                }
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Spawning shell then running `claude` command:** Adds unnecessary shell layer, loses direct process control. Launch Claude Code directly via `startProcess(executable:)`.
- **Using AppleScript for embedded terminal:** The embedded terminal is in-process. Use `send(txt:)` directly, not AppleScript.
- **Hardcoding claude CLI path:** Users may have different install locations. Check multiple paths or use PATH resolution.
- **Blocking on completion detection:** Pattern matching should be async/polling-based, not synchronous blocking.
- **Ignoring HookServer:** Pattern matching is a fallback. HookServer (stop hook) is primary and more reliable. Use both.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal environment setup | Manual env dict building | Terminal.getEnvironmentVariables() | Handles TERM, COLORTERM, LANG with proper values for color support |
| PTY text sending | Custom write to process stdin | LocalProcessTerminalView.send(txt:) | Goes through SwiftTerm's PTY handling, proper escape sequence handling |
| Completion detection | Custom output parser | HookServer (primary) + pattern matching (fallback) | Hook is authoritative, pattern is safety net |
| Process lifecycle | Track Claude PID separately | TerminalProcessRegistry from Phase 16 | Already handles PID persistence, orphan cleanup |
| Multi-line prompt handling | Custom escaping | send(txt:) with literal newlines | PTY handles newlines correctly, no escaping needed |

**Key insight:** The infrastructure from Phases 14-16 already provides the building blocks. Phase 17 is about integration and configuration, not new low-level mechanisms.

## Common Pitfalls

### Pitfall 1: Missing PATH for Claude CLI
**What goes wrong:** `startProcess(executable: "claude")` fails with "command not found" because PATH doesn't include Claude CLI location.
**Why it happens:** SwiftTerm's `startProcess()` without full path requires the executable to be in PATH. The default environment may not include `~/.claude/local/bin`.
**How to avoid:**
1. Use full path: `startProcess(executable: "/Users/xxx/.claude/local/bin/claude")`
2. Or extend PATH in environment array before spawn
3. Validate claude CLI exists before attempting spawn
**Warning signs:**
- Process terminates immediately after spawn
- Exit code 127 ("command not found")
- Terminal shows shell error message

### Pitfall 2: Wrong TERM/COLORTERM Causing Garbled Output
**What goes wrong:** Claude Code's colored output appears as raw ANSI escape codes or garbled characters.
**Why it happens:** If TERM isn't set to a color-capable terminal type, or COLORTERM isn't set, Claude Code may output differently or CLI tools may not use colors.
**How to avoid:**
1. Use Terminal.getEnvironmentVariables() which sets TERM=xterm-256color and COLORTERM=truecolor
2. Or explicitly set: `["TERM=xterm-256color", "COLORTERM=truecolor"]`
3. Also ensure LANG includes UTF-8 for Unicode characters: `LANG=en_US.UTF-8`
**Warning signs:**
- Escape sequences visible: `\e[32mtext\e[0m` instead of green text
- Box-drawing characters appear as `?` or rectangles
- Emoji not rendering correctly

### Pitfall 3: Prompt Dispatch Without Newline
**What goes wrong:** Prompt appears in terminal but doesn't execute. Claude Code waits for Enter.
**Why it happens:** PTY receives text but without `\n`, Claude Code treats it as incomplete input.
**How to avoid:**
1. Always append newline: `terminal.send(txt: prompt + "\n")`
2. Check if prompt already ends with newline before appending
**Warning signs:**
- Prompt text visible in terminal input area
- Claude Code not processing the prompt
- Need to manually press Enter

### Pitfall 4: Pattern Matching False Positives
**What goes wrong:** Completion detected while Claude Code is still running (during output that contains box characters).
**Why it happens:** Claude Code's output may include box-drawing characters in its responses, not just its idle prompt.
**How to avoid:**
1. Check pattern position is near end of buffer (within last ~100 chars)
2. Use HookServer as primary detection, pattern matching as secondary
3. Consider debouncing: require pattern to be stable for 0.5-1s before triggering
**Warning signs:**
- Execution marked complete mid-response
- New prompt sent before Claude finishes
- Incomplete responses in history

### Pitfall 5: Not Registering Claude Code PID
**What goes wrong:** App quit or crash leaves Claude Code running as orphan.
**Why it happens:** When launching Claude Code directly (not via shell), the PID is the Claude Code process, not a shell. If not registered, TerminalProcessRegistry can't clean it up.
**How to avoid:**
1. Register PID immediately after startProcess(): `TerminalProcessRegistry.shared.register(pid: terminal.process.shellPid)`
2. shellPid property works for any spawned process, not just shells
3. Unregister on natural termination in processTerminated delegate
**Warning signs:**
- `ps aux | grep claude` shows orphaned processes after app crash
- Multiple claude processes accumulate over time
- System resources consumed by zombie processes

### Pitfall 6: Environment Variable Inheritance Issues
**What goes wrong:** Claude Code can't access user's API key, custom configurations, or environment-specific settings.
**Why it happens:** `startProcess(environment:)` replaces the entire environment if provided. Missing ANTHROPIC_API_KEY or other required vars.
**How to avoid:**
1. Start with ProcessInfo.processInfo.environment to inherit current env
2. Merge/override specific vars (TERM, COLORTERM, PATH)
3. Or use `environment: nil` to inherit full current environment, then set only TERM vars
**Warning signs:**
- Claude Code authentication failures
- "API key not found" errors
- User's shell aliases/config not working

## Code Examples

Verified patterns from official sources and existing codebase:

### Complete Claude Code Launch Sequence
```swift
// Source: SwiftTerm API + existing EmbeddedTerminalView patterns
func launchClaudeCodeSession(
    workingDirectory: String,
    skipPermissions: Bool = true
) -> LocalProcessTerminalView {
    let terminal = LocalProcessTerminalView(frame: .zero)

    // Build environment with terminal and Claude requirements
    var environment: [String] = []

    // Start with SwiftTerm's terminal environment helpers
    environment.append(contentsOf: Terminal.getEnvironmentVariables(
        termName: "xterm-256color",
        trueColor: true
    ))

    // Inherit and extend PATH
    let processEnv = ProcessInfo.processInfo.environment
    if var path = processEnv["PATH"] {
        let claudePaths = [
            "\(NSHomeDirectory())/.claude/local/bin",
            "/usr/local/bin"
        ]
        for claudePath in claudePaths where !path.contains(claudePath) {
            path = "\(claudePath):\(path)"
        }
        environment.append("PATH=\(path)")
    }

    // Inherit authentication and user vars
    let inheritKeys = ["HOME", "USER", "LOGNAME", "ANTHROPIC_API_KEY", "SHELL"]
    for key in inheritKeys {
        if let value = processEnv[key] {
            if !environment.contains(where: { $0.hasPrefix("\(key)=") }) {
                environment.append("\(key)=\(value)")
            }
        }
    }

    // Find Claude CLI
    let claudePath = findClaudeCLI()

    // Build args
    var args: [String] = []
    if skipPermissions {
        args.append("--dangerously-skip-permissions")
    }

    // Launch Claude Code directly
    terminal.startProcess(
        executable: claudePath,
        args: args,
        environment: environment,
        execName: "claude"
    )

    // Register for lifecycle management
    let pid = terminal.process.shellPid
    if pid > 0 {
        TerminalProcessRegistry.shared.register(pid: pid)
        logInfo("Claude Code started with PID \(pid)", category: .terminal)
    }

    return terminal
}

private func findClaudeCLI() -> String {
    let candidates = [
        "\(NSHomeDirectory())/.claude/local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude"
    ]

    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    return "claude"  // Let PATH resolve it
}
```

### Prompt Dispatch with Execution Tracking
```swift
// Source: Existing ExecutionManager + EmbeddedTerminalView patterns
func dispatchPromptToEmbeddedTerminal(
    content: String,
    terminal: LocalProcessTerminalView,
    monitor: TerminalOutputMonitor,
    stateMachine: ExecutionStateMachine
) async throws {
    guard !content.isEmpty else {
        throw TerminalServiceError.invalidPromptContent
    }

    // Create execution context
    let context = ExecutionContext(
        promptContent: content,
        promptTitle: "Prompt",
        isFromChain: false
    )

    // Transition to sending state
    stateMachine.beginSending(context: context)

    // Send prompt with newline
    let fullPrompt = content.hasSuffix("\n") ? content : content + "\n"
    terminal.send(txt: fullPrompt)

    logInfo("Prompt dispatched (\(fullPrompt.count) chars)", category: .terminal)

    // Transition to executing
    stateMachine.beginExecuting()

    // Start dual completion detection:
    // 1. HookServer will call handleHookCompletion() when stop hook fires
    // 2. Pattern monitoring as fallback
    stateMachine.startEmbeddedTerminalMonitoring(monitor: monitor, interval: 1.5)
}
```

### Terminal Output Pattern Detection
```swift
// Source: Existing TerminalService.isClaudeCodePromptVisible() + SwiftTerm buffer access
class EmbeddedTerminalOutputMonitor {
    private static let promptPatterns = [
        "╭─",     // Top-left corner of Claude prompt box
        "╰─",     // Bottom-left corner
        "> "      // Alternative simpler prompt
    ]

    weak var terminalView: LocalProcessTerminalView?

    func checkForCompletionPattern() -> Bool {
        guard let terminal = terminalView else { return false }

        // Get terminal's text buffer
        let terminalInstance = terminal.getTerminal()

        // Get text from buffer (last portion)
        // Note: getScrollInvariantText() or buffer access methods vary by SwiftTerm version
        // May need to iterate rows if no direct text getter
        var recentText = ""
        let rows = terminalInstance.rows
        let startRow = max(0, terminalInstance.buffer.yBase + rows - 5)

        for row in startRow..<(terminalInstance.buffer.yBase + rows) {
            if let line = terminalInstance.buffer.lines[row] {
                recentText += line.translateToString() + "\n"
            }
        }

        // Check for patterns near end
        for pattern in Self.promptPatterns {
            if recentText.contains(pattern) {
                // Verify it's near the end (within last 100 chars of our sample)
                if let range = recentText.range(of: pattern, options: .backwards) {
                    let distance = recentText.distance(from: range.lowerBound, to: recentText.endIndex)
                    if distance < 80 {
                        return true
                    }
                }
            }
        }

        return false
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AppleScript Terminal.app dispatch | PTY send(txt:) via embedded terminal | Phase 14 (2026) | Direct, in-process, no IPC overhead |
| Shell spawn then `claude` command | Direct Claude Code process launch | This phase | Cleaner process tree, direct PID tracking |
| Polling Terminal.app content | Buffer pattern matching + HookServer | This phase | Event-driven primary (hooks), efficient fallback (buffer) |
| typeText() clipboard paste | send(txt:) direct PTY write | This phase | No clipboard clobber, instant delivery |
| Window ID targeting | Session reference | Phases 14-16 | In-process session management |

**Deprecated/outdated:**
- **AppleScript-based dispatch**: Replaced by embedded terminal PTY writes for in-app sessions
- **Terminal.app polling**: Replaced by buffer monitoring for embedded sessions (Terminal.app approach still exists for external windows)
- **Clipboard-based text paste**: send(txt:) is direct and doesn't affect system clipboard

## Open Questions

Things that couldn't be fully resolved:

1. **SwiftTerm buffer access API specifics**
   - What we know: Terminal has buffer with lines, can iterate rows
   - What's unclear: Exact API for getting recent text content varies. `getScrollInvariantText()` may not exist in all versions
   - Recommendation: Test with SwiftTerm 1.10.1. If no direct getter, iterate last N rows and translate to string.

2. **Claude Code startup delay**
   - What we know: Claude Code takes time to initialize (loading CLAUDE.md, etc.)
   - What's unclear: How long to wait before considering it ready for prompts
   - Recommendation: Wait for first prompt pattern to appear before enabling dispatch. Could monitor for ">" or "╭─" after launch.

3. **Environment variable completeness**
   - What we know: TERM, COLORTERM, LANG, PATH, HOME are essential
   - What's unclear: Are there other Claude Code-specific env vars needed? What about LC_* locale vars?
   - Recommendation: Start with documented essentials. Inherit full environment with `environment: nil` if issues arise.

4. **Multi-prompt dispatch timing**
   - What we know: send(txt:) is immediate, but Claude Code may not be ready
   - What's unclear: Can prompts be queued while Claude Code is busy? Will they buffer?
   - Recommendation: Respect ExecutionStateMachine states. Only dispatch when in IDLE state.

5. **Hook vs Pattern priority**
   - What we know: HookServer is authoritative, pattern matching is fallback
   - What's unclear: Should pattern matching be disabled when hooks are working? Race conditions?
   - Recommendation: Keep both active. HookServer will trigger first if working. Pattern matching catches cases where hook fails.

## Sources

### Primary (HIGH confidence)
- [SwiftTerm Terminal.getEnvironmentVariables](https://github.com/migueldeicaza/SwiftTerm) - SwiftTerm source code shows this helper
- [SwiftTerm LocalProcessTerminalView.startProcess](https://github.com/migueldeicaza/SwiftTerm) - Source confirms `environment: [String]?` parameter
- [Phase 14 Research](/Users/eric/Dispatch/.planning/phases/14-swiftterm-integration/14-RESEARCH.md) - Verified SwiftTerm patterns
- [Phase 16 Research](/Users/eric/Dispatch/.planning/phases/16-process-lifecycle/16-RESEARCH.md) - Process lifecycle patterns
- [Existing EmbeddedTerminalView](/Users/eric/Dispatch/Dispatch/Views/Terminal/EmbeddedTerminalView.swift) - Current implementation with send(txt:)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Official documentation for Stop hook

### Secondary (MEDIUM confidence)
- [Claude Code Environment Variables](https://medium.com/@dan.avila7/claude-code-environment-variables-a-complete-reference-guide-41229ef18120) - Community guide on env vars
- [SwiftTerm GitHub Discussions](https://github.com/migueldeicaza/SwiftTerm/discussions) - Community patterns
- [Existing TerminalService.isClaudeCodePromptVisible](/Users/eric/Dispatch/Dispatch/Services/TerminalService.swift) - Pattern detection logic

### Tertiary (LOW confidence - flagged for validation)
- Terminal buffer access specifics - Need to verify exact API in SwiftTerm 1.10.1
- Claude Code startup timing - Based on observation, not official documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftTerm APIs verified in source, existing code patterns
- Architecture: HIGH - Extension of proven Phase 14-16 patterns
- Pitfalls: MEDIUM-HIGH - Based on existing codebase patterns and general PTY/process knowledge
- Code examples: MEDIUM - Synthesized from verified APIs but not tested in this phase yet

**Research date:** 2026-02-07
**Valid until:** 2026-03-07 (30 days - SwiftTerm stable, Claude Code hooks API stable)

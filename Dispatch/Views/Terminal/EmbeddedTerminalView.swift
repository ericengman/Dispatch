//
//  EmbeddedTerminalView.swift
//  Dispatch
//
//  NSViewRepresentable wrapper for SwiftTerm LocalProcessTerminalView
//  Provides embedded bash shell with ANSI color support
//

import SwiftTerm
import SwiftUI

/// Launch mode for embedded terminal
enum TerminalLaunchMode {
    case shell // Launch user's default shell
    case claudeCode(workingDirectory: String?, skipPermissions: Bool) // Launch Claude Code directly
    case claudeCodeResume(sessionId: String, workingDirectory: String?, skipPermissions: Bool) // Resume existing session
    case claudeCodeContinue(workingDirectory: String?, skipPermissions: Bool) // Continue most recent session in directory
}

struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = SmartScrollTerminalView

    // Optional session ID for multi-session support (nil = legacy single-session mode)
    var sessionId: UUID?

    // Launch mode determines what process to spawn
    var launchMode: TerminalLaunchMode = .shell

    // Whether this terminal should process scroll/click events
    var isScrollInteractive: Bool = true

    // Optional callback for process exit
    var onProcessExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> SmartScrollTerminalView {
        if let sessionId = sessionId {
            logDebug("Creating embedded terminal view for session: \(sessionId)", category: .terminal)
        } else {
            logDebug("Creating embedded terminal view (legacy mode)", category: .terminal)
        }

        let terminal = SmartScrollTerminalView(frame: .zero)
        terminal.sessionId = sessionId
        terminal.processDelegate = context.coordinator
        terminal.setupScrollPassThrough()
        terminal.setupMouseDownMonitor()

        // Store reference in coordinator for cleanup
        context.coordinator.terminalView = terminal

        // Register with bridge for ExecutionManager access
        if let sessionId = sessionId {
            // Multi-session mode: register with specific session ID
            EmbeddedTerminalBridge.shared.register(sessionId: sessionId, coordinator: context.coordinator, terminal: terminal)

            // Store runtime references in manager (coordinator/terminal cannot be persisted in @Model)
            TerminalSessionManager.shared.setCoordinator(context.coordinator, for: sessionId)
            TerminalSessionManager.shared.setTerminal(terminal, for: sessionId)
        } else {
            // Legacy mode: use single-session API
            EmbeddedTerminalBridge.shared.register(coordinator: context.coordinator, terminal: terminal)
        }

        // Launch appropriate process based on mode
        logInfo("RESUME-DBG EmbeddedTerminalView.makeNSView: launchMode=\(String(describing: launchMode)), sessionId=\(sessionId?.uuidString ?? "nil")", category: .terminal)

        switch launchMode {
        case .shell:
            // Use user's default shell
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
            logInfo("Starting shell: \(shell)", category: .terminal)

            // Register PID for crash recovery (shell mode only - Claude mode handled by launcher)
            let pid = terminal.process.shellPid
            if pid > 0 {
                TerminalProcessRegistry.shared.register(pid: pid)
                logInfo("Terminal process started with PID \(pid)", category: .terminal)
            }

        case let .claudeCode(workingDirectory, skipPermissions):
            logInfo("Launching Claude Code mode", category: .terminal)
            // ClaudeCodeLauncher handles PID registration
            ClaudeCodeLauncher.shared.launchClaudeCode(
                in: terminal,
                workingDirectory: workingDirectory,
                skipPermissions: skipPermissions
            )
            // Detect session ID via lsof (PID-based, deterministic — no race conditions)
            if let capturedSessionId = sessionId, let capturedWorkingDirectory = workingDirectory {
                TerminalSessionManager.shared.detectClaudeSessionId(
                    for: capturedSessionId,
                    workingDirectory: capturedWorkingDirectory
                )
            }

        case let .claudeCodeResume(claudeSessionId, workingDirectory, skipPermissions):
            logInfo("RESUME-DBG EmbeddedTerminalView: RESUME case hit! claudeSessionId=\(claudeSessionId), workingDir=\(workingDirectory ?? "nil"), skipPerms=\(skipPermissions)", category: .terminal)
            // ClaudeCodeLauncher handles PID registration
            ClaudeCodeLauncher.shared.launchClaudeCode(
                in: terminal,
                workingDirectory: workingDirectory,
                skipPermissions: skipPermissions,
                resumeSessionId: claudeSessionId
            )

            // For resume mode, verify session is valid after launch
            Task {
                logInfo("RESUME-DBG EmbeddedTerminalView: post-resume validation Task STARTED for sessionId=\(sessionId?.uuidString ?? "nil")", category: .terminal)

                // Wait for terminal to initialize
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s

                // Check terminal content for error patterns
                guard let terminal = context.coordinator.terminalView else {
                    logWarning("RESUME-DBG EmbeddedTerminalView: post-resume check — terminalView is nil, cannot validate", category: .terminal)
                    return
                }

                let terminalInstance = terminal.getTerminal()
                let data = terminalInstance.getBufferAsData()
                logDebug("RESUME-DBG EmbeddedTerminalView: buffer data size=\(data.count) bytes", category: .terminal)

                guard let content = String(data: data, encoding: .utf8) else {
                    logWarning("RESUME-DBG EmbeddedTerminalView: UTF-8 decode failed for buffer (\(data.count) bytes)", category: .terminal)
                    return
                }

                let tail = String(content.suffix(500))
                let head = String(content.prefix(500))
                logInfo("RESUME-DBG EmbeddedTerminalView: post-resume terminal content (first 500 chars): \(head)", category: .terminal)
                logInfo("RESUME-DBG EmbeddedTerminalView: post-resume terminal content (last 500 chars): \(tail)", category: .terminal)

                if content.contains("Session not found") ||
                    content.contains("No session") ||
                    content.contains("No conversation found") ||
                    content.contains("does not exist") {
                    logWarning("RESUME-DBG EmbeddedTerminalView: resume FAILED — terminal shows session error, calling handleStaleSession", category: .terminal)
                    await MainActor.run {
                        if let sessionId = sessionId {
                            TerminalSessionManager.shared.handleStaleSession(sessionId)
                        }
                    }
                } else {
                    logInfo("RESUME-DBG EmbeddedTerminalView: post-resume check PASSED — no error patterns found", category: .terminal)
                }
            }

        case let .claudeCodeContinue(workingDirectory, skipPermissions):
            logInfo("Launching Claude Code with --continue (most recent session)", category: .terminal)
            ClaudeCodeLauncher.shared.launchClaudeCode(
                in: terminal,
                workingDirectory: workingDirectory,
                skipPermissions: skipPermissions,
                continueLastSession: true
            )
            // Detect which session --continue picked up via lsof (PID-based, deterministic)
            if let capturedSessionId = sessionId, let capturedWorkingDirectory = workingDirectory {
                TerminalSessionManager.shared.detectClaudeSessionId(
                    for: capturedSessionId,
                    workingDirectory: capturedWorkingDirectory
                )
            }
        }

        return terminal
    }

    func updateNSView(_ nsView: SmartScrollTerminalView, context: Context) {
        context.coordinator.onProcessExit = onProcessExit
        nsView.isScrollInteractive = isScrollInteractive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, onProcessExit: onProcessExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let sessionId: UUID? // Optional session ID for multi-session support
        let registrationId = UUID() // Unique identity for bridge registration
        var onProcessExit: ((Int32?) -> Void)?
        var terminalView: SmartScrollTerminalView? // Strong reference for cleanup

        init(sessionId: UUID?, onProcessExit: ((Int32?) -> Void)?) {
            self.sessionId = sessionId
            self.onProcessExit = onProcessExit
            super.init()
        }

        deinit {
            if let sessionId = sessionId {
                logDebug("Coordinator deinit for session \(sessionId) - terminating process group", category: .terminal)
            } else {
                logDebug("Coordinator deinit (legacy mode) - terminating process group", category: .terminal)
            }

            // Unregister from bridge before cleanup (safe to assume main actor in SwiftUI)
            // Uses registrationId to prevent stale coordinator from unregistering newer one
            let regId = registrationId
            MainActor.assumeIsolated {
                if let sessionId = sessionId {
                    EmbeddedTerminalBridge.shared.unregister(sessionId: sessionId, registrationId: regId)
                } else {
                    EmbeddedTerminalBridge.shared.unregister(registrationId: regId)
                }
            }

            guard let terminal = terminalView else { return }
            let pid = terminal.process.shellPid

            // Terminate entire process group (shell + children like Claude Code)
            TerminalProcessRegistry.shared.terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)

            // Unregister after termination
            TerminalProcessRegistry.shared.unregister(pid: pid)

            terminalView = nil
        }

        func processTerminated(source _: TerminalView, exitCode: Int32?) {
            logDebug("Terminal process exited with code: \(exitCode ?? -1)", category: .terminal)

            // Unregister from tracking when process exits naturally
            if let terminal = terminalView {
                TerminalProcessRegistry.shared.unregister(pid: terminal.process.shellPid)
            }

            // Clear reference since process is gone
            terminalView = nil
            DispatchQueue.main.async {
                self.onProcessExit?(exitCode)
            }
        }

        /// Safely send data to terminal, checking process state first
        func sendIfRunning(_ data: Data) -> Bool {
            guard let terminal = terminalView else {
                logDebug("Cannot send: no terminal view", category: .terminal)
                return false
            }
            logDebug("Sending \(data.count) bytes to terminal", category: .terminal)
            terminal.send(txt: String(data: data, encoding: .utf8) ?? "")
            return true
        }

        /// Dispatch a prompt to Claude Code running in this terminal.
        /// Async to guarantee the Enter keystroke is sent before returning,
        /// preventing callers from dismissing windows or changing focus too early.
        /// - Parameter prompt: The prompt text to send
        /// - Returns: true if prompt was sent, false if terminal unavailable
        func dispatchPrompt(_ prompt: String) async -> Bool {
            guard let terminal = terminalView else {
                logDebug("Cannot dispatch: no terminal view", category: .terminal)
                return false
            }

            // Update session activity
            if let sessionId = sessionId {
                TerminalSessionManager.shared.updateSessionActivity(sessionId)
            }

            logInfo("Dispatching prompt (\(prompt.count) chars)", category: .terminal)

            // Reset scroll to bottom so user sees the response
            terminal.scrollToBottom()

            // Use bracketed paste mode to send the entire prompt as a single paste.
            // This prevents multi-line prompts (e.g. image paths + text) from being
            // interpreted as multiple Enter presses by Claude Code.
            let terminalInstance = terminal.getTerminal()
            if terminalInstance.bracketedPasteMode {
                // Send paste start + content + paste end, then Enter separately.
                // Claude Code's TUI needs time to fully process the bracketed paste
                // before it can accept Enter as a submission. Without sufficient delay,
                // the \r arrives while the TUI is still rendering/processing the paste
                // content and gets dropped silently.
                let pasteContent = "\u{1b}[200~\(prompt)\u{1b}[201~"
                terminal.send(txt: pasteContent)
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms — paste processing
                terminal.send(txt: "\r")
                logDebug("Sent bracketed paste + Enter", category: .terminal)
            } else {
                // Fallback: send prompt then Enter separately
                // Claude Code's readline expects \r for submission
                terminal.send(txt: prompt)
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms — input processing
                terminal.send(txt: "\r")
                logDebug("Sent prompt + Enter (non-bracketed mode)", category: .terminal)
            }

            // Wait for Claude Code to fully process the Enter keystroke before
            // returning. Callers activate windows and change focus immediately
            // after dispatch returns — doing so too early can disrupt the
            // terminal's input processing.
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms — post-Enter settle

            return true
        }

        /// Check if terminal is ready to receive a prompt
        var isReadyForDispatch: Bool {
            terminalView != nil
        }

        /// Check if terminal is available for commands
        var isTerminalActive: Bool {
            terminalView != nil
        }

        func sizeChanged(source _: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            logDebug("Terminal resized to \(newCols)x\(newRows)", category: .terminal)
        }

        func setTerminalTitle(source _: LocalProcessTerminalView, title: String) {
            guard let sessionId = sessionId else { return }

            let (prefix, cleanTitle) = Self.extractTitlePrefix(from: title)
            BrewModeController.shared.handleTitleChange(sessionId: sessionId, prefix: prefix)

            if let parsed = Self.parseSessionName(from: cleanTitle) {
                TerminalSessionManager.shared.sessions
                    .first(where: { $0.id == sessionId })?.name = parsed
            }
        }

        /// Claude Code terminal title prefix indicating activity state
        enum ClaudeTitlePrefix {
            case working // · or braille spinner prefix — Claude is thinking/executing
            case finished // ✳ prefix — Claude finished, needs attention
            case none // No prefix — idle or non-Claude title
        }

        /// Extract Claude Code activity prefix from terminal title.
        /// Returns the detected prefix and the clean title with prefix stripped.
        static func extractTitlePrefix(from title: String) -> (ClaudeTitlePrefix, String) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for middle dot prefix (· = U+00B7) — working state
            if trimmed.hasPrefix("· ") || trimmed.hasPrefix("·") {
                let clean = String(trimmed.drop(while: { $0 == "·" || $0 == " " }))
                return (.working, clean)
            }

            // Check for braille spinner prefix (U+2800–U+28FF) — working state
            // Claude Code uses braille pattern characters as an animated spinner (⠐ ⠂ ⠈ etc.)
            if let first = trimmed.first, first.unicodeScalars.first.map({ $0.value >= 0x2800 && $0.value <= 0x28FF }) == true {
                let clean = String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                return (.working, clean)
            }

            // Check for star/asterisk prefix — finished state
            // Match: ✳ (U+2733), ✱ (U+2731), ✻ (U+273B), ❋ (U+275B), * (U+002A)
            if let first = trimmed.first, "✳✱✻❋*".contains(first) {
                let clean = String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                return (.finished, clean)
            }

            return (.none, trimmed)
        }

        /// Parse a meaningful session name from a terminal title.
        /// Returns nil for generic/empty titles so the default "Session N" is kept.
        static func parseSessionName(from title: String) -> String? {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            // Skip generic shell names
            let genericNames: Set<String> = ["bash", "zsh", "sh", "fish", "login", "-bash", "-zsh"]
            if genericNames.contains(trimmed.lowercased()) { return nil }

            // "Claude Code - description" → extract description
            if let range = trimmed.range(of: "Claude Code - ", options: .caseInsensitive) {
                let description = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return description.isEmpty ? nil : description
            }

            // "claude-code" alone is not useful
            if trimmed.lowercased() == "claude-code" || trimmed.lowercased() == "claude code" {
                return nil
            }

            // Path-only title → extract last component
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                let expanded = trimmed.hasPrefix("~")
                    ? (trimmed as NSString).expandingTildeInPath
                    : trimmed
                let last = (expanded as NSString).lastPathComponent
                return last.isEmpty ? nil : last
            }

            return trimmed
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            if let directory = directory {
                logDebug("Terminal directory changed to: \(directory)", category: .terminal)
            }
        }
    }
}

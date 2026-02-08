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
}

struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    // Optional session ID for multi-session support (nil = legacy single-session mode)
    var sessionId: UUID?

    // Launch mode determines what process to spawn
    var launchMode: TerminalLaunchMode = .shell

    // Optional callback for process exit
    var onProcessExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        if let sessionId = sessionId {
            logDebug("Creating embedded terminal view for session: \(sessionId)", category: .terminal)
        } else {
            logDebug("Creating embedded terminal view (legacy mode)", category: .terminal)
        }

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator

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
        switch launchMode {
        case .shell:
            // Use user's default shell
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
            logInfo("Starting shell: \(shell)", category: .terminal)

            terminal.startProcess(executable: shell)

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

        case let .claudeCodeResume(claudeSessionId, workingDirectory, skipPermissions):
            logInfo("Launching Claude Code with resume session: \(claudeSessionId)", category: .terminal)
            // ClaudeCodeLauncher handles PID registration
            ClaudeCodeLauncher.shared.launchClaudeCode(
                in: terminal,
                workingDirectory: workingDirectory,
                skipPermissions: skipPermissions,
                resumeSessionId: claudeSessionId
            )

            // For resume mode, verify session is valid after launch
            Task {
                // Wait for terminal to initialize
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s

                // Check terminal content for error patterns
                if let terminal = context.coordinator.terminalView {
                    let terminalInstance = terminal.getTerminal()
                    let data = terminalInstance.getBufferAsData()
                    if let content = String(data: data, encoding: .utf8) {
                        if content.contains("Session not found") ||
                            content.contains("No session") ||
                            content.contains("does not exist") {
                            await MainActor.run {
                                if let sessionId = sessionId {
                                    TerminalSessionManager.shared.handleStaleSession(sessionId)
                                }
                            }
                        }
                    }
                }
            }
        }

        return terminal
    }

    func updateNSView(_: LocalProcessTerminalView, context: Context) {
        // Update coordinator's callback reference
        context.coordinator.onProcessExit = onProcessExit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, onProcessExit: onProcessExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let sessionId: UUID? // Optional session ID for multi-session support
        var onProcessExit: ((Int32?) -> Void)?
        var terminalView: LocalProcessTerminalView? // Strong reference for cleanup

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
            MainActor.assumeIsolated {
                if let sessionId = sessionId {
                    EmbeddedTerminalBridge.shared.unregister(sessionId: sessionId)
                } else {
                    EmbeddedTerminalBridge.shared.unregister()
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

        /// Dispatch a prompt to Claude Code running in this terminal
        /// - Parameter prompt: The prompt text to send
        /// - Returns: true if prompt was sent, false if terminal unavailable
        func dispatchPrompt(_ prompt: String) -> Bool {
            guard let terminal = terminalView else {
                logDebug("Cannot dispatch: no terminal view", category: .terminal)
                return false
            }

            // Update session activity
            if let sessionId = sessionId {
                TerminalSessionManager.shared.updateSessionActivity(sessionId)
            }

            // Prompts need newline to submit to Claude Code
            let fullPrompt = prompt.hasSuffix("\n") ? prompt : prompt + "\n"

            logInfo("Dispatching prompt (\(fullPrompt.count) chars)", category: .terminal)
            terminal.send(txt: fullPrompt)

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
            logDebug("Terminal title changed to: \(title)", category: .terminal)
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            if let directory = directory {
                logDebug("Terminal directory changed to: \(directory)", category: .terminal)
            }
        }
    }
}

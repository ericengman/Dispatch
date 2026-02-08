//
//  ClaudeCodeLauncher.swift
//  Dispatch
//
//  Service to launch Claude Code with proper terminal environment
//  Configures TERM, COLORTERM, and PATH for colored output
//

import Foundation
import SwiftTerm

/// Launches Claude Code in embedded terminal with proper environment configuration
class ClaudeCodeLauncher {
    static let shared = ClaudeCodeLauncher()

    private init() {}

    /// Find the claude CLI executable
    /// Checks common installation paths before falling back to PATH resolution
    func findClaudeCLI() -> String {
        let candidates = [
            "\(NSHomeDirectory())/.claude/local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                logInfo("Found claude CLI at: \(path)", category: .terminal)
                return path
            }
        }

        logInfo("Using PATH resolution for claude CLI", category: .terminal)
        return "claude"
    }

    /// Build environment array with terminal and PATH configuration
    func buildEnvironment() -> [String] {
        // Start with SwiftTerm's terminal environment (TERM, COLORTERM, LANG)
        var environment = Terminal.getEnvironmentVariables(
            termName: "xterm-256color",
            trueColor: true
        )

        let processEnv = ProcessInfo.processInfo.environment

        // Build PATH with claude CLI locations prepended
        if var path = processEnv["PATH"] {
            let claudePaths = [
                "\(NSHomeDirectory())/.claude/local/bin",
                "/usr/local/bin"
            ]

            for claudePath in claudePaths where !path.contains(claudePath) {
                path = "\(claudePath):\(path)"
            }

            // Only add PATH if not already in environment array
            if !environment.contains(where: { $0.hasPrefix("PATH=") }) {
                environment.append("PATH=\(path)")
                logInfo("Built PATH: \(path)", category: .terminal)
            }
        }

        // Inherit essential environment variables
        let inheritKeys = ["HOME", "USER", "LOGNAME", "SHELL", "ANTHROPIC_API_KEY"]
        for key in inheritKeys {
            if let value = processEnv[key] {
                if !environment.contains(where: { $0.hasPrefix("\(key)=") }) {
                    environment.append("\(key)=\(value)")
                }
            }
        }

        return environment
    }

    /// Launch Claude Code in the given terminal
    /// - Parameters:
    ///   - terminal: The terminal view to launch Claude Code in
    ///   - workingDirectory: Optional working directory (currently unused, for future)
    ///   - skipPermissions: Whether to pass --dangerously-skip-permissions flag
    func launchClaudeCode(
        in terminal: LocalProcessTerminalView,
        workingDirectory _: String? = nil,
        skipPermissions: Bool = true
    ) {
        let claudePath = findClaudeCLI()
        let environment = buildEnvironment()

        var args: [String] = []
        if skipPermissions {
            args.append("--dangerously-skip-permissions")
        }

        logInfo("Launching Claude Code with args: \(args)", category: .terminal)

        terminal.startProcess(
            executable: claudePath,
            args: args,
            environment: environment,
            execName: "claude"
        )

        // Register PID for lifecycle tracking
        let pid = terminal.process.shellPid
        if pid > 0 {
            TerminalProcessRegistry.shared.register(pid: pid)
            logInfo("Claude Code started with PID \(pid)", category: .terminal)
        } else {
            logError("Failed to get PID for Claude Code process", category: .terminal)
        }
    }
}

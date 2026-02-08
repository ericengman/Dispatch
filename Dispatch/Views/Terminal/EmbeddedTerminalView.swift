//
//  EmbeddedTerminalView.swift
//  Dispatch
//
//  NSViewRepresentable wrapper for SwiftTerm LocalProcessTerminalView
//  Provides embedded bash shell with ANSI color support
//

import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    // Optional callback for process exit
    var onProcessExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        logDebug("Creating embedded terminal view", category: .terminal)

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator

        // Use user's default shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
        logInfo("Starting shell: \(shell)", category: .terminal)

        terminal.startProcess(executable: shell)

        // Store reference in coordinator for cleanup
        context.coordinator.terminalView = terminal

        // Register PID for crash recovery
        let pid = terminal.process.shellPid
        if pid > 0 {
            TerminalProcessRegistry.shared.register(pid: pid)
            logInfo("Terminal process started with PID \(pid)", category: .terminal)
        }

        return terminal
    }

    func updateNSView(_: LocalProcessTerminalView, context: Context) {
        // Update coordinator's callback reference
        context.coordinator.onProcessExit = onProcessExit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessExit: onProcessExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onProcessExit: ((Int32?) -> Void)?
        var terminalView: LocalProcessTerminalView? // Strong reference for cleanup

        init(onProcessExit: ((Int32?) -> Void)?) {
            self.onProcessExit = onProcessExit
            super.init()
        }

        deinit {
            logDebug("Coordinator deinit - terminating process group", category: .terminal)

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

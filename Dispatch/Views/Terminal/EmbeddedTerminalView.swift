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

        init(onProcessExit: ((Int32?) -> Void)?) {
            self.onProcessExit = onProcessExit
            super.init()
        }

        func processTerminated(source _: TerminalView, exitCode: Int32?) {
            logDebug("Terminal process exited with code: \(exitCode ?? -1)", category: .terminal)
            DispatchQueue.main.async {
                self.onProcessExit?(exitCode)
            }
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

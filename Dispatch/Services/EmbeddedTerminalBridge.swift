//
//  EmbeddedTerminalBridge.swift
//  Dispatch
//
//  Bridge between ExecutionManager and embedded terminal coordinator
//  Allows services to dispatch prompts to the active terminal without direct coupling
//

import Combine
import Foundation
import SwiftTerm

/// Connects ExecutionManager to embedded terminal for prompt dispatch
/// Coordinator registers/unregisters itself during lifecycle
@MainActor
final class EmbeddedTerminalBridge: ObservableObject {
    static let shared = EmbeddedTerminalBridge()

    /// Currently registered coordinator (nil if no terminal open)
    @Published private(set) var activeCoordinator: EmbeddedTerminalView.Coordinator?

    /// Terminal view for completion monitoring
    @Published private(set) var activeTerminal: LocalProcessTerminalView?

    private init() {}

    /// Register the active terminal coordinator
    /// Called by Coordinator.init or when terminal becomes active
    func register(coordinator: EmbeddedTerminalView.Coordinator, terminal: LocalProcessTerminalView) {
        activeCoordinator = coordinator
        activeTerminal = terminal
        logInfo("Embedded terminal registered for dispatch", category: .terminal)
    }

    /// Unregister when terminal closes
    /// Called by Coordinator.deinit
    func unregister() {
        activeCoordinator = nil
        activeTerminal = nil
        logInfo("Embedded terminal unregistered", category: .terminal)
    }

    /// Check if embedded terminal is available for dispatch
    var isAvailable: Bool {
        activeCoordinator?.isReadyForDispatch ?? false
    }

    /// Dispatch a prompt to the embedded terminal
    /// - Parameter prompt: The prompt text to send
    /// - Returns: true if dispatched, false if no terminal available
    func dispatchPrompt(_ prompt: String) -> Bool {
        guard let coordinator = activeCoordinator else {
            logDebug("Cannot dispatch: no active coordinator", category: .terminal)
            return false
        }

        return coordinator.dispatchPrompt(prompt)
    }
}

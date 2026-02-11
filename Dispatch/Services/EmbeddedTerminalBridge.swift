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

    // MARK: - Multi-Session Registry

    /// Session-aware coordinator registry (keyed by session UUID)
    private var sessionCoordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]

    /// Session-aware terminal registry (keyed by session UUID)
    private var sessionTerminals: [UUID: LocalProcessTerminalView] = [:]

    /// Registration identity tracking (sessionId → registrationId)
    /// Prevents old coordinator deinit from unregistering a newer coordinator
    private var registrationIds: [UUID: UUID] = [:]

    // MARK: - Legacy Single-Session Support

    /// Currently registered coordinator (nil if no terminal open)
    /// Maintained for backward compatibility with MainView
    @Published private(set) var activeCoordinator: EmbeddedTerminalView.Coordinator?

    /// Terminal view for completion monitoring
    /// Maintained for backward compatibility with MainView
    @Published private(set) var activeTerminal: LocalProcessTerminalView?

    private init() {}

    // MARK: - Multi-Session Registration

    /// Register a terminal coordinator for a specific session
    /// - Parameters:
    ///   - sessionId: The session UUID
    ///   - coordinator: The coordinator instance
    ///   - terminal: The terminal view instance
    func register(sessionId: UUID, coordinator: EmbeddedTerminalView.Coordinator, terminal: LocalProcessTerminalView) {
        sessionCoordinators[sessionId] = coordinator
        sessionTerminals[sessionId] = terminal
        registrationIds[sessionId] = coordinator.registrationId
        logInfo("Embedded terminal registered for session: \(sessionId) (reg: \(coordinator.registrationId))", category: .terminal)
    }

    /// Unregister a terminal coordinator for a specific session, only if the registrationId matches.
    /// This prevents a stale coordinator's deinit from unregistering a newer coordinator.
    func unregister(sessionId: UUID, registrationId: UUID) {
        guard registrationIds[sessionId] == registrationId else {
            logDebug("Skipping unregister for session \(sessionId): registrationId mismatch (stale coordinator deinit)", category: .terminal)
            return
        }
        sessionCoordinators.removeValue(forKey: sessionId)
        sessionTerminals.removeValue(forKey: sessionId)
        registrationIds.removeValue(forKey: sessionId)
        logInfo("Embedded terminal unregistered for session: \(sessionId)", category: .terminal)
    }

    /// Force-unregister a session (used by closeSession cleanup)
    func forceUnregister(sessionId: UUID) {
        sessionCoordinators.removeValue(forKey: sessionId)
        sessionTerminals.removeValue(forKey: sessionId)
        registrationIds.removeValue(forKey: sessionId)
        logInfo("Embedded terminal force-unregistered for session: \(sessionId)", category: .terminal)
    }

    /// Check if a specific session is available for dispatch
    /// - Parameter sessionId: The session UUID
    /// - Returns: true if session is ready for dispatch
    func isAvailable(sessionId: UUID) -> Bool {
        sessionCoordinators[sessionId]?.isReadyForDispatch ?? false
    }

    /// Get terminal for a specific session (for completion monitoring)
    /// - Parameter sessionId: The session UUID
    /// - Returns: Terminal view if available
    func getTerminal(for sessionId: UUID) -> LocalProcessTerminalView? {
        sessionTerminals[sessionId]
    }

    /// Dispatch a prompt to a specific session
    /// - Parameters:
    ///   - prompt: The prompt text to send
    ///   - sessionId: The session UUID to dispatch to
    /// - Returns: true if dispatched, false if session unavailable
    func dispatchPrompt(_ prompt: String, to sessionId: UUID) async -> Bool {
        guard let coordinator = sessionCoordinators[sessionId] else {
            logDebug("Cannot dispatch: session \(sessionId) not found", category: .terminal)
            return false
        }

        logDebug("Dispatching to session: \(sessionId)", category: .terminal)
        return await coordinator.dispatchPrompt(prompt)
    }

    // MARK: - Legacy Single-Session API (Backward Compatibility)

    /// Register the active terminal coordinator (legacy API)
    /// Delegates to session-aware API using TerminalSessionManager.activeSessionId
    /// Called by Coordinator.init or when terminal becomes active
    func register(coordinator: EmbeddedTerminalView.Coordinator, terminal: LocalProcessTerminalView) {
        // Update legacy properties
        activeCoordinator = coordinator
        activeTerminal = terminal

        // If there's an active session, register there too
        if let sessionId = TerminalSessionManager.shared.activeSessionId {
            register(sessionId: sessionId, coordinator: coordinator, terminal: terminal)
        }

        logInfo("Embedded terminal registered for dispatch (legacy mode)", category: .terminal)
    }

    /// Unregister when terminal closes (legacy API)
    /// Called by Coordinator.deinit
    func unregister(registrationId: UUID) {
        // Only clear legacy properties if this coordinator is still the active one
        if activeCoordinator?.registrationId == registrationId {
            activeCoordinator = nil
            activeTerminal = nil
        }

        // If there's an active session, unregister it too (with identity check)
        if let sessionId = TerminalSessionManager.shared.activeSessionId {
            unregister(sessionId: sessionId, registrationId: registrationId)
        }

        logInfo("Embedded terminal unregistered (legacy mode)", category: .terminal)
    }

    /// Check if embedded terminal is available for dispatch (legacy API)
    var isAvailable: Bool {
        activeCoordinator?.isReadyForDispatch ?? false
    }

    /// Dispatch a prompt to the embedded terminal (legacy API)
    /// Dispatches to activeSessionId if available, otherwise uses legacy activeCoordinator
    /// - Parameter prompt: The prompt text to send
    /// - Returns: true if dispatched, false if no terminal available
    func dispatchPrompt(_ prompt: String) async -> Bool {
        // Try session-aware dispatch first
        if let sessionId = TerminalSessionManager.shared.activeSessionId {
            return await dispatchPrompt(prompt, to: sessionId)
        }

        // Fallback to legacy behavior
        guard let coordinator = activeCoordinator else {
            logDebug("Cannot dispatch: no active coordinator", category: .terminal)
            return false
        }

        return await coordinator.dispatchPrompt(prompt)
    }
}

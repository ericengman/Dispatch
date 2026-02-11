//
//  EmbeddedTerminalService.swift
//  Dispatch
//
//  Service for dispatching prompts to embedded terminals (PTY-based)
//  Wraps EmbeddedTerminalBridge to provide service-layer interface
//

import Foundation
import SwiftTerm

/// Service for dispatching prompts to embedded terminals (PTY-based)
/// Wraps EmbeddedTerminalBridge to provide service-layer interface
@MainActor
final class EmbeddedTerminalService {
    static let shared = EmbeddedTerminalService()

    private let bridge = EmbeddedTerminalBridge.shared
    private let sessionManager = TerminalSessionManager.shared

    private init() {}

    // MARK: - Availability

    /// Check if any embedded terminal is available for dispatch
    var isAvailable: Bool { bridge.isAvailable }

    /// Check if specific session is available
    func isAvailable(sessionId: UUID) -> Bool {
        bridge.isAvailable(sessionId: sessionId)
    }

    // MARK: - Session Info

    /// Currently active session ID (for targeting/tracking)
    var activeSessionId: UUID? { sessionManager.activeSessionId }

    /// Get terminal for session (for completion monitoring)
    func getTerminal(for sessionId: UUID) -> LocalProcessTerminalView? {
        bridge.getTerminal(for: sessionId)
    }

    // MARK: - Dispatch

    /// Dispatch prompt to active session
    /// Updates session activity timestamp on successful dispatch
    @discardableResult
    func dispatchPrompt(_ content: String) async -> Bool {
        let result = await bridge.dispatchPrompt(content)
        if result, let sessionId = sessionManager.activeSessionId {
            sessionManager.updateSessionActivity(sessionId)
        }
        return result
    }

    /// Dispatch prompt to specific session
    /// Updates session activity timestamp on successful dispatch
    @discardableResult
    func dispatchPrompt(_ content: String, to sessionId: UUID) async -> Bool {
        let result = await bridge.dispatchPrompt(content, to: sessionId)
        if result {
            sessionManager.updateSessionActivity(sessionId)
        }
        return result
    }
}

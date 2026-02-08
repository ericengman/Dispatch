// TerminalSessionManager.swift
// Manages collection of terminal sessions, active session, and layout mode

import Foundation

@Observable
@MainActor
final class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private(set) var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var layoutMode: LayoutMode = .single
    let maxSessions: Int = 4 // SESS-06: limit to prevent resource exhaustion
    private var nextSessionNumber: Int = 1

    enum LayoutMode: String, CaseIterable {
        case single // Focus mode (one session fullscreen)
        case horizontalSplit // Side-by-side
        case verticalSplit // Above-and-below
    }

    private init() {}

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    var canCreateSession: Bool {
        sessions.count < maxSessions
    }

    @discardableResult
    func createSession(name: String? = nil) -> TerminalSession? {
        guard canCreateSession else {
            logWarning("Cannot create session: max limit (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        let sessionName = name ?? "Session \(nextSessionNumber)"
        nextSessionNumber += 1
        let session = TerminalSession(name: sessionName)
        sessions.append(session)

        // Auto-activate if first session
        if activeSessionId == nil {
            activeSessionId = session.id
        }

        logInfo("Created session: \(session.name) (\(session.id))", category: .terminal)
        return session
    }

    func closeSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            logWarning("Cannot close session: \(sessionId) not found", category: .terminal)
            return
        }

        let session = sessions[index]
        logInfo("Closing session: \(session.name)", category: .terminal)

        // Clear references (triggers coordinator deinit -> process cleanup)
        session.coordinator = nil
        session.terminal = nil

        sessions.remove(at: index)

        // If active session closed, select another
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
            logDebug("Active session changed to: \(activeSessionId?.uuidString ?? "none")", category: .terminal)
        }
    }

    func setActiveSession(_ sessionId: UUID) {
        guard sessions.contains(where: { $0.id == sessionId }) else {
            logWarning("Cannot activate session: \(sessionId) not found", category: .terminal)
            return
        }
        activeSessionId = sessionId
        logDebug("Active session set to: \(sessionId)", category: .terminal)
    }

    func toggleLayoutMode() {
        switch layoutMode {
        case .single:
            layoutMode = .horizontalSplit
        case .horizontalSplit:
            layoutMode = .verticalSplit
        case .verticalSplit:
            layoutMode = .single
        }
        logDebug("Layout mode changed to: \(layoutMode.rawValue)", category: .terminal)
    }

    func setLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        logDebug("Layout mode set to: \(mode.rawValue)", category: .terminal)
    }
}

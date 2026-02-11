// TerminalSession.swift
// SwiftData model representing a single terminal session

import Foundation
import SwiftData

@Model
final class TerminalSession {
    // MARK: - Properties

    var id: UUID
    var name: String
    var createdAt: Date
    var lastActivity: Date

    // Claude Code session resumption support
    var claudeSessionId: String? // Claude session ID if resuming
    var workingDirectory: String? // Project path for Claude Code

    // MARK: - Transient State

    @Transient var wasRestoredFromPersistence = false

    // MARK: - Relationships

    var project: Project?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastActivity: Date = Date(),
        claudeSessionId: String? = nil,
        workingDirectory: String? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.claudeSessionId = claudeSessionId
        self.workingDirectory = workingDirectory
        self.project = project
    }

    // MARK: - Computed Properties

    /// Computed launch mode based on session configuration
    var launchMode: TerminalLaunchMode {
        logInfo("RESUME-DBG launchMode called for session '\(name)' (id=\(id))", category: .terminal)
        logInfo("RESUME-DBG   claudeSessionId=\(claudeSessionId ?? "nil")", category: .terminal)
        logInfo("RESUME-DBG   workingDirectory=\(workingDirectory ?? "nil")", category: .terminal)
        logInfo("RESUME-DBG   wasRestoredFromPersistence=\(wasRestoredFromPersistence)", category: .terminal)
        logInfo("RESUME-DBG   lastActivity=\(lastActivity), createdAt=\(createdAt), lastActivity > createdAt = \(lastActivity > createdAt)", category: .terminal)

        if let sessionId = claudeSessionId {
            logInfo("RESUME-DBG   -> DECISION: .claudeCodeResume with sessionId=\(sessionId)", category: .terminal)
            return .claudeCodeResume(
                sessionId: sessionId,
                workingDirectory: workingDirectory,
                skipPermissions: true
            )
        }
        // Restored from persistence but lost session ID (validation cleared it) — start fresh
        // Don't use --continue which could pick up the wrong session
        if wasRestoredFromPersistence {
            logInfo("RESUME-DBG   -> DECISION: .claudeCode (fresh) because wasRestoredFromPersistence=true and claudeSessionId=nil", category: .terminal)
            return .claudeCode(workingDirectory: workingDirectory, skipPermissions: true)
        }
        // If we have a working directory and prior activity, use --continue to resume
        // the most recent session instead of starting fresh
        if workingDirectory != nil, lastActivity > createdAt {
            logInfo("RESUME-DBG   -> DECISION: .claudeCodeContinue (--continue flag)", category: .terminal)
            return .claudeCodeContinue(workingDirectory: workingDirectory, skipPermissions: true)
        }
        logInfo("RESUME-DBG   -> DECISION: .claudeCode (fresh, no special conditions)", category: .terminal)
        return .claudeCode(workingDirectory: workingDirectory, skipPermissions: true)
    }

    /// Whether this session can be resumed
    var isResumable: Bool {
        claudeSessionId != nil
    }

    /// Relative time string for last activity
    var relativeLastActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastActivity, relativeTo: Date())
    }

    // MARK: - Methods

    /// Update the last activity timestamp to current time
    func updateActivity() {
        lastActivity = Date()
    }
}

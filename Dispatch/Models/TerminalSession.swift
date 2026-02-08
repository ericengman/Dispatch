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
        if let sessionId = claudeSessionId {
            return .claudeCodeResume(
                sessionId: sessionId,
                workingDirectory: workingDirectory,
                skipPermissions: true
            )
        }
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

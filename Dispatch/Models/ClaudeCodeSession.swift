//
//  ClaudeCodeSession.swift
//  Dispatch
//
//  Represents a Claude Code session from ~/.claude/projects/
//  Used for session resumption feature
//

import Foundation

/// Represents a Claude Code session that can be resumed
nonisolated struct ClaudeCodeSession: Identifiable, Hashable, Codable {
    let id: UUID
    let sessionId: String // Claude's session UUID string
    let projectPath: String // Original project path (e.g., "/Users/eric/Dispatch")
    let firstPrompt: String // First user message (for display)
    let messageCount: Int // Number of messages in conversation
    let created: Date
    let modified: Date
    let gitBranch: String?
    let isSidechain: Bool

    /// Truncated first prompt for UI display
    var displayPrompt: String {
        let trimmed = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 {
            return trimmed
        }
        return String(trimmed.prefix(77)) + "..."
    }

    /// Relative time since last modified (e.g., "2 hours ago")
    var relativeModified: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modified, relativeTo: Date())
    }

    // MARK: - Codable for JSON parsing

    enum CodingKeys: String, CodingKey {
        case sessionId
        case projectPath
        case firstPrompt
        case messageCount
        case created
        case modified
        case gitBranch
        case isSidechain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let sessionIdString = try container.decode(String.self, forKey: .sessionId)
        id = UUID(uuidString: sessionIdString) ?? UUID()
        sessionId = sessionIdString
        projectPath = try container.decode(String.self, forKey: .projectPath)
        firstPrompt = try container.decode(String.self, forKey: .firstPrompt)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        isSidechain = try container.decodeIfPresent(Bool.self, forKey: .isSidechain) ?? false

        // Parse ISO8601 dates
        let createdString = try container.decode(String.self, forKey: .created)
        let modifiedString = try container.decode(String.self, forKey: .modified)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        created = formatter.date(from: createdString) ?? Date.distantPast
        modified = formatter.date(from: modifiedString) ?? Date.distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(firstPrompt, forKey: .firstPrompt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encode(isSidechain, forKey: .isSidechain)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: created), forKey: .created)
        try container.encode(formatter.string(from: modified), forKey: .modified)
    }

    // For manual creation (non-JSON)
    init(
        sessionId: String,
        projectPath: String,
        firstPrompt: String,
        messageCount: Int,
        created: Date,
        modified: Date,
        gitBranch: String?,
        isSidechain: Bool = false
    ) {
        id = UUID(uuidString: sessionId) ?? UUID()
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.firstPrompt = firstPrompt
        self.messageCount = messageCount
        self.created = created
        self.modified = modified
        self.gitBranch = gitBranch
        self.isSidechain = isSidechain
    }
}

// MARK: - Sessions Index JSON Structure

/// Root structure for sessions-index.json
nonisolated struct ClaudeSessionsIndex: Codable {
    let version: Int
    let entries: [ClaudeCodeSession]
}

//
//  PromptHistory.swift
//  Dispatch
//
//  Immutable snapshot of sent prompts for history tracking
//

import Foundation
import SwiftData

@Model
final class PromptHistory {
    // MARK: - Properties

    var id: UUID

    /// Snapshot of the prompt content at time of sending
    var content: String

    /// When the prompt was sent
    var sentAt: Date

    /// Denormalized project name for persistence (project may be deleted)
    var projectName: String?

    /// Which terminal window it was sent to
    var terminalWindowName: String?

    /// Terminal window ID for reference
    var terminalWindowId: String?

    /// Whether this was part of an automated chain execution
    var wasFromChain: Bool

    /// If from chain, which chain name
    var chainName: String?

    /// Original prompt ID for reference (prompt may be deleted)
    var originalPromptId: UUID?

    /// Original prompt title at time of sending
    var originalPromptTitle: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        content: String,
        sentAt: Date = Date(),
        projectName: String? = nil,
        terminalWindowName: String? = nil,
        terminalWindowId: String? = nil,
        wasFromChain: Bool = false,
        chainName: String? = nil,
        originalPromptId: UUID? = nil,
        originalPromptTitle: String? = nil
    ) {
        self.id = id
        self.content = content
        self.sentAt = sentAt
        self.projectName = projectName
        self.terminalWindowName = terminalWindowName
        self.terminalWindowId = terminalWindowId
        self.wasFromChain = wasFromChain
        self.chainName = chainName
        self.originalPromptId = originalPromptId
        self.originalPromptTitle = originalPromptTitle

        logDebug("Created history entry for '\(displayTitle)'", category: .history)
    }

    // MARK: - Factory Methods

    /// Creates a history entry from a Prompt
    static func from(
        prompt: Prompt,
        terminalWindowName: String? = nil,
        terminalWindowId: String? = nil,
        wasFromChain: Bool = false,
        chainName: String? = nil
    ) -> PromptHistory {
        PromptHistory(
            content: prompt.content,
            projectName: prompt.project?.name,
            terminalWindowName: terminalWindowName,
            terminalWindowId: terminalWindowId,
            wasFromChain: wasFromChain,
            chainName: chainName,
            originalPromptId: prompt.id,
            originalPromptTitle: prompt.displayTitle
        )
    }

    /// Creates a history entry from inline content
    static func fromInline(
        content: String,
        terminalWindowName: String? = nil,
        terminalWindowId: String? = nil,
        wasFromChain: Bool = false,
        chainName: String? = nil
    ) -> PromptHistory {
        PromptHistory(
            content: content,
            terminalWindowName: terminalWindowName,
            terminalWindowId: terminalWindowId,
            wasFromChain: wasFromChain,
            chainName: chainName
        )
    }

    // MARK: - Computed Properties

    /// Display title for the history entry
    var displayTitle: String {
        if let title = originalPromptTitle, !title.isEmpty {
            return title
        }

        // Auto-generate from content
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        if firstLine.count <= 50 {
            return firstLine.trimmingCharacters(in: .whitespaces)
        }
        return String(firstLine.prefix(50)) + "..."
    }

    /// Preview text (first 100 chars, single line)
    var previewText: String {
        let singleLine = content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if singleLine.count <= 100 {
            return singleLine
        }
        return String(singleLine.prefix(100)) + "..."
    }

    /// Relative time since sent
    var relativeSentTime: String {
        RelativeTimeFormatter.format(sentAt)
    }

    /// Formatted sent date for display
    var formattedSentDate: String {
        Self.dateFormatter.string(from: sentAt)
    }

    /// Description of the source
    var sourceDescription: String {
        if wasFromChain, let chainName = chainName {
            return "Chain: \(chainName)"
        }
        if let projectName = projectName {
            return projectName
        }
        return "Manual"
    }

    /// Target description
    var targetDescription: String {
        terminalWindowName ?? "Active Window"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - History Queries

extension PromptHistory {
    /// Predicate for entries within the retention period
    static func withinRetention(days: Int) -> Predicate<PromptHistory> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return #Predicate<PromptHistory> { history in
            history.sentAt >= cutoffDate
        }
    }

    /// Predicate for searching history content
    static func matching(searchText: String) -> Predicate<PromptHistory> {
        #Predicate<PromptHistory> { history in
            history.content.localizedStandardContains(searchText) ||
            (history.originalPromptTitle?.localizedStandardContains(searchText) ?? false) ||
            (history.chainName?.localizedStandardContains(searchText) ?? false)
        }
    }
}

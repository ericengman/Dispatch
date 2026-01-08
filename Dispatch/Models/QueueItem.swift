//
//  QueueItem.swift
//  Dispatch
//
//  Model for items in the execution queue
//

import Foundation
import SwiftData

/// Status of a queue item
enum QueueItemStatus: String, Codable, Sendable {
    case pending        // Waiting to be executed
    case executing      // Currently being executed
    case completed      // Successfully executed
    case failed         // Failed to execute
}

@Model
final class QueueItem {
    // MARK: - Properties

    var id: UUID

    /// Order in the queue (0-indexed, lower = higher priority)
    var order: Int

    /// Inline prompt content (used if prompt reference is nil)
    var inlineContent: String?

    /// When this item was added to the queue
    var addedAt: Date

    /// Specific terminal to target (nil = active window)
    var targetTerminalId: String?

    /// Display name of target terminal for UI
    var targetTerminalName: String?

    /// Current status of this queue item
    var statusRaw: String

    /// Error message if execution failed
    var errorMessage: String?

    // MARK: - Relationships

    /// Reference to a library prompt (mutually exclusive with inlineContent)
    var prompt: Prompt?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        prompt: Prompt? = nil,
        inlineContent: String? = nil,
        order: Int = 0,
        addedAt: Date = Date(),
        targetTerminalId: String? = nil,
        targetTerminalName: String? = nil,
        status: QueueItemStatus = .pending
    ) {
        self.id = id
        self.prompt = prompt
        self.inlineContent = inlineContent
        self.order = order
        self.addedAt = addedAt
        self.targetTerminalId = targetTerminalId
        self.targetTerminalName = targetTerminalName
        self.statusRaw = status.rawValue

        logDebug("Created queue item at order \(order), status: \(status)", category: .queue)
    }

    // MARK: - Computed Properties

    /// Current status as enum
    var status: QueueItemStatus {
        get { QueueItemStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// Returns true if this item has valid content
    var hasContent: Bool {
        prompt != nil || (inlineContent != nil && !inlineContent!.isEmpty)
    }

    /// Returns the content to be sent
    var effectiveContent: String? {
        if let prompt = prompt {
            return prompt.content
        }
        return inlineContent
    }

    /// Display title for the queue item
    var displayTitle: String {
        if let prompt = prompt {
            return prompt.displayTitle
        }

        if let inline = inlineContent, !inline.isEmpty {
            let firstLine = inline.components(separatedBy: .newlines).first ?? inline
            if firstLine.count <= 40 {
                return firstLine
            }
            return String(firstLine.prefix(40)) + "..."
        }

        return "Empty Item"
    }

    /// Preview text for display
    var previewText: String {
        guard let content = effectiveContent else { return "" }

        let singleLine = content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if singleLine.count <= 80 {
            return singleLine
        }
        return String(singleLine.prefix(80)) + "..."
    }

    /// Target description for display
    var targetDescription: String {
        targetTerminalName ?? "Active Window"
    }

    /// Indicates if using library reference
    var isLibraryReference: Bool {
        prompt != nil
    }

    /// Check if content has placeholders
    var hasPlaceholders: Bool {
        if let content = effectiveContent {
            return PlaceholderPattern.hasPlaceholders(in: content)
        }
        return false
    }

    /// Get placeholder names from content
    var placeholderNames: [String] {
        if let content = effectiveContent {
            return PlaceholderPattern.extractPlaceholders(from: content)
        }
        return []
    }

    /// Time since added to queue
    var relativeAddedTime: String {
        RelativeTimeFormatter.format(addedAt)
    }

    /// Whether this item is ready to execute
    var isReady: Bool {
        status == .pending && hasContent
    }

    /// Whether this item can be removed from queue
    var canRemove: Bool {
        status != .executing
    }

    // MARK: - Methods

    /// Marks the item as executing
    func markExecuting() {
        status = .executing
        errorMessage = nil
        logDebug("Queue item '\(displayTitle)' marked as executing", category: .queue)
    }

    /// Marks the item as completed
    func markCompleted() {
        status = .completed
        errorMessage = nil
        logDebug("Queue item '\(displayTitle)' marked as completed", category: .queue)
    }

    /// Marks the item as failed
    func markFailed(error: String) {
        status = .failed
        errorMessage = error
        logError("Queue item '\(displayTitle)' failed: \(error)", category: .queue)
    }

    /// Resets the item to pending state
    func reset() {
        status = .pending
        errorMessage = nil
        logDebug("Queue item '\(displayTitle)' reset to pending", category: .queue)
    }

    /// Updates the target terminal
    func setTarget(id: String?, name: String?) {
        targetTerminalId = id
        targetTerminalName = name
        logDebug("Queue item '\(displayTitle)' target set to '\(name ?? "Active Window")'", category: .queue)
    }
}

// MARK: - Queue Item Factory

extension QueueItem {
    /// Creates a queue item from a Prompt
    static func from(prompt: Prompt, order: Int = 0, targetTerminalId: String? = nil, targetTerminalName: String? = nil) -> QueueItem {
        QueueItem(
            prompt: prompt,
            order: order,
            targetTerminalId: targetTerminalId,
            targetTerminalName: targetTerminalName
        )
    }

    /// Creates a queue item from inline content
    static func fromInline(content: String, order: Int = 0, targetTerminalId: String? = nil, targetTerminalName: String? = nil) -> QueueItem {
        QueueItem(
            inlineContent: content,
            order: order,
            targetTerminalId: targetTerminalId,
            targetTerminalName: targetTerminalName
        )
    }
}

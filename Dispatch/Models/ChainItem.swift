//
//  ChainItem.swift
//  Dispatch
//
//  Model for individual steps within a PromptChain
//

import Foundation
import SwiftData

@Model
final class ChainItem {
    // MARK: - Properties

    var id: UUID

    /// Order within the chain (0-indexed)
    var order: Int

    /// Inline prompt content (used if prompt reference is nil)
    var inlineContent: String?

    /// Delay in seconds after this step completes before executing next
    var delaySeconds: Int

    // MARK: - Relationships

    /// Reference to a library prompt (mutually exclusive with inlineContent)
    var prompt: Prompt?

    /// Back-reference to the parent chain
    var chain: PromptChain?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        prompt: Prompt? = nil,
        inlineContent: String? = nil,
        order: Int = 0,
        delaySeconds: Int = 0,
        chain: PromptChain? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.inlineContent = inlineContent
        self.order = order
        self.delaySeconds = delaySeconds
        self.chain = chain

        logDebug("Created chain item at order \(order), delay: \(delaySeconds)s", category: .chain)
    }

    // MARK: - Computed Properties

    /// Returns true if this item has valid content (either prompt or inline)
    var hasContent: Bool {
        prompt != nil || (inlineContent != nil && !inlineContent!.isEmpty)
    }

    /// Returns the content to be sent (from prompt or inline)
    var effectiveContent: String? {
        if let prompt = prompt {
            return prompt.content
        }
        return inlineContent
    }

    /// Returns a display title for this item
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

        return "Empty Step"
    }

    /// Returns the source type for display
    var sourceDescription: String {
        if prompt != nil {
            return "From library"
        }
        return "Inline prompt"
    }

    /// Indicates if this uses a library reference
    var isLibraryReference: Bool {
        prompt != nil
    }

    /// Indicates if this uses inline content
    var isInlineContent: Bool {
        prompt == nil && inlineContent != nil
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

    // MARK: - Methods

    /// Updates the inline content
    func setInlineContent(_ content: String) {
        self.inlineContent = content
        self.prompt = nil  // Clear prompt reference
        logDebug("Set inline content for chain item at order \(order)", category: .chain)
    }

    /// Updates the prompt reference
    func setPrompt(_ prompt: Prompt) {
        self.prompt = prompt
        self.inlineContent = nil  // Clear inline content
        logDebug("Set prompt reference '\(prompt.displayTitle)' for chain item at order \(order)", category: .chain)
    }

    /// Updates the delay
    func setDelay(_ seconds: Int) {
        guard seconds >= 0 && seconds <= 60 else {
            logWarning("Invalid delay \(seconds)s for chain item, must be 0-60", category: .chain)
            return
        }
        self.delaySeconds = seconds
        logDebug("Set delay to \(seconds)s for chain item at order \(order)", category: .chain)
    }
}

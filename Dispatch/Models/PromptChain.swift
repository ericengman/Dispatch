//
//  PromptChain.swift
//  Dispatch
//
//  Model for sequential prompt chains
//

import Foundation
import SwiftData

@Model
final class PromptChain {
    // MARK: - Properties

    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Relationships

    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \ChainItem.chain)
    var chainItems: [ChainItem] = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project

        logDebug("Created chain: '\(name)'", category: .chain)
    }

    // MARK: - Computed Properties

    /// Returns chain items sorted by order
    var sortedItems: [ChainItem] {
        chainItems.sorted { $0.order < $1.order }
    }

    /// Number of steps in the chain
    var stepCount: Int {
        chainItems.count
    }

    /// Total estimated delay for the entire chain
    var totalDelaySeconds: Int {
        chainItems.reduce(0) { $0 + $1.delaySeconds }
    }

    /// Validates that all chain items have valid content
    var isValid: Bool {
        !chainItems.isEmpty && chainItems.allSatisfy { $0.hasContent }
    }

    // MARK: - Methods

    /// Adds a new item at the end of the chain
    func addItem(prompt: Prompt? = nil, inlineContent: String? = nil, delaySeconds: Int = 0) -> ChainItem {
        let order = (chainItems.map(\.order).max() ?? -1) + 1
        let item = ChainItem(
            prompt: prompt,
            inlineContent: inlineContent,
            order: order,
            delaySeconds: delaySeconds,
            chain: self
        )
        chainItems.append(item)
        updatedAt = Date()
        logDebug("Added item at order \(order) to chain '\(name)'", category: .chain)
        return item
    }

    /// Inserts an item at a specific position
    func insertItem(at index: Int, prompt: Prompt? = nil, inlineContent: String? = nil, delaySeconds: Int = 0) -> ChainItem {
        let item = ChainItem(
            prompt: prompt,
            inlineContent: inlineContent,
            order: index,
            delaySeconds: delaySeconds,
            chain: self
        )

        // Shift existing items
        for existingItem in chainItems where existingItem.order >= index {
            existingItem.order += 1
        }

        chainItems.append(item)
        updatedAt = Date()
        logDebug("Inserted item at index \(index) in chain '\(name)'", category: .chain)
        return item
    }

    /// Removes an item from the chain and reorders remaining items
    func removeItem(_ item: ChainItem) {
        guard let index = chainItems.firstIndex(where: { $0.id == item.id }) else {
            logWarning("Attempted to remove item not in chain '\(name)'", category: .chain)
            return
        }

        let removedOrder = item.order
        chainItems.remove(at: index)

        // Reorder remaining items
        for existingItem in chainItems where existingItem.order > removedOrder {
            existingItem.order -= 1
        }

        updatedAt = Date()
        logDebug("Removed item from chain '\(name)', reordered remaining items", category: .chain)
    }

    /// Moves an item from one position to another
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }

        let sorted = sortedItems
        guard sourceIndex < sorted.count, destinationIndex < sorted.count else {
            logWarning("Invalid move indices in chain '\(name)': \(sourceIndex) -> \(destinationIndex)", category: .chain)
            return
        }

        let item = sorted[sourceIndex]

        if sourceIndex < destinationIndex {
            // Moving down: decrease order of items in between
            for i in (sourceIndex + 1)...destinationIndex {
                sorted[i].order -= 1
            }
        } else {
            // Moving up: increase order of items in between
            for i in destinationIndex..<sourceIndex {
                sorted[i].order += 1
            }
        }

        item.order = destinationIndex
        updatedAt = Date()
        logDebug("Moved item in chain '\(name)' from \(sourceIndex) to \(destinationIndex)", category: .chain)
    }

    /// Creates a duplicate of this chain
    func duplicate() -> PromptChain {
        let copy = PromptChain(
            name: "\(name) (Copy)",
            project: project
        )

        for item in sortedItems {
            _ = copy.addItem(
                prompt: item.prompt,
                inlineContent: item.inlineContent,
                delaySeconds: item.delaySeconds
            )
        }

        logDebug("Duplicated chain '\(name)'", category: .chain)
        return copy
    }
}

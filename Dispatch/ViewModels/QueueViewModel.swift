//
//  QueueViewModel.swift
//  Dispatch
//
//  ViewModel for managing the prompt execution queue
//

import Combine
import Foundation
import SwiftData

// MARK: - Queue ViewModel

@MainActor
final class QueueViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var items: [QueueItem] = []
    @Published var isExecuting: Bool = false
    @Published var isRunningAll: Bool = false
    @Published var currentExecutingItem: QueueItem?
    @Published var error: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var runAllTask: Task<Void, Never>?

    // MARK: - Singleton

    static let shared = QueueViewModel()

    private init() {
        setupExecutionObserver()
    }

    func configure(with context: ModelContext) {
        modelContext = context
        fetchItems()
    }

    // MARK: - Fetch

    func fetchItems() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .queue)
            return
        }

        do {
            var descriptor = FetchDescriptor<QueueItem>()
            descriptor.sortBy = [SortDescriptor(\.order)]

            // Only fetch pending items
            descriptor.predicate = #Predicate<QueueItem> { item in
                item.statusRaw == "pending"
            }

            items = try context.fetch(descriptor)
            logDebug("Fetched \(items.count) queue items", category: .queue)

        } catch {
            self.error = error.localizedDescription
            logError("Failed to fetch queue items: \(error)", category: .queue)
        }
    }

    // MARK: - Queue Management

    /// Adds a prompt to the queue
    func addToQueue(prompt: Prompt, targetWindowId: String? = nil, targetWindowName: String? = nil) {
        guard let context = modelContext else { return }

        let order = (items.map(\.order).max() ?? -1) + 1

        let item = QueueItem.from(
            prompt: prompt,
            order: order,
            targetTerminalId: targetWindowId,
            targetTerminalName: targetWindowName
        )

        context.insert(item)
        saveContext()
        fetchItems()

        logInfo("Added '\(prompt.displayTitle)' to queue at position \(order + 1)", category: .queue)
    }

    /// Adds inline content to the queue
    func addInlineToQueue(content: String, targetWindowId: String? = nil, targetWindowName: String? = nil) {
        guard let context = modelContext else { return }
        guard !content.isEmpty else {
            logWarning("Attempted to add empty content to queue", category: .queue)
            return
        }

        let order = (items.map(\.order).max() ?? -1) + 1

        let item = QueueItem.fromInline(
            content: content,
            order: order,
            targetTerminalId: targetWindowId,
            targetTerminalName: targetWindowName
        )

        context.insert(item)
        saveContext()
        fetchItems()

        logInfo("Added inline prompt to queue at position \(order + 1)", category: .queue)
    }

    /// Removes an item from the queue
    func removeFromQueue(_ item: QueueItem) {
        guard let context = modelContext else { return }
        guard item.canRemove else {
            logWarning("Cannot remove executing item", category: .queue)
            return
        }

        let removedOrder = item.order
        context.delete(item)

        // Reorder remaining items
        for remaining in items where remaining.order > removedOrder {
            remaining.order -= 1
        }

        saveContext()
        fetchItems()

        logInfo("Removed item from queue", category: .queue)
    }

    /// Clears all items from the queue
    func clearQueue() {
        guard let context = modelContext else { return }

        // Cancel any running execution
        runAllTask?.cancel()
        isRunningAll = false

        for item in items where item.canRemove {
            context.delete(item)
        }

        saveContext()
        fetchItems()

        logInfo("Queue cleared", category: .queue)
    }

    /// Moves an item within the queue
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }
        guard sourceIndex < items.count, destinationIndex < items.count else { return }

        let item = items[sourceIndex]

        if sourceIndex < destinationIndex {
            // Moving down
            for i in (sourceIndex + 1) ... destinationIndex {
                items[i].order -= 1
            }
        } else {
            // Moving up
            for i in destinationIndex ..< sourceIndex {
                items[i].order += 1
            }
        }

        item.order = destinationIndex

        saveContext()
        fetchItems()

        logDebug("Moved queue item from \(sourceIndex) to \(destinationIndex)", category: .queue)
    }

    /// Updates the target terminal for an item
    func updateTarget(for item: QueueItem, windowId: String?, windowName: String?) {
        item.setTarget(id: windowId, name: windowName)
        saveContext()
        objectWillChange.send()
    }

    // MARK: - Execution

    /// Executes the next item in the queue
    func runNext() async {
        guard !items.isEmpty else {
            logDebug("Queue is empty", category: .queue)
            return
        }

        guard !isExecuting else {
            logWarning("Already executing", category: .queue)
            return
        }

        guard let nextItem = items.first(where: { $0.isReady }) else {
            logWarning("No ready items in queue", category: .queue)
            return
        }

        await executeItem(nextItem)
    }

    /// Executes all items in the queue sequentially
    func runAll() async {
        guard !items.isEmpty else {
            logDebug("Queue is empty", category: .queue)
            return
        }

        guard !isExecuting else {
            logWarning("Already executing", category: .queue)
            return
        }

        isRunningAll = true
        logInfo("Starting Run All (\(items.count) items)", category: .queue)

        runAllTask = Task {
            while !Task.isCancelled {
                guard let nextItem = items.first(where: { $0.isReady }) else {
                    break
                }

                await executeItem(nextItem)

                // Wait for completion
                while isExecuting && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }

                // Check if paused
                if ExecutionStateMachine.shared.isPaused {
                    logInfo("Run All paused", category: .queue)
                    break
                }
            }

            await MainActor.run {
                self.isRunningAll = false
                logInfo("Run All completed", category: .queue)
            }
        }
    }

    /// Stops the Run All operation
    func stopRunAll() {
        runAllTask?.cancel()
        isRunningAll = false
        ExecutionStateMachine.shared.cancel()
        logInfo("Run All stopped", category: .queue)
    }

    private func executeItem(_ item: QueueItem) async {
        guard let content = item.effectiveContent else {
            logError("Queue item has no content", category: .queue)
            item.markFailed(error: "No content")
            saveContext()
            fetchItems()
            return
        }

        logInfo("Queue executing item: '\(item.displayTitle)' via ExecutionManager", category: .queue)

        isExecuting = true
        currentExecutingItem = item
        item.markExecuting()
        saveContext()

        do {
            // Check for placeholders
            let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

            if !resolveResult.isFullyResolved {
                // Need user input - mark as failed for now
                throw PromptError.unresolvedPlaceholders(resolveResult.unresolvedPlaceholders.map(\.name))
            }

            try await ExecutionManager.shared.execute(
                content: resolveResult.resolvedText,
                title: item.displayTitle
            )

            // Wait for completion signal
            // The ExecutionStateMachine will handle the state transition

        } catch {
            await MainActor.run {
                item.markFailed(error: error.localizedDescription)
                self.error = error.localizedDescription
                self.isExecuting = false
                self.currentExecutingItem = nil
                self.saveContext()
                self.fetchItems()
            }
        }
    }

    // MARK: - Observers

    private func setupExecutionObserver() {
        ExecutionStateMachine.shared.onCompletion { [weak self] result in
            Task { @MainActor in
                guard let self = self, let currentItem = self.currentExecutingItem else { return }

                switch result {
                case .success:
                    currentItem.markCompleted()
                    // Remove from active queue
                    if let context = self.modelContext {
                        context.delete(currentItem)
                    }

                case let .failure(error):
                    currentItem.markFailed(error: error.localizedDescription)
                    self.error = error.localizedDescription

                case .cancelled:
                    currentItem.reset()
                }

                self.saveContext()
                self.isExecuting = false
                self.currentExecutingItem = nil
                self.fetchItems()
            }
        }
    }

    // MARK: - Computed Properties

    var count: Int {
        items.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var hasReadyItems: Bool {
        items.contains { $0.isReady }
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .queue)
        }
    }
}

// MARK: - Queue Convenience Extensions

extension QueueViewModel {
    /// Adds multiple prompts to the queue
    func addPromptsToQueue(_ prompts: [Prompt], targetWindowId: String? = nil, targetWindowName: String? = nil) {
        for prompt in prompts {
            addToQueue(prompt: prompt, targetWindowId: targetWindowId, targetWindowName: targetWindowName)
        }
    }

    /// Creates a history entry for a completed queue item
    func createHistoryEntry(for item: QueueItem, context: ModelContext) {
        if let prompt = item.prompt {
            let history = PromptHistory.from(
                prompt: prompt,
                terminalWindowName: item.targetTerminalName,
                terminalWindowId: item.targetTerminalId
            )
            context.insert(history)
        } else if let content = item.inlineContent {
            let history = PromptHistory.fromInline(
                content: content,
                terminalWindowName: item.targetTerminalName,
                terminalWindowId: item.targetTerminalId
            )
            context.insert(history)
        }
    }
}

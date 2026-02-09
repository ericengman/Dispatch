//
//  ChainViewModel.swift
//  Dispatch
//
//  ViewModel for managing prompt chains
//

import Combine
import Foundation
import SwiftData

// MARK: - Chain Execution State

enum ChainExecutionState: Sendable {
    case idle
    case running(currentStep: Int, totalSteps: Int)
    case paused(atStep: Int, totalSteps: Int)
    case completed
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .running, .paused:
            return true
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case let .running(current, total):
            return "Running \(current + 1)/\(total)"
        case let .paused(current, total):
            return "Paused at \(current + 1)/\(total)"
        case .completed:
            return "Completed"
        case let .failed(error):
            return "Failed: \(error)"
        }
    }
}

// MARK: - Chain ViewModel

@MainActor
final class ChainViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var chains: [PromptChain] = []
    @Published var selectedChain: PromptChain?
    @Published var executionState: ChainExecutionState = .idle
    @Published var currentExecutingChain: PromptChain?
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var executionTask: Task<Void, Never>?
    private var currentStepIndex: Int = 0

    // MARK: - Singleton

    static let shared = ChainViewModel()

    private init() {}

    func configure(with context: ModelContext) {
        modelContext = context
        fetchChains()
    }

    // MARK: - Fetch

    func fetchChains() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .chain)
            return
        }

        isLoading = true

        do {
            var descriptor = FetchDescriptor<PromptChain>()
            descriptor.sortBy = [SortDescriptor(\.name)]

            chains = try context.fetch(descriptor)
            isLoading = false
            logDebug("Fetched \(chains.count) chains", category: .chain)

        } catch {
            self.error = error.localizedDescription
            isLoading = false
            logError("Failed to fetch chains: \(error)", category: .chain)
        }
    }

    // MARK: - CRUD Operations

    /// Creates a new chain
    func createChain(name: String, project: Project? = nil) -> PromptChain? {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .chain)
            return nil
        }

        let chain = PromptChain(name: name, project: project)
        context.insert(chain)

        do {
            try context.save()
            fetchChains()
            logInfo("Created chain: '\(name)'", category: .chain)
            return chain
        } catch {
            self.error = error.localizedDescription
            logError("Failed to create chain: \(error)", category: .chain)
            return nil
        }
    }

    /// Updates a chain
    func updateChain(_ chain: PromptChain, name: String? = nil, project: Project? = nil) {
        if let name = name {
            chain.name = name
        }
        if let project = project {
            chain.project = project
        }
        chain.updatedAt = Date()

        saveContext()
        objectWillChange.send()
        logDebug("Updated chain: '\(chain.name)'", category: .chain)
    }

    /// Deletes a chain
    func deleteChain(_ chain: PromptChain) {
        guard let context = modelContext else { return }

        // Cancel if executing
        if currentExecutingChain?.id == chain.id {
            stopExecution()
        }

        context.delete(chain)

        if selectedChain?.id == chain.id {
            selectedChain = nil
        }

        saveContext()
        fetchChains()

        logInfo("Deleted chain: '\(chain.name)'", category: .chain)
    }

    /// Duplicates a chain
    func duplicateChain(_ chain: PromptChain) -> PromptChain? {
        guard let context = modelContext else { return nil }

        let copy = chain.duplicate()
        context.insert(copy)

        do {
            try context.save()
            fetchChains()
            return copy
        } catch {
            self.error = error.localizedDescription
            logError("Failed to duplicate chain: \(error)", category: .chain)
            return nil
        }
    }

    // MARK: - Chain Item Management

    /// Adds an item to a chain from a library prompt
    func addItem(to chain: PromptChain, prompt: Prompt, delaySeconds: Int = 0) -> ChainItem {
        let item = chain.addItem(prompt: prompt, delaySeconds: delaySeconds)
        saveContext()
        objectWillChange.send()
        return item
    }

    /// Adds an inline item to a chain
    func addInlineItem(to chain: PromptChain, content: String, delaySeconds: Int = 0) -> ChainItem {
        let item = chain.addItem(inlineContent: content, delaySeconds: delaySeconds)
        saveContext()
        objectWillChange.send()
        return item
    }

    /// Removes an item from a chain
    func removeItem(_ item: ChainItem, from chain: PromptChain) {
        chain.removeItem(item)
        saveContext()
        objectWillChange.send()
    }

    /// Moves an item within a chain
    func moveItem(in chain: PromptChain, from sourceIndex: Int, to destinationIndex: Int) {
        chain.moveItem(from: sourceIndex, to: destinationIndex)
        saveContext()
        objectWillChange.send()
    }

    /// Updates an item's delay
    func updateItemDelay(_ item: ChainItem, seconds: Int) {
        item.setDelay(seconds)
        saveContext()
        objectWillChange.send()
    }

    // MARK: - Execution

    /// Starts executing a chain
    func startExecution(of chain: PromptChain) async {
        guard !executionState.isActive else {
            logWarning("Chain already executing", category: .chain)
            return
        }

        guard chain.isValid else {
            error = "Chain has no valid items"
            logError("Cannot execute invalid chain", category: .chain)
            return
        }

        logInfo("Starting chain execution: '\(chain.name)'", category: .chain)

        currentExecutingChain = chain
        currentStepIndex = 0
        executionState = .running(currentStep: 0, totalSteps: chain.stepCount)

        executionTask = Task {
            let items = chain.sortedItems

            for (index, item) in items.enumerated() {
                guard !Task.isCancelled else { break }

                // Check if paused
                while case .paused = executionState {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                guard !Task.isCancelled else { break }

                currentStepIndex = index
                executionState = .running(currentStep: index, totalSteps: items.count)

                do {
                    try await executeItem(item, index: index, totalSteps: items.count)

                    // Wait for delay before next step
                    if item.delaySeconds > 0 && index < items.count - 1 {
                        logInfo("Chain applying \(item.delaySeconds)s delay before next step", category: .chain)
                        try await Task.sleep(nanoseconds: UInt64(item.delaySeconds) * 1_000_000_000)
                    }

                } catch {
                    await MainActor.run {
                        self.executionState = .failed(error: error.localizedDescription)
                        self.error = error.localizedDescription
                        logError("Chain execution failed at step \(index + 1): \(error)", category: .chain)
                    }
                    return
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.executionState = .completed
                    logInfo("Chain execution completed: '\(chain.name)'", category: .chain)
                }
                self.cleanupExecution()
            }
        }
    }

    private func executeItem(_ item: ChainItem, index: Int, totalSteps: Int) async throws {
        guard let content = item.effectiveContent else {
            throw ExecutionError.chainItemInvalid
        }

        logInfo("Chain step \(index + 1)/\(totalSteps) executing via ExecutionManager", category: .chain)

        // Resolve placeholders
        let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

        if !resolveResult.isFullyResolved {
            throw PromptError.unresolvedPlaceholders(resolveResult.unresolvedPlaceholders.map(\.name))
        }

        // Execute through the ExecutionManager
        try await ExecutionManager.shared.execute(
            content: resolveResult.resolvedText,
            title: item.displayTitle,
            isFromChain: true,
            chainName: currentExecutingChain?.name,
            chainStepIndex: index,
            chainTotalSteps: totalSteps
        )

        // Wait for completion
        while ExecutionStateMachine.shared.state == .executing {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        logInfo("Chain step \(index + 1) completed, state: \(ExecutionStateMachine.shared.state)", category: .chain)

        // Check result
        if case let .failure(error) = ExecutionStateMachine.shared.lastResult {
            throw error
        }

        // Record usage for library prompts
        if let prompt = item.prompt {
            await MainActor.run {
                prompt.recordUsage()
                self.saveContext()
            }
        }
    }

    /// Pauses chain execution
    func pauseExecution() {
        guard case let .running(step, total) = executionState else { return }

        executionState = .paused(atStep: step, totalSteps: total)
        ExecutionStateMachine.shared.pause()
        logInfo("Chain execution paused at step \(step + 1)", category: .chain)
    }

    /// Resumes chain execution
    func resumeExecution() {
        guard case let .paused(step, total) = executionState else { return }

        executionState = .running(currentStep: step, totalSteps: total)
        ExecutionStateMachine.shared.resume()
        logInfo("Chain execution resumed at step \(step + 1)", category: .chain)
    }

    /// Stops chain execution
    func stopExecution() {
        executionTask?.cancel()
        ExecutionStateMachine.shared.cancel()
        cleanupExecution()
        logInfo("Chain execution stopped", category: .chain)
    }

    private func cleanupExecution() {
        executionTask = nil
        currentExecutingChain = nil
        currentStepIndex = 0

        // Reset to idle after a delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            await MainActor.run {
                if case .completed = self.executionState {
                    self.executionState = .idle
                } else if case .failed = self.executionState {
                    // Keep failed state for user visibility
                } else {
                    self.executionState = .idle
                }
            }
        }
    }

    // MARK: - Selection

    func selectChain(_ chain: PromptChain?) {
        selectedChain = chain
        if let chain = chain {
            logDebug("Selected chain: '\(chain.name)'", category: .ui)
        }
    }

    // MARK: - Computed Properties

    var count: Int {
        chains.count
    }

    var isEmpty: Bool {
        chains.isEmpty
    }

    /// Chains filtered by project
    func chains(for project: Project?) -> [PromptChain] {
        if let project = project {
            return chains.filter { $0.project?.id == project.id }
        }
        return chains
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .chain)
        }
    }
}

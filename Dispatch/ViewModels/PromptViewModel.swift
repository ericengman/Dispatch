//
//  PromptViewModel.swift
//  Dispatch
//
//  ViewModel for managing prompts
//

import Foundation
import SwiftData
import Combine

// MARK: - Sort Options

enum PromptSortOption: String, CaseIterable, Identifiable, Sendable {
    case recentlyUsed = "Recently Used"
    case recentlyCreated = "Recently Created"
    case alphabetical = "Alphabetical"
    case mostUsed = "Most Used"

    var id: String { rawValue }
}

// MARK: - Filter Options

enum PromptFilterOption: Equatable, Sendable {
    case all
    case starred
    case project(UUID)

    var displayName: String {
        switch self {
        case .all: return "All Prompts"
        case .starred: return "Starred"
        case .project: return "Project"
        }
    }
}

// MARK: - Prompt ViewModel

@MainActor
final class PromptViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var prompts: [Prompt] = []
    @Published var selectedPrompt: Prompt?
    @Published var selectedPromptIds: Set<UUID> = []
    @Published var searchText: String = ""
    @Published var sortOption: PromptSortOption = .recentlyUsed
    @Published var filterOption: PromptFilterOption = .all
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupSearchDebounce()
        logDebug("PromptViewModel initialized", category: .ui)
    }

    func configure(with context: ModelContext) {
        self.modelContext = context
        fetchPrompts()
    }

    // MARK: - Fetch

    func fetchPrompts() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .data)
            return
        }

        isLoading = true

        Task {
            let perf = PerformanceLogger("fetchPrompts", category: .data)
            defer { perf.end() }

            do {
                var descriptor = FetchDescriptor<Prompt>()

                // Apply sorting
                switch sortOption {
                case .recentlyUsed:
                    descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
                case .recentlyCreated:
                    descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
                case .alphabetical:
                    descriptor.sortBy = [SortDescriptor(\.title)]
                case .mostUsed:
                    descriptor.sortBy = [SortDescriptor(\.usageCount, order: .reverse)]
                }

                var results = try context.fetch(descriptor)

                // Apply filters
                results = applyFilters(to: results)

                await MainActor.run {
                    self.prompts = results
                    self.isLoading = false
                    logDebug("Fetched \(results.count) prompts", category: .data)
                }

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    logError("Failed to fetch prompts: \(error)", category: .data)
                }
            }
        }
    }

    private func applyFilters(to prompts: [Prompt]) -> [Prompt] {
        var filtered = prompts

        // Apply filter option
        switch filterOption {
        case .all:
            break
        case .starred:
            filtered = filtered.filter { $0.isStarred }
        case .project(let projectId):
            filtered = filtered.filter { $0.project?.id == projectId }
        }

        // Apply search
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            filtered = filtered.filter { prompt in
                prompt.displayTitle.lowercased().contains(search) ||
                prompt.content.lowercased().contains(search)
            }
        }

        // Sort starred prompts to the top (unless already viewing starred filter)
        if filterOption != .starred {
            filtered = sortStarredFirst(filtered)
        }

        return filtered
    }

    private func sortStarredFirst(_ prompts: [Prompt]) -> [Prompt] {
        let starred = prompts.filter { $0.isStarred }
        let unstarred = prompts.filter { !$0.isStarred }
        return starred + unstarred
    }

    // MARK: - CRUD Operations

    func createPrompt(
        title: String = "",
        content: String = "",
        isStarred: Bool = false,
        project: Project? = nil
    ) -> Prompt? {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .data)
            return nil
        }

        let prompt = Prompt(
            title: title,
            content: content,
            isStarred: isStarred,
            project: project
        )

        context.insert(prompt)

        do {
            try context.save()
            fetchPrompts()
            logInfo("Created prompt: '\(prompt.displayTitle)'", category: .data)
            return prompt
        } catch {
            self.error = error.localizedDescription
            logError("Failed to create prompt: \(error)", category: .data)
            return nil
        }
    }

    func updatePrompt(_ prompt: Prompt, title: String? = nil, content: String? = nil, isStarred: Bool? = nil, project: Project? = nil) {
        if let title = title {
            prompt.updateTitle(title)
        }
        if let content = content {
            prompt.updateContent(content)
        }
        if let isStarred = isStarred {
            prompt.isStarred = isStarred
            prompt.updatedAt = Date()
        }
        if let project = project {
            prompt.project = project
            prompt.updatedAt = Date()
        }

        saveContext()
        objectWillChange.send()
        logDebug("Updated prompt: '\(prompt.displayTitle)'", category: .data)
    }

    func deletePrompt(_ prompt: Prompt) {
        guard let context = modelContext else { return }

        context.delete(prompt)
        saveContext()

        if selectedPrompt?.id == prompt.id {
            selectedPrompt = nil
        }
        selectedPromptIds.remove(prompt.id)

        fetchPrompts()
        logInfo("Deleted prompt: '\(prompt.displayTitle)'", category: .data)
    }

    func deletePrompts(_ prompts: [Prompt]) {
        guard let context = modelContext else { return }

        for prompt in prompts {
            context.delete(prompt)
            selectedPromptIds.remove(prompt.id)
        }

        saveContext()
        selectedPrompt = nil
        fetchPrompts()
        logInfo("Deleted \(prompts.count) prompts", category: .data)
    }

    func duplicatePrompt(_ prompt: Prompt) -> Prompt? {
        guard let context = modelContext else { return nil }

        let copy = prompt.duplicate()
        context.insert(copy)

        do {
            try context.save()
            fetchPrompts()
            return copy
        } catch {
            self.error = error.localizedDescription
            logError("Failed to duplicate prompt: \(error)", category: .data)
            return nil
        }
    }

    // MARK: - Selection

    func selectPrompt(_ prompt: Prompt?) {
        selectedPrompt = prompt
        if let prompt = prompt {
            logDebug("Selected prompt: '\(prompt.displayTitle)'", category: .ui)
        }
    }

    func toggleSelection(_ prompt: Prompt) {
        if selectedPromptIds.contains(prompt.id) {
            selectedPromptIds.remove(prompt.id)
        } else {
            selectedPromptIds.insert(prompt.id)
        }
    }

    func selectAll() {
        selectedPromptIds = Set(prompts.map(\.id))
    }

    func clearSelection() {
        selectedPromptIds.removeAll()
    }

    var selectedPrompts: [Prompt] {
        prompts.filter { selectedPromptIds.contains($0.id) }
    }

    // MARK: - Actions

    func toggleStarred(_ prompt: Prompt) {
        prompt.toggleStarred()
        saveContext()
        objectWillChange.send()
    }

    func moveToProject(_ prompts: [Prompt], project: Project?) {
        for prompt in prompts {
            prompt.project = project
            prompt.updatedAt = Date()
        }
        saveContext()
        fetchPrompts()
        logInfo("Moved \(prompts.count) prompts to project: \(project?.name ?? "None")", category: .data)
    }

    // MARK: - Sending

    func sendPrompt(_ prompt: Prompt, toWindowId windowId: String? = nil) async throws {
        logInfo("Sending prompt: '\(prompt.displayTitle)'", category: .execution)

        // Resolve placeholders if needed
        var content = prompt.content

        if prompt.hasPlaceholders {
            let result = await PlaceholderResolver.shared.autoResolve(text: content)
            if !result.isFullyResolved {
                // Need user input for remaining placeholders
                logDebug("Prompt has unresolved placeholders", category: .placeholder)
                throw PromptError.unresolvedPlaceholders(result.unresolvedPlaceholders.map(\.name))
            }
            content = result.resolvedText
        }

        // Execute
        try await ExecutionManager.shared.execute(
            content: content,
            title: prompt.displayTitle,
            targetWindowId: windowId
        )

        // Record usage
        prompt.recordUsage()
        saveContext()

        // Create history entry
        createHistoryEntry(for: prompt, windowId: windowId)
    }

    private func createHistoryEntry(for prompt: Prompt, windowId: String?, windowName: String? = nil) {
        guard let context = modelContext else { return }

        let history = PromptHistory.from(
            prompt: prompt,
            terminalWindowName: windowName,
            terminalWindowId: windowId
        )

        context.insert(history)
        saveContext()
        logDebug("Created history entry for prompt", category: .history)
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .data)
        }
    }

    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.fetchPrompts()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Prompt Errors

enum PromptError: Error, LocalizedError {
    case unresolvedPlaceholders([String])
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .unresolvedPlaceholders(let names):
            return "Unresolved placeholders: \(names.joined(separator: ", "))"
        case .emptyContent:
            return "Prompt content is empty"
        }
    }
}

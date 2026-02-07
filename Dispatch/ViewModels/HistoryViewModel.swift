//
//  HistoryViewModel.swift
//  Dispatch
//
//  ViewModel for managing prompt history
//

import Foundation
import SwiftData
import Combine

// MARK: - History ViewModel

@MainActor
final class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var entries: [PromptHistory] = []
    @Published var selectedEntry: PromptHistory?
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var retentionDays: Int = 30

    // MARK: - Singleton

    static let shared = HistoryViewModel()

    private init() {
        setupSearchDebounce()
    }

    func configure(with context: ModelContext, retentionDays: Int = 30) {
        self.modelContext = context
        self.retentionDays = retentionDays
        fetchEntries()
        cleanupOldEntries()
    }

    // MARK: - Fetch

    func fetchEntries() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .history)
            return
        }

        isLoading = true

        Task {
            do {
                var descriptor = FetchDescriptor<PromptHistory>()
                descriptor.sortBy = [SortDescriptor(\.sentAt, order: .reverse)]

                var results = try context.fetch(descriptor)

                // Apply search filter
                if !searchText.isEmpty {
                    let search = searchText.lowercased()
                    results = results.filter { entry in
                        entry.content.lowercased().contains(search) ||
                        (entry.originalPromptTitle?.lowercased().contains(search) ?? false) ||
                        (entry.chainName?.lowercased().contains(search) ?? false) ||
                        (entry.projectName?.lowercased().contains(search) ?? false)
                    }
                }

                await MainActor.run {
                    self.entries = results
                    self.isLoading = false
                }

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    logError("Failed to fetch history: \(error)", category: .history)
                }
            }
        }
    }

    // MARK: - Actions

    /// Copies entry content to clipboard
    func copyToClipboard(_ entry: PromptHistory) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
        logDebug("Copied history entry to clipboard", category: .history)
    }

    /// Saves history entry as a new prompt in the library
    func saveToLibrary(_ entry: PromptHistory, context: ModelContext) -> Prompt {
        let prompt = Prompt(
            title: entry.originalPromptTitle ?? "",
            content: entry.content
        )

        context.insert(prompt)

        do {
            try context.save()
            logInfo("Saved history entry to library", category: .history)
        } catch {
            logError("Failed to save to library: \(error)", category: .history)
        }

        return prompt
    }

    /// Resends a history entry
    func resend(_ entry: PromptHistory) async throws {
        logInfo("Resending history entry", category: .history)

        try await ExecutionManager.shared.execute(
            content: entry.content,
            title: entry.displayTitle,
            targetWindowId: entry.terminalWindowId,
            targetWindowName: entry.terminalWindowName
        )

        // Create new history entry
        addEntry(from: entry)
    }

    /// Adds entry to queue
    func addToQueue(_ entry: PromptHistory) {
        QueueViewModel.shared.addInlineToQueue(
            content: entry.content,
            targetWindowId: entry.terminalWindowId,
            targetWindowName: entry.terminalWindowName
        )
        logInfo("Added history entry to queue", category: .history)
    }

    /// Deletes a history entry
    func deleteEntry(_ entry: PromptHistory) {
        guard let context = modelContext else { return }

        context.delete(entry)
        saveContext()

        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }

        fetchEntries()
        logDebug("Deleted history entry", category: .history)
    }

    /// Clears all history
    func clearAllHistory() {
        guard let context = modelContext else { return }

        for entry in entries {
            context.delete(entry)
        }

        saveContext()
        selectedEntry = nil
        fetchEntries()

        logInfo("Cleared all history", category: .history)
    }

    // MARK: - History Creation

    /// Adds a new history entry
    func addEntry(
        content: String,
        projectName: String? = nil,
        terminalWindowName: String? = nil,
        terminalWindowId: String? = nil,
        wasFromChain: Bool = false,
        chainName: String? = nil,
        originalPromptId: UUID? = nil,
        originalPromptTitle: String? = nil
    ) {
        guard let context = modelContext else { return }

        let entry = PromptHistory(
            content: content,
            projectName: projectName,
            terminalWindowName: terminalWindowName,
            terminalWindowId: terminalWindowId,
            wasFromChain: wasFromChain,
            chainName: chainName,
            originalPromptId: originalPromptId,
            originalPromptTitle: originalPromptTitle
        )

        context.insert(entry)
        saveContext()
        fetchEntries()

        logDebug("Added history entry", category: .history)
    }

    /// Adds a history entry from an existing entry (for resend)
    func addEntry(from existing: PromptHistory) {
        addEntry(
            content: existing.content,
            projectName: existing.projectName,
            terminalWindowName: existing.terminalWindowName,
            terminalWindowId: existing.terminalWindowId,
            wasFromChain: existing.wasFromChain,
            chainName: existing.chainName,
            originalPromptId: existing.originalPromptId,
            originalPromptTitle: existing.originalPromptTitle
        )
    }

    // MARK: - Cleanup

    /// Removes entries older than retention period
    func cleanupOldEntries() {
        guard let context = modelContext else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        do {
            let descriptor = FetchDescriptor<PromptHistory>(
                predicate: #Predicate<PromptHistory> { entry in
                    entry.sentAt < cutoffDate
                }
            )

            let oldEntries = try context.fetch(descriptor)

            if !oldEntries.isEmpty {
                for entry in oldEntries {
                    context.delete(entry)
                }
                saveContext()
                logInfo("Cleaned up \(oldEntries.count) old history entries", category: .history)
            }

        } catch {
            logError("Failed to cleanup old history: \(error)", category: .history)
        }
    }

    /// Updates retention period and cleans up
    func setRetentionDays(_ days: Int) {
        retentionDays = days
        cleanupOldEntries()
        logDebug("History retention set to \(days) days", category: .history)
    }

    // MARK: - Computed Properties

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Groups entries by date for section display
    var entriesByDate: [(date: Date, entries: [PromptHistory])] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.sentAt)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, entries: $0.value) }
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .history)
        }
    }

    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.fetchEntries()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Import NSPasteboard

import AppKit

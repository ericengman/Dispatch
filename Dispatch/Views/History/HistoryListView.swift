//
//  HistoryListView.swift
//  Dispatch
//
//  View for displaying prompt history
//

import SwiftData
import SwiftUI

struct HistoryListView: View {
    // MARK: - Environment

    @EnvironmentObject private var historyVM: HistoryViewModel

    // MARK: - State

    @State private var selectedEntry: PromptHistory?
    @State private var showingClearConfirmation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBarView(text: $historyVM.searchText)
                .padding()

            Divider()

            // History list
            if historyVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if historyVM.isEmpty {
                emptyStateView
            } else {
                historyList
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(historyVM.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                historyVM.clearAllHistory()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List(selection: $selectedEntry) {
            ForEach(historyVM.entriesByDate, id: \.date) { section in
                Section(header: Text(formatSectionDate(section.date))) {
                    ForEach(section.entries) { entry in
                        HistoryRowView(entry: entry)
                            .tag(entry)
                            .contextMenu {
                                historyContextMenu(for: entry)
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No History", systemImage: "clock")
        } description: {
            Text("Prompts you send will appear here.")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func historyContextMenu(for entry: PromptHistory) -> some View {
        Button {
            Task {
                try? await historyVM.resend(entry)
            }
        } label: {
            Label("Resend", systemImage: "paperplane")
        }

        Button {
            historyVM.copyToClipboard(entry)
        } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
        }

        Button {
            // TODO: Save to library with sheet for title
            if let context = try? ModelContainer(for: Prompt.self).mainContext {
                _ = historyVM.saveToLibrary(entry, context: context)
            }
        } label: {
            Label("Save to Library", systemImage: "square.and.arrow.down")
        }

        Divider()

        Button(role: .destructive) {
            historyVM.deleteEntry(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    let entry: PromptHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text(entry.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Source indicator
                if entry.wasFromChain {
                    Label(entry.chainName ?? "Chain", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let projectName = entry.projectName {
                    Text(projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Text(entry.relativeSentTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Preview
            Text(entry.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Target info
            HStack(spacing: 8) {
                Label(entry.targetDescription, systemImage: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    HistoryListView()
        .environmentObject(HistoryViewModel.shared)
}

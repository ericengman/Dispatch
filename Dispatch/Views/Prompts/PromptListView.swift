//
//  PromptListView.swift
//  Dispatch
//
//  List view for displaying and managing prompts with inline editing
//

import SwiftData
import SwiftUI

struct PromptListView: View {
    // MARK: - Environment

    @EnvironmentObject private var promptVM: PromptViewModel
    @EnvironmentObject private var queueVM: QueueViewModel

    // MARK: - Properties

    let filter: PromptFilterOption

    // MARK: - State

    @State private var showingDeleteConfirmation = false

    // MARK: - Computed Properties

    /// The currently selected project based on sidebar filter
    private var currentProject: Project? {
        if case let .project(projectId) = filter {
            return ProjectViewModel.shared.projects.first { $0.id == projectId }
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Left side - Prompt list
            VStack(spacing: 0) {
                // Search bar
                SearchBarView(text: $promptVM.searchText)
                    .padding()

                // Toolbar
                promptToolbar

                Divider()

                // Prompt list
                if promptVM.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if promptVM.prompts.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: Binding(
                        get: { promptVM.selectedPrompt?.id },
                        set: { id in
                            if let id = id {
                                promptVM.selectPrompt(promptVM.prompts.first { $0.id == id })
                            } else {
                                promptVM.selectPrompt(nil)
                            }
                        }
                    )) {
                        ForEach(promptVM.prompts) { prompt in
                            PromptRowView(prompt: prompt) { p in
                                promptVM.toggleStarred(p)
                            }
                            .tag(prompt.id)
                            .contextMenu {
                                promptContextMenu(for: prompt)
                            }
                        }
                        .onDelete { indexSet in
                            deletePrompts(at: indexSet)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

            // Right side - Inline editor
            if let prompt = promptVM.selectedPrompt {
                PromptEditorPane(prompt: prompt, selectedProject: currentProject)
                    .environmentObject(promptVM)
                    .environmentObject(queueVM)
            } else {
                // Empty state when no prompt selected
                ContentUnavailableView(
                    "Select a Prompt",
                    systemImage: "doc.text",
                    description: Text("Choose a prompt from the list to edit, or create a new one with ⌘N")
                )
            }
        }
        .navigationTitle(navigationTitle)
        .confirmationDialog(
            "Delete \(promptVM.selectedPromptIds.count) prompt(s)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedPrompts()
            }
        }
        .onAppear {
            promptVM.filterOption = filter
            promptVM.fetchPrompts()
        }
        .onChange(of: filter) { _, newFilter in
            promptVM.filterOption = newFilter
            promptVM.fetchPrompts()
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        switch filter {
        case .all:
            return "All Prompts"
        case .starred:
            return "Starred"
        case .project:
            return "Project"
        }
    }

    // MARK: - Toolbar

    private var promptToolbar: some View {
        HStack {
            // New prompt button
            Button {
                createNewPrompt()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Prompt")

            // Sort picker
            Menu {
                ForEach(PromptSortOption.allCases) { option in
                    Button {
                        promptVM.sortOption = option
                        promptVM.fetchPrompts()
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if promptVM.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Count
            Text("\(promptVM.prompts.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Prompts", systemImage: "doc.text")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            Button {
                createNewPrompt()
            } label: {
                Text("Create Prompt")
            }
        }
    }

    private var emptyStateDescription: String {
        if !promptVM.searchText.isEmpty {
            return "No prompts match your search."
        }
        switch filter {
        case .starred:
            return "Star prompts to see them here."
        case .project:
            return "No prompts in this project."
        case .all:
            return "Create your first prompt to get started."
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func promptContextMenu(for prompt: Prompt) -> some View {
        Button {
            Task {
                try? await promptVM.sendPrompt(prompt)
            }
        } label: {
            Label("Send", systemImage: "paperplane")
        }

        Button {
            queueVM.addToQueue(prompt: prompt)
        } label: {
            Label("Add to Queue", systemImage: "plus.circle")
        }

        Divider()

        Button {
            _ = promptVM.duplicatePrompt(prompt)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            promptVM.toggleStarred(prompt)
        } label: {
            Label(prompt.isStarred ? "Unstar" : "Star", systemImage: prompt.isStarred ? "star.slash" : "star")
        }

        Divider()

        Button {
            copyToClipboard(prompt)
        } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            promptVM.deletePrompt(prompt)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func createNewPrompt() {
        if let prompt = promptVM.createPrompt(project: currentProject) {
            promptVM.selectPrompt(prompt)
        }
    }

    private func deletePrompts(at indexSet: IndexSet) {
        for index in indexSet {
            let prompt = promptVM.prompts[index]
            promptVM.deletePrompt(prompt)
        }
    }

    private func deleteSelectedPrompts() {
        promptVM.deletePrompts(promptVM.selectedPrompts)
    }

    private func copyToClipboard(_ prompt: Prompt) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.content, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    PromptListView(filter: .all)
        .environmentObject(PromptViewModel())
        .environmentObject(QueueViewModel.shared)
}

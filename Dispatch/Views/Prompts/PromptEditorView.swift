//
//  PromptEditorView.swift
//  Dispatch
//
//  Inline editor pane for creating and editing prompts
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Prompt Editor Pane

struct PromptEditorPane: View {
    // MARK: - Environment

    @EnvironmentObject private var promptVM: PromptViewModel
    @EnvironmentObject private var queueVM: QueueViewModel

    // MARK: - Properties

    @Bindable var prompt: Prompt

    // MARK: - State

    @State private var showingPlaceholderMenu = false
    @FocusState private var isContentFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and star
            headerView

            Divider()

            // Content editor
            contentEditor

            Divider()

            // Options bar
            optionsBar

            Divider()

            // Action bar
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // Title field
            TextField("Title (auto-generated if empty)", text: $prompt.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .onSubmit {
                    isContentFocused = true
                }

            Spacer()

            // Star button on the right
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    prompt.toggleStarred()
                    promptVM.objectWillChange.send()
                }
            } label: {
                Image(systemName: prompt.isStarred ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(prompt.isStarred ? .yellow : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(prompt.isStarred ? "Remove from Starred" : "Add to Starred")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Content Editor

    private var contentEditor: some View {
        TextEditor(text: $prompt.content)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($isContentFocused)
            .overlay(alignment: .topLeading) {
                // Placeholder text
                if prompt.content.isEmpty {
                    Text("Enter your prompt here...\n\nUse {{placeholder}} syntax for dynamic values.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: prompt.content) { _, _ in
                prompt.updatedAt = Date()
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            // Project picker
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                Picker("", selection: $prompt.project) {
                    Text("No Project").tag(nil as Project?)
                    ForEach(ProjectViewModel.shared.projects) { project in
                        HStack {
                            Circle()
                                .fill(project.color)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                        }
                        .tag(project as Project?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Divider()
                .frame(height: 16)

            // Insert placeholder button
            Menu {
                ForEach(BuiltInPlaceholder.allCases, id: \.rawValue) { placeholder in
                    Button {
                        insertPlaceholder(placeholder)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("{{\(placeholder.name)}}")
                                .font(.system(.body, design: .monospaced))
                            Text(placeholder.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Label("Insert Placeholder", systemImage: "curlybraces")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Placeholder count indicator
            if PlaceholderPattern.hasPlaceholders(in: prompt.content) {
                let count = PlaceholderPattern.extractPlaceholders(from: prompt.content).count
                Label("\(count) placeholder\(count == 1 ? "" : "s")", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Character count
            Text("\(prompt.content.count) chars")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Delete button
            Button(role: .destructive) {
                promptVM.deletePrompt(prompt)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderless)

            // Duplicate button
            Button {
                if let newPrompt = promptVM.duplicatePrompt(prompt) {
                    promptVM.selectPrompt(newPrompt)
                }
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)

            Spacer()

            // Add to queue button
            Button {
                queueVM.addToQueue(prompt: prompt)
            } label: {
                Label("Add to Queue", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Send button
            Button {
                Task {
                    try? await promptVM.sendPrompt(prompt)
                }
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(prompt.content.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private func insertPlaceholder(_ placeholder: BuiltInPlaceholder) {
        prompt.content += "{{\(placeholder.name)}}"
        prompt.updatedAt = Date()
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Prompt.self, configurations: config)
    let prompt = Prompt(title: "Test Prompt", content: "Hello {{name}}")
    container.mainContext.insert(prompt)

    return PromptEditorPane(prompt: prompt)
        .environmentObject(PromptViewModel())
        .environmentObject(QueueViewModel.shared)
        .frame(width: 500, height: 400)
}

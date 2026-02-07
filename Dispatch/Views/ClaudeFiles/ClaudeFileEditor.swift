//
//  ClaudeFileEditor.swift
//  Dispatch
//
//  Editor view for CLAUDE.md files with editing capabilities
//

import SwiftUI
import UniformTypeIdentifiers

struct ClaudeFileEditor: View {
    // MARK: - Properties

    let file: ClaudeFile
    let onDismiss: () -> Void

    // MARK: - State

    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var showingDiscardAlert = false
    @State private var saveError: String?
    @State private var undoManager: UndoManager? = UndoManager()

    @FocusState private var isEditorFocused: Bool

    // MARK: - Computed Properties

    private var hasChanges: Bool {
        content != originalContent
    }

    private var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }

    private var wordCount: Int {
        content.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with toolbar
            headerView

            Divider()

            // Editor
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorView
            }

            Divider()

            // Footer with stats and actions
            footerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            loadContent()
        }
        .onChange(of: content) { _, newValue in
            hasUnsavedChanges = newValue != originalContent
        }
        .alert("Unsaved Changes", isPresented: $showingDiscardAlert) {
            Button("Discard", role: .destructive) {
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .alert("Save Error", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // File info
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(file.displayName)
                        .font(.headline)

                    // Unsaved indicator
                    if hasChanges {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .help("Unsaved changes")
                    }
                }

                Text(file.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Toolbar buttons
            toolbarButtons
        }
        .padding()
        .background(.bar)
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            // Undo
            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!(undoManager?.canUndo ?? false))
            .help("Undo")

            // Redo
            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!(undoManager?.canRedo ?? false))
            .help("Redo")

            Divider()
                .frame(height: 16)

            // Revert
            Button {
                content = originalContent
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasChanges)
            .help("Revert to saved")

            Divider()
                .frame(height: 16)

            // Open externally
            Button {
                file.openInEditor()
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open in external editor")

            Divider()
                .frame(height: 16)

            // Save
            Button {
                saveContent()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasChanges || isSaving)
            .keyboardShortcut("s", modifiers: .command)

            // Close
            Button {
                if hasChanges {
                    showingDiscardAlert = true
                } else {
                    onDismiss()
                }
            } label: {
                Label("Close", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Editor

    private var editorView: some View {
        TextEditor(text: $content)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .overlay(alignment: .topLeading) {
                // Placeholder for new files
                if content.isEmpty && !file.exists {
                    Text("# CLAUDE.md\n\nAdd your project-specific instructions here...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 16) {
            // File stats
            HStack(spacing: 12) {
                Label("\(lineCount) lines", systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(wordCount) words", systemImage: "textformat.abc")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(content.count) chars", systemImage: "character.cursor.ibeam")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status
            if isSaving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if hasChanges {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("No changes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Save & Close button
            Button {
                saveAndClose()
            } label: {
                Label("Save & Close", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasChanges || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadContent() {
        Task {
            if let existingContent = file.readContent() {
                await MainActor.run {
                    content = existingContent
                    originalContent = existingContent
                    isLoading = false
                    isEditorFocused = true
                }
            } else {
                // File doesn't exist - start with empty content
                await MainActor.run {
                    content = ""
                    originalContent = ""
                    isLoading = false
                    isEditorFocused = true
                }
            }
        }
    }

    private func saveContent() {
        isSaving = true

        Task {
            do {
                try file.writeContent(content)
                await MainActor.run {
                    originalContent = content
                    hasUnsavedChanges = false
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func saveAndClose() {
        isSaving = true

        Task {
            do {
                try file.writeContent(content)
                await MainActor.run {
                    originalContent = content
                    hasUnsavedChanges = false
                    isSaving = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ClaudeFileEditor(
        file: ClaudeFile(
            scope: .system,
            filePath: URL(fileURLWithPath: "/tmp/CLAUDE.md")
        ),
        onDismiss: {}
    )
    .frame(width: 700, height: 500)
}

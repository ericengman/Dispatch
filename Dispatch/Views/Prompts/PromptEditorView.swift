//
//  PromptEditorView.swift
//  Dispatch
//
//  Inline editor pane for creating and editing prompts
//

import Combine
import SwiftData
import SwiftUI

// MARK: - Prompt Editor Pane

struct PromptEditorPane: View {
    // MARK: - Environment

    @EnvironmentObject private var promptVM: PromptViewModel
    @EnvironmentObject private var queueVM: QueueViewModel

    // MARK: - Properties

    @Bindable var prompt: Prompt
    var selectedProject: Project?

    // MARK: - State

    @State private var showingPlaceholderMenu = false
    @State private var matchingTerminals: [TerminalWindow] = []
    @State private var isLoadingTerminals = false
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
        .onAppear {
            loadMatchingTerminals()
        }
        .onChange(of: prompt.project) { _, _ in
            loadMatchingTerminals()
        }
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
        PlaceholderTextEditor(
            text: $prompt.content,
            placeholder: "Enter your prompt here...\n\nUse {{placeholder}} syntax for dynamic values."
        )
        .focused($isContentFocused)
        .onChange(of: prompt.content) { _, _ in
            prompt.updatedAt = Date()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            // Project indicator (read-only, based on sidebar selection)
            if let project = prompt.project {
                HStack(spacing: 6) {
                    Circle()
                        .fill(project.color)
                        .frame(width: 8, height: 8)
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 16)
            }

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

            // Send button - shows dropdown when multiple terminals match
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var sendButton: some View {
        DispatchButton(
            terminals: matchingTerminals,
            isDisabled: prompt.content.isEmpty,
            onDispatch: { terminal in
                if let terminal = terminal {
                    sendToTerminal(terminal)
                } else {
                    sendToNewTerminal()
                }
            },
            onNewSession: {
                sendToNewTerminal()
            }
        )
    }

    // MARK: - Actions

    private func insertPlaceholder(_ placeholder: BuiltInPlaceholder) {
        prompt.content += "{{\(placeholder.name)}}"
        prompt.updatedAt = Date()
    }

    private func loadMatchingTerminals() {
        guard let projectName = prompt.project?.name ?? selectedProject?.name else {
            matchingTerminals = []
            return
        }

        isLoadingTerminals = true
        Task {
            do {
                let terminals = try await TerminalService.shared.findTerminalsForProject(named: projectName)
                await MainActor.run {
                    matchingTerminals = terminals
                    isLoadingTerminals = false
                }
            } catch {
                await MainActor.run {
                    matchingTerminals = []
                    isLoadingTerminals = false
                }
            }
        }
    }

    private func sendToTerminal(_: TerminalWindow) {
        Task {
            do {
                // Resolve placeholders first
                var content = prompt.content
                if prompt.hasPlaceholders {
                    let result = await PlaceholderResolver.shared.autoResolve(text: content)
                    content = result.resolvedText
                }

                // Use typeText which will activate Terminal and paste
                // This is needed for clipboard paste to work
                try await TerminalService.shared.typeText(content, pressEnter: true)

                // Record usage
                prompt.recordUsage()

                // Auto-open a new prompt for the next entry
                await MainActor.run {
                    if let newPrompt = promptVM.createPrompt(project: selectedProject) {
                        promptVM.selectPrompt(newPrompt)
                    }
                }
            } catch {
                // Handle error silently for now
            }
        }
    }

    private func sendToNewTerminal() {
        Task {
            do {
                let projectPath = prompt.project?.path ?? selectedProject?.path
                let workingDir = projectPath ?? FileManager.default.homeDirectoryForCurrentUser.path

                // Open new terminal at project path
                _ = try await TerminalService.shared.openNewWindow(at: workingDir)

                // Wait for terminal to initialize
                try await Task.sleep(nanoseconds: 500_000_000)

                // Start Claude Code using typeText (sendPrompt would create a new tab)
                try await TerminalService.shared.typeText("claude --dangerously-skip-permissions", pressEnter: true)

                // Wait for Claude to start up
                try await Task.sleep(nanoseconds: 2_000_000_000)

                // Resolve placeholders
                var content = prompt.content
                if prompt.hasPlaceholders {
                    let result = await PlaceholderResolver.shared.autoResolve(text: content)
                    content = result.resolvedText
                }

                // Type the content
                try await TerminalService.shared.typeText(content, pressEnter: true)

                // Record usage
                prompt.recordUsage()

                // Reload terminals
                loadMatchingTerminals()

                // Auto-open a new prompt for the next entry
                await MainActor.run {
                    if let newPrompt = promptVM.createPrompt(project: selectedProject) {
                        promptVM.selectPrompt(newPrompt)
                    }
                }
            } catch {
                // Handle error silently for now
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Prompt.self, configurations: config)
    let prompt = Prompt(title: "Test Prompt", content: "Hello {{name}}")
    container.mainContext.insert(prompt)

    return PromptEditorPane(prompt: prompt, selectedProject: nil)
        .environmentObject(PromptViewModel())
        .environmentObject(QueueViewModel.shared)
        .frame(width: 500, height: 400)
}

// MARK: - Placeholder Text Editor

/// A TextEditor wrapper that properly displays placeholder text aligned with the cursor
struct PlaceholderTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Store placeholder for later use
        context.coordinator.placeholder = placeholder
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text changed externally
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        context.coordinator.updatePlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var placeholder: String = ""
        weak var textView: NSTextView?
        private var placeholderView: NSTextField?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updatePlaceholder()
        }

        func updatePlaceholder() {
            guard let textView = textView else { return }

            if text.isEmpty {
                if placeholderView == nil {
                    let label = NSTextField(labelWithString: placeholder)
                    label.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                    label.textColor = .tertiaryLabelColor
                    label.backgroundColor = .clear
                    label.isBezeled = false
                    label.isEditable = false
                    label.isSelectable = false
                    label.lineBreakMode = .byWordWrapping
                    label.maximumNumberOfLines = 0

                    // Position at the text container origin
                    let containerOrigin = textView.textContainerOrigin
                    let inset = textView.textContainerInset
                    label.frame.origin = NSPoint(
                        x: containerOrigin.x + inset.width,
                        y: containerOrigin.y + inset.height
                    )
                    label.sizeToFit()

                    textView.addSubview(label)
                    placeholderView = label
                }
                placeholderView?.isHidden = false
            } else {
                placeholderView?.isHidden = true
            }
        }
    }
}

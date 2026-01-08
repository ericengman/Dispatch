//
//  ChainEditorView.swift
//  Dispatch
//
//  Editor view for creating and editing prompt chains
//

import SwiftUI

struct ChainEditorView: View {
    // MARK: - Environment

    @EnvironmentObject private var chainVM: ChainViewModel
    @EnvironmentObject private var promptVM: PromptViewModel

    // MARK: - Properties

    let chain: PromptChain

    // MARK: - State

    @State private var showingAddPromptSheet = false
    @State private var showingAddInlineSheet = false
    @State private var inlineContent = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Chain info header
            chainHeader

            Divider()

            // Chain items
            if chain.chainItems.isEmpty {
                emptyStateView
            } else {
                chainItemsList
            }

            Divider()

            // Execution controls
            executionControls
        }
        .navigationTitle(chain.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddPromptSheet = true
                    } label: {
                        Label("Add from Library", systemImage: "doc.text")
                    }

                    Button {
                        showingAddInlineSheet = true
                    } label: {
                        Label("Add Inline Prompt", systemImage: "text.cursor")
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPromptSheet) {
            promptPickerSheet
        }
        .sheet(isPresented: $showingAddInlineSheet) {
            inlinePromptSheet
        }
    }

    // MARK: - Chain Header

    private var chainHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chain.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label("\(chain.stepCount) steps", systemImage: "list.number")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if chain.totalDelaySeconds > 0 {
                        Label("\(chain.totalDelaySeconds)s total delay", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let project = chain.project {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(project.color)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Chain Items List

    private var chainItemsList: some View {
        List {
            ForEach(chain.sortedItems) { item in
                ChainItemRowView(item: item, chain: chain)
            }
            .onMove { source, destination in
                if let from = source.first {
                    chainVM.moveItem(in: chain, from: from, to: destination)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let item = chain.sortedItems[index]
                    chainVM.removeItem(item, from: chain)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Steps", systemImage: "link")
        } description: {
            Text("Add prompts to create a chain sequence.")
        } actions: {
            HStack(spacing: 12) {
                Button {
                    showingAddPromptSheet = true
                } label: {
                    Label("From Library", systemImage: "doc.text")
                }

                Button {
                    showingAddInlineSheet = true
                } label: {
                    Label("Inline", systemImage: "text.cursor")
                }
            }
        }
    }

    // MARK: - Execution Controls

    private var executionControls: some View {
        HStack {
            // Status
            if chainVM.executionState.isActive {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)

                    Text(chainVM.executionState.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Control buttons
            if chainVM.currentExecutingChain?.id == chain.id {
                switch chainVM.executionState {
                case .running:
                    Button {
                        chainVM.pauseExecution()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }

                    Button(role: .destructive) {
                        chainVM.stopExecution()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }

                case .paused:
                    Button {
                        chainVM.resumeExecution()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        chainVM.stopExecution()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }

                default:
                    EmptyView()
                }
            } else {
                Button {
                    Task {
                        await chainVM.startExecution(of: chain)
                    }
                } label: {
                    Label("Run Chain", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!chain.isValid || chainVM.executionState.isActive)
            }
        }
        .padding()
    }

    // MARK: - Prompt Picker Sheet

    private var promptPickerSheet: some View {
        NavigationStack {
            List(promptVM.prompts) { prompt in
                Button {
                    _ = chainVM.addItem(to: chain, prompt: prompt)
                    showingAddPromptSheet = false
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(prompt.displayTitle)
                                .font(.body)

                            Text(prompt.previewText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let project = prompt.project {
                            Circle()
                                .fill(project.color)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddPromptSheet = false
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Inline Prompt Sheet

    private var inlinePromptSheet: some View {
        NavigationStack {
            Form {
                Section("Prompt Content") {
                    TextEditor(text: $inlineContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Inline Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddInlineSheet = false
                        inlineContent = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !inlineContent.isEmpty {
                            _ = chainVM.addInlineItem(to: chain, content: inlineContent)
                            showingAddInlineSheet = false
                            inlineContent = ""
                        }
                    }
                    .disabled(inlineContent.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Chain Item Row View

struct ChainItemRowView: View {
    @EnvironmentObject private var chainVM: ChainViewModel

    let item: ChainItem
    let chain: PromptChain

    @State private var delay: Int

    init(item: ChainItem, chain: PromptChain) {
        self.item = item
        self.chain = chain
        _delay = State(initialValue: item.delaySeconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Step number
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 24, height: 24)

                Text("\(item.order + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if item.hasPlaceholders {
                        Label("Has placeholders", systemImage: "curlybraces")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Delay picker
            HStack(spacing: 4) {
                Stepper(value: $delay, in: 0...60) {
                    Text("\(delay)s")
                        .font(.caption)
                        .monospacedDigit()
                }
                .fixedSize()
                .onChange(of: delay) { _, newValue in
                    chainVM.updateItemDelay(item, seconds: newValue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let chain = PromptChain(name: "Test Chain")
    return ChainEditorView(chain: chain)
        .environmentObject(ChainViewModel.shared)
        .environmentObject(PromptViewModel())
}

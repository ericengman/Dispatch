//
//  MainView.swift
//  Dispatch
//
//  Main application view with navigation split view
//

import SwiftData
import SwiftUI

// MARK: - Navigation Selection

enum NavigationSelection: Hashable, Identifiable, Codable {
    case allPrompts
    case starred
    case history
    case project(UUID)
    case chain(UUID)

    var id: String {
        switch self {
        case .allPrompts: return "allPrompts"
        case .starred: return "starred"
        case .history: return "history"
        case let .project(id): return "project-\(id)"
        case let .chain(id): return "chain-\(id)"
        }
    }

    /// Returns the project ID if this selection is a project
    var projectId: UUID? {
        if case let .project(id) = self {
            return id
        }
        return nil
    }

    // MARK: - Persistence

    private static let persistenceKey = "lastNavigationSelection"

    static func loadSaved() -> NavigationSelection? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            return nil
        }
        return try? JSONDecoder().decode(NavigationSelection.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }
}

// MARK: - Main View

struct MainView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var selection: NavigationSelection? = NavigationSelection.loadSaved() ?? .allPrompts
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingQueue: Bool = false
    @State private var queueHeight: CGFloat = 150
    @State private var selectedSkill: Skill?
    @State private var selectedClaudeFile: ClaudeFile?
    @State private var selectedRun: SimulatorRun?
    @State private var showTerminal: Bool = false

    // MARK: - View Models

    @StateObject private var promptVM = PromptViewModel()
    @StateObject private var projectVM = ProjectViewModel.shared
    @StateObject private var chainVM = ChainViewModel.shared
    @StateObject private var queueVM = QueueViewModel.shared
    @StateObject private var historyVM = HistoryViewModel.shared
    @StateObject private var executionState = ExecutionStateMachine.shared
    @StateObject private var simulatorVM = SimulatorViewModel.shared

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .environmentObject(projectVM)
                .environmentObject(chainVM)
        } detail: {
            VStack(spacing: 0) {
                // Main content area with optional skills panel and terminal
                if showTerminal {
                    HSplitView {
                        contentWrapper
                            .frame(minWidth: 400)

                        // Multi-session terminal panel
                        MultiSessionTerminalView()
                            .frame(minWidth: 400)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    contentWrapper
                        .frame(maxHeight: .infinity)
                }

                // Queue panel (collapsible)
                Divider()

                CollapsibleQueuePanel(
                    isExpanded: $showingQueue,
                    expandedHeight: queueHeight
                )
                .environmentObject(queueVM)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            configureViewModels()
        }
        .onChange(of: selection) { _, newSelection in
            newSelection?.save()
            // Clear selections when navigating away
            selectedSkill = nil
            selectedClaudeFile = nil
            selectedRun = nil
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Content Wrapper (with skills panel)

    @ViewBuilder
    private var contentWrapper: some View {
        HStack(spacing: 0) {
            // Skills panel (shown when a project is selected)
            if let projectId = selection?.projectId,
               let project = projectVM.projects.first(where: { $0.id == projectId }) {
                SkillsSidePanel(
                    project: project,
                    selectedSkill: $selectedSkill,
                    selectedClaudeFile: $selectedClaudeFile,
                    selectedRun: $selectedRun
                )
                Divider()
            }

            // Main content, run detail, skill viewer, or claude file editor
            if let run = selectedRun {
                RunDetailView(run: run) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRun = nil
                    }
                }
                .id(run.id) // Force new view when run changes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let claudeFile = selectedClaudeFile {
                ClaudeFileEditor(file: claudeFile) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedClaudeFile = nil
                    }
                }
                .id(claudeFile.id) // Force new view when file changes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let skill = selectedSkill {
                SkillFileViewer(skill: skill) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSkill = nil
                    }
                }
                .id(skill.id) // Force new view when skill changes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selection {
        case .allPrompts:
            PromptListView(filter: .all)
                .environmentObject(promptVM)
                .environmentObject(queueVM)

        case .starred:
            PromptListView(filter: .starred)
                .environmentObject(promptVM)
                .environmentObject(queueVM)

        case .history:
            HistoryListView()
                .environmentObject(historyVM)
                .environmentObject(queueVM)

        case let .project(projectId):
            PromptListView(filter: .project(projectId))
                .environmentObject(promptVM)
                .environmentObject(queueVM)

        case let .chain(chainId):
            if let chain = chainVM.chains.first(where: { $0.id == chainId }) {
                ChainEditorView(chain: chain)
                    .environmentObject(chainVM)
                    .environmentObject(promptVM)
            } else {
                ContentUnavailableView("Chain Not Found", systemImage: "link")
            }

        case nil:
            ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Execution state indicator
            if executionState.state.isActive {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)

                    Text(executionState.state.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        executionState.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            // Terminal toggle button
            Button {
                showTerminal.toggle()
                logInfo("Terminal toggled: \(showTerminal)", category: .terminal)
            } label: {
                Label("Terminal", systemImage: showTerminal ? "terminal.fill" : "terminal")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            // New session shortcut (only when terminal visible)
            if showTerminal {
                Button {
                    _ = TerminalSessionManager.shared.createSession()
                } label: {
                    Label("New Session", systemImage: "plus.rectangle")
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!TerminalSessionManager.shared.canCreateSession)
            }

            // New prompt button
            Button {
                createNewPrompt()
            } label: {
                Label("New Prompt", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: - Actions

    private func configureViewModels() {
        promptVM.configure(with: modelContext)
        projectVM.configure(with: modelContext)
        chainVM.configure(with: modelContext)
        queueVM.configure(with: modelContext)
        historyVM.configure(with: modelContext)
        simulatorVM.configure(with: modelContext)
        SettingsManager.shared.configure(with: modelContext)

        logInfo("ViewModels configured", category: .app)
    }

    private func createNewPrompt() {
        if let prompt = promptVM.createPrompt() {
            promptVM.selectPrompt(prompt)
        }
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .modelContainer(for: [
            Prompt.self,
            Project.self,
            PromptHistory.self,
            PromptChain.self,
            ChainItem.self,
            QueueItem.self,
            AppSettings.self
        ], inMemory: true)
}

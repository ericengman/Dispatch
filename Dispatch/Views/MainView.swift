//
//  MainView.swift
//  Dispatch
//
//  Main application view with navigation split view
//

import SwiftUI
import SwiftData

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
        case .project(let id): return "project-\(id)"
        case .chain(let id): return "chain-\(id)"
        }
    }

    /// Returns the project ID if this selection is a project
    var projectId: UUID? {
        if case .project(let id) = self {
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
    @State private var showingQueue: Bool = true
    @State private var queueHeight: CGFloat = 150
    @State private var selectedSkill: Skill?

    // MARK: - View Models

    @StateObject private var promptVM = PromptViewModel()
    @StateObject private var projectVM = ProjectViewModel.shared
    @StateObject private var chainVM = ChainViewModel.shared
    @StateObject private var queueVM = QueueViewModel.shared
    @StateObject private var historyVM = HistoryViewModel.shared
    @StateObject private var executionState = ExecutionStateMachine.shared

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .environmentObject(projectVM)
                .environmentObject(chainVM)
        } detail: {
            VStack(spacing: 0) {
                // Main content area with optional skills panel
                HStack(spacing: 0) {
                    // Skills panel (shown when a project is selected)
                    if let projectId = selection?.projectId,
                       let project = projectVM.projects.first(where: { $0.id == projectId }) {
                        SkillsSidePanel(project: project, selectedSkill: $selectedSkill)
                        Divider()
                    }

                    // Main content or skill viewer
                    if let skill = selectedSkill {
                        SkillFileViewer(skill: skill) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSkill = nil
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        contentView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Queue panel
                if showingQueue {
                    Divider()

                    QueuePanelView()
                        .environmentObject(queueVM)
                        .frame(height: queueHeight)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            configureViewModels()
        }
        .onChange(of: selection) { _, newSelection in
            newSelection?.save()
            // Clear selected skill when navigating away
            selectedSkill = nil
        }
        .toolbar {
            toolbarContent
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

        case .project(let projectId):
            PromptListView(filter: .project(projectId))
                .environmentObject(promptVM)
                .environmentObject(queueVM)

        case .chain(let chainId):
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

            // New prompt button
            Button {
                createNewPrompt()
            } label: {
                Label("New Prompt", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            // Toggle queue
            Button {
                withAnimation {
                    showingQueue.toggle()
                }
            } label: {
                Label("Toggle Queue", systemImage: showingQueue ? "tray.fill" : "tray")
            }
        }
    }

    // MARK: - Actions

    private func configureViewModels() {
        promptVM.configure(with: modelContext)
        projectVM.configure(with: modelContext)
        chainVM.configure(with: modelContext)
        queueVM.configure(with: modelContext)
        historyVM.configure(with: modelContext)
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

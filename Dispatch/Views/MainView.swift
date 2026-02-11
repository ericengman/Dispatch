//
//  MainView.swift
//  Dispatch
//
//  Main application view with HStack layout (sidebar + detail)
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

// MARK: - Sidebar Mode

enum SidebarMode: String {
    case expanded
    case condensed

    static func loadSaved() -> SidebarMode {
        let raw = UserDefaults.standard.string(forKey: "mainView.sidebarMode") ?? "expanded"
        return SidebarMode(rawValue: raw) ?? .expanded
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "mainView.sidebarMode")
    }
}

// MARK: - Main View

struct MainView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    // MARK: - State

    @State private var selection: NavigationSelection? = NavigationSelection.loadSaved()
    @State private var sidebarMode: SidebarMode = .loadSaved()

    @State private var selectedSkill: Skill?
    @State private var selectedClaudeFile: ClaudeFile?
    @State private var selectedRun: SimulatorRun?

    /// True when a file viewer (skill, claude file, or run) is active
    private var isFileViewerActive: Bool {
        selectedSkill != nil || selectedClaudeFile != nil || selectedRun != nil
    }

    /// True when terminal panel should be visible (not just rendered)
    private var isTerminalVisible: Bool {
        !isFileViewerActive
    }

    /// Whether the content wrapper needs to expand (file viewer open or non-project content)
    private var shouldContentWrapperExpand: Bool {
        isFileViewerActive || selection?.projectId == nil
    }

    /// Path of the currently selected project (nil if no project selected)
    private var selectedProjectPath: String? {
        guard let projectId = selection?.projectId,
              let project = projectVM.projects.first(where: { $0.id == projectId })
        else {
            return nil
        }
        return project.path
    }

    // MARK: - View Models

    @StateObject private var projectVM = ProjectViewModel.shared
    @StateObject private var chainVM = ChainViewModel.shared
    @StateObject private var executionState = ExecutionStateMachine.shared
    @ObservedObject private var captureCoordinator = CaptureCoordinator.shared
    @Bindable private var buildController = BuildRunController.shared

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                selection: $selection,
                mode: sidebarMode,
                onToggleMode: { toggleSidebarMode() }
            )
            .environmentObject(projectVM)

            Divider()

            // Detail content
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    contentWrapper
                        .frame(maxWidth: shouldContentWrapperExpand ? .infinity : nil)

                    if isTerminalVisible {
                        Divider()
                    }

                    MultiSessionTerminalView(projectPath: selectedProjectPath)
                        .frame(maxWidth: isTerminalVisible ? .infinity : 0)
                        .frame(width: isTerminalVisible ? nil : 0)
                        .clipped()
                        .allowsHitTesting(isTerminalVisible)
                        .opacity(isTerminalVisible ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            configureViewModels()
        }
        .onChange(of: sidebarMode) { _, newMode in
            newMode.save()
        }
        .onChange(of: selection) { _, newSelection in
            newSelection?.save()
            selectedSkill = nil
            selectedClaudeFile = nil
            selectedRun = nil
        }
        .onChange(of: captureCoordinator.pendingCapture) { _, newValue in
            if let capture = newValue {
                openWindow(value: capture)
                captureCoordinator.pendingCapture = nil
            }
        }
        .toolbar {
            toolbarContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTerminalSession)) { _ in
            let path = selectedProjectPath
            logDebug("Cmd+T: creating new terminal session (project: \(path ?? "none"))", category: .terminal)
            TerminalSessionManager.shared.createSession(workingDirectory: path)
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
            }

            // File viewer content (run detail, skill viewer, or claude file editor)
            if let run = selectedRun {
                Divider()
                RunDetailView(run: run) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRun = nil
                    }
                }
                .id(run.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let claudeFile = selectedClaudeFile {
                Divider()
                ClaudeFileEditor(file: claudeFile) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedClaudeFile = nil
                    }
                }
                .id(claudeFile.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let skill = selectedSkill {
                Divider()
                SkillFileViewer(skill: skill) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSkill = nil
                    }
                }
                .id(skill.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selection?.projectId == nil {
                // Non-project content (chains, empty states)
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selection {
        case .allPrompts, .starred, .history:
            ContentUnavailableView("Select a Project", systemImage: "folder")

        case .project:
            EmptyView()

        case let .chain(chainId):
            if let chain = chainVM.chains.first(where: { $0.id == chainId }) {
                ChainEditorView(chain: chain)
                    .environmentObject(chainVM)
            } else {
                ContentUnavailableView("Chain Not Found", systemImage: "link")
            }

        case nil:
            ContentUnavailableView("Select a Project", systemImage: "folder")
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

            // Build & Run button
            Button {
                if let path = selectedProjectPath {
                    Task {
                        await buildController.startBuildForProject(path: path)
                    }
                }
            } label: {
                if buildController.hasActiveBuilds {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "hammer.fill")
                }
            }
            .help("Build & Run")
            .disabled(buildController.hasActiveBuilds || selectedProjectPath == nil)
        }
    }

    // MARK: - Actions

    private func toggleSidebarMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarMode = sidebarMode == .expanded ? .condensed : .expanded
        }
    }

    private func configureViewModels() {
        projectVM.configure(with: modelContext)
        chainVM.configure(with: modelContext)
        SettingsManager.shared.configure(with: modelContext)

        logInfo("ViewModels configured", category: .app)
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .modelContainer(for: [
            Project.self,
            PromptChain.self,
            ChainItem.self,
            AppSettings.self
        ], inMemory: true)
}

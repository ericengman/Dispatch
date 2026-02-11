//
//  SkillsSidePanel.swift
//  Dispatch
//
//  Panel with three independent collapsible sections:
//  1. Screenshot Runs - horizontal scroll of recent test runs
//  2. Memory - CLAUDE.md files
//  3. Skills - system and project skills
//

import SwiftData
import SwiftUI

struct SkillsSidePanel: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var skillManager = SkillManager.shared
    @ObservedObject private var claudeFileManager = ClaudeFileManager.shared

    // MARK: - Properties

    let project: Project?
    @Binding var selectedSkill: Skill?
    @Binding var selectedClaudeFile: ClaudeFile?
    @Binding var selectedRun: SimulatorRun?

    // MARK: - State

    // Expanded sections (loaded from UserDefaults on init)
    @State private var expandedSections: Set<String> = Self.loadExpandedSections()

    // Screenshot runs state
    @State private var runs: [SimulatorRun] = []
    @State private var runsFileWatcher: DispatchSourceFileSystemObject?
    @State private var isRefreshingRuns = false

    // Skills state
    @State private var isRefreshingSkills = false

    // Terminal state (shared across all skill cards)
    @State private var matchingTerminals: [TerminalWindow] = []

    // Grid columns for 2xN layout
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    /// The project name for terminal matching
    private var projectName: String {
        project?.name ?? ""
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Section 1: Quick Capture
                QuickCaptureSection(
                    project: project,
                    isExpanded: expandedSections.contains("capture"),
                    onToggle: { toggleSection("capture") }
                )

                // Section 2: Screenshot Runs
                screenshotRunsSection

                // Section 3: Memory
                memorySection

                // Section 4: Skills
                skillsSection
            }
        }
        .scrollIndicators(.hidden, axes: .horizontal)
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadSkills()
            loadClaudeFiles()
            fetchRuns()
            startWatchingRunsDirectory()
        }
        .onDisappear {
            stopWatchingRunsDirectory()
        }
        .onChange(of: project) { _, newProject in
            Task {
                if let path = newProject?.pathURL {
                    await skillManager.loadProjectSkills(for: path)
                    await claudeFileManager.loadFiles(for: path)
                } else {
                    await skillManager.loadProjectSkills(for: nil)
                    await claudeFileManager.loadFiles(for: nil)
                }
                fetchRuns()
            }
        }
    }

    // MARK: - Section 1: Screenshot Runs

    private var screenshotRunsSection: some View {
        VStack(spacing: 0) {
            // Header bar
            SectionHeaderBar(
                title: "Screenshot Runs",
                icon: "camera.viewfinder",
                iconColor: .blue,
                count: runs.count,
                isExpanded: expandedSections.contains("runs"),
                isRefreshing: isRefreshingRuns,
                onToggle: { toggleSection("runs") },
                onRefresh: {
                    isRefreshingRuns = true
                    fetchRuns()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshingRuns = false
                    }
                }
            )

            // Content
            if expandedSections.contains("runs") {
                if runs.isEmpty {
                    emptyRunsView
                        .padding(12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(runs) { run in
                                UnifiedCard(
                                    title: run.displayName,
                                    subtitle: "\(run.screenshotCount) screenshots",
                                    icon: "photo.stack",
                                    iconColor: .blue,
                                    accessory: run.relativeCreatedTime
                                )
                                .frame(width: 140)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedRun = run
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedRun = run
                                        }
                                    } label: {
                                        Label("View Details", systemImage: "eye")
                                    }
                                    Button {
                                        AnnotationWindowController.shared.open(run: run)
                                    } label: {
                                        Label("Open in Window", systemImage: "rectangle.on.rectangle")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        deleteRun(run)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(height: 94)
                }

                Divider()
            }
        }
    }

    private var emptyRunsView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
                Text("No runs yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: 60)
    }

    // MARK: - Section 2: Memory

    private var memorySection: some View {
        let files = claudeFileManager.allFiles.filter { $0.exists }

        return VStack(spacing: 0) {
            // Header bar
            SectionHeaderBar(
                title: "Memory",
                icon: "doc.text.fill",
                iconColor: .purple,
                count: files.count,
                isExpanded: expandedSections.contains("memory"),
                isRefreshing: false,
                onToggle: { toggleSection("memory") },
                onRefresh: {
                    Task {
                        await claudeFileManager.loadFiles(for: project?.pathURL)
                    }
                }
            )

            // Content
            if expandedSections.contains("memory") {
                if files.isEmpty {
                    emptyMemoryView
                        .padding(12)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        if let systemFile = claudeFileManager.systemFile {
                            UnifiedCard(
                                title: "System",
                                subtitle: nil,
                                icon: "globe",
                                iconColor: .secondary,
                                accessory: nil,
                                showCheckmark: systemFile.exists
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedClaudeFile = systemFile
                                }
                            }
                            .onTapGesture(count: 2) {
                                systemFile.openInEditor()
                            }
                        }

                        if let projectFile = claudeFileManager.projectFile {
                            UnifiedCard(
                                title: "Project",
                                subtitle: nil,
                                icon: "folder",
                                iconColor: .secondary,
                                accessory: nil,
                                showCheckmark: projectFile.exists
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedClaudeFile = projectFile
                                }
                            }
                            .onTapGesture(count: 2) {
                                projectFile.openInEditor()
                            }
                        }
                    }
                    .padding(12)
                }

                Divider()
            }
        }
    }

    private var emptyMemoryView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
                Text("No CLAUDE.md files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: 60)
    }

    // MARK: - Section 3: Skills

    private var skillsSection: some View {
        let allSkills = skillManager.systemSkills + skillManager.projectSkills

        return VStack(spacing: 0) {
            // Header bar
            SectionHeaderBar(
                title: "Skills",
                icon: "sparkles",
                iconColor: .orange,
                count: allSkills.count,
                isExpanded: expandedSections.contains("skills"),
                isRefreshing: isRefreshingSkills,
                onToggle: { toggleSection("skills") },
                onRefresh: {
                    Task {
                        isRefreshingSkills = true
                        await skillManager.refresh()
                        isRefreshingSkills = false
                    }
                }
            )

            // Content
            if expandedSections.contains("skills") {
                if allSkills.isEmpty && !skillManager.isLoading {
                    emptySkillsView
                        .padding(12)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(allSkills) { skill in
                            SkillCardCompact(
                                skill: skill,
                                project: project,
                                matchingTerminals: matchingTerminals,
                                selectedSkill: $selectedSkill,
                                onAutomationPermissionDenied: {},
                                onAccessibilityPermissionDenied: {}
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var emptySkillsView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
                Text("No skills found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Add .md files to ~/.claude/skills/")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    // MARK: - Section Toggle

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSections.contains(id) {
                expandedSections.remove(id)
            } else {
                expandedSections.insert(id)
            }
            Self.saveExpandedSections(expandedSections)
        }
    }

    // MARK: - Persistence Helpers

    private static let expandedSectionsKey = "skillsPanel.expandedSections"

    private static func loadExpandedSections() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: expandedSectionsKey),
              let sections = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return ["capture", "runs", "memory", "skills"]
        }
        return sections
    }

    private static func saveExpandedSections(_ sections: Set<String>) {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: expandedSectionsKey)
        }
    }

    // MARK: - Screenshot Runs Data

    private func fetchRuns() {
        var descriptor = FetchDescriptor<SimulatorRun>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]

        if let project = project {
            let projectId = project.id
            descriptor.predicate = #Predicate<SimulatorRun> { run in
                run.project?.id == projectId
            }
        }

        descriptor.fetchLimit = 10

        runs = (try? modelContext.fetch(descriptor)) ?? []
        logDebug("Fetched \(runs.count) runs for side panel", category: .simulator)
    }

    private func deleteRun(_ run: SimulatorRun) {
        for screenshot in run.screenshots {
            screenshot.deleteFile()
        }

        if let projectName = run.project?.name {
            Task {
                try? await ScreenshotWatcherService.shared.deleteRunDirectory(
                    runId: run.id,
                    projectName: projectName
                )
            }
        }

        modelContext.delete(run)
        try? modelContext.save()

        fetchRuns()
        logInfo("Deleted run: \(run.displayName)", category: .simulator)
    }

    // MARK: - File Watching for Runs

    private func startWatchingRunsDirectory() {
        Task {
            let config = await ScreenshotWatcherService.shared.getConfig()
            let baseDir = config.baseDirectory

            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let fd = open(baseDir.path, O_EVTONLY)
            guard fd >= 0 else {
                logWarning("Could not open runs directory for watching", category: .simulator)
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )

            source.setEventHandler { [self] in
                logDebug("Runs directory changed, refreshing", category: .simulator)
                fetchRuns()
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            runsFileWatcher = source
            logDebug("Started watching runs directory: \(baseDir.path)", category: .simulator)
        }
    }

    private func stopWatchingRunsDirectory() {
        runsFileWatcher?.cancel()
        runsFileWatcher = nil
    }

    // MARK: - Skills Data

    private func loadSkills() {
        Task {
            await skillManager.loadSkills()
            if let path = project?.pathURL {
                await skillManager.loadProjectSkills(for: path)
            }
        }
    }

    private func loadClaudeFiles() {
        Task {
            await claudeFileManager.loadFiles(for: project?.pathURL)
        }
    }
}

// MARK: - Section Header Bar

struct SectionHeaderBar<TrailingContent: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let count: Int
    let isExpanded: Bool
    let isRefreshing: Bool
    let onToggle: () -> Void
    let onRefresh: (() -> Void)?
    let trailingContent: TrailingContent

    init(
        title: String,
        icon: String,
        iconColor: Color,
        count: Int,
        isExpanded: Bool,
        isRefreshing: Bool = false,
        onToggle: @escaping () -> Void,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.count = count
        self.isExpanded = isExpanded
        self.isRefreshing = isRefreshing
        self.onToggle = onToggle
        self.onRefresh = onRefresh
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack {
            // Collapse chevron + icon + title + count (tappable area)
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Label {
                        HStack(spacing: 4) {
                            Text(title)
                            Text("(\(count))")
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: icon)
                            .foregroundStyle(iconColor)
                    }
                    .font(.headline)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Custom trailing content (e.g., capture buttons)
            trailingContent

            // Refresh button (shown only when onRefresh is provided)
            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// Convenience initializer without trailing content
extension SectionHeaderBar where TrailingContent == EmptyView {
    init(
        title: String,
        icon: String,
        iconColor: Color,
        count: Int,
        isExpanded: Bool,
        isRefreshing: Bool = false,
        onToggle: @escaping () -> Void,
        onRefresh: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            icon: icon,
            iconColor: iconColor,
            count: count,
            isExpanded: isExpanded,
            isRefreshing: isRefreshing,
            onToggle: onToggle,
            onRefresh: onRefresh,
            trailingContent: { EmptyView() }
        )
    }
}

// MARK: - Unified Card

struct UnifiedCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let accessory: String?
    var showCheckmark: Bool = false

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor.opacity(0.7))
            }

            Spacer()

            HStack {
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.7))
                } else if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if let accessory = accessory {
                    Text(accessory)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(minHeight: 70)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovering ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                    lineWidth: isHovering ? 1.5 : 1
                )
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Compact Skill Card

struct SkillCardCompact: View {
    let skill: Skill
    let project: Project?
    let matchingTerminals: [TerminalWindow]
    @Binding var selectedSkill: Skill?
    var onAutomationPermissionDenied: () -> Void
    var onAccessibilityPermissionDenied: () -> Void

    @ObservedObject private var skillManager = SkillManager.shared
    @State private var isHovering = false

    private var isStarred: Bool {
        skillManager.isStarred(skill)
    }

    private var projectPath: URL? {
        project?.pathURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        skillManager.toggleStarred(skill)
                    }
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(isStarred ? Color.yellow : Color.secondary.opacity(0.3))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if isHovering {
                CompactDispatchButton(
                    skillId: skill.id.uuidString,
                    terminals: matchingTerminals,
                    onDispatch: { terminal, pressEnter in
                        dispatchToTerminal(windowId: terminal.id, pressEnter: pressEnter)
                    },
                    onNewSession: { pressEnter in
                        launchNewTerminal(pressEnter: pressEnter)
                    }
                )
            }
        }
        .padding(12)
        .frame(minHeight: 70)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovering ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                    lineWidth: isHovering ? 1.5 : 1
                )
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            skillManager.openSkillFile(skill)
        }
        .onTapGesture(count: 1) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSkill = skill
            }
        }
        .help("Tap to preview, double-tap to open file")
    }

    private func dispatchToTerminal(windowId: String?, pressEnter: Bool) {
        Task {
            do {
                logDebug("Dispatching skill '\(skill.name)' to terminal", category: .execution)
                try await SkillManager.shared.runInExistingTerminal(skill, windowId: windowId, pressEnter: pressEnter)
                logInfo("Skill '\(skill.name)' dispatched successfully", category: .execution)
            } catch TerminalServiceError.accessibilityPermissionDenied {
                logError("Accessibility permission denied", category: .execution)
                await MainActor.run { onAccessibilityPermissionDenied() }
            } catch TerminalServiceError.permissionDenied {
                logError("Automation permission denied", category: .execution)
                await MainActor.run { onAutomationPermissionDenied() }
            } catch {
                logError("Failed to dispatch skill: \(error)", category: .execution)
            }
        }
    }

    private func launchNewTerminal(pressEnter: Bool = true) {
        Task {
            do {
                logDebug("Launching new terminal for skill '\(skill.name)'", category: .execution)
                try await SkillManager.shared.runInNewTerminal(skill, projectPath: projectPath, pressEnter: pressEnter)
                logInfo("New terminal launched for skill '\(skill.name)'", category: .execution)
            } catch TerminalServiceError.accessibilityPermissionDenied {
                logError("Accessibility permission denied", category: .execution)
                await MainActor.run { onAccessibilityPermissionDenied() }
            } catch TerminalServiceError.permissionDenied {
                logError("Automation permission denied", category: .execution)
                await MainActor.run { onAutomationPermissionDenied() }
            } catch {
                logError("Failed to launch terminal: \(error)", category: .execution)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedSkill: Skill?
    @Previewable @State var selectedClaudeFile: ClaudeFile?
    @Previewable @State var selectedRun: SimulatorRun?
    SkillsSidePanel(
        project: nil,
        selectedSkill: $selectedSkill,
        selectedClaudeFile: $selectedClaudeFile,
        selectedRun: $selectedRun
    )
    .frame(height: 600)
}

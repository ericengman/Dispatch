//
//  SkillsSidePanel.swift
//  Dispatch
//
//  Compact skills panel shown alongside projects
//

import SwiftUI

struct SkillsSidePanel: View {
    // MARK: - Environment

    @ObservedObject private var skillManager = SkillManager.shared

    // MARK: - Properties

    let project: Project?
    @Binding var selectedSkill: Skill?

    // MARK: - State

    @State private var isRefreshing = false
    @State private var expandedSections: Set<String> = ["system", "project"]

    // Terminal state (shared across all skill cards)
    @State private var matchingTerminals: [TerminalWindow] = []
    @State private var isLoadingTerminals = false
    @State private var showingAutomationPermissionAlert = false
    @State private var showingAccessibilityPermissionAlert = false

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
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Skills grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // System Skills
                    if !skillManager.systemSkills.isEmpty {
                        skillSection(
                            id: "system",
                            title: "System",
                            icon: "globe",
                            skills: skillManager.systemSkills
                        )
                    }

                    // Project Skills
                    if let project = project, project.isLinkedToFileSystem {
                        if !skillManager.projectSkills.isEmpty {
                            skillSection(
                                id: "project",
                                title: project.name,
                                icon: "folder",
                                skills: skillManager.projectSkills
                            )
                        } else {
                            emptyProjectSection(project: project)
                        }
                    }

                    // Empty state
                    if skillManager.systemSkills.isEmpty && skillManager.projectSkills.isEmpty && !skillManager.isLoading {
                        emptyStateView
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadSkills()
            loadTerminals()
        }
        .onChange(of: project) { _, newProject in
            Task {
                if let path = newProject?.pathURL {
                    await skillManager.loadProjectSkills(for: path)
                } else {
                    await skillManager.loadProjectSkills(for: nil)
                }
                // Reload terminals when project changes
                await loadTerminalsAsync()
            }
        }
        .alert("Terminal Permission Required", isPresented: $showingAutomationPermissionAlert) {
            Button("Open Settings") {
                Task {
                    await TerminalService.shared.openAutomationSettings()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dispatch needs permission to control Terminal.app.\n\nGo to System Settings > Privacy & Security > Automation and enable Terminal for Dispatch.")
        }
        .alert("Accessibility Permission Required", isPresented: $showingAccessibilityPermissionAlert) {
            Button("Open Settings") {
                Task {
                    await TerminalService.shared.openAccessibilitySettings()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dispatch needs Accessibility permission to send keystrokes to Terminal.\n\nGo to System Settings > Privacy & Security > Accessibility and add Dispatch to the list.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Label("Skills", systemImage: "sparkles")
                .font(.headline)

            Spacer()

            Button {
                Task {
                    isRefreshing = true
                    await skillManager.refresh()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Skill Section

    private func skillSection(id: String, title: String, icon: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header (collapsible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedSections.contains(id) {
                        expandedSections.remove(id)
                    } else {
                        expandedSections.insert(id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedSections.contains(id) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("(\(skills.count))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Skills grid (2 columns)
            if expandedSections.contains(id) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(skills) { skill in
                        SkillCardCompact(
                            skill: skill,
                            project: project,
                            matchingTerminals: matchingTerminals,
                            selectedSkill: $selectedSkill,
                            onAutomationPermissionDenied: { showingAutomationPermissionAlert = true },
                            onAccessibilityPermissionDenied: { showingAccessibilityPermissionAlert = true }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private func emptyProjectSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(project.name)
                    .font(.subheadline.weight(.medium))
            }

            Text("No skills in project")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 16)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No Skills")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Add .md files to\n~/.claude/skills/")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Actions

    private func loadSkills() {
        Task {
            await skillManager.loadSkills()
            if let path = project?.pathURL {
                await skillManager.loadProjectSkills(for: path)
            }
        }
    }

    private func loadTerminals() {
        Task {
            await loadTerminalsAsync()
        }
    }

    private func loadTerminalsAsync() async {
        guard !projectName.isEmpty else {
            await MainActor.run { matchingTerminals = [] }
            return
        }

        logDebug("Loading terminals for project: '\(projectName)'", category: .terminal)
        isLoadingTerminals = true

        do {
            let allTerminals = try await TerminalService.shared.getWindows(forceRefresh: true)
            logDebug("Found \(allTerminals.count) total terminal windows", category: .terminal)

            // Filter to terminals matching the project
            let matching = allTerminals.filter { terminal in
                let name = terminal.name.lowercased()
                let tabTitle = terminal.tabTitle?.lowercased() ?? ""
                let projectLower = projectName.lowercased()
                return name.contains(projectLower) || tabTitle.contains(projectLower)
            }

            logDebug("Found \(matching.count) terminals matching project '\(projectName)'", category: .terminal)

            await MainActor.run {
                matchingTerminals = matching
                isLoadingTerminals = false
            }
        } catch TerminalServiceError.permissionDenied {
            logWarning("Automation permission denied when loading terminals", category: .terminal)
            await MainActor.run {
                matchingTerminals = []
                isLoadingTerminals = false
                showingAutomationPermissionAlert = true
            }
        } catch TerminalServiceError.accessibilityPermissionDenied {
            logWarning("Accessibility permission denied when loading terminals", category: .terminal)
            await MainActor.run {
                matchingTerminals = []
                isLoadingTerminals = false
                showingAccessibilityPermissionAlert = true
            }
        } catch {
            logError("Failed to load terminals: \(error)", category: .terminal)
            await MainActor.run {
                matchingTerminals = []
                isLoadingTerminals = false
            }
        }
    }
}

// MARK: - Compact Skill Card

struct SkillCardCompact: View {
    let skill: Skill
    let project: Project?  // Currently selected project (for terminal operations)
    let matchingTerminals: [TerminalWindow]  // Terminals matching current project (from parent)
    @Binding var selectedSkill: Skill?
    var onAutomationPermissionDenied: () -> Void  // Callback when automation permission is denied
    var onAccessibilityPermissionDenied: () -> Void  // Callback when accessibility permission is denied

    @ObservedObject private var skillManager = SkillManager.shared
    @State private var isHovering = false

    private var isStarred: Bool {
        skillManager.isStarred(skill)
    }

    /// The project path to use for terminal operations
    private var projectPath: URL? {
        project?.pathURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with star
            HStack(alignment: .top) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Spacer()

                // Star button
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

            // Action buttons (shown on hover)
            if isHovering {
                HStack(spacing: 8) {
                    // Show dispatch button only if there are matching terminals
                    if matchingTerminals.count == 1 {
                        // Single matching terminal - direct dispatch button
                        Button {
                            dispatchToTerminal(windowId: matchingTerminals.first?.id, pressEnter: true)
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Run in \(terminalDisplayName(matchingTerminals.first!))")
                    } else if matchingTerminals.count > 1 {
                        // Multiple matching terminals - show picker
                        Menu {
                            ForEach(matchingTerminals) { terminal in
                                Button {
                                    dispatchToTerminal(windowId: terminal.id, pressEnter: true)
                                } label: {
                                    Label(terminalDisplayName(terminal), systemImage: terminal.isActive ? "terminal.fill" : "terminal")
                                }
                            }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Run in terminal")
                    }
                    // If no matching terminals, don't show dispatch button at all

                    // New terminal button (green) - always shown
                    Button {
                        launchNewTerminal()
                    } label: {
                        Image(systemName: "plus.rectangle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("New Claude session")

                    Spacer()

                    // Params button (orange) - only for skills with parameters
                    // Types the command but doesn't press enter, letting user fill in params
                    if skill.hasInputParameters && !matchingTerminals.isEmpty {
                        if matchingTerminals.count == 1 {
                            Button {
                                dispatchToTerminal(windowId: matchingTerminals.first?.id, pressEnter: false)
                            } label: {
                                Image(systemName: "pencil.line")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("Type command (edit params first)")
                        } else {
                            Menu {
                                ForEach(matchingTerminals) { terminal in
                                    Button {
                                        dispatchToTerminal(windowId: terminal.id, pressEnter: false)
                                    } label: {
                                        Label(terminalDisplayName(terminal), systemImage: terminal.isActive ? "terminal.fill" : "terminal")
                                    }
                                }
                            } label: {
                                Image(systemName: "pencil.line")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Type command (edit params first)")
                        }
                    }
                }
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
            // Double tap: open file in editor
            skillManager.openSkillFile(skill)
        }
        .onTapGesture(count: 1) {
            // Single tap: show in viewer
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSkill = skill
            }
        }
        .help("Tap to preview, double-tap to open file")
    }

    // MARK: - Actions

    private func dispatchToTerminal(windowId: String?, pressEnter: Bool) {
        Task {
            do {
                logDebug("Dispatching skill '\(skill.name)' (command: \(skill.slashCommand)) to terminal (windowId: \(windowId ?? "active"), pressEnter: \(pressEnter))", category: .execution)
                try await SkillManager.shared.runInExistingTerminal(skill, windowId: windowId, pressEnter: pressEnter)
                logInfo("Skill '\(skill.name)' dispatched successfully", category: .execution)
            } catch TerminalServiceError.accessibilityPermissionDenied {
                logError("Accessibility permission denied when dispatching skill '\(skill.name)'", category: .execution)
                await MainActor.run {
                    onAccessibilityPermissionDenied()
                }
            } catch TerminalServiceError.permissionDenied {
                logError("Automation permission denied when dispatching skill '\(skill.name)'", category: .execution)
                await MainActor.run {
                    onAutomationPermissionDenied()
                }
            } catch {
                logError("Failed to dispatch skill '\(skill.name)': \(error)", category: .execution)
            }
        }
    }

    private func launchNewTerminal() {
        Task {
            do {
                logDebug("Launching new terminal for skill '\(skill.name)' at project: \(project?.name ?? "none")", category: .execution)
                try await SkillManager.shared.runInNewTerminal(skill, projectPath: projectPath)
                logInfo("New terminal launched for skill '\(skill.name)'", category: .execution)
            } catch TerminalServiceError.accessibilityPermissionDenied {
                logError("Accessibility permission denied when launching terminal for skill '\(skill.name)'", category: .execution)
                await MainActor.run {
                    onAccessibilityPermissionDenied()
                }
            } catch TerminalServiceError.permissionDenied {
                logError("Automation permission denied when launching terminal for skill '\(skill.name)'", category: .execution)
                await MainActor.run {
                    onAutomationPermissionDenied()
                }
            } catch {
                logError("Failed to launch terminal for skill '\(skill.name)': \(error)", category: .execution)
            }
        }
    }

    // MARK: - Helpers

    private func terminalDisplayName(_ terminal: TerminalWindow) -> String {
        // Parse the terminal name/title to show something meaningful
        var displayName = terminal.tabTitle ?? terminal.name

        // Try to extract just the directory name if it's a path
        if displayName.contains("/") {
            if let lastComponent = displayName.components(separatedBy: "/").last, !lastComponent.isEmpty {
                displayName = lastComponent
            }
        }

        // Remove common prefixes like "user@hostname: "
        if let colonIndex = displayName.lastIndex(of: ":") {
            let afterColon = displayName[displayName.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            if !afterColon.isEmpty {
                displayName = afterColon
            }
        }

        // Add active indicator
        if terminal.isActive {
            displayName = "● \(displayName)"
        }

        // Truncate if too long
        if displayName.count > 30 {
            displayName = String(displayName.prefix(27)) + "..."
        }

        return displayName
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedSkill: Skill? = nil
    SkillsSidePanel(project: nil, selectedSkill: $selectedSkill)
        .frame(height: 400)
}

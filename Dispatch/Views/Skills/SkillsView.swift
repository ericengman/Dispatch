//
//  SkillsView.swift
//  Dispatch
//
//  View for displaying and running Claude Code skills
//

import SwiftUI

struct SkillsView: View {
    // MARK: - Environment

    @EnvironmentObject private var projectVM: ProjectViewModel
    @ObservedObject private var skillManager = SkillManager.shared

    // MARK: - State

    @State private var selectedProject: Project?
    @State private var isRefreshing = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with project picker
                headerView

                // System Skills Section
                if !skillManager.systemSkills.isEmpty {
                    skillSection(
                        title: "System Skills",
                        subtitle: "Available globally in ~/.claude/commands",
                        icon: "globe",
                        skills: skillManager.systemSkills
                    )
                }

                // Project Skills Section
                if let project = selectedProject, project.isLinkedToFileSystem {
                    if !skillManager.projectSkills.isEmpty {
                        skillSection(
                            title: "Project Skills",
                            subtitle: project.name,
                            icon: "folder",
                            skills: skillManager.projectSkills
                        )
                    } else {
                        emptyProjectSkillsView(project: project)
                    }
                }

                // Empty state
                if skillManager.systemSkills.isEmpty && skillManager.projectSkills.isEmpty && !skillManager.isLoading {
                    emptyStateView
                }

                Spacer()
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Skills")
        .onAppear {
            Task {
                await skillManager.loadSkills()
            }
        }
        .onChange(of: selectedProject) { _, newProject in
            Task {
                if let path = newProject?.pathURL {
                    await skillManager.loadProjectSkills(for: path)
                } else {
                    await skillManager.loadProjectSkills(for: nil)
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills")
                    .font(.largeTitle.bold())

                Text("Custom slash commands for Claude Code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Project Picker
            HStack(spacing: 12) {
                Picker("Project", selection: $selectedProject) {
                    Text("Select Project").tag(nil as Project?)
                    ForEach(projectVM.projects.filter { $0.isLinkedToFileSystem }) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                // Refresh button
                Button {
                    Task {
                        isRefreshing = true
                        await skillManager.refresh()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Skill Section

    private func skillSection(title: String, subtitle: String, icon: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)

                Text("(\(skills.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Skills grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(skills) { skill in
                    SkillCard(skill: skill)
                }
            }
        }
    }

    // MARK: - Empty States

    private func emptyProjectSkillsView(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                Text("Project Skills")
                    .font(.headline)

                Spacer()
            }

            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.tertiary)

                    Text("No skills found in \(project.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Add .md files to .claude/commands/ in your project")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 24)
                Spacer()
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Skills Found")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Create custom slash commands by adding .md files to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("~/.claude/commands/ (system-wide)", systemImage: "globe")
                Label(".claude/commands/ (project-level)", systemImage: "folder")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Skill Card

struct SkillCard: View {
    let skill: Skill

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Scope badge
                Image(systemName: skill.scope.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.quaternary, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(skill.slashCommand)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .fontDesign(.monospaced)
                }

                Spacer()
            }

            // Description
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                // Run in existing terminal
                Button {
                    Task {
                        try? await SkillManager.shared.runInExistingTerminal(skill)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Run in existing terminal")

                // Run in new terminal
                Button {
                    Task {
                        try? await SkillManager.shared.runInNewTerminal(skill)
                    }
                } label: {
                    Label("New Session", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Start new Claude session and run")

                Spacer()
            }
        }
        .padding(16)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.15 : 0.08), radius: isHovering ? 8 : 4, y: isHovering ? 4 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    SkillsView()
        .environmentObject(ProjectViewModel.shared)
        .frame(width: 800, height: 600)
}

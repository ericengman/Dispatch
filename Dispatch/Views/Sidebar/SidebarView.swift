//
//  SidebarView.swift
//  Dispatch
//
//  Unified sidebar view handling both expanded and condensed modes.
//

import SwiftUI

struct SidebarView: View {
    // MARK: - Bindings

    @Binding var selection: NavigationSelection?
    var mode: SidebarMode
    var onToggleMode: () -> Void

    // MARK: - Environment

    @EnvironmentObject private var projectVM: ProjectViewModel

    // MARK: - State

    @State private var showingNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var newProjectColor: ProjectColor = .blue

    private let sessionManager = TerminalSessionManager.shared

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .expanded:
                expandedContent
            case .condensed:
                condensedContent
            }

            Spacer(minLength: 0)

            // Toggle button (both modes)
            Button {
                onToggleMode()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: mode == .expanded ? .leading : .center)
            .padding(.leading, mode == .expanded ? 12 : 0)
            .padding(.bottom, 4)
        }
        .frame(width: mode == .expanded ? 160 : 60)
        .background(.bar)
        .contextMenu {
            Button {
                Task {
                    await projectVM.refreshProjects()
                }
            } label: {
                Label("Refresh Projects", systemImage: "arrow.clockwise")
            }

            Divider()

            Button {
                showingNewProjectSheet = true
            } label: {
                Label("New Project...", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            newProjectSheet
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        List(selection: $selection) {
            Section {
                expandedProjectList
            }
        }
        .listStyle(.sidebar)
    }

    private var expandedProjectList: some View {
        ForEach(projectVM.projects) { project in
            expandedRow(for: project)
                .tag(NavigationSelection.project(project.id))
                .contextMenu {
                    projectContextMenu(for: project)
                }
        }
        .onMove { source, destination in
            if let from = source.first {
                projectVM.moveProject(from: from, to: destination)
            }
        }
    }

    @ViewBuilder
    private func expandedRow(for project: Project) -> some View {
        let hasActiveSessions = !sessionManager.sessionsForProject(
            id: project.id, path: project.path
        ).isEmpty

        HStack(spacing: 8) {
            projectIcon(for: project, size: 28, cornerRadius: 6)

            Text(project.name)
                .lineLimit(1)
                .font(.callout)

            Spacer()

            if hasActiveSessions {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Condensed Content

    private var condensedContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(projectVM.projects) { project in
                    condensedIcon(for: project)
                        .onTapGesture {
                            selection = .project(project.id)
                        }
                        .contextMenu {
                            projectContextMenu(for: project)
                        }
                }
            }
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func condensedIcon(for project: Project) -> some View {
        let isSelected = selection == .project(project.id)
        let hasActiveSessions = !sessionManager.sessionsForProject(
            id: project.id, path: project.path
        ).isEmpty

        VStack(spacing: 4) {
            projectIcon(for: project, size: 36, cornerRadius: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

            if hasActiveSessions {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            } else {
                Color.clear
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 48)
        .contentShape(Rectangle())
    }

    // MARK: - Shared Project Icon

    @ViewBuilder
    private func projectIcon(for project: Project, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let iconImage = project.iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(project.color.gradient)
                .frame(width: size, height: size)
                .overlay {
                    Text(project.initial)
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        if project.isLinkedToFileSystem {
            Button {
                projectVM.openInFinder(project)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Button {
                projectVM.openInTerminal(project)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }

            Divider()
        }

        Button {
            projectVM.setCustomIcon(for: project)
        } label: {
            Label("Set Icon...", systemImage: "photo")
        }

        if project.isCustomIcon {
            Button {
                projectVM.clearCustomIcon(for: project)
            } label: {
                Label("Clear Custom Icon", systemImage: "arrow.counterclockwise")
            }
        }

        Divider()

        Button {
            Task {
                await projectVM.refreshProjects()
            }
        } label: {
            Label("Refresh Projects", systemImage: "arrow.clockwise")
        }

        Button {
            showingNewProjectSheet = true
        } label: {
            Label("New Project...", systemImage: "plus")
        }

        Divider()

        Button("Delete", role: .destructive) {
            projectVM.deleteProject(project)
        }
    }

    // MARK: - New Project Sheet

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                TextField("Project Name", text: $newProjectName)

                Picker("Color", selection: $newProjectColor) {
                    ForEach(ProjectColor.allCases) { color in
                        HStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 12, height: 12)
                            Text(color.name)
                        }
                        .tag(color)
                    }
                }
            }
            .frame(width: 300, height: 150)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewProjectSheet = false
                        newProjectName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if !newProjectName.isEmpty {
                            _ = projectVM.createProject(name: newProjectName, color: newProjectColor)
                            showingNewProjectSheet = false
                            newProjectName = ""
                            newProjectColor = .blue
                        }
                    }
                    .disabled(newProjectName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Expanded") {
    SidebarView(selection: .constant(nil), mode: .expanded, onToggleMode: {})
        .environmentObject(ProjectViewModel.shared)
        .frame(height: 400)
}

#Preview("Condensed") {
    SidebarView(selection: .constant(nil), mode: .condensed, onToggleMode: {})
        .environmentObject(ProjectViewModel.shared)
        .frame(height: 400)
}

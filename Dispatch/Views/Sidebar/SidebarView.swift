//
//  SidebarView.swift
//  Dispatch
//
//  Sidebar navigation view
//

import SwiftUI

struct SidebarView: View {
    // MARK: - Environment

    @EnvironmentObject private var projectVM: ProjectViewModel

    // MARK: - Binding

    @Binding var selection: NavigationSelection?
    var onCollapse: () -> Void

    // MARK: - State

    @State private var showingNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var newProjectColor: ProjectColor = .blue

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            Section {
                projectList
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)
        .safeAreaInset(edge: .bottom) {
            Button {
                onCollapse()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.bottom, 4)
        }
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

    // MARK: - Project List View

    private var projectList: some View {
        ForEach(projectVM.projects) { project in
            NavigationLink(value: NavigationSelection.project(project.id)) {
                HStack(spacing: 8) {
                    projectIcon(for: project)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(project.name)
                        .lineLimit(1)
                        .font(.callout)
                }
            }
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

    // MARK: - Project Icon

    @ViewBuilder
    private func projectIcon(for project: Project) -> some View {
        if let iconImage = project.iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(project.color.gradient)
                .overlay {
                    Text(project.initial)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Shared Context Menu

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
}

// MARK: - Preview

#Preview {
    SidebarView(selection: .constant(nil), onCollapse: {})
        .environmentObject(ProjectViewModel.shared)
        .frame(width: 160)
}

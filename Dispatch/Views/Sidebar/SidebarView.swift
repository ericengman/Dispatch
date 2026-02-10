//
//  SidebarView.swift
//  Dispatch
//
//  Sidebar navigation view
//

import SwiftData
import SwiftUI

struct SidebarView: View {
    // MARK: - Environment

    @EnvironmentObject private var projectVM: ProjectViewModel
    @EnvironmentObject private var chainVM: ChainViewModel

    // MARK: - Binding

    @Binding var selection: NavigationSelection?

    // MARK: - State

    @State private var showingNewProjectSheet = false
    @State private var showingNewChainSheet = false
    @State private var newProjectName = ""
    @State private var newProjectColor: ProjectColor = .blue
    @State private var newChainName = ""

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            // MARK: - Quick Capture Section

            QuickCaptureSidebarSection()

            // MARK: - Projects Section

            Section {
                ForEach(projectVM.projects) { project in
                    NavigationLink(value: NavigationSelection.project(project.id)) {
                        HStack {
                            Circle()
                                .fill(project.color)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.name)
                                    .lineLimit(1)

                                // Show path indicator for linked projects
                                if project.isLinkedToFileSystem {
                                    Text(project.path ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                        }
                    }
                    .contextMenu {
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

                        Button("Delete", role: .destructive) {
                            projectVM.deleteProject(project)
                        }
                    }
                }
                .onMove { source, destination in
                    if let from = source.first {
                        projectVM.moveProject(from: from, to: destination)
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()

                    // Refresh projects button
                    Button {
                        Task {
                            await projectVM.refreshProjects()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh projects from file system")

                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: - Chains Section

            Section {
                ForEach(chainVM.chains) { chain in
                    NavigationLink(value: NavigationSelection.chain(chain.id)) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)

                            Text(chain.name)

                            Spacer()

                            Text("\(chain.stepCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .contextMenu {
                        Button("Run Chain") {
                            Task {
                                await chainVM.startExecution(of: chain)
                            }
                        }
                        Divider()
                        Button("Duplicate") {
                            _ = chainVM.duplicateChain(chain)
                        }
                        Button("Delete", role: .destructive) {
                            chainVM.deleteChain(chain)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Chains")
                    Spacer()
                    Button {
                        showingNewChainSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .sheet(isPresented: $showingNewProjectSheet) {
            newProjectSheet
        }
        .sheet(isPresented: $showingNewChainSheet) {
            newChainSheet
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

    // MARK: - New Chain Sheet

    private var newChainSheet: some View {
        NavigationStack {
            Form {
                TextField("Chain Name", text: $newChainName)
            }
            .frame(width: 300, height: 100)
            .navigationTitle("New Chain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewChainSheet = false
                        newChainName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if !newChainName.isEmpty {
                            if let chain = chainVM.createChain(name: newChainName) {
                                selection = .chain(chain.id)
                            }
                            showingNewChainSheet = false
                            newChainName = ""
                        }
                    }
                    .disabled(newChainName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SidebarView(selection: .constant(nil))
        .environmentObject(ProjectViewModel.shared)
        .environmentObject(ChainViewModel.shared)
        .frame(width: 250)
}

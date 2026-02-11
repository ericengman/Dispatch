//
//  DestinationPickerStrip.swift
//  Dispatch
//
//  Horizontal strip for scheme and destination selection, shown above SessionTabBar
//

import SwiftUI

struct DestinationPickerStrip: View {
    let projectPath: String
    @Bindable var buildController: BuildRunController

    @State private var projectInfo: XcodeProjectInfo?
    @State private var availableDestinations: [DestinationGroup: [BuildDestination]] = [:]
    @State private var isLoadingDestinations = false

    private var selectedScheme: String? {
        buildController.selectedScheme(for: projectPath)
    }

    private var selectedDestinations: [BuildDestination] {
        buildController.destinations(for: projectPath)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Scheme picker menu
            schemeMenu

            if !selectedDestinations.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }

            // Selected destination chips
            ForEach(selectedDestinations, id: \.id) { dest in
                destinationChip(dest)
            }

            // Add destination button
            addDestinationMenu

            Spacer()

            // Build & Run button
            buildButton
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .task {
            await loadProjectInfo()
        }
        .onChange(of: projectPath) { _, _ in
            Task { await loadProjectInfo() }
        }
    }

    // MARK: - Scheme Menu

    @ViewBuilder
    private var schemeMenu: some View {
        if let info = projectInfo, !info.schemes.isEmpty {
            Menu {
                ForEach(info.schemes, id: \.self) { scheme in
                    Button {
                        buildController.setSelectedScheme(scheme, for: projectPath)
                    } label: {
                        HStack {
                            Text(scheme)
                            if scheme == selectedScheme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hammer")
                        .font(.system(size: 10))
                    Text(selectedScheme ?? "Scheme")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Destination Chip

    private func destinationChip(_ destination: BuildDestination) -> some View {
        HStack(spacing: 4) {
            Image(systemName: destination.group.systemImage)
                .font(.system(size: 9))
            Text(destination.name)
                .font(.system(size: 11, weight: .medium))
            Button {
                buildController.removeDestination(destination, for: projectPath)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Add Destination Menu

    @ViewBuilder
    private var addDestinationMenu: some View {
        Menu {
            // Recent destinations
            if !buildController.recentDestinations.isEmpty {
                Section("Recent") {
                    ForEach(buildController.recentDestinations, id: \.id) { dest in
                        Button {
                            buildController.addDestination(dest, for: projectPath)
                        } label: {
                            Label(dest.displayName, systemImage: dest.group.systemImage)
                        }
                        .disabled(selectedDestinations.contains(where: { $0.id == dest.id }))
                    }
                }
            }

            // Mac destination
            Section("Mac") {
                Button {
                    buildController.addDestination(.myMac, for: projectPath)
                } label: {
                    Label("My Mac", systemImage: "macbook")
                }
                .disabled(selectedDestinations.contains(where: { $0.id == BuildDestination.myMac.id }))
            }

            // iPhone simulators
            let iPhones = availableDestinations[.iPhone] ?? []
            if !iPhones.isEmpty {
                Section("iPhone") {
                    ForEach(iPhones, id: \.id) { dest in
                        Button {
                            buildController.addDestination(dest, for: projectPath)
                        } label: {
                            Label(dest.displayName, systemImage: "iphone")
                        }
                        .disabled(selectedDestinations.contains(where: { $0.id == dest.id }))
                    }
                }
            }

            // iPad simulators
            let iPads = availableDestinations[.iPad] ?? []
            if !iPads.isEmpty {
                Section("iPad") {
                    ForEach(iPads, id: \.id) { dest in
                        Button {
                            buildController.addDestination(dest, for: projectPath)
                        } label: {
                            Label(dest.displayName, systemImage: "ipad")
                        }
                        .disabled(selectedDestinations.contains(where: { $0.id == dest.id }))
                    }
                }
            }

            Divider()

            // Refresh
            Button {
                Task { await refreshDestinations() }
            } label: {
                Label("Refresh Simulators", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                if isLoadingDestinations {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Build Button

    @ViewBuilder
    private var buildButton: some View {
        Button {
            Task {
                await buildController.startBuildForProject(path: projectPath)
            }
        } label: {
            HStack(spacing: 4) {
                if buildController.hasActiveBuilds {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                }
                Text("Build & Run")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(buildController.hasActiveBuilds ? Color.gray.opacity(0.2) : Color.accentColor)
            )
            .foregroundStyle(buildController.hasActiveBuilds ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(buildController.hasActiveBuilds || selectedScheme == nil)
    }

    // MARK: - Data Loading

    private func loadProjectInfo() async {
        let info = await buildController.projectInfo(for: projectPath)
        projectInfo = info

        // Auto-select first scheme if none selected
        if let info, buildController.selectedScheme(for: projectPath) == nil,
           let firstScheme = info.schemes.first {
            buildController.setSelectedScheme(firstScheme, for: projectPath)
        }

        // Auto-select Mac for macOS projects with no destinations
        if let info, selectedDestinations.isEmpty {
            if info.platformHint == .macOS {
                buildController.addDestination(.myMac, for: projectPath)
            }
        }

        await refreshDestinations()
    }

    private func refreshDestinations() async {
        isLoadingDestinations = true
        let simulators = await XcodeProjectDetector.shared.availableSimulators()

        var grouped: [DestinationGroup: [BuildDestination]] = [:]
        for sim in simulators {
            grouped[sim.group, default: []].append(sim)
        }
        availableDestinations = grouped
        isLoadingDestinations = false
    }
}

//
//  SimulatorRunsStripView.swift
//  Dispatch
//
//  Horizontal scrollable strip of simulator run cards for project tab
//

import SwiftData
import SwiftUI

struct SimulatorRunsStripView: View {
    // MARK: - Properties

    let project: Project?

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var simulatorVM: SimulatorViewModel

    // MARK: - State

    @State private var runs: [SimulatorRun] = []

    // MARK: - Body

    var body: some View {
        Group {
            if !runs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Section header
                    HStack {
                        Label("Screenshot Runs", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(runs.count) run\(runs.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)

                    runStrip
                }
            }
        }
        .onAppear {
            fetchRuns()
        }
        .onChange(of: project) { _, _ in
            fetchRuns()
        }
    }

    // MARK: - Run Strip

    private var runStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(runs) { run in
                    SimulatorRunCard(run: run)
                        .onTapGesture {
                            openAnnotationWindow(for: run)
                        }
                        .contextMenu {
                            runContextMenu(for: run)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .frame(height: 140)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func runContextMenu(for run: SimulatorRun) -> some View {
        Button {
            openAnnotationWindow(for: run)
        } label: {
            Label("Open in Annotation Window", systemImage: "pencil.and.outline")
        }

        Divider()

        Button(role: .destructive) {
            deleteRun(run)
        } label: {
            Label("Delete Run", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func openAnnotationWindow(for run: SimulatorRun) {
        AnnotationWindowController.shared.open(run: run)
    }

    // MARK: - Data

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

        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        runs = fetched.filter { $0.screenshotCount > 0 }
        logDebug("Fetched \(fetched.count) runs, \(runs.count) with screenshots for strip view", category: .simulator)
    }

    private func deleteRun(_ run: SimulatorRun) {
        simulatorVM.deleteRun(run)
        fetchRuns()
    }
}

// MARK: - Simulator Run Card

struct SimulatorRunCard: View {
    let run: SimulatorRun

    // MARK: - State

    @State private var thumbnail: NSImage?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail preview
            thumbnailView
                .frame(width: 160, height: 90)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Run info
            VStack(alignment: .leading, spacing: 2) {
                Text(run.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(run.screenshotCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(run.relativeCreatedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .frame(width: 160)
        .onAppear {
            loadThumbnail()
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 160, height: 90)
                .clipped()
        } else {
            // Placeholder
            VStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.title2)
                    .foregroundStyle(.quaternary)

                Text("\(run.screenshotCount) screenshots")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func loadThumbnail() {
        guard thumbnail == nil,
              let firstScreenshot = run.thumbnailScreenshot else { return }

        Task.detached(priority: .userInitiated) {
            let image = firstScreenshot.thumbnail
            await MainActor.run {
                self.thumbnail = image
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SimulatorRunsStripView(project: nil)
        .environmentObject(SimulatorViewModel.shared)
        .frame(height: 200)
}

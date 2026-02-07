//
//  SimulatorViewModel.swift
//  Dispatch
//
//  ViewModel for managing simulator screenshot runs
//

import AppKit
import Combine
import Foundation
import SwiftData
import SwiftUI

// MARK: - Simulator ViewModel

@MainActor
final class SimulatorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var runs: [SimulatorRun] = []
    @Published var selectedRun: SimulatorRun?
    @Published var selectedScreenshot: Screenshot?
    @Published var isLoading: Bool = false
    @Published var error: String?

    // Filter/display options
    @Published var currentProject: Project?
    @Published var showHiddenScreenshots: Bool = false

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    static let shared = SimulatorViewModel()

    private init() {}

    func configure(with context: ModelContext) {
        modelContext = context
        logDebug("SimulatorViewModel configured with ModelContext", category: .simulator)
    }

    // MARK: - Fetch

    /// Fetches runs for a specific project
    func fetchRuns(for project: Project?) {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .simulator)
            return
        }

        currentProject = project
        isLoading = true

        Task {
            do {
                var descriptor = FetchDescriptor<SimulatorRun>()
                descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]

                if let project = project {
                    let projectId = project.id
                    descriptor.predicate = #Predicate<SimulatorRun> { run in
                        run.project?.id == projectId
                    }
                }

                let results = try context.fetch(descriptor)

                await MainActor.run {
                    self.runs = results
                    self.isLoading = false
                    logDebug("Fetched \(results.count) runs for project: \(project?.name ?? "all")", category: .simulator)
                }

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    logError("Failed to fetch runs: \(error)", category: .simulator)
                }
            }
        }
    }

    /// Fetches all runs across all projects
    func fetchAllRuns() {
        fetchRuns(for: nil)
    }

    /// Refreshes the current fetch
    func refresh() {
        fetchRuns(for: currentProject)
    }

    // MARK: - Selection

    func selectRun(_ run: SimulatorRun?) {
        selectedRun = run
        selectedScreenshot = nil

        if let run = run {
            logDebug("Selected run: \(run.displayName)", category: .simulator)
        }
    }

    func selectScreenshot(_ screenshot: Screenshot?) {
        selectedScreenshot = screenshot

        if let screenshot = screenshot {
            logDebug("Selected screenshot: \(screenshot.displayLabel)", category: .simulator)
        }
    }

    func selectNextScreenshot() {
        guard let run = selectedRun else { return }

        let screenshots = filteredScreenshots(for: run)
        guard !screenshots.isEmpty else { return }

        if let current = selectedScreenshot,
           let currentIndex = screenshots.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = min(currentIndex + 1, screenshots.count - 1)
            selectedScreenshot = screenshots[nextIndex]
        } else {
            selectedScreenshot = screenshots.first
        }
    }

    func selectPreviousScreenshot() {
        guard let run = selectedRun else { return }

        let screenshots = filteredScreenshots(for: run)
        guard !screenshots.isEmpty else { return }

        if let current = selectedScreenshot,
           let currentIndex = screenshots.firstIndex(where: { $0.id == current.id }) {
            let prevIndex = max(currentIndex - 1, 0)
            selectedScreenshot = screenshots[prevIndex]
        } else {
            selectedScreenshot = screenshots.last
        }
    }

    // MARK: - Filtering

    /// Returns screenshots for a run, filtered based on visibility settings
    func filteredScreenshots(for run: SimulatorRun) -> [Screenshot] {
        let sorted = run.sortedScreenshots

        if showHiddenScreenshots {
            return sorted
        } else {
            return sorted.filter { !$0.isHidden }
        }
    }

    /// Returns visible screenshot count for a run
    func visibleScreenshotCount(for run: SimulatorRun) -> Int {
        run.screenshots.filter { !$0.isHidden }.count
    }

    // MARK: - Screenshot Actions

    /// Toggles the hidden state of a screenshot
    func toggleScreenshotHidden(_ screenshot: Screenshot) {
        screenshot.toggleHidden()
        saveContext()

        logDebug("Toggled screenshot hidden: \(screenshot.isHidden)", category: .simulator)
    }

    /// Sets a label on a screenshot
    func setScreenshotLabel(_ screenshot: Screenshot, label: String?) {
        screenshot.setLabel(label)
        saveContext()
    }

    // MARK: - Run Actions

    /// Deletes a run and all its screenshots
    func deleteRun(_ run: SimulatorRun) {
        guard let context = modelContext else { return }

        // Delete screenshot files first
        for screenshot in run.screenshots {
            screenshot.deleteFile()
        }

        // Delete the run directory
        if let projectName = run.project?.name {
            Task {
                try? await ScreenshotWatcherService.shared.deleteRunDirectory(
                    runId: run.id,
                    projectName: projectName
                )
            }
        }

        // Delete from database
        context.delete(run)
        saveContext()

        if selectedRun?.id == run.id {
            selectedRun = nil
            selectedScreenshot = nil
        }

        refresh()
        logInfo("Deleted run: \(run.displayName)", category: .simulator)
    }

    /// Marks a run as complete
    func markRunComplete(_ run: SimulatorRun) {
        run.markComplete()
        saveContext()
    }

    // MARK: - Computed Properties

    var count: Int {
        runs.count
    }

    var isEmpty: Bool {
        runs.isEmpty
    }

    /// Returns runs grouped by project
    var runsByProject: [(project: Project?, runs: [SimulatorRun])] {
        let grouped = Dictionary(grouping: runs) { $0.project }

        return grouped
            .sorted { ($0.key?.name ?? "") < ($1.key?.name ?? "") }
            .map { (project: $0.key, runs: $0.value) }
    }

    /// Returns the most recent runs (for dashboard display)
    var recentRuns: [SimulatorRun] {
        Array(runs.prefix(5))
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .simulator)
        }
    }
}

// MARK: - Annotation ViewModel

/// ViewModel for the annotation window
@MainActor
final class AnnotationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var activeImage: AnnotatedImage?
    @Published var sendQueue: [AnnotatedImage] = []
    @Published var currentTool: AnnotationTool = .crop
    @Published var currentColor: AnnotationColor = .red
    @Published var promptText: String = ""
    @Published var isDrawing: Bool = false

    // Canvas state
    @Published var zoomLevel: CGFloat = 1.0
    @Published var panOffset: CGPoint = .zero

    // Crop state
    @Published var cropRect: CGRect?
    @Published var isCropping: Bool = false

    // MARK: - Private Properties

    private let undoManager = AnnotationUndoManager()
    private let maxQueueSize = 5

    // MARK: - Computed Properties

    var canUndo: Bool {
        undoManager.canUndo
    }

    var canRedo: Bool {
        undoManager.canRedo
    }

    var queueCount: Int {
        sendQueue.count
    }

    var canAddToQueue: Bool {
        sendQueue.count < maxQueueSize
    }

    var hasQueuedImages: Bool {
        !sendQueue.isEmpty
    }

    // MARK: - Image Loading

    func loadScreenshot(_ screenshot: Screenshot) {
        activeImage = AnnotatedImage(screenshot: screenshot)
        resetCanvas()
        logDebug("Loaded screenshot into annotation view: \(screenshot.displayLabel)", category: .simulator)
    }

    func loadAnnotatedImage(_ image: AnnotatedImage) {
        activeImage = image
        resetCanvas()
    }

    // MARK: - Annotation Actions

    func addAnnotation(_ annotation: Annotation) {
        guard var image = activeImage else { return }

        image.addAnnotation(annotation)
        activeImage = image

        undoManager.recordAction(.addAnnotation(annotation))

        // Auto-add to queue if not already queued
        addToQueueIfNeeded()
    }

    func removeAnnotation(id: UUID) {
        guard var image = activeImage else { return }

        if let annotation = image.annotations.first(where: { $0.id == id }) {
            image.removeAnnotation(id: id)
            activeImage = image

            undoManager.recordAction(.removeAnnotation(annotation))
        }
    }

    func clearAnnotations() {
        guard var image = activeImage else { return }

        let cleared = image.annotations
        image.clearAnnotations()
        activeImage = image

        if !cleared.isEmpty {
            undoManager.recordAction(.clearAnnotations(cleared))
        }
    }

    // MARK: - Crop Actions

    func applyCrop(_ rect: CGRect) {
        guard var image = activeImage else { return }

        let oldCrop = image.cropRect
        image.setCrop(rect)
        activeImage = image

        undoManager.recordAction(.setCrop(old: oldCrop, new: rect))

        // Auto-add to queue if not already queued
        addToQueueIfNeeded()
    }

    func clearCrop() {
        guard var image = activeImage else { return }

        let oldCrop = image.cropRect
        image.setCrop(nil)
        activeImage = image

        if oldCrop != nil {
            undoManager.recordAction(.setCrop(old: oldCrop, new: nil))
        }
    }

    // MARK: - Undo/Redo

    func undo() {
        guard var image = activeImage,
              let action = undoManager.popUndo() else { return }

        applyInverseAction(action, to: &image)
        activeImage = image
    }

    func redo() {
        guard var image = activeImage,
              let action = undoManager.popRedo() else { return }

        applyAction(action, to: &image)
        activeImage = image
    }

    private func applyAction(_ action: AnnotationAction, to image: inout AnnotatedImage) {
        switch action {
        case let .addAnnotation(annotation):
            image.addAnnotation(annotation)
        case let .removeAnnotation(annotation):
            image.removeAnnotation(id: annotation.id)
        case let .setCrop(_, new):
            image.setCrop(new)
        case .clearAnnotations:
            image.clearAnnotations()
        }
    }

    private func applyInverseAction(_ action: AnnotationAction, to image: inout AnnotatedImage) {
        applyAction(action.inverse, to: &image)

        // Special case: clearAnnotations needs to restore all annotations
        if case let .clearAnnotations(annotations) = action {
            for annotation in annotations {
                image.addAnnotation(annotation)
            }
        }
    }

    // MARK: - Queue Management

    func addToQueue(_ image: AnnotatedImage) {
        guard sendQueue.count < maxQueueSize else {
            logWarning("Queue full, cannot add more images", category: .simulator)
            return
        }

        // Check if already in queue
        if !sendQueue.contains(where: { $0.id == image.id }) {
            sendQueue.append(image)
            logDebug("Added image to queue, count: \(sendQueue.count)", category: .simulator)
        }
    }

    func removeFromQueue(id: UUID) {
        sendQueue.removeAll { $0.id == id }
        logDebug("Removed image from queue, count: \(sendQueue.count)", category: .simulator)
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < sendQueue.count else { return }
        sendQueue.remove(at: index)
    }

    func clearQueue() {
        sendQueue.removeAll()
        logDebug("Cleared send queue", category: .simulator)
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        sendQueue.move(fromOffsets: source, toOffset: destination)
    }

    /// Adds active image to queue if it has modifications and isn't already queued
    private func addToQueueIfNeeded() {
        guard let image = activeImage,
              image.hasModifications,
              canAddToQueue else { return }

        addToQueue(image)
    }

    // MARK: - Canvas Controls

    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.25, 5.0)
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.25, 0.25)
    }

    func resetZoom() {
        zoomLevel = 1.0
        panOffset = .zero
    }

    func resetCanvas() {
        zoomLevel = 1.0
        panOffset = .zero
        cropRect = nil
        isCropping = false
        undoManager.clear()
    }

    // MARK: - Tool Selection

    func selectTool(_ tool: AnnotationTool) {
        currentTool = tool
        isCropping = (tool == .crop)
        logDebug("Selected tool: \(tool.displayName)", category: .simulator)
    }

    func selectColor(_ color: AnnotationColor) {
        currentColor = color
        logDebug("Selected color: \(color.rawValue)", category: .simulator)
    }

    // MARK: - Dispatch

    /// Prepares images for dispatch and returns the rendered images
    func prepareForDispatch() async -> [NSImage] {
        await AnnotationRenderer.shared.renderBatch(sendQueue)
    }

    /// Copies queued images to clipboard
    func copyToClipboard() async -> Bool {
        await AnnotationRenderer.shared.copyToClipboard(sendQueue)
    }

    /// Clears state after successful dispatch
    func handleDispatchComplete() {
        clearQueue()
        promptText = ""
        logInfo("Dispatch complete, cleared queue", category: .simulator)
    }
}

//
//  ScreenshotCaptureService.swift
//  Dispatch
//
//  Service for capturing screenshots using native macOS screencapture CLI
//

import AppKit
import Foundation
import ScreenCaptureKit

// MARK: - Capture Result

/// Result of a screenshot capture operation
enum CaptureResult {
    case success(URL) // Path to saved screenshot
    case cancelled // User pressed Escape
    case error(Error) // screencapture failed
}

// MARK: - Capture Error

/// Errors that can occur during capture operations
enum CaptureError: Error {
    case pngConversionFailed
    case captureDirectoryCreationFailed
}

// MARK: - Screenshot Capture Service

/// Service for capturing screenshots via native macOS screencapture CLI
@MainActor
final class ScreenshotCaptureService: NSObject, SCContentSharingPickerObserver {
    static let shared = ScreenshotCaptureService()

    // MARK: - Properties

    /// QuickCaptures directory in Application Support
    private let capturesDirectory: URL

    /// Shared content sharing picker for window capture
    private let picker = SCContentSharingPicker.shared

    /// Continuation for window capture async operation
    private var windowCaptureContinuation: CheckedContinuation<CaptureResult, Never>?

    // MARK: - Initialization

    override private init() {
        // Initialize capturesDirectory to ~/Library/Application Support/Dispatch/QuickCaptures/
        // Uses same pattern as ScreenshotWatcherService.ScreenshotDirectoryConfig.defaultBaseDirectory
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dispatch/QuickCaptures", isDirectory: true)

        capturesDirectory = baseDirectory

        logDebug("ScreenshotCaptureService initialized with directory: \(capturesDirectory.path)", category: .capture)
    }

    // MARK: - Window Capture

    /// Captures a window selected by the user using SCContentSharingPicker
    /// - Returns: CaptureResult indicating success, cancellation, or error
    func captureWindow() async -> CaptureResult {
        logDebug("Starting window capture", category: .capture)

        return await withCheckedContinuation { continuation in
            // Store continuation for later resume
            windowCaptureContinuation = continuation

            // Add self as observer
            picker.add(self)

            // Configure picker
            picker.isActive = true

            logDebug("Presenting SCContentSharingPicker for window selection", category: .capture)

            // Present picker
            picker.present()
        }
    }

    // MARK: - SCContentSharingPickerObserver

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for _: SCStream?
    ) {
        Task { @MainActor in
            logDebug("Window selected in picker", category: .capture)

            do {
                let url = try await captureWithFilter(filter)
                windowCaptureContinuation?.resume(returning: .success(url))
            } catch {
                logError("Failed to capture window: \(error)", category: .capture)
                windowCaptureContinuation?.resume(returning: .error(error))
            }

            windowCaptureContinuation = nil
            picker.remove(self)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            logError("Picker failed to start: \(error)", category: .capture)
            windowCaptureContinuation?.resume(returning: .error(error))
            windowCaptureContinuation = nil
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor _: SCStream?
    ) {
        Task { @MainActor in
            logInfo("Window capture cancelled by user", category: .capture)
            windowCaptureContinuation?.resume(returning: .cancelled)
            windowCaptureContinuation = nil
            picker.remove(self)
        }
    }

    // MARK: - Region Capture

    /// Captures a region of the screen selected by the user
    /// - Returns: CaptureResult indicating success, cancellation, or error
    func captureRegion() async -> CaptureResult {
        logDebug("Starting region capture", category: .capture)

        // 1. Ensure QuickCaptures directory exists
        do {
            try ensureCapturesDirectoryExists()
        } catch {
            logError("Failed to create captures directory: \(error)", category: .capture)
            return .error(error)
        }

        // 2. Generate unique filename: {UUID}.png
        let filename = "\(UUID().uuidString).png"
        let outputPath = capturesDirectory.appendingPathComponent(filename)

        logDebug("Capture output path: \(outputPath.path)", category: .capture)

        // 3. Invoke screencapture -i -x {path}
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-i", // Interactive (cross-hair selection)
            "-x", // No sound
            outputPath.path // Output path
        ]

        do {
            logDebug("Launching screencapture process", category: .capture)
            try process.run()
            process.waitUntilExit()

            logDebug("screencapture terminated with status: \(process.terminationStatus)", category: .capture)

            // 4. Check Process.terminationStatus and file existence
            if process.terminationStatus == 0 {
                // Check if file was created
                if FileManager.default.fileExists(atPath: outputPath.path) {
                    logInfo("Region captured successfully: \(filename)", category: .capture)
                    return .success(outputPath)
                } else {
                    // Status 0 but no file = user pressed Escape
                    logInfo("Region capture cancelled by user", category: .capture)
                    return .cancelled
                }
            } else {
                // Non-zero status = error
                let error = NSError(
                    domain: "ScreenshotCaptureService",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "screencapture exited with status \(process.terminationStatus)"]
                )
                logError("Region capture failed with status \(process.terminationStatus)", category: .capture)
                return .error(error)
            }
        } catch {
            logError("Failed to launch screencapture: \(error)", category: .capture)
            return .error(error)
        }
    }

    // MARK: - Private Helpers

    /// Captures a window using SCScreenshotManager with the given filter
    /// - Parameter filter: Content filter for the window to capture
    /// - Returns: URL of the saved PNG file
    private func captureWithFilter(_ filter: SCContentFilter) async throws -> URL {
        logDebug("Capturing window with filter", category: .capture)

        // 1. Ensure QuickCaptures directory exists
        try ensureCapturesDirectoryExists()

        // 2. Configure stream configuration
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.width = Int(Float(filter.contentRect.width) * filter.pointPixelScale)
        config.height = Int(Float(filter.contentRect.height) * filter.pointPixelScale)

        logDebug("Capture dimensions: \(config.width)x\(config.height)", category: .capture)

        // 3. Capture image
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        logDebug("Window captured as CGImage", category: .capture)

        // 4. Generate filename and save
        let filename = "\(UUID().uuidString).png"
        let outputPath = capturesDirectory.appendingPathComponent(filename)

        try saveCGImageAsPNG(cgImage, to: outputPath)

        logInfo("Window captured successfully: \(filename)", category: .capture)

        return outputPath
    }

    /// Saves a CGImage as a PNG file
    /// - Parameters:
    ///   - cgImage: The image to save
    ///   - url: The destination URL
    private func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL) throws {
        logDebug("Saving CGImage as PNG to: \(url.path)", category: .capture)

        // Create bitmap representation from CGImage
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        // Get PNG data
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            logError("Failed to convert CGImage to PNG data", category: .capture)
            throw CaptureError.pngConversionFailed
        }

        // Write to file
        try pngData.write(to: url)

        logDebug("PNG saved successfully", category: .capture)
    }

    /// Ensures the QuickCaptures directory exists, creating it if needed
    private func ensureCapturesDirectoryExists() throws {
        let path = capturesDirectory.path
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                at: capturesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logInfo("Created QuickCaptures directory: \(path)", category: .capture)
        }
    }
}

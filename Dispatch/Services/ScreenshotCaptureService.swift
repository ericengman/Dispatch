//
//  ScreenshotCaptureService.swift
//  Dispatch
//
//  Service for capturing screenshots using native macOS screencapture CLI
//

import Foundation

// MARK: - Capture Result

/// Result of a screenshot capture operation
enum CaptureResult {
    case success(URL) // Path to saved screenshot
    case cancelled // User pressed Escape
    case error(Error) // screencapture failed
}

// MARK: - Screenshot Capture Service

/// Service for capturing screenshots via native macOS screencapture CLI
@MainActor
final class ScreenshotCaptureService {
    static let shared = ScreenshotCaptureService()

    // MARK: - Properties

    /// QuickCaptures directory in Application Support
    private let capturesDirectory: URL

    // MARK: - Initialization

    private init() {
        // Initialize capturesDirectory to ~/Library/Application Support/Dispatch/QuickCaptures/
        // Uses same pattern as ScreenshotWatcherService.ScreenshotDirectoryConfig.defaultBaseDirectory
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dispatch/QuickCaptures", isDirectory: true)

        capturesDirectory = baseDirectory

        logDebug("ScreenshotCaptureService initialized with directory: \(capturesDirectory.path)", category: .capture)
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

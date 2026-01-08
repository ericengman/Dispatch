//
//  HookInstaller.swift
//  Dispatch
//
//  Service for installing/uninstalling Claude Code completion hooks
//

import Foundation
import Combine

// MARK: - Hook Installation Status

enum HookInstallationStatus: Sendable {
    case installed
    case notInstalled
    case outdated
    case error(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

// MARK: - Hook Installer

/// Service for managing Claude Code hook installation
actor HookInstaller {
    static let shared = HookInstaller()

    // MARK: - Properties

    private let hookDirectory: URL
    private let hookFileName = "post-tool-use.sh"
    private let hookMarker = "# Dispatch completion notification hook"
    private let dispatchVersion = "1.0"

    // MARK: - Initialization

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.hookDirectory = home.appendingPathComponent(".claude/hooks", isDirectory: true)

        logDebug("HookInstaller initialized, hook directory: \(hookDirectory.path)", category: .hooks)
    }

    // MARK: - Status Check

    /// Checks the current installation status
    func checkStatus() -> HookInstallationStatus {
        let hookPath = hookDirectory.appendingPathComponent(hookFileName)

        guard FileManager.default.fileExists(atPath: hookPath.path) else {
            logDebug("Hook not installed (file doesn't exist)", category: .hooks)
            return .notInstalled
        }

        do {
            let content = try String(contentsOf: hookPath, encoding: .utf8)

            // Check if this is our hook
            guard content.contains(hookMarker) else {
                logDebug("Hook file exists but not from Dispatch", category: .hooks)
                return .notInstalled
            }

            // Check version
            if content.contains("Dispatch v\(dispatchVersion)") {
                logDebug("Hook installed and up to date", category: .hooks)
                return .installed
            } else if content.contains("Dispatch v") {
                logDebug("Hook installed but outdated", category: .hooks)
                return .outdated
            }

            return .installed

        } catch {
            logError("Failed to read hook file: \(error)", category: .hooks)
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Installation

    /// Installs the Claude Code completion hook
    func install(port: Int = 19847) throws {
        logInfo("Installing Claude Code hook on port \(port)", category: .hooks)

        // Create hooks directory if needed
        try FileManager.default.createDirectory(
            at: hookDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let hookPath = hookDirectory.appendingPathComponent(hookFileName)
        let hookContent = generateHookScript(port: port)

        // Check if file exists and might have other content
        if FileManager.default.fileExists(atPath: hookPath.path) {
            let existingContent = try? String(contentsOf: hookPath, encoding: .utf8)

            if let existing = existingContent, !existing.contains(hookMarker) {
                // File exists with other content - append our hook
                logInfo("Appending to existing hook file", category: .hooks)
                let updatedContent = existing + "\n\n" + hookContent
                try updatedContent.write(to: hookPath, atomically: true, encoding: .utf8)
            } else {
                // Our hook or empty - replace
                try hookContent.write(to: hookPath, atomically: true, encoding: .utf8)
            }
        } else {
            // New file
            try hookContent.write(to: hookPath, atomically: true, encoding: .utf8)
        }

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookPath.path
        )

        logInfo("Hook installed successfully at \(hookPath.path)", category: .hooks)
    }

    /// Uninstalls the Claude Code completion hook
    func uninstall() throws {
        logInfo("Uninstalling Claude Code hook", category: .hooks)

        let hookPath = hookDirectory.appendingPathComponent(hookFileName)

        guard FileManager.default.fileExists(atPath: hookPath.path) else {
            logDebug("Hook file doesn't exist, nothing to uninstall", category: .hooks)
            return
        }

        let content = try String(contentsOf: hookPath, encoding: .utf8)

        // Check if file has other content besides our hook
        let lines = content.components(separatedBy: "\n")
        var ourHookLines: Set<Int> = []
        var inOurBlock = false
        var blockStart = -1

        for (index, line) in lines.enumerated() {
            if line.contains(hookMarker) {
                inOurBlock = true
                blockStart = index
            }

            if inOurBlock {
                ourHookLines.insert(index)

                // End of our block (empty line or EOF after curl command)
                if line.isEmpty || (index > blockStart && !line.hasPrefix("#") && !line.hasPrefix("curl") && !line.contains("||")) {
                    if !line.isEmpty {
                        ourHookLines.remove(index)
                    }
                    inOurBlock = false
                }
            }
        }

        if ourHookLines.count == lines.count || ourHookLines.count >= lines.count - 2 {
            // Our hook is the only content - remove the file
            try FileManager.default.removeItem(at: hookPath)
            logInfo("Hook file removed completely", category: .hooks)
        } else {
            // Other content exists - remove only our hook
            let remainingLines = lines.enumerated()
                .filter { !ourHookLines.contains($0.offset) }
                .map { $0.element }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if remainingLines.isEmpty {
                try FileManager.default.removeItem(at: hookPath)
            } else {
                try remainingLines.write(to: hookPath, atomically: true, encoding: .utf8)
            }
            logInfo("Dispatch hook removed, other hooks preserved", category: .hooks)
        }
    }

    /// Updates the hook with a new port
    func updatePort(_ port: Int) throws {
        let status = checkStatus()

        switch status {
        case .installed, .outdated:
            try uninstall()
            try install(port: port)
            logInfo("Hook updated with new port: \(port)", category: .hooks)

        case .notInstalled:
            try install(port: port)

        case .error(let message):
            throw HookInstallerError.updateFailed(message)
        }
    }

    // MARK: - Hook Script Generation

    private func generateHookScript(port: Int) -> String {
        """
        #!/bin/bash
        \(hookMarker)
        # Dispatch v\(dispatchVersion)
        # Notifies Dispatch app when Claude Code completes a response

        curl -s -X POST "http://localhost:\(port)/hook/complete" \\
          -H "Content-Type: application/json" \\
          -d "{\\"session\\": \\"$CLAUDE_SESSION_ID\\", \\"timestamp\\": \\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\\"}" \\
          2>/dev/null || true
        """
    }

    // MARK: - Verification

    /// Verifies the hook is working by checking file permissions and content
    func verify() -> HookVerificationResult {
        let hookPath = hookDirectory.appendingPathComponent(hookFileName)

        guard FileManager.default.fileExists(atPath: hookPath.path) else {
            return HookVerificationResult(
                success: false,
                issues: ["Hook file not found"]
            )
        }

        var issues: [String] = []

        // Check permissions
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: hookPath.path)
            if let permissions = attributes[.posixPermissions] as? Int {
                if permissions & 0o111 == 0 {
                    issues.append("Hook file is not executable")
                }
            }
        } catch {
            issues.append("Could not check file permissions: \(error.localizedDescription)")
        }

        // Check content
        do {
            let content = try String(contentsOf: hookPath, encoding: .utf8)

            if !content.contains("#!/bin/bash") && !content.contains("#!/bin/sh") {
                issues.append("Hook file missing shebang")
            }

            if !content.contains(hookMarker) {
                issues.append("Hook file missing Dispatch marker")
            }

            if !content.contains("curl") {
                issues.append("Hook file missing curl command")
            }

        } catch {
            issues.append("Could not read hook file: \(error.localizedDescription)")
        }

        let success = issues.isEmpty
        if success {
            logDebug("Hook verification passed", category: .hooks)
        } else {
            logWarning("Hook verification issues: \(issues)", category: .hooks)
        }

        return HookVerificationResult(success: success, issues: issues)
    }

    /// Gets the hook file path for display
    func getHookPath() -> String {
        hookDirectory.appendingPathComponent(hookFileName).path
    }
}

// MARK: - Verification Result

struct HookVerificationResult: Sendable {
    let success: Bool
    let issues: [String]
}

// MARK: - Hook Installer Errors

enum HookInstallerError: Error, LocalizedError {
    case installFailed(String)
    case uninstallFailed(String)
    case updateFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .installFailed(let message):
            return "Failed to install hook: \(message)"
        case .uninstallFailed(let message):
            return "Failed to uninstall hook: \(message)"
        case .updateFailed(let message):
            return "Failed to update hook: \(message)"
        case .permissionDenied:
            return "Permission denied when accessing hook file"
        }
    }
}

// MARK: - Hook Installer Manager (MainActor)

/// MainActor wrapper for UI integration
@MainActor
final class HookInstallerManager: ObservableObject {
    static let shared = HookInstallerManager()

    @Published private(set) var status: HookInstallationStatus = .notInstalled
    @Published private(set) var isInstalling: Bool = false
    @Published private(set) var lastError: String?

    private init() {
        Task {
            await refreshStatus()
        }
        logDebug("HookInstallerManager initialized", category: .hooks)
    }

    func refreshStatus() async {
        status = await HookInstaller.shared.checkStatus()
    }

    func install(port: Int = 19847) async {
        isInstalling = true
        lastError = nil

        do {
            try await HookInstaller.shared.install(port: port)
            await refreshStatus()
            logInfo("Hook installed successfully", category: .hooks)
        } catch {
            lastError = error.localizedDescription
            logError("Hook installation failed: \(error)", category: .hooks)
        }

        isInstalling = false
    }

    func uninstall() async {
        isInstalling = true
        lastError = nil

        do {
            try await HookInstaller.shared.uninstall()
            await refreshStatus()
            logInfo("Hook uninstalled successfully", category: .hooks)
        } catch {
            lastError = error.localizedDescription
            logError("Hook uninstallation failed: \(error)", category: .hooks)
        }

        isInstalling = false
    }

    func updatePort(_ port: Int) async {
        isInstalling = true
        lastError = nil

        do {
            try await HookInstaller.shared.updatePort(port)
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }

        isInstalling = false
    }

    func verify() async -> HookVerificationResult {
        await HookInstaller.shared.verify()
    }

    func getHookPath() async -> String {
        await HookInstaller.shared.getHookPath()
    }
}

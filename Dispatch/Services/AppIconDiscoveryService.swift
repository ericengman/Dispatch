//
//  AppIconDiscoveryService.swift
//  Dispatch
//
//  Discovers app icons from Xcode project asset catalogs
//

import Foundation

actor AppIconDiscoveryService {
    static let shared = AppIconDiscoveryService()

    /// Directories to skip during search
    private let skipDirectoryNames: Set<String> = [
        "node_modules", "Pods", "Carthage", "build", "Build",
        "DerivedData", ".git", "vendor", "venv", "__pycache__"
    ]

    /// Common relative locations to check first before recursive search
    private let commonAssetPaths: [String] = [
        "Assets.xcassets",
        "Resources/Assets.xcassets"
    ]

    // MARK: - Public API

    /// Discovers the app icon for a project at the given path.
    /// Returns PNG data for the best icon found, or nil.
    func discoverIcon(at projectPath: String) -> Data? {
        let projectURL = URL(fileURLWithPath: projectPath)
        let projectName = projectURL.lastPathComponent

        logDebug("Searching for app icon in: \(projectPath)", category: .data)

        // 1. Check common locations first (fast path)
        let commonLocations = commonAssetPaths + [
            "\(projectName)/Assets.xcassets"
        ]

        for relativePath in commonLocations {
            let assetCatalogURL = projectURL.appendingPathComponent(relativePath)
            let appIconSetURL = assetCatalogURL.appendingPathComponent("AppIcon.appiconset")
            if let data = loadBestIcon(from: appIconSetURL) {
                logDebug("Found app icon at common path: \(relativePath)", category: .data)
                return data
            }
        }

        // 2. Recursive search (up to 3 levels)
        if let data = searchForAppIcon(in: projectURL, currentDepth: 0, maxDepth: 3) {
            return data
        }

        logDebug("No app icon found for project at: \(projectPath)", category: .data)
        return nil
    }

    // MARK: - Private

    /// Recursively searches for AppIcon.appiconset within .xcassets directories
    private func searchForAppIcon(in directory: URL, currentDepth: Int, maxDepth: Int) -> Data? {
        guard currentDepth <= maxDepth else { return nil }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for item in contents {
            let name = item.lastPathComponent

            // Skip excluded directories
            if skipDirectoryNames.contains(name) || name.hasPrefix(".") {
                continue
            }

            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }

            // Check if this is an xcassets directory
            if name.hasSuffix(".xcassets") {
                let appIconSetURL = item.appendingPathComponent("AppIcon.appiconset")
                if let data = loadBestIcon(from: appIconSetURL) {
                    logDebug("Found app icon via recursive search: \(item.path)", category: .data)
                    return data
                }
            }

            // Recurse into subdirectories
            if let data = searchForAppIcon(in: item, currentDepth: currentDepth + 1, maxDepth: maxDepth) {
                return data
            }
        }

        return nil
    }

    /// Loads the best icon from an AppIcon.appiconset directory by parsing Contents.json
    private func loadBestIcon(from appIconSetURL: URL) -> Data? {
        let contentsURL = appIconSetURL.appendingPathComponent("Contents.json")
        let fm = FileManager.default

        guard fm.fileExists(atPath: contentsURL.path),
              let jsonData = try? Data(contentsOf: contentsURL)
        else {
            return nil
        }

        guard let contents = try? JSONDecoder().decode(AssetContents.self, from: jsonData) else {
            logWarning("Failed to parse Contents.json at: \(contentsURL.path)", category: .data)
            return nil
        }

        // Find the best icon: prefer ~128px for retina sidebar display
        let bestFilename = selectBestIcon(from: contents.images)

        guard let filename = bestFilename else {
            return nil
        }

        let iconURL = appIconSetURL.appendingPathComponent(filename)
        guard let iconData = try? Data(contentsOf: iconURL) else {
            logWarning("Icon file not readable: \(iconURL.path)", category: .data)
            return nil
        }

        return iconData
    }

    /// Selects the best icon filename from the asset catalog images array.
    /// Prefers sizes around 128px, falls back to the largest available.
    private func selectBestIcon(from images: [AssetImage]) -> String? {
        // Filter to images that have actual files
        let available = images.filter { $0.filename != nil && !$0.filename!.isEmpty }

        guard !available.isEmpty else { return nil }

        // Parse sizes and sort by preference (closest to 128 first, then largest)
        let scored = available.compactMap { image -> (String, Double)? in
            guard let filename = image.filename else { return nil }

            let size = parseSize(from: image)
            let scale = parseScale(from: image)
            let effectiveSize = size * scale

            return (filename, effectiveSize)
        }

        // Prefer icons closest to 128px (for crisp sidebar at retina)
        if let best = scored.min(by: { abs($0.1 - 128) < abs($1.1 - 128) }) {
            return best.0
        }

        // Fallback: any available file
        return available.first?.filename
    }

    private func parseSize(from image: AssetImage) -> Double {
        guard let sizeStr = image.size else { return 0 }
        // Format: "128x128" or "64x64"
        let parts = sizeStr.split(separator: "x")
        return Double(parts.first ?? "0") ?? 0
    }

    private func parseScale(from image: AssetImage) -> Double {
        guard let scaleStr = image.scale else { return 1 }
        // Format: "1x", "2x", "3x"
        let cleaned = scaleStr.replacingOccurrences(of: "x", with: "")
        return Double(cleaned) ?? 1
    }
}

// MARK: - Contents.json Models

private struct AssetContents: Decodable {
    let images: [AssetImage]
}

private struct AssetImage: Decodable {
    let filename: String?
    let size: String?
    let scale: String?
}

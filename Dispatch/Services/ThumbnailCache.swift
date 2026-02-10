//
//  ThumbnailCache.swift
//  Dispatch
//
//  Fast thumbnail generation with CGImageSource and NSCache.
//

import AppKit
import Foundation
import ImageIO

/// Actor-based thumbnail cache with fast generation using CGImageSource.
/// Uses NSCache for automatic memory management.
actor ThumbnailCache {
    // MARK: - Singleton

    static let shared = ThumbnailCache()

    // MARK: - Properties

    private let cache: NSCache<NSString, NSImage>
    private let maxPixelSize: CGFloat = 120

    // MARK: - Initialization

    private init() {
        cache = NSCache()
        cache.countLimit = 50
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }

    // MARK: - Public API

    /// Generates or retrieves a cached thumbnail for the given capture.
    /// - Parameter capture: The QuickCapture to generate a thumbnail for.
    /// - Returns: The thumbnail image, or nil if generation failed.
    func thumbnail(for capture: QuickCapture) async -> NSImage? {
        let cacheKey = capture.filePath as NSString

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Generate thumbnail
        guard let thumbnail = generateThumbnail(for: capture.fileURL) else {
            return nil
        }

        // Calculate cost (estimated bytes: width * height * 4 bytes per pixel)
        let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
        cache.setObject(thumbnail, forKey: cacheKey, cost: cost)

        return thumbnail
    }

    /// Removes a cached thumbnail for the given capture.
    func invalidate(capture: QuickCapture) {
        let cacheKey = capture.filePath as NSString
        cache.removeObject(forKey: cacheKey)
    }

    /// Clears all cached thumbnails.
    func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func generateThumbnail(for url: URL) -> NSImage? {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        // Create image source
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // Configure thumbnail options
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        // Generate thumbnail
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Convert to NSImage
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}

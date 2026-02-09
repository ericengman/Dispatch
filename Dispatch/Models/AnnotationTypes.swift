//
//  AnnotationTypes.swift
//  Dispatch
//
//  Non-persisted types for screenshot annotation (in-memory only)
//

import AppKit
import Foundation
import SwiftUI

// MARK: - AnnotationType

/// The type of annotation drawn on a screenshot
enum AnnotationType: String, Codable, Sendable, CaseIterable, Identifiable {
    case freehand
    case arrow
    case rectangle
    case text

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .freehand: return "Draw"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .freehand: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "character.textbox"
        }
    }

    /// Keyboard shortcut key
    var shortcutKey: Character {
        switch self {
        case .freehand: return "d"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .text: return "t"
        }
    }
}

// MARK: - AnnotationTool

/// All available annotation tools including crop
enum AnnotationTool: String, Codable, Sendable, CaseIterable, Identifiable {
    case crop
    case freehand
    case arrow
    case rectangle
    case text

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .crop: return "Crop"
        case .freehand: return "Draw"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .crop: return "crop"
        case .freehand: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "character.textbox"
        }
    }

    /// Keyboard shortcut key
    var shortcutKey: Character {
        switch self {
        case .crop: return "c"
        case .freehand: return "d"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .text: return "t"
        }
    }

    /// Convert to AnnotationType (if not crop)
    var annotationType: AnnotationType? {
        switch self {
        case .crop: return nil
        case .freehand: return .freehand
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .text: return .text
        }
    }
}

// MARK: - AnnotationColor

/// Preset colors for annotations
enum AnnotationColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case white
    case black

    var id: String { rawValue }

    /// The SwiftUI Color value
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .white: return .white
        case .black: return .black
        }
    }

    /// NSColor for drawing operations
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .white: return .white
        case .black: return .black
        }
    }

    /// Keyboard shortcut (1-7)
    var shortcutNumber: Int {
        switch self {
        case .red: return 1
        case .orange: return 2
        case .yellow: return 3
        case .green: return 4
        case .blue: return 5
        case .white: return 6
        case .black: return 7
        }
    }

    /// Get color by shortcut number
    static func fromShortcut(_ number: Int) -> AnnotationColor? {
        allCases.first { $0.shortcutNumber == number }
    }
}

// MARK: - Annotation

/// A single annotation drawn on a screenshot
struct Annotation: Identifiable, Sendable {
    let id: UUID
    let type: AnnotationType
    let points: [CGPoint]
    let color: AnnotationColor
    let text: String?
    let lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        points: [CGPoint],
        color: AnnotationColor = .red,
        text: String? = nil,
        lineWidth: CGFloat = 3.0
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.color = color
        self.text = text
        self.lineWidth = lineWidth
    }

    /// Creates a freehand annotation from a series of points
    static func freehand(points: [CGPoint], color: AnnotationColor = .red, lineWidth: CGFloat = 3.0) -> Annotation {
        Annotation(type: .freehand, points: points, color: color, lineWidth: lineWidth)
    }

    /// Creates an arrow annotation from start to end point
    static func arrow(from start: CGPoint, to end: CGPoint, color: AnnotationColor = .red, lineWidth: CGFloat = 3.0) -> Annotation {
        Annotation(type: .arrow, points: [start, end], color: color, lineWidth: lineWidth)
    }

    /// Creates a rectangle annotation from two corner points
    static func rectangle(from corner1: CGPoint, to corner2: CGPoint, color: AnnotationColor = .red, lineWidth: CGFloat = 3.0) -> Annotation {
        Annotation(type: .rectangle, points: [corner1, corner2], color: color, lineWidth: lineWidth)
    }

    /// Creates a text annotation at a position
    static func text(_ text: String, at position: CGPoint, color: AnnotationColor = .red) -> Annotation {
        Annotation(type: .text, points: [position], color: color, text: text)
    }

    /// Bounding rect for this annotation
    var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }

        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - AnnotatedImage

/// An image with annotations applied, ready for dispatch
struct AnnotatedImage: Identifiable, Sendable {
    let id: UUID
    let screenshot: Screenshot
    var annotations: [Annotation]
    var cropRect: CGRect?

    init(
        id: UUID = UUID(),
        screenshot: Screenshot,
        annotations: [Annotation] = [],
        cropRect: CGRect? = nil
    ) {
        self.id = id
        self.screenshot = screenshot
        self.annotations = annotations
        self.cropRect = cropRect
    }

    /// Whether this image has any modifications (annotations or crop)
    var hasModifications: Bool {
        !annotations.isEmpty || cropRect != nil
    }

    /// Add an annotation
    mutating func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        logDebug("Added \(annotation.type.rawValue) annotation to image", category: .data)
    }

    /// Remove an annotation by ID
    mutating func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        logDebug("Removed annotation from image", category: .data)
    }

    /// Clear all annotations
    mutating func clearAnnotations() {
        annotations.removeAll()
        logDebug("Cleared all annotations from image", category: .data)
    }

    /// Set crop region
    mutating func setCrop(_ rect: CGRect?) {
        cropRect = rect
        if let rect = rect {
            logDebug("Set crop region: \(rect)", category: .data)
        } else {
            logDebug("Cleared crop region", category: .data)
        }
    }

    /// Display title for the image
    var displayTitle: String {
        screenshot.displayLabel
    }
}

// MARK: - QuickCapture Support

extension AnnotatedImage {
    /// Alternative storage for QuickCapture (non-SwiftData) images.
    /// Uses filePath directly when Screenshot is not available.
    private static var quickCaptureImages: [UUID: (filePath: String, image: NSImage)] = [:]

    /// Creates an AnnotatedImage from a QuickCapture (no Screenshot required).
    /// Stores the image data separately since we can't use SwiftData outside the model context.
    init(quickCapture: QuickCapture) {
        // Create a minimal Screenshot-like wrapper using dummy values
        // The actual image is retrieved from quickCaptureImages cache
        id = quickCapture.id

        // Store the image in static cache for later retrieval
        if let image = quickCapture.image {
            Self.quickCaptureImages[quickCapture.id] = (quickCapture.filePath, image)
        }

        // We need a Screenshot object for the existing API, but we'll create a detached one
        // Note: This Screenshot is NOT persisted to SwiftData - it's purely for API compatibility
        screenshot = Screenshot(
            id: quickCapture.id,
            filePath: quickCapture.filePath,
            captureIndex: 0,
            label: quickCapture.label
        )
        annotations = []
        cropRect = nil
    }

    /// Retrieves the cached image for QuickCapture-based AnnotatedImages.
    /// Falls back to screenshot.image for Screenshot-based AnnotatedImages.
    var resolvedImage: NSImage? {
        if let cached = Self.quickCaptureImages[id] {
            return cached.image
        }
        return screenshot.image
    }

    /// Cleans up cached QuickCapture image data when no longer needed.
    static func cleanupQuickCapture(id: UUID) {
        quickCaptureImages.removeValue(forKey: id)
    }
}

// MARK: - AnnotationAction (for Undo/Redo)

/// Represents an action that can be undone/redone
enum AnnotationAction: Sendable {
    case addAnnotation(Annotation)
    case removeAnnotation(Annotation)
    case setCrop(old: CGRect?, new: CGRect?)
    case clearAnnotations([Annotation])

    /// Returns the inverse action for undo
    var inverse: AnnotationAction {
        switch self {
        case let .addAnnotation(annotation):
            return .removeAnnotation(annotation)
        case let .removeAnnotation(annotation):
            return .addAnnotation(annotation)
        case let .setCrop(old, new):
            return .setCrop(old: new, new: old)
        case let .clearAnnotations(annotations):
            // Inverse would need to restore all annotations - handled specially
            return .clearAnnotations(annotations)
        }
    }
}

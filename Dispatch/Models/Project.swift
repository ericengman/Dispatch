//
//  Project.swift
//  Dispatch
//
//  Project model for organizing prompts and chains
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    // MARK: - Properties

    var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var sortOrder: Int

    /// File system path for discovered Claude Code projects (optional)
    var path: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify, inverse: \Prompt.project)
    var prompts: [Prompt] = []

    @Relationship(deleteRule: .nullify, inverse: \PromptChain.project)
    var chains: [PromptChain] = []

    @Relationship(deleteRule: .nullify, inverse: \TerminalSession.project)
    var sessions: [TerminalSession] = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = ProjectColor.blue.hex,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        path: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.path = path

        logDebug("Created project: \(name) with color \(colorHex)", category: .data)
    }

    // MARK: - Computed Properties

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var promptCount: Int {
        prompts.count
    }

    var chainCount: Int {
        chains.count
    }

    var sessionCount: Int {
        sessions.count
    }

    /// URL representation of the path
    var pathURL: URL? {
        guard let path = path else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whether this project is linked to a file system path
    var isLinkedToFileSystem: Bool {
        path != nil
    }

    // MARK: - Methods

    func updateColor(_ newColor: ProjectColor) {
        colorHex = newColor.hex
        logDebug("Updated project '\(name)' color to \(newColor.hex)", category: .data)
    }
}

// MARK: - Project Colors

/// Preset color palette for projects as defined in spec
enum ProjectColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .red: return "#FF6B6B"
        case .orange: return "#FFA94D"
        case .yellow: return "#FFE066"
        case .green: return "#69DB7C"
        case .teal: return "#38D9A9"
        case .blue: return "#4DABF7"
        case .purple: return "#9775FA"
        case .pink: return "#F06595"
        }
    }

    var color: Color {
        Color(hex: hex) ?? .blue
    }

    var name: String {
        rawValue.capitalized
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else {
            return nil
        }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

//
//  PlaceholderResolver.swift
//  Dispatch
//
//  Service for parsing and resolving template placeholders in prompts
//

import Foundation
import AppKit

// MARK: - Placeholder Types

/// Represents a placeholder found in prompt text
struct Placeholder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let requiresUserInput: Bool

    init(name: String) {
        self.id = name.lowercased()
        self.name = name
        self.isBuiltIn = BuiltInPlaceholder.allCases.contains { $0.name.lowercased() == name.lowercased() }
        self.requiresUserInput = !isBuiltIn || BuiltInPlaceholder(rawValue: name.lowercased())?.requiresInput ?? true
    }

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var placeholder: String {
        "{{\(name)}}"
    }
}

// MARK: - Built-in Placeholders

/// Built-in placeholders that can be auto-filled
enum BuiltInPlaceholder: String, CaseIterable, Sendable {
    case clipboard
    case date
    case time
    case datetime
    case filename
    case path
    case selection

    var name: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .date: return "Date"
        case .time: return "Time"
        case .datetime: return "Date & Time"
        case .filename: return "Filename"
        case .path: return "Path"
        case .selection: return "Selection"
        }
    }

    var description: String {
        switch self {
        case .clipboard: return "Current clipboard text"
        case .date: return "Current date (YYYY-MM-DD)"
        case .time: return "Current time (HH:MM)"
        case .datetime: return "Current date and time"
        case .filename: return "Enter a filename"
        case .path: return "Enter a file path"
        case .selection: return "Enter selected text"
        }
    }

    var requiresInput: Bool {
        switch self {
        case .clipboard, .date, .time, .datetime:
            return false
        case .filename, .path, .selection:
            return true
        }
    }

    /// Auto-fills the placeholder value if possible
    func autoFill() -> String? {
        switch self {
        case .clipboard:
            return NSPasteboard.general.string(forType: .string)

        case .date:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())

        case .time:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: Date())

        case .datetime:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: Date())

        case .filename, .path, .selection:
            return nil  // Requires user input
        }
    }
}

// MARK: - Placeholder Resolution Result

/// Result of placeholder resolution
struct PlaceholderResolutionResult: Sendable {
    let originalText: String
    let resolvedText: String
    let resolvedPlaceholders: [String: String]
    let unresolvedPlaceholders: [Placeholder]

    var isFullyResolved: Bool {
        unresolvedPlaceholders.isEmpty
    }
}

// MARK: - Placeholder Resolver

/// Service for parsing and resolving placeholders in prompt text
actor PlaceholderResolver {
    static let shared = PlaceholderResolver()

    private init() {
    }

    // MARK: - Parsing

    /// Extracts all placeholders from text
    func extractPlaceholders(from text: String) -> [Placeholder] {
        let pattern = #"\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            logError("Failed to create placeholder regex", category: .placeholder)
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var placeholders: [Placeholder] = []
        var seen = Set<String>()

        for match in matches {
            if let captureRange = Range(match.range(at: 1), in: text) {
                let name = String(text[captureRange])
                let key = name.lowercased()

                if !seen.contains(key) {
                    seen.insert(key)
                    placeholders.append(Placeholder(name: name))
                }
            }
        }

        logDebug("Extracted \(placeholders.count) placeholders from text", category: .placeholder)
        return placeholders
    }

    /// Checks if text contains any placeholders
    func hasPlaceholders(in text: String) -> Bool {
        let pattern = #"\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // MARK: - Resolution

    /// Resolves placeholders with provided values and auto-fillable built-ins
    func resolve(
        text: String,
        userValues: [String: String] = [:],
        autoFillBuiltIns: Bool = true
    ) -> PlaceholderResolutionResult {
        let placeholders = extractPlaceholders(from: text)

        var resolvedValues: [String: String] = [:]
        var unresolvedPlaceholders: [Placeholder] = []
        var resultText = text

        for placeholder in placeholders {
            let key = placeholder.name.lowercased()

            // Check user-provided values first
            if let userValue = userValues.first(where: { $0.key.lowercased() == key })?.value {
                resolvedValues[placeholder.name] = userValue
                resultText = replacePlaceholder(placeholder.name, with: userValue, in: resultText)
                logDebug("Resolved '\(placeholder.name)' with user value", category: .placeholder)
                continue
            }

            // Try auto-fill for built-in placeholders
            if autoFillBuiltIns, let builtIn = BuiltInPlaceholder(rawValue: key), let value = builtIn.autoFill() {
                resolvedValues[placeholder.name] = value
                resultText = replacePlaceholder(placeholder.name, with: value, in: resultText)
                logDebug("Auto-filled '\(placeholder.name)' with: \(value.prefix(50))...", category: .placeholder)
                continue
            }

            // Unresolved
            unresolvedPlaceholders.append(placeholder)
        }

        if !unresolvedPlaceholders.isEmpty {
            logDebug("\(unresolvedPlaceholders.count) placeholders remain unresolved", category: .placeholder)
        }

        return PlaceholderResolutionResult(
            originalText: text,
            resolvedText: resultText,
            resolvedPlaceholders: resolvedValues,
            unresolvedPlaceholders: unresolvedPlaceholders
        )
    }

    /// Resolves only auto-fillable built-in placeholders
    func autoResolve(text: String) -> PlaceholderResolutionResult {
        resolve(text: text, userValues: [:], autoFillBuiltIns: true)
    }

    /// Replaces a specific placeholder with a value
    private func replacePlaceholder(_ name: String, with value: String, in text: String) -> String {
        // Case-insensitive replacement
        let pattern = #"\{\{"# + NSRegularExpression.escapedPattern(for: name) + #"\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text.replacingOccurrences(of: "{{\(name)}}", with: value, options: .caseInsensitive)
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: value)
    }

    // MARK: - Validation

    /// Validates placeholder syntax in text
    func validatePlaceholders(in text: String) -> [PlaceholderValidationError] {
        var errors: [PlaceholderValidationError] = []

        // Check for unclosed placeholders
        let unclosedPattern = #"\{\{[^}]*$"#
        if let regex = try? NSRegularExpression(pattern: unclosedPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                errors.append(.unclosedPlaceholder)
            }
        }

        // Check for empty placeholders
        if text.contains("{{}}") {
            errors.append(.emptyPlaceholder)
        }

        // Check for invalid characters in placeholder names
        let invalidPattern = #"\{\{[^a-zA-Z_][^}]*\}\}"#
        if let regex = try? NSRegularExpression(pattern: invalidPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                errors.append(.invalidPlaceholderName)
            }
        }

        if !errors.isEmpty {
            logWarning("Placeholder validation errors: \(errors)", category: .placeholder)
        }

        return errors
    }
}

// MARK: - Validation Errors

enum PlaceholderValidationError: Error, LocalizedError, Sendable {
    case unclosedPlaceholder
    case emptyPlaceholder
    case invalidPlaceholderName

    var errorDescription: String? {
        switch self {
        case .unclosedPlaceholder:
            return "Unclosed placeholder found (missing '}}' )"
        case .emptyPlaceholder:
            return "Empty placeholder found ('{{}}')"
        case .invalidPlaceholderName:
            return "Invalid placeholder name (must start with letter or underscore)"
        }
    }
}

// MARK: - Placeholder Insertion Helpers

extension PlaceholderResolver {
    /// Returns common placeholder strings for quick insertion
    var commonPlaceholders: [(name: String, placeholder: String)] {
        [
            ("Clipboard", "{{clipboard}}"),
            ("Date", "{{date}}"),
            ("Time", "{{time}}"),
            ("Filename", "{{filename}}"),
            ("Path", "{{path}}"),
            ("Selection", "{{selection}}")
        ]
    }

    /// Wraps text in placeholder syntax
    func createPlaceholder(named name: String) -> String {
        let sanitized = name
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        guard !sanitized.isEmpty else {
            return "{{placeholder}}"
        }

        // Ensure starts with letter or underscore
        if let first = sanitized.first, !first.isLetter && first != "_" {
            return "{{_\(sanitized)}}"
        }

        return "{{\(sanitized)}}"
    }
}

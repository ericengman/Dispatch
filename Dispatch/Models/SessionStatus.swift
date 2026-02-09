//
//  SessionStatus.swift
//  Dispatch
//
//  Status model for Claude Code session state and context usage
//

import SwiftUI

// MARK: - Session State

/// Represents the current execution state of a Claude Code session
enum SessionState: String, Sendable {
    case idle = "Idle"
    case thinking = "Thinking" // Assistant generating response
    case executing = "Executing" // Tool calls in progress
    case waiting = "Waiting" // User input needed

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .thinking: return .blue
        case .executing: return .orange
        case .waiting: return .yellow
        }
    }

    /// Whether this state should show pulse animation
    var isAnimated: Bool {
        switch self {
        case .thinking, .executing: return true
        case .idle, .waiting: return false
        }
    }
}

// MARK: - Context Usage

/// Token usage statistics for a Claude Code session
struct ContextUsage: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheTokens: Int?

    /// Total tokens used (input + output)
    /// Note: cache tokens are already included in input, not additive
    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

// MARK: - Session Status

/// Complete status for a Claude Code session including state and context
struct SessionStatus: Sendable {
    var state: SessionState
    var contextUsage: ContextUsage?
    var lastUpdated: Date

    /// Model context window limit (Opus 4.5 = 200K tokens)
    static let contextLimit: Int = 200_000

    init(state: SessionState = .idle, contextUsage: ContextUsage? = nil) {
        self.state = state
        self.contextUsage = contextUsage
        lastUpdated = Date()
    }

    /// Context usage as percentage of model limit (0.0 to 1.0)
    var contextPercentage: Double {
        guard let usage = contextUsage else { return 0 }
        return min(Double(usage.totalTokens) / Double(Self.contextLimit), 1.0)
    }

    /// Color for context usage indicator based on percentage
    var usageColor: Color {
        switch contextPercentage {
        case 0 ..< 0.7: return .green
        case 0.7 ..< 0.9: return .orange
        default: return .red
        }
    }
}

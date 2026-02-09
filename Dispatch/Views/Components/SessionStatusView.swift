//
//  SessionStatusView.swift
//  Dispatch
//
//  UI component for displaying Claude Code session status in tab bar
//

import SwiftUI

/// Displays session state badge with animations and context usage ring
struct SessionStatusView: View {
    let status: SessionStatus

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            stateBadge
            if status.contextUsage != nil {
                contextRing
            }
        }
    }

    // MARK: - State Badge

    @ViewBuilder
    private var stateBadge: some View {
        HStack(spacing: 3) {
            stateCircle
            Text(status.state.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateCircle: some View {
        let color = status.state.color

        if status.state.isAnimated {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
        } else {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Context Ring

    private var contextRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 2)

            // Progress ring
            Circle()
                .trim(from: 0, to: status.contextPercentage)
                .stroke(status.usageColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Percentage text
            Text("\(Int(status.contextPercentage * 100))%")
                .font(.system(size: 7, design: .rounded))
                .fontWeight(.medium)
        }
        .frame(width: 20, height: 20)
        .help(contextTooltip)
    }

    private var contextTooltip: String {
        guard let usage = status.contextUsage else { return "" }
        var tooltip = "Input: \(formatTokens(usage.inputTokens))\nOutput: \(formatTokens(usage.outputTokens))"
        if let cache = usage.cacheTokens {
            tooltip += "\nCached: \(formatTokens(cache))"
        }
        tooltip += "\nTotal: \(formatTokens(usage.totalTokens)) / \(formatTokens(SessionStatus.contextLimit))"
        return tooltip
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - Previews

#Preview("Idle") {
    SessionStatusView(status: SessionStatus(state: .idle))
        .padding()
}

#Preview("Thinking") {
    SessionStatusView(status: SessionStatus(state: .thinking))
        .padding()
}

#Preview("Executing") {
    SessionStatusView(status: SessionStatus(state: .executing))
        .padding()
}

#Preview("With Context Usage") {
    SessionStatusView(
        status: SessionStatus(
            state: .executing,
            contextUsage: ContextUsage(inputTokens: 45000, outputTokens: 12000, cacheTokens: 8000)
        )
    )
    .padding()
}

#Preview("High Context Usage") {
    SessionStatusView(
        status: SessionStatus(
            state: .thinking,
            contextUsage: ContextUsage(inputTokens: 160_000, outputTokens: 25000, cacheTokens: nil)
        )
    )
    .padding()
}

#Preview("All States") {
    VStack(spacing: 16) {
        SessionStatusView(status: SessionStatus(state: .idle))
        SessionStatusView(status: SessionStatus(state: .thinking))
        SessionStatusView(status: SessionStatus(state: .executing))
        SessionStatusView(status: SessionStatus(state: .waiting))

        Divider()

        SessionStatusView(
            status: SessionStatus(
                state: .executing,
                contextUsage: ContextUsage(inputTokens: 50000, outputTokens: 10000, cacheTokens: nil)
            )
        )
        SessionStatusView(
            status: SessionStatus(
                state: .thinking,
                contextUsage: ContextUsage(inputTokens: 150_000, outputTokens: 20000, cacheTokens: 30000)
            )
        )
        SessionStatusView(
            status: SessionStatus(
                state: .executing,
                contextUsage: ContextUsage(inputTokens: 180_000, outputTokens: 15000, cacheTokens: nil)
            )
        )
    }
    .padding()
}

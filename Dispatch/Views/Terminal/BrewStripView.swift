//
//  BrewStripView.swift
//  Dispatch
//
//  Compact "brew strip" view shown when a terminal session is auto-condensed.
//  Displays session name, terminal preview, elapsed time, and token count.
//

import SwiftUI

struct BrewStripView: View {
    let session: TerminalSession
    let brewController: BrewModeController

    static let stripHeight: CGFloat = 70

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }

    private var statusMonitor: SessionStatusMonitor? {
        sessionManager.statusMonitor(for: session.id)
    }

    private var previewText: String {
        brewController.previewTexts[session.id] ?? ""
    }

    private var brewStartTime: Date? {
        brewController.brewStartTimes[session.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: status dot + session name + elapsed time
            HStack(spacing: 6) {
                // Pulsing status dot
                statusDot

                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Elapsed time
                if let startTime = brewStartTime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.formatElapsed(from: startTime, to: context.date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Middle row: preview text
            Text(previewText.isEmpty ? "Working..." : previewText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Bottom row: token count
            HStack {
                Spacer()

                if let usage = statusMonitor?.status.contextUsage {
                    Text(Self.formatTokens(usage.totalTokens))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(statusMonitor?.status.usageColor ?? .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.stripHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((statusMonitor?.status.state.color ?? .gray).opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                brewController.startHoverPeek(session.id)
            } else {
                brewController.cancelHoverPeek(session.id)
            }
        }
        .onTapGesture {
            brewController.manualExpand(session.id)
        }
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        let state = statusMonitor?.status.state ?? .idle
        Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
            .scaleEffect(state.isAnimated ? 1.3 : 1.0)
            .opacity(state.isAnimated ? 0.7 : 1.0)
            .animation(
                state.isAnimated
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: state.isAnimated
            )
    }

    // MARK: - Formatters

    static func formatElapsed(from start: Date, to now: Date) -> String {
        let interval = Int(now.timeIntervalSince(start))
        let minutes = interval / 60
        let seconds = interval % 60
        if minutes > 0 {
            return "\(minutes)m \(String(format: "%02d", seconds))s"
        }
        return "\(seconds)s"
    }

    static func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            if k >= 100 {
                return "\(Int(k))K tokens"
            }
            return String(format: "%.1fK tokens", k)
        }
        return "\(count) tokens"
    }
}

#Preview {
    BrewStripView(
        session: TerminalSession(name: "Session 1"),
        brewController: BrewModeController.shared
    )
    .frame(width: 600)
    .padding()
}

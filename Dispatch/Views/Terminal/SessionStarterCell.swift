//
//  SessionStarterCell.swift
//  Dispatch
//
//  Interactive empty state for terminal panel - shows new session button and recent sessions
//

import SwiftUI

struct SessionStarterCell: View {
    var projectPath: String?
    var onNewSession: () -> Void
    var onResumeSession: (ClaudeCodeSession) -> Void

    @State private var recentSessions: [ClaudeCodeSession] = []
    @State private var isLoadingSessions = true

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Main action card - "New Claude Code Session"
            Button(action: onNewSession) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("New Claude Code Session")
                        .font(.headline)

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Recent sessions section
            if isLoadingSessions {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.vertical, 8)
            } else if !recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Resume Previous")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    VStack(spacing: 8) {
                        ForEach(recentSessions.prefix(3)) { session in
                            RecentSessionRow(session: session) {
                                onResumeSession(session)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 400)
        .task {
            await loadRecentSessions()
        }
    }

    private func loadRecentSessions() async {
        let path = projectPath ?? FileManager.default.currentDirectoryPath
        let sessions = await ClaudeSessionDiscoveryService.shared.getRecentSessions(
            for: path,
            maxCount: 5,
            withinHours: 168 // 1 week
        )

        await MainActor.run {
            recentSessions = sessions
            isLoadingSessions = false
        }
    }
}

// MARK: - Recent Session Row

private struct RecentSessionRow: View {
    let session: ClaudeCodeSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                // Message count badge
                VStack(spacing: 2) {
                    Text("\(session.messageCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("msgs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 36)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    // First prompt (truncated)
                    Text(session.displayPrompt)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    // Metadata row
                    HStack(spacing: 6) {
                        // Git branch
                        if let branch = session.gitBranch, !branch.isEmpty {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Relative time
                        Text(session.relativeModified)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    SessionStarterCell(
        projectPath: "/Users/eric/Dispatch",
        onNewSession: { print("New session") },
        onResumeSession: { session in print("Resume: \(session.sessionId)") }
    )
    .frame(width: 500, height: 400)
}

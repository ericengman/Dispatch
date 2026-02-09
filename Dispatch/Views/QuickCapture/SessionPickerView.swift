//
//  SessionPickerView.swift
//  Dispatch
//
//  Dropdown picker for selecting target Claude Code session.
//

import SwiftUI

/// Dropdown picker for selecting target Claude Code session.
/// Shows only active sessions with available terminals.
struct SessionPickerView: View {
    @Binding var selectedSessionId: UUID?

    // Use direct observation of TerminalSessionManager
    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }

    /// Filter to only sessions with active terminals
    private var availableSessions: [TerminalSession] {
        sessionManager.sessions.filter { session in
            sessionManager.terminal(for: session.id) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Target Session", systemImage: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedSessionId) {
                Text("Select Claude Code session...")
                    .tag(nil as UUID?)

                if availableSessions.isEmpty {
                    Text("No sessions available")
                        .foregroundStyle(.secondary)
                        .tag(nil as UUID?)
                } else {
                    ForEach(availableSessions) { session in
                        sessionLabel(for: session)
                            .tag(session.id as UUID?)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(availableSessions.isEmpty)

            // Status indicator
            if let selectedId = selectedSessionId,
               let session = sessionManager.sessions.first(where: { $0.id == selectedId }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready: \(session.name)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if availableSessions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No terminal sessions open")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sessionLabel(for session: TerminalSession) -> some View {
        HStack {
            Text(session.name)
            Spacer()

            // Claude session indicator
            if session.claudeSessionId != nil {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .help("Claude Code session")
            }

            // Active session indicator
            if session.id == sessionManager.activeSessionId {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 6))
                    .help("Active session")
            }
        }
    }
}

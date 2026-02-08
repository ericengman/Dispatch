//
//  MultiSessionTerminalView.swift
//  Dispatch
//
//  Container view for multi-session terminal with tab bar and layout modes
//

import SwiftUI

struct MultiSessionTerminalView: View {
    @State private var sessionManager = TerminalSessionManager.shared

    // Project path for session discovery
    var projectPath: String?

    // State for persisted session handling
    @State private var persistedSessions: [TerminalSession] = []
    @State private var showPersistedSessionsPicker = false
    @State private var hasCheckedForSessions = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar for session switching (hidden when empty)
            if !sessionManager.sessions.isEmpty {
                SessionTabBar(projectPath: projectPath)
                Divider()
            }

            // Layout mode picker (only show with 2+ sessions)
            if sessionManager.sessions.count >= 2 {
                HStack {
                    Picker("Layout", selection: $sessionManager.layoutMode) {
                        Label("Focus", systemImage: "rectangle").tag(TerminalSessionManager.LayoutMode.single)
                        Label("Side by Side", systemImage: "rectangle.split.2x1").tag(TerminalSessionManager.LayoutMode.horizontalSplit)
                        Label("Stacked", systemImage: "rectangle.split.1x2").tag(TerminalSessionManager.LayoutMode.verticalSplit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // Terminal content area
            if sessionManager.sessions.isEmpty {
                // Interactive empty state with session discovery
                SessionStarterCell(
                    projectPath: projectPath,
                    onNewSession: {
                        _ = sessionManager.createSession()
                    },
                    onResumeSession: { claudeSession in
                        _ = sessionManager.createResumeSession(claudeSession: claudeSession)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                terminalContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if sessionManager.sessions.isEmpty && !hasCheckedForSessions {
                hasCheckedForSessions = true

                // First, check for persisted sessions from SwiftData
                persistedSessions = sessionManager.loadPersistedSessions()

                if !persistedSessions.isEmpty {
                    // Has persisted sessions - show picker to resume or start fresh
                    showPersistedSessionsPicker = true
                } else {
                    // No persisted sessions - check Claude Code session files for discovery
                    Task {
                        await checkForRecentSessions()
                    }
                }

                // Cleanup stale sessions in background
                Task.detached {
                    await MainActor.run {
                        sessionManager.cleanupStaleSessions(olderThanDays: 7)
                    }
                }
            }
        }
        .sheet(isPresented: $showPersistedSessionsPicker) {
            PersistedSessionPicker(
                sessions: persistedSessions,
                onResume: { session in
                    // Resume the persisted session
                    if sessionManager.resumePersistedSession(session) {
                        // Try to associate with project
                        sessionManager.associateWithProject(session)
                    }
                },
                onStartFresh: {
                    // User wants fresh session - create new one
                    _ = sessionManager.createSession()
                },
                onDismiss: {
                    // User dismissed without choice - create fresh session
                    if sessionManager.sessions.isEmpty {
                        _ = sessionManager.createSession()
                    }
                }
            )
        }
    }

    private func checkForRecentSessions() async {
        // Existing SessionStarterCell handles Claude Code session discovery
        // This function is for future direct discovery from MultiSessionTerminalView if needed
    }

    @ViewBuilder
    private var terminalContent: some View {
        // Simplified layout: just show active session
        if let activeSession = sessionManager.activeSession {
            SessionPaneView(session: activeSession)
                .padding(8)
        } else if let firstSession = sessionManager.sessions.first {
            // Fallback: show first session if no active session
            SessionPaneView(session: firstSession)
                .padding(8)
        } else {
            // This shouldn't happen since we check isEmpty above
            Text("No active session")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layout Calculations

    private func shouldShow(session: TerminalSession, activeId: UUID?, sessions: [TerminalSession]) -> Bool {
        switch sessionManager.layoutMode {
        case .single:
            return session.id == activeId
        case .horizontalSplit, .verticalSplit:
            guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
            return index < 2
        }
    }

    private func frameWidth(for _: TerminalSession, in geometry: GeometryProxy, sessions _: [TerminalSession]) -> CGFloat {
        let available = geometry.size.width - 16 // Account for padding

        switch sessionManager.layoutMode {
        case .single:
            return available
        case .horizontalSplit:
            return (available - 8) / 2 // Split with gap
        case .verticalSplit:
            return available
        }
    }

    private func frameHeight(for _: TerminalSession, in geometry: GeometryProxy, sessions _: [TerminalSession]) -> CGFloat {
        let available = geometry.size.height - 16 // Account for padding

        switch sessionManager.layoutMode {
        case .single:
            return available
        case .horizontalSplit:
            return available
        case .verticalSplit:
            return (available - 8) / 2 // Split with gap
        }
    }

    private func positionX(for session: TerminalSession, in geometry: GeometryProxy, sessions: [TerminalSession]) -> CGFloat {
        let available = geometry.size.width - 16
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return available / 2
        }

        switch sessionManager.layoutMode {
        case .single:
            return available / 2
        case .horizontalSplit:
            let paneWidth = (available - 8) / 2
            return index == 0 ? paneWidth / 2 : available - paneWidth / 2
        case .verticalSplit:
            return available / 2
        }
    }

    private func positionY(for session: TerminalSession, in geometry: GeometryProxy, sessions: [TerminalSession]) -> CGFloat {
        let available = geometry.size.height - 16
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return available / 2
        }

        switch sessionManager.layoutMode {
        case .single:
            return available / 2
        case .horizontalSplit:
            return available / 2
        case .verticalSplit:
            let paneHeight = (available - 8) / 2
            return index == 0 ? paneHeight / 2 : available - paneHeight / 2
        }
    }
}

// MARK: - Persisted Session Picker

private struct PersistedSessionPicker: View {
    let sessions: [TerminalSession]
    let onResume: (TerminalSession) -> Void
    let onStartFresh: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Resume Previous Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Previous Sessions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No sessions found to resume")
                )
                .frame(minHeight: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            PersistedSessionRow(session: session) {
                                onResume(session)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Start Fresh Session") {
                    onStartFresh()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450)
    }
}

private struct PersistedSessionRow: View {
    let session: TerminalSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if session.isResumable {
                            Label("Resumable", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        Text(session.relativeLastActivity)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MultiSessionTerminalView()
        .frame(width: 800, height: 600)
}

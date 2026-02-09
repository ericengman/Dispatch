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
                        _ = sessionManager.createSession(workingDirectory: projectPath)
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

                // Check for persisted sessions from SwiftData
                let persistedSessions = sessionManager.loadPersistedSessions()

                if !persistedSessions.isEmpty {
                    // Auto-resume ALL persisted sessions (preserves terminal count)
                    // Sessions are sorted by lastActivity (newest first) from loadPersistedSessions
                    for session in persistedSessions {
                        if sessionManager.resumePersistedSession(session) {
                            sessionManager.associateWithProject(session)
                        }
                    }
                    // The first (newest) session will already be active from resumePersistedSession
                    logInfo("Auto-resumed \(persistedSessions.count) persisted session(s)", category: .terminal)
                }
                // If no persisted sessions, the empty state (SessionStarterCell) will show

                // Cleanup stale sessions in background
                Task.detached {
                    await MainActor.run {
                        sessionManager.cleanupStaleSessions(olderThanDays: 7)
                    }
                }
            }
        }
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

#Preview {
    MultiSessionTerminalView()
        .frame(width: 800, height: 600)
}

//
//  SessionTabBar.swift
//  Dispatch
//
//  Tab bar for session switching with new session button
//

import SwiftUI

struct SessionTabBar: View {
    @State private var sessionManager = TerminalSessionManager.shared
    @State private var showResumePicker = false
    @State private var recentSessions: [ClaudeCodeSession] = []
    @State private var availableSessions: [ClaudeCodeSession] = []

    // Project path for session discovery (defaults to current directory)
    var projectPath: String?

    var body: some View {
        HStack(spacing: 0) {
            // Session tabs
            ForEach(sessionManager.sessions) { session in
                SessionTab(session: session)
            }

            // Session switcher - shows available Claude sessions not currently open
            if !availableSessions.isEmpty && sessionManager.canCreateSession {
                Menu {
                    ForEach(availableSessions.prefix(5)) { session in
                        Button {
                            _ = sessionManager.createResumeSession(claudeSession: session)
                            // Refresh available sessions
                            Task { await loadAvailableSessions() }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(session.displayPrompt)
                                Text("\(session.messageCount) msgs • \(session.relativeModified)")
                                    .font(.caption)
                            }
                        }
                    }

                    if availableSessions.count > 5 {
                        Divider()
                        Button("Show All...") {
                            Task {
                                await loadRecentSessions()
                                showResumePicker = true
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                        Text("\(availableSessions.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Resume another session")
            }

            Spacer()

            // New session menu
            Menu {
                Button("New Session", systemImage: "plus") {
                    _ = sessionManager.createSession(workingDirectory: projectPath)
                }

                Divider()

                Button("Resume Previous...", systemImage: "clock.arrow.circlepath") {
                    Task {
                        await loadRecentSessions()
                        showResumePicker = true
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!sessionManager.canCreateSession)
            .opacity(sessionManager.canCreateSession ? 1.0 : 0.5)
            .help(sessionManager.canCreateSession ? "New Session" : "Max sessions reached")
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            await loadAvailableSessions()
        }
        .sheet(isPresented: $showResumePicker) {
            SessionResumePicker(sessions: recentSessions) { selectedSession in
                if let session = selectedSession {
                    _ = sessionManager.createResumeSession(claudeSession: session)
                } else {
                    _ = sessionManager.createSession(workingDirectory: projectPath)
                }
                // Refresh available sessions
                Task { await loadAvailableSessions() }
            }
        }
    }

    private func loadRecentSessions() async {
        let path = projectPath ?? FileManager.default.currentDirectoryPath
        recentSessions = await ClaudeSessionDiscoveryService.shared.getRecentSessions(for: path)
    }

    /// Load available Claude sessions that are NOT currently open as terminals
    private func loadAvailableSessions() async {
        let path = projectPath ?? FileManager.default.currentDirectoryPath
        let allSessions = await ClaudeSessionDiscoveryService.shared.getRecentSessions(
            for: path,
            maxCount: 10,
            withinHours: 168 // 1 week
        )

        // Filter out sessions that are already open
        let openSessionIds = Set(sessionManager.sessions.compactMap { $0.claudeSessionId })

        await MainActor.run {
            availableSessions = allSessions.filter { !openSessionIds.contains($0.sessionId) }
        }
    }
}

private struct SessionTab: View {
    let session: TerminalSession
    @State private var sessionManager = TerminalSessionManager.shared

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    private var statusMonitor: SessionStatusMonitor? {
        sessionManager.statusMonitor(for: session.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(session.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            // Show status for active session when not idle
            if let monitor = statusMonitor, monitor.status.state != .idle {
                SessionStatusView(status: monitor.status)
            }

            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.setActiveSession(session.id)
        }
    }
}

#Preview {
    VStack {
        SessionTabBar()
    }
    .frame(width: 600)
}

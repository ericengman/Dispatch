//
//  SessionTabBar.swift
//  Dispatch
//
//  Safari-like tab bar for session switching with new session button
//

import SwiftUI

struct SessionTabBar: View {
    @Bindable var sessionManager: TerminalSessionManager
    @Bindable private var brewController = BrewModeController.shared
    @State private var showResumePicker = false
    @State private var recentSessions: [ClaudeCodeSession] = []
    @State private var availableSessions: [ClaudeCodeSession] = []

    // Project path for session discovery (defaults to current directory)
    var projectPath: String?

    /// Sessions belonging to the current project
    private var projectSessions: [TerminalSession] {
        guard let projectPath else { return sessionManager.sessions }
        return sessionManager.sessionsForProject(id: nil, path: projectPath)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Session tabs (filtered to current project)
            ForEach(projectSessions) { session in
                SessionTab(session: session, sessionManager: sessionManager)
            }

            // New session button (click = new session, long-press = resume menu)
            Menu {
                if !availableSessions.isEmpty {
                    Text("Resume Session")

                    ForEach(availableSessions.prefix(5)) { session in
                        Button {
                            _ = sessionManager.createResumeSession(claudeSession: session)
                            Task { await loadAvailableSessions() }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(session.displayPrompt)
                                Text("\(session.messageCount) msgs \u{00B7} \(session.relativeModified)")
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
                } else {
                    Button("Resume Previous...", systemImage: "clock.arrow.circlepath") {
                        Task {
                            await loadRecentSessions()
                            showResumePicker = true
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            } primaryAction: {
                _ = sessionManager.createSession(workingDirectory: projectPath)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!sessionManager.canCreateSession)
            .opacity(sessionManager.canCreateSession ? 1.0 : 0.5)
            .help(sessionManager.canCreateSession ? "New Session (click) / Resume (long-press)" : "Max sessions reached")

            Spacer()

            // Resize presets (visible when 2+ sessions in project)
            if projectSessions.count >= 2 {
                ResizePresetButton(
                    systemImage: "rectangle.compress.vertical",
                    help: "Fit All on Screen"
                ) {
                    let sessions = projectSessions
                    let areaHeight = sessionManager.terminalAreaHeight
                    guard areaHeight > 0 else { return }
                    let count = sessions.count
                    let perSession: CGFloat
                    if count <= 2 {
                        perSession = areaHeight / CGFloat(count)
                    } else if count == 3 {
                        perSession = areaHeight / 3
                    } else {
                        perSession = areaHeight * 2 / 5
                    }
                    let clamped = max(150, perSession)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        for session in sessions {
                            sessionManager.sessionHeights[session.id] = clamped
                        }
                    }
                    sessionManager.saveSessionHeights()
                }

                ResizePresetButton(
                    systemImage: "rectangle.expand.vertical",
                    help: "Maximize All"
                ) {
                    let sessions = projectSessions
                    let areaHeight = sessionManager.terminalAreaHeight
                    guard areaHeight > 0 else { return }
                    let expandedHeight = max(150, areaHeight * 0.85)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        for session in sessions {
                            sessionManager.sessionHeights[session.id] = expandedHeight
                        }
                    }
                    sessionManager.saveSessionHeights()
                }
            }

            // Brew mode toggle (always visible)
            BrewModeToggle(isEnabled: $brewController.isBrewModeEnabled)
                .padding(.trailing, 8)
        }
        .padding(.leading, 8)
        .frame(height: 34)
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
    @Bindable var sessionManager: TerminalSessionManager
    @State private var isHovered = false

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    private var statusMonitor: SessionStatusMonitor? {
        sessionManager.statusMonitor(for: session.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(session.name)
                .font(.system(size: 12))
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            // Show status for active session when not idle
            if let monitor = statusMonitor, monitor.status.state != .idle {
                SessionStatusView(status: monitor.status)
            }

            // Close button: visible on hover or when active
            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 0.8 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Group {
                if isActive {
                    Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)
                } else if isHovered {
                    Color.primary.opacity(0.05)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            sessionManager.setActiveSession(session.id)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

private struct BrewModeToggle: View {
    @Binding var isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            isEnabled
                                ? Color.accentColor.opacity(0.15)
                                : isHovered
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(isEnabled ? "Brew Mode On" : "Brew Mode Off")
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}

private struct ResizePresetButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

#Preview {
    VStack {
        SessionTabBar(sessionManager: TerminalSessionManager.shared)
    }
    .frame(width: 600)
}

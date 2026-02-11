//
//  MultiSessionTerminalView.swift
//  Dispatch
//
//  Container view for multi-session terminal with tab bar and stacked scroll layout
//

import AppKit
import SwiftUI

/// Bridge to access the backing NSScrollView from SwiftUI for precise scroll control.
/// `ScrollViewProxy.scrollTo()` doesn't work correctly with ZStack + `.position()` layout
/// because positioned views report their full parent size, making anchor-based scrolling unreliable.
private struct ScrollViewBridge: NSViewRepresentable {
    @Binding var scrollView: NSScrollView?

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.scrollView = view.enclosingScrollView
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if scrollView == nil {
            DispatchQueue.main.async {
                self.scrollView = nsView.enclosingScrollView
            }
        }
    }
}

struct MultiSessionTerminalView: View {
    @Bindable private var sessionManager = TerminalSessionManager.shared
    @Bindable private var brewController = BrewModeController.shared
    @Bindable private var buildController = BuildRunController.shared
    @Bindable private var simulatorAttacher = SimulatorWindowAttacher.shared
    @State private var availableSessions: [ClaudeCodeSession] = []
    @State private var backingScrollView: NSScrollView?
    @State private var hasXcodeProject = false

    // Drag gesture state (ephemeral)
    @State private var dragStartHeights: (CGFloat, CGFloat)?
    @State private var trailingDragStartHeight: CGFloat?
    private let minPaneHeight: CGFloat = 150

    // Project path for session discovery
    var projectPath: String?

    /// Sessions belonging to the current project
    private var projectSessions: [TerminalSession] {
        guard let projectPath else { return [] }
        return sessionManager.sessionsForProject(id: nil, path: projectPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Destination picker strip (shown when Xcode project detected)
            if hasXcodeProject, let path = projectPath {
                DestinationPickerStrip(projectPath: path, buildController: buildController)
                Divider()
            }

            // Simulator attachment bar
            SimulatorAttachmentBar(attacher: simulatorAttacher)

            // Build strips (shown when builds are active)
            if !buildController.orderedBuilds.isEmpty {
                buildStripsSection
                Divider()
            }

            // Chrome: tab bar (always shown when project has sessions)
            if projectPath != nil && !projectSessions.isEmpty {
                SessionTabBar(sessionManager: sessionManager, projectPath: projectPath)
                Divider()
            }

            // Terminal layer: ALWAYS rendered, never inside a conditional.
            // Empty states overlay on top — they don't cause terminal teardown.
            ZStack {
                terminalContent

                if projectPath == nil {
                    noProjectView
                } else if projectSessions.isEmpty {
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await loadAvailableSessions()
            brewController.startObserving()
            await detectXcodeProject()
        }
        .onChange(of: projectPath) { _, newPath in
            if let newPath {
                sessionManager.switchToProject(path: newPath)
            }
            Task { await detectXcodeProject() }
        }
    }

    @ViewBuilder
    private var noProjectView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a project")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose a project from the sidebar to view its terminal sessions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var terminalContent: some View {
        GeometryReader { geometry in
            let allSessions = sessionManager.sessions
            let currentProjectSessions = projectSessions
            let isSingleSession = currentProjectSessions.count <= 1
            let horizontalPadding: CGFloat = isSingleSession ? 0 : 24
            let topPadding: CGFloat = isSingleSession ? 0 : 8
            let bottomPadding: CGFloat = isSingleSession ? 0 : 24
            let spacing: CGFloat = 8
            let sessionCount = currentProjectSessions.count
            let isScrollable = sessionCount >= 2
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let availableHeight = geometry.size.height - topPadding - bottomPadding
            let trailingHandleSpace: CGFloat = isScrollable ? spacing + 8 : 0
            let totalContentHeight: CGFloat = isScrollable
                ? currentProjectSessions.reduce(CGFloat(0)) { $0 + effectiveHeight($1.id) }
                + CGFloat(max(0, sessionCount - 1)) * spacing + topPadding + bottomPadding + trailingHandleSpace
                : geometry.size.height

            ScrollView(.vertical) {
                ZStack {
                    // Invisible spacer to set scroll content height
                    if isScrollable {
                        Color.clear
                            .frame(height: totalContentHeight)
                    }

                    // Bridge to backing NSScrollView for precise programmatic scrolling
                    ScrollViewBridge(scrollView: $backingScrollView)
                        .frame(width: 0, height: 0)

                    // Render ALL sessions with stable identity
                    ForEach(allSessions) { session in
                        let projectIndex = currentProjectSessions.firstIndex(where: { $0.id == session.id })
                        let isInProject = projectIndex != nil
                        let index = projectIndex ?? 0
                        let isSessionCondensed = brewController.isCondensed(session.id)

                        let isInteractive = isInProject && !isSessionCondensed
                        SessionPaneView(session: session, showChrome: !isSingleSession, isScrollInteractive: isInteractive)
                            // Hide terminal content when condensed (but keep in hierarchy)
                            .opacity(isInProject && !isSessionCondensed ? 1.0 : 0.0)
                            .allowsHitTesting(isInProject && !isSessionCondensed)
                            .overlay {
                                // Brew strip overlay when condensed
                                if isInProject && isSessionCondensed {
                                    BrewStripView(session: session, brewController: brewController)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .transition(.opacity)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                // Condense button for peeking/manually expanded brew sessions
                                let brewState = brewController.brewStates[session.id]
                                if isInProject && (brewState == .peeking || brewState == .manuallyExpanded) {
                                    Button {
                                        brewController.manualCondense(session.id)
                                    } label: {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(.ultraThinMaterial)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(8)
                                    .help("Condense")
                                    .transition(.opacity)
                                }
                            }
                            .overlay {
                                // Red flash border for attention-needed expansions
                                if brewController.expandedWithAlert[session.id] == true {
                                    RoundedRectangle(cornerRadius: isSingleSession ? 0 : 4)
                                        .stroke(Color.red, lineWidth: 3)
                                        .opacity(0.8)
                                        .transition(.opacity)
                                }
                            }
                            .frame(
                                width: availableWidth,
                                height: frameHeight(for: session.id, availableHeight: availableHeight, isSingleSession: isSingleSession)
                            )
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active:
                                    brewController.hoverActive(session.id)
                                case .ended:
                                    brewController.hoverEnded(session.id)
                                }
                            }
                            .position(
                                x: horizontalPadding + availableWidth / 2,
                                y: positionY(for: index, availableHeight: availableHeight, spacing: spacing, topPadding: topPadding, isSingleSession: isSingleSession, projectSessions: currentProjectSessions)
                            )
                            .animation(.easeInOut(duration: 0.2), value: isSessionCondensed)
                            .animation(.easeInOut(duration: 0.3), value: brewController.expandedWithAlert[session.id])
                            .id(session.id)
                    }

                    // Resize handles between stacked panes (hidden when adjacent session is condensed)
                    if isScrollable {
                        ForEach(0 ..< max(0, sessionCount - 1), id: \.self) { i in
                            let topCondensed = brewController.isCondensed(currentProjectSessions[i].id)
                            let bottomCondensed = brewController.isCondensed(currentProjectSessions[i + 1].id)
                            let hideHandle = topCondensed || bottomCondensed

                            ResizeHandleView()
                                .frame(width: availableWidth, height: 8)
                                .position(
                                    x: horizontalPadding + availableWidth / 2,
                                    y: handleY(for: i, topPadding: topPadding, spacing: spacing, projectSessions: currentProjectSessions)
                                )
                                .opacity(hideHandle ? 0 : 1)
                                .allowsHitTesting(!hideHandle)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let topId = currentProjectSessions[i].id
                                            let bottomId = currentProjectSessions[i + 1].id
                                            let activeId = sessionManager.activeSessionId

                                            // Only resize the highlighted/active session
                                            if activeId == topId {
                                                if dragStartHeights == nil {
                                                    dragStartHeights = (sessionManager.heightForSession(topId), 0)
                                                }
                                                guard let start = dragStartHeights else { return }
                                                sessionManager.sessionHeights[topId] = max(minPaneHeight, start.0 + value.translation.height)
                                            } else if activeId == bottomId {
                                                if dragStartHeights == nil {
                                                    dragStartHeights = (0, sessionManager.heightForSession(bottomId))
                                                }
                                                guard let start = dragStartHeights else { return }
                                                sessionManager.sessionHeights[bottomId] = max(minPaneHeight, start.1 - value.translation.height)
                                            } else {
                                                // Fallback: resize the top pane if neither is active
                                                if dragStartHeights == nil {
                                                    dragStartHeights = (sessionManager.heightForSession(topId), 0)
                                                }
                                                guard let start = dragStartHeights else { return }
                                                sessionManager.sessionHeights[topId] = max(minPaneHeight, start.0 + value.translation.height)
                                            }
                                        }
                                        .onEnded { _ in
                                            dragStartHeights = nil
                                            sessionManager.saveSessionHeights()
                                        }
                                )
                        }

                        // Trailing resize handle below the last pane (hidden when last session is condensed)
                        let lastCondensed = brewController.isCondensed(currentProjectSessions[sessionCount - 1].id)

                        ResizeHandleView()
                            .frame(width: availableWidth, height: 8)
                            .position(
                                x: horizontalPadding + availableWidth / 2,
                                y: trailingHandleY(topPadding: topPadding, spacing: spacing, projectSessions: currentProjectSessions)
                            )
                            .opacity(lastCondensed ? 0 : 1)
                            .allowsHitTesting(!lastCondensed)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let lastId = currentProjectSessions[sessionCount - 1].id
                                        if trailingDragStartHeight == nil {
                                            trailingDragStartHeight = sessionManager.heightForSession(lastId)
                                        }
                                        guard let startHeight = trailingDragStartHeight else { return }
                                        let newHeight = max(minPaneHeight, startHeight + value.translation.height)
                                        sessionManager.sessionHeights[lastId] = newHeight
                                    }
                                    .onEnded { _ in
                                        trailingDragStartHeight = nil
                                        sessionManager.saveSessionHeights()
                                    }
                            )
                    }
                }
                .frame(height: isScrollable ? totalContentHeight : geometry.size.height)
            }
            .scrollDisabled(!isScrollable)
            .onChange(of: sessionManager.activeSessionId) { _, newId in
                guard let newId, isScrollable else { return }
                guard let sessionIndex = currentProjectSessions.firstIndex(where: { $0.id == newId }) else { return }
                guard let backingScrollView else { return }

                let centerY = positionY(for: sessionIndex, availableHeight: availableHeight, spacing: spacing, topPadding: topPadding, isSingleSession: isSingleSession, projectSessions: currentProjectSessions)
                let height = effectiveHeight(newId)
                let sessionTop = centerY - height / 2
                let sessionBottom = centerY + height / 2

                let viewportHeight = geometry.size.height
                let currentScrollY = backingScrollView.contentView.bounds.origin.y
                let viewportTop = currentScrollY
                let viewportBottom = currentScrollY + viewportHeight

                // Fully visible — don't scroll
                if sessionTop >= viewportTop && sessionBottom <= viewportBottom {
                    return
                }

                let targetScrollY: CGFloat
                if height > viewportHeight {
                    // Taller than viewport — scroll minimum to reveal nearest edge
                    if sessionTop < viewportTop {
                        targetScrollY = sessionTop
                    } else {
                        targetScrollY = sessionBottom - viewportHeight
                    }
                } else if sessionTop < viewportTop {
                    // Top clipped or entirely above — align top of session to top of viewport
                    targetScrollY = sessionTop
                } else {
                    // Bottom clipped or entirely below — align bottom of session to bottom of viewport
                    targetScrollY = sessionBottom - viewportHeight
                }

                let maxScroll = max(0, totalContentHeight - viewportHeight)
                let clampedY = max(0, min(targetScrollY, maxScroll))

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    backingScrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                    backingScrollView.reflectScrolledClipView(backingScrollView.contentView)
                }
            }
            .onAppear {
                sessionManager.terminalAreaHeight = geometry.size.height
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                sessionManager.terminalAreaHeight = newHeight
            }
        }
    }

    // MARK: - Build Strips Section

    @ViewBuilder
    private var buildStripsSection: some View {
        VStack(spacing: 0) {
            ForEach(buildController.orderedBuilds) { build in
                let isCondensed = buildController.isCondensed(build.id)

                if isCondensed {
                    BuildStripView(build: build, buildController: buildController)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: buildController.hoverActive(build.id)
                            case .ended: buildController.hoverEnded(build.id)
                            }
                        }
                        .onTapGesture {
                            buildController.manualExpand(build.id)
                        }
                        .transition(.opacity)
                } else {
                    BuildOutputExpandedView(build: build, buildController: buildController)
                        .frame(height: 200)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: buildController.orderedBuilds.map(\.id))
    }

    // MARK: - Project Detection

    private func detectXcodeProject() async {
        guard let path = projectPath else {
            hasXcodeProject = false
            return
        }
        let info = await buildController.projectInfo(for: path)
        hasXcodeProject = info != nil
    }

    // MARK: - Session Discovery

    private func loadAvailableSessions() async {
        guard let path = projectPath else { return }
        let allSessions = await ClaudeSessionDiscoveryService.shared.getRecentSessions(
            for: path,
            maxCount: 10,
            withinHours: 168
        )
        let openSessionIds = Set(sessionManager.sessions.compactMap { $0.claudeSessionId })
        await MainActor.run {
            availableSessions = allSessions.filter { !openSessionIds.contains($0.sessionId) }
        }
    }

    // MARK: - Stack Layout Calculations

    private func frameHeight(for sessionId: UUID, availableHeight: CGFloat, isSingleSession: Bool) -> CGFloat {
        if isSingleSession {
            return availableHeight
        }
        if brewController.isCondensed(sessionId) {
            return BrewStripView.stripHeight
        }
        return sessionManager.heightForSession(sessionId)
    }

    /// Height actually displayed, accounting for brew mode condensing
    private func effectiveHeight(_ id: UUID) -> CGFloat {
        if brewController.isCondensed(id) {
            return BrewStripView.stripHeight
        }
        return sessionManager.heightForSession(id)
    }

    private func handleY(for handleIndex: Int, topPadding: CGFloat, spacing: CGFloat, projectSessions: [TerminalSession]) -> CGFloat {
        var y = topPadding
        for i in 0 ... handleIndex {
            y += effectiveHeight(projectSessions[i].id)
            if i <= handleIndex {
                y += spacing / 2
            }
        }
        return y
    }

    private func trailingHandleY(topPadding: CGFloat, spacing: CGFloat, projectSessions: [TerminalSession]) -> CGFloat {
        var y = topPadding
        for session in projectSessions {
            y += effectiveHeight(session.id) + spacing
        }
        return y - spacing / 2
    }

    private func positionY(for index: Int, availableHeight: CGFloat, spacing: CGFloat, topPadding: CGFloat, isSingleSession: Bool, projectSessions: [TerminalSession]) -> CGFloat {
        if isSingleSession {
            return topPadding + availableHeight / 2
        }
        // Stack layout: sum heights of preceding panes
        var y = topPadding
        for i in 0 ..< index {
            y += effectiveHeight(projectSessions[i].id) + spacing
        }
        let thisHeight = effectiveHeight(projectSessions[index].id)
        return y + thisHeight / 2
    }
}

#Preview {
    MultiSessionTerminalView()
        .frame(width: 800, height: 600)
}

//
//  SessionPaneView.swift
//  Dispatch
//
//  Wrapper view for individual terminal session with header and focus indicator
//

import SwiftUI

struct SessionPaneView: View {
    let session: TerminalSession

    /// When true, adds padding/border/radius for split layouts. When false, fills edge-to-edge.
    var showChrome: Bool = true

    /// Whether scroll/click events should be processed by this terminal
    var isScrollInteractive: Bool = true

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }
    private var brewController: BrewModeController { BrewModeController.shared }

    /// Whether the action buttons are visible (mouse within proximity)
    @State private var showActionButtons = false

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    /// Distance in points from the button area to trigger visibility
    private let buttonProximity: CGFloat = 100

    var body: some View {
        let mode = session.launchMode
        EmbeddedTerminalView(
            sessionId: session.id,
            launchMode: mode,
            isScrollInteractive: isScrollInteractive
        )
        .onAppear {
            logDebug("RESUME-DBG SessionPaneView: session '\(session.name)' (id=\(session.id)) resolved launchMode=\(String(describing: mode))", category: .terminal)
        }
        .padding(showChrome ? 4 : 0)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: showChrome ? 4 : 0))
        .overlay(
            RoundedRectangle(cornerRadius: showChrome ? 4 : 0)
                .stroke(showChrome && isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                // Fold/condense button
                Button {
                    brewController.userCondense(session.id)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Fold terminal")

                // Close button
                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close session")
            }
            .padding(8)
            .opacity(showActionButtons ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: showActionButtons)
        }
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            // Button area center: between fold and close buttons near top-right
                            let areaCenter = CGPoint(x: geometry.size.width - 30, y: 18)
                            let dx = location.x - areaCenter.x
                            let dy = location.y - areaCenter.y
                            let distance = sqrt(dx * dx + dy * dy)
                            showActionButtons = distance < buttonProximity
                        case .ended:
                            showActionButtons = false
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.setActiveSession(session.id)
        }
    }
}

#Preview {
    SessionPaneView(session: TerminalSession(name: "Test Session"))
        .frame(width: 400, height: 300)
}

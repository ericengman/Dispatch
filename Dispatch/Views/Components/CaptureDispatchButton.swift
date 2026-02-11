//
//  CaptureDispatchButton.swift
//  Dispatch
//
//  Split button combining session selection and dispatch for capture views.
//

import AppKit
import SwiftUI

// MARK: - Name Cleaning

/// Strip leading "· " prefix that macOS terminal adds to tab titles
private func cleanedName(_ name: String) -> String {
    var result = name
    if result.hasPrefix("· ") {
        result = String(result.dropFirst(2))
    } else if result.hasPrefix("·") {
        result = String(result.dropFirst(1))
    }
    return result
}

// MARK: - Hidden Popup Button (for programmatic menu opening)

/// Invisible NSPopUpButton that can be triggered programmatically via `isExpanded`.
/// Used to open a native dropdown menu when the user presses Tab.
private struct HiddenPopUpButton: NSViewRepresentable {
    let sessions: [TerminalSession]
    @Binding var selectedSessionId: UUID?
    @Binding var isExpanded: Bool

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 1, height: 1), pullsDown: false)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.isHidden = true
        popup.alphaValue = 0
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self

        popup.removeAllItems()

        guard !sessions.isEmpty else { return }

        for session in sessions {
            var title = cleanedName(session.name)
            if session.claudeSessionId != nil {
                title += " \u{2726}"
            }
            if session.id == sessionManager.activeSessionId {
                title += " \u{25CF}"
            }
            popup.addItem(withTitle: title)
            popup.lastItem?.tag = sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        }

        // Sync selection
        if let selectedId = selectedSessionId,
           let index = sessions.firstIndex(where: { $0.id == selectedId }) {
            popup.selectItem(at: index)
        }

        // Open programmatically when requested
        if isExpanded {
            DispatchQueue.main.async {
                self.isExpanded = false
                popup.performClick(nil)
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: HiddenPopUpButton

        init(_ parent: HiddenPopUpButton) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let tag = sender.selectedItem?.tag ?? -1
            if tag >= 0, tag < parent.sessions.count {
                parent.selectedSessionId = parent.sessions[tag].id
            }
        }
    }
}

// MARK: - Capture Dispatch Button

/// Split button that combines session selection (right chevron menu) and dispatch (left click).
/// Used by QuickCaptureAnnotationView and AnnotationWindowContent.
struct CaptureDispatchButton: View {
    @Binding var selectedSessionId: UUID?
    @Binding var isExpanded: Bool
    let sessions: [TerminalSession]
    let isDisabled: Bool
    let onDispatch: (UUID) async -> Void
    var onNewSession: (() -> Void)?

    @State private var status: DispatchStatus = .idle

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }

    /// Display name for the currently selected session, with leading dot stripped
    private var selectedSessionName: String {
        guard let id = selectedSessionId,
              let session = sessions.first(where: { $0.id == id })
        else {
            return "Select Session"
        }
        return cleanedName(session.name)
    }

    /// Whether the button can dispatch (has a valid selected session and isn't already dispatching)
    private var isActionDisabled: Bool {
        isDisabled || selectedSessionId == nil || status == .dispatching
    }

    var body: some View {
        HStack(spacing: 0) {
            splitButton
            statusIndicator
        }
        .overlay {
            HiddenPopUpButton(
                sessions: sessions,
                selectedSessionId: $selectedSessionId,
                isExpanded: $isExpanded
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
    }

    // MARK: - Split Button

    private var splitButton: some View {
        HStack(spacing: 0) {
            // Left side: dispatch action
            Button {
                guard let sessionId = selectedSessionId else { return }
                performDispatch(sessionId: sessionId)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                    Text(selectedSessionName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isActionDisabled)

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 14)

            // Right side: session menu (click to open)
            Menu {
                menuContent
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(sessions.isEmpty && onNewSession == nil)
        }
        .background(isActionDisabled ? Color.gray : Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        ForEach(0 ..< sessions.count, id: \.self) { index in
            let session = sessions[index]
            Button {
                selectedSessionId = session.id
            } label: {
                HStack {
                    if session.id == selectedSessionId {
                        Image(systemName: "checkmark")
                    }
                    Text(sessionLabel(for: session))
                    Spacer()
                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if onNewSession != nil {
            Divider()

            Button {
                onNewSession?()
            } label: {
                Label("New Session", systemImage: "plus.rectangle")
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            EmptyView()
        case .dispatching:
            ProgressView()
                .scaleEffect(0.6)
                .padding(.leading, 8)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .padding(.leading, 8)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.leading, 8)
        }
    }

    // MARK: - Helpers

    private func sessionLabel(for session: TerminalSession) -> String {
        var label = cleanedName(session.name)
        if session.claudeSessionId != nil {
            label += " \u{2726}" // ✦
        }
        if session.id == sessionManager.activeSessionId {
            label += " \u{25CF}" // ●
        }
        return label
    }

    func performDispatch(sessionId: UUID) {
        status = .dispatching
        Task {
            await onDispatch(sessionId)
            withAnimation {
                status = .success
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                status = .idle
            }
        }
    }
}

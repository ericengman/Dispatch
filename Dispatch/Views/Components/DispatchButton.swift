//
//  DispatchButton.swift
//  Dispatch
//
//  Unified dispatch button component for sending prompts/skills to Terminal
//

import Combine
import SwiftUI

// MARK: - Execute Now Settings Storage

/// Stores per-skill "Execute Now" settings
class ExecuteNowSettings: ObservableObject {
    static let shared = ExecuteNowSettings()

    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "executeNow_"

    /// Gets the execute now setting for a skill (defaults to true)
    func isExecuteNow(for skillId: String) -> Bool {
        // If no setting exists, default to true
        if userDefaults.object(forKey: keyPrefix + skillId) == nil {
            return true
        }
        return userDefaults.bool(forKey: keyPrefix + skillId)
    }

    /// Sets the execute now setting for a skill
    func setExecuteNow(_ value: Bool, for skillId: String) {
        userDefaults.set(value, forKey: keyPrefix + skillId)
        objectWillChange.send()
    }

    /// Toggles the execute now setting for a skill
    func toggleExecuteNow(for skillId: String) {
        let current = isExecuteNow(for: skillId)
        setExecuteNow(!current, for: skillId)
    }
}

// MARK: - Dispatch Status

enum DispatchStatus: Equatable {
    case idle
    case dispatching
    case success
    case error(String)
}

// MARK: - Dispatch Button for Prompts

struct DispatchButton: View {
    let terminals: [TerminalWindow]
    let isDisabled: Bool
    let onDispatch: (TerminalWindow?) -> Void // nil means new session
    let onNewSession: () -> Void

    @State private var status: DispatchStatus = .idle

    var body: some View {
        HStack(spacing: 0) {
            if terminals.count == 1 {
                // Single terminal: split button (main dispatches, chevron shows menu)
                singleTerminalButton
            } else {
                // Multiple or no terminals: full dropdown
                multipleTerminalButton
            }

            // Status indicator
            statusIndicator
        }
    }

    // MARK: - Single Terminal (Split Button)

    private var singleTerminalButton: some View {
        HStack(spacing: 0) {
            // Main dispatch area (left side)
            Button {
                dispatchToTerminal(terminals.first)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                    Text("Dispatch")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || status == .dispatching)
            .keyboardShortcut(.return, modifiers: .shift)

            // Separator inside button
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 14)

            // Dropdown chevron area (right side)
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
            .disabled(isDisabled)
        }
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Multiple Terminals (Full Dropdown)

    private var multipleTerminalButton: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                Text("Dispatch")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled || status == .dispatching)
        .keyboardShortcut(.return, modifiers: .shift)
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        // Terminal options with number key shortcuts (1, 2, 3, ...)
        ForEach(0 ..< terminals.count, id: \.self) { index in
            let terminal = terminals[index]
            Button {
                dispatchToTerminal(terminal)
            } label: {
                HStack {
                    Label(terminal.displayNameWithStatus, systemImage: "terminal")
                    Spacer()
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        }

        if !terminals.isEmpty {
            Divider()
        }

        // New session option - use 0 for new
        Button {
            dispatchToNewSession()
        } label: {
            HStack {
                Label("New Claude Session", systemImage: "plus.rectangle")
                Spacer()
                Text("0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .keyboardShortcut("0", modifiers: [])
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

    // MARK: - Actions

    private func dispatchToTerminal(_ terminal: TerminalWindow?) {
        status = .dispatching

        // Call the dispatch handler
        onDispatch(terminal)

        // Show success after a brief delay (simulating completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                status = .success
            }
            // Reset after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    status = .idle
                }
            }
        }
    }

    private func dispatchToNewSession() {
        status = .dispatching
        onNewSession()

        // For new session, takes longer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                status = .success
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    status = .idle
                }
            }
        }
    }
}

// MARK: - Compact Dispatch Button for Skills

struct CompactDispatchButton: View {
    let skillId: String
    let terminals: [TerminalWindow]
    let onDispatch: (TerminalWindow, Bool) -> Void // (terminal, pressEnter)
    let onNewSession: (Bool) -> Void // (pressEnter)

    @ObservedObject private var executeNowSettings = ExecuteNowSettings.shared
    @State private var status: DispatchStatus = .idle

    private var executeNow: Bool {
        executeNowSettings.isExecuteNow(for: skillId)
    }

    var body: some View {
        HStack(spacing: 4) {
            if terminals.count == 1 {
                // Single terminal: split button
                singleTerminalButton
            } else {
                // Multiple or no terminals: full dropdown
                multipleTerminalButton
            }

            // Status indicator
            statusIndicator
        }
    }

    // MARK: - Single Terminal (Split Button)

    private var singleTerminalButton: some View {
        HStack(spacing: 0) {
            // Main dispatch area (left side)
            Button {
                dispatchToTerminal(terminals.first!)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                    Text("Dispatch")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(status == .dispatching)

            // Separator inside button
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 12)

            // Dropdown chevron area (right side)
            Menu {
                menuContent
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Multiple Terminals (Full Dropdown)

    private var multipleTerminalButton: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 9))
                Text("Dispatch")
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(status == .dispatching)
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        // Terminal options with number key shortcuts (1, 2, 3, ...)
        ForEach(0 ..< terminals.count, id: \.self) { index in
            let terminal = terminals[index]
            Button {
                dispatchToTerminal(terminal)
            } label: {
                HStack {
                    Label(terminal.displayNameWithStatus, systemImage: "terminal")
                    Spacer()
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        }

        if !terminals.isEmpty {
            Divider()
        }

        // New session option - use 0 for new
        Button {
            dispatchToNewSession()
        } label: {
            HStack {
                Label("New Claude Session", systemImage: "plus.rectangle")
                Spacer()
                Text("0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .keyboardShortcut("0", modifiers: [])

        Divider()

        // Execute Now toggle
        Toggle(isOn: Binding(
            get: { executeNow },
            set: { executeNowSettings.setExecuteNow($0, for: skillId) }
        )) {
            Label("Execute Now", systemImage: executeNow ? "play.fill" : "pause.fill")
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
                .scaleEffect(0.5)
                .padding(.leading, 4)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 10))
                .padding(.leading, 4)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 10))
                .padding(.leading, 4)
        }
    }

    // MARK: - Actions

    private func dispatchToTerminal(_ terminal: TerminalWindow) {
        status = .dispatching
        onDispatch(terminal, executeNow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                status = .success
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    status = .idle
                }
            }
        }
    }

    private func dispatchToNewSession() {
        status = .dispatching
        onNewSession(executeNow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                status = .success
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    status = .idle
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Single terminal
        DispatchButton(
            terminals: [
                TerminalWindow(id: "1", name: "Test", tabTitle: "Session 1", isActive: true)
            ],
            isDisabled: false,
            onDispatch: { _ in },
            onNewSession: {}
        )

        // Multiple terminals
        DispatchButton(
            terminals: [
                TerminalWindow(id: "1", name: "Test 1", tabTitle: "Session 1", isActive: true),
                TerminalWindow(id: "2", name: "Test 2", tabTitle: "Session 2", isActive: false)
            ],
            isDisabled: false,
            onDispatch: { _ in },
            onNewSession: {}
        )

        // No terminals
        DispatchButton(
            terminals: [],
            isDisabled: false,
            onDispatch: { _ in },
            onNewSession: {}
        )

        Divider()

        // Compact versions
        CompactDispatchButton(
            skillId: "test-skill",
            terminals: [
                TerminalWindow(id: "1", name: "Test", tabTitle: nil, isActive: true)
            ],
            onDispatch: { _, _ in },
            onNewSession: { _ in }
        )
    }
    .padding()
}

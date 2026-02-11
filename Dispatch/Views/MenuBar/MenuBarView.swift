//
//  MenuBarView.swift
//  Dispatch
//
//  Menu bar popover view for quick access
//

import SwiftUI

struct MenuBarPopoverView: View {
    // MARK: - Environment

    @Environment(\.openWindow) private var openWindow

    // MARK: - State

    @State private var searchText = ""
    @StateObject private var promptVM = PromptViewModel()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search prompts...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary)

            Divider()

            // Recent starred prompts
            if !recentStarredPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Starred")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(recentStarredPrompts) { prompt in
                        Button {
                            sendPrompt(prompt)
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)

                                Text(prompt.displayTitle)
                                    .lineLimit(1)

                                Spacer()

                                if let project = prompt.project {
                                    Circle()
                                        .fill(project.color)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.001))
                    }
                }
            }

            Divider()

            // Actions
            VStack(spacing: 0) {
                Button {
                    openMainWindow()
                } label: {
                    HStack {
                        Text("Open Dispatch")
                        Spacer()
                        Text("⌘O")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    openSettings()
                } label: {
                    HStack {
                        Text("Settings...")
                        Spacer()
                        Text("⌘,")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Text("Quit")
                        Spacer()
                        Text("⌘Q")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
    }

    // MARK: - Computed Properties

    private var recentStarredPrompts: [Prompt] {
        promptVM.prompts
            .filter { $0.isStarred }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Actions

    private func sendPrompt(_ prompt: Prompt) {
        Task {
            try? await promptVM.sendPrompt(prompt)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Menu Bar Icon View

struct MenuBarIconView: View {
    @ObservedObject var executionState = ExecutionStateMachine.shared

    var body: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        if executionState.state.isActive {
            return "paperplane.fill"
        }
        return "paperplane"
    }
}

// MARK: - Preview

#Preview {
    MenuBarPopoverView()
        .frame(height: 400)
}

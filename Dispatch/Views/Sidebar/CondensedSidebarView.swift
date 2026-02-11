//
//  CondensedSidebarView.swift
//  Dispatch
//
//  Icon-only sidebar strip (~60px) for condensed mode.
//  Shows project icons with blue activity dots for projects with open terminal sessions.
//

import SwiftUI

struct CondensedSidebarView: View {
    @Binding var selection: NavigationSelection?
    var onToggleExpand: () -> Void

    @EnvironmentObject private var projectVM: ProjectViewModel
    private let sessionManager = TerminalSessionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(projectVM.projects) { project in
                        condensedIcon(for: project)
                            .onTapGesture {
                                selection = .project(project.id)
                            }
                    }
                }
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            // Expand button
            Button {
                onToggleExpand()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .frame(width: 60)
        .background(.bar)
    }

    // MARK: - Icon View

    @ViewBuilder
    private func condensedIcon(for project: Project) -> some View {
        let isSelected = selection == .project(project.id)
        let hasActiveSessions = !sessionManager.sessionsForProject(
            id: project.id, path: project.path
        ).isEmpty

        VStack(spacing: 4) {
            iconImage(for: project)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

            if hasActiveSessions {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            } else {
                // Spacer to maintain consistent layout
                Color.clear
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 48)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconImage(for project: Project) -> some View {
        if let iconImage = project.iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(project.color.gradient)
                .overlay {
                    Text(project.initial)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }
}

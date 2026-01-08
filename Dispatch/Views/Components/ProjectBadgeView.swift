//
//  ProjectBadgeView.swift
//  Dispatch
//
//  Badge component for displaying project information
//

import SwiftUI

struct ProjectBadgeView: View {
    // MARK: - Properties

    let project: Project

    // MARK: - Configuration

    var showName: Bool = true
    var compact: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(project.color)
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)

            if showName {
                Text(project.name)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Color Only Badge

struct ProjectColorBadge: View {
    let project: Project

    var body: some View {
        Circle()
            .fill(project.color)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProjectBadgeView(project: previewProject)
        ProjectBadgeView(project: previewProject, compact: true)
        ProjectColorBadge(project: previewProject)
    }
    .padding()
}

private var previewProject: Project {
    Project(name: "Test Project", colorHex: "#4DABF7")
}

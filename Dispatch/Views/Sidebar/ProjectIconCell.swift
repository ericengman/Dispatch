//
//  ProjectIconCell.swift
//  Dispatch
//
//  Compact icon cell for project grid view in sidebar
//

import SwiftUI

struct ProjectIconCell: View {
    let project: Project

    var body: some View {
        VStack(spacing: 4) {
            iconView
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(project.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
        .frame(width: 64)
    }

    @ViewBuilder
    private var iconView: some View {
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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }
}

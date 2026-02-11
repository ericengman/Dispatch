//
//  ResizeHandleView.swift
//  Dispatch
//
//  Draggable resize handle between stacked terminal panes
//

import SwiftUI

struct ResizeHandleView: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Hit area
            Color.clear

            // Visible divider line
            Rectangle()
                .fill(Color.primary.opacity(isHovered ? 0.2 : 0.08))
                .frame(height: 2)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        Color.black.frame(height: 200)
        ResizeHandleView()
        Color.black.frame(height: 200)
    }
    .frame(width: 400)
}

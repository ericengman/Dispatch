//
//  SearchBarView.swift
//  Dispatch
//
//  Reusable search bar component
//

import SwiftUI

struct SearchBarView: View {
    // MARK: - Binding

    @Binding var text: String

    // MARK: - Properties

    var placeholder: String = "Search..."

    // MARK: - State

    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    SearchBarView(text: .constant("test"))
        .padding()
        .frame(width: 300)
}

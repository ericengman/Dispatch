//
//  TerminalPickerView.swift
//  Dispatch
//
//  Picker component for selecting Terminal windows
//

import SwiftUI

@available(*, deprecated, message: "Terminal.app window selection is no longer used. Embedded terminal uses active session.")
struct TerminalPickerView: View {
    // MARK: - Properties

    var selectedId: String?
    var selectedName: String?
    var onSelect: (String?, String?) -> Void

    // MARK: - State

    @State private var windows: [TerminalWindow] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var useAutoDetect = true

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(selectedId: String?, selectedName: String?, onSelect: @escaping (String?, String?) -> Void) {
        self.selectedId = selectedId
        self.selectedName = selectedName
        self.onSelect = onSelect
        _useAutoDetect = State(initialValue: selectedId == nil)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading Terminal windows...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            fetchWindows()
                        }
                    }
                } else {
                    windowList
                }
            }
            .frame(width: 350, height: 300)
            .navigationTitle("Select Terminal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        fetchWindows()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            fetchWindows()
        }
    }

    // MARK: - Window List

    private var windowList: some View {
        List {
            // Auto-detect option
            Button {
                onSelect(nil, nil)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: useAutoDetect ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(useAutoDetect ? .blue : .secondary)

                    VStack(alignment: .leading) {
                        Text("Active Window (Auto-detect)")
                            .font(.body)

                        Text("Uses the frontmost Terminal window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if !windows.isEmpty {
                Section("Available Windows") {
                    ForEach(windows) { window in
                        Button {
                            onSelect(window.id, window.displayName)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: selectedId == window.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedId == window.id ? .blue : .secondary)

                                VStack(alignment: .leading) {
                                    Text(window.displayName)
                                        .font(.body)

                                    if window.isActive {
                                        Text("Currently active")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Spacer()

                                if window.isActive {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func fetchWindows() {
        isLoading = true
        error = nil

        Task {
            do {
                let fetchedWindows = try await TerminalService.shared.getWindows(forceRefresh: true)

                await MainActor.run {
                    self.windows = fetchedWindows
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Inline Terminal Picker

@available(*, deprecated, message: "Terminal.app window selection is no longer used.")
struct InlineTerminalPicker: View {
    @Binding var selectedId: String?
    @Binding var selectedName: String?

    @State private var windows: [TerminalWindow] = []
    @State private var showingPicker = false

    var body: some View {
        Menu {
            Button {
                selectedId = nil
                selectedName = nil
            } label: {
                HStack {
                    Text("Active Window (Auto-detect)")
                    if selectedId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !windows.isEmpty {
                Divider()

                ForEach(windows) { window in
                    Button {
                        selectedId = window.id
                        selectedName = window.displayName
                    } label: {
                        HStack {
                            Text(window.displayName)
                            if selectedId == window.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                refreshWindows()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Label(selectedName ?? "Active Window", systemImage: "terminal")
        }
        .onAppear {
            refreshWindows()
        }
    }

    private func refreshWindows() {
        Task {
            do {
                windows = try await TerminalService.shared.getWindows(forceRefresh: true)
            } catch {
                logError("Failed to refresh terminal windows: \(error)", category: .terminal)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TerminalPickerView(selectedId: nil, selectedName: nil) { id, name in
        print("Selected: \(id ?? "auto") - \(name ?? "active")")
    }
}

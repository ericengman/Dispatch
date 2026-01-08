//
//  QueuePanelView.swift
//  Dispatch
//
//  Collapsible panel for managing the prompt queue
//

import SwiftUI

struct QueuePanelView: View {
    // MARK: - Environment

    @EnvironmentObject private var queueVM: QueueViewModel

    // MARK: - State

    @State private var showingClearConfirmation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            queueHeader

            Divider()

            // Queue content
            if queueVM.isEmpty {
                emptyStateView
            } else {
                queueList
            }
        }
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "Clear all items from queue?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Queue", role: .destructive) {
                queueVM.clearQueue()
            }
        }
    }

    // MARK: - Header

    private var queueHeader: some View {
        HStack {
            Label("Queue (\(queueVM.count))", systemImage: "tray.full")
                .font(.headline)

            Spacer()

            // Run controls
            if !queueVM.isEmpty {
                if queueVM.isRunningAll {
                    Button {
                        queueVM.stopRunAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await queueVM.runNext()
                            }
                        } label: {
                            Label("Run Next", systemImage: "play.fill")
                        }
                        .disabled(queueVM.isExecuting || !queueVM.hasReadyItems)

                        Button {
                            Task {
                                await queueVM.runAll()
                            }
                        } label: {
                            Label("Run All", systemImage: "forward.fill")
                        }
                        .disabled(queueVM.isExecuting || !queueVM.hasReadyItems)
                    }
                }

                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(queueVM.isExecuting)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Queue List

    private var queueList: some View {
        List {
            ForEach(queueVM.items) { item in
                QueueItemRowView(item: item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
            .onMove { source, destination in
                if let from = source.first {
                    queueVM.moveItem(from: from, to: destination)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    queueVM.removeFromQueue(queueVM.items[index])
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Queue Empty", systemImage: "tray")
        } description: {
            Text("Add prompts to the queue to execute them sequentially.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue Item Row View

struct QueueItemRowView: View {
    @EnvironmentObject private var queueVM: QueueViewModel

    let item: QueueItem

    @State private var showingTerminalPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Order number
            Text("\(item.order + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                if !item.previewText.isEmpty && item.previewText != item.displayTitle {
                    Text(item.previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status indicator
            statusIndicator

            // Terminal target
            Button {
                showingTerminalPicker = true
            } label: {
                Label(item.targetDescription, systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Remove button
            Button {
                queueVM.removeFromQueue(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!item.canRemove)
        }
        .padding(.vertical, 4)
        .opacity(item.status == .completed ? 0.5 : 1)
        .sheet(isPresented: $showingTerminalPicker) {
            TerminalPickerView(
                selectedId: item.targetTerminalId,
                selectedName: item.targetTerminalName
            ) { id, name in
                queueVM.updateTarget(for: item, windowId: id, windowName: name)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .executing:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Preview

#Preview {
    QueuePanelView()
        .environmentObject(QueueViewModel.shared)
        .frame(height: 200)
}

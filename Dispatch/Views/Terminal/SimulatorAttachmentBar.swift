//
//  SimulatorAttachmentBar.swift
//  Dispatch
//
//  Thin indicator bar showing attached simulator windows with detach/reattach controls
//

import SwiftUI

struct SimulatorAttachmentBar: View {
    @Bindable var attacher: SimulatorWindowAttacher

    var body: some View {
        if !attacher.attachments.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                ForEach(attacher.attachments) { attachment in
                    attachmentChip(attachment)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: SimulatorAttachment) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(attachment.isAttached ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            Text(attachment.deviceName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(attachment.isAttached ? .primary : .tertiary)

            if attachment.isAttached {
                Button {
                    attacher.detachSimulator(id: attachment.id)
                } label: {
                    Text("Detach")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    attacher.reattachSimulator(id: attachment.id)
                } label: {
                    Text("Reattach")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

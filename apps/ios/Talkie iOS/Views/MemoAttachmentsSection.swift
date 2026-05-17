//
//  MemoAttachmentsSection.swift
//  Talkie iOS
//
//  Image attachments for a voice memo.
//

import SwiftUI

struct MemoAttachmentsSection: View {
    let attachments: [MemoImageAttachment]
    let imageProvider: (MemoImageAttachment) -> UIImage?
    let onAdd: () -> Void
    let onSelect: (MemoImageAttachment) -> Void
    let onRemove: (MemoImageAttachment) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96), spacing: Spacing.xs)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                TalkieEyebrow(text: "Attachments")

                if !attachments.isEmpty {
                    Text("\(attachments.count)")
                        .font(.techLabelSmall)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 4)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.sm)
                }

                Spacer()

                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.techLabelSmall)
                            .tracking(1)
                    }
                    .foregroundColor(.active)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.active.opacity(0.08))
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }

            if attachments.isEmpty {
                Button(action: onAdd) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.active)

                        VStack(spacing: 2) {
                            Text("Add screenshots or photos")
                                .font(.bodySmall)
                                .foregroundColor(.textPrimary)

                            Text("Keep visual context with the memo.")
                                .font(.techLabelSmall)
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(
                                Color.borderPrimary,
                                style: StrokeStyle(lineWidth: 0.5, dash: [5, 3])
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.xs) {
                    ForEach(attachments) { attachment in
                        MemoAttachmentTile(
                            attachment: attachment,
                            image: imageProvider(attachment),
                            onSelect: { onSelect(attachment) },
                            onRemove: { onRemove(attachment) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }
}

private struct MemoAttachmentTile: View {
    let attachment: MemoImageAttachment
    let image: UIImage?
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.surfaceSecondary
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

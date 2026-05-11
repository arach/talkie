//
//  TOAttachmentsSection.swift
//  Talkie
//
//  File attachments section — browse, drop, manage attached files.
//  Self-gates: always shows (attachments can be added at any time).
//

import SwiftUI
import TalkieKit

struct TOAttachmentsSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    @Binding var localAttachments: [RecordingAttachment]
    var onPickFiles: () -> Void = {}
    var onRemoveAttachment: (RecordingAttachment) -> Void = { _ in }

    private var countText: String { "\(localAttachments.count)" }

    var body: some View {
        if !localAttachments.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header
                HStack(alignment: .center, spacing: Spacing.xs) {
                    Text("ATTACHMENTS")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(countText)
                        .font(settings.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(Theme.current.foreground.opacity(0.08))
                        .clipShape(Capsule())

                    Spacer()

                    Button {
                        onPickFiles()
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "plus")
                                .font(settings.fontXS)
                            Text("Add")
                                .font(settings.fontXSMedium)
                        }
                        .foregroundColor(settings.resolvedAccentColor)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(settings.resolvedAccentColor.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(settings.resolvedAccentColor.opacity(0.2), lineWidth: BorderWidth.thin)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if slot.mode == .gallery {
                    galleryLayout
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(localAttachments) { attachment in
                            attachmentRow(attachment)
                        }
                        dropZone
                    }
                }
            }
        }
    }

    // MARK: - Gallery Layout

    private var galleryLayout: some View {
        VStack(spacing: Spacing.sm) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(localAttachments) { attachment in
                    galleryTile(attachment)
                }
            }
            dropZone
        }
    }

    private func galleryTile(_ attachment: RecordingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if attachment.kind == .image, let image = loadImage(attachment) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: attachment.kind.icon)
                        .font(.system(size: 18))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text(attachment.originalName)
                        .font(settings.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 108)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Theme.current.foreground.opacity(0.04))
                )
            }

            // Delete button
            Button { onRemoveAttachment(attachment) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(settings.fontSM)
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    // MARK: - List Layout

    private func attachmentRow(_ attachment: RecordingAttachment) -> some View {
        HStack(spacing: Spacing.sm) {
            if attachment.kind == .image, let image = loadImage(attachment) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: attachment.kind.icon)
                    .font(settings.fontSM)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(attachment.originalName)
                    .font(settings.contentFontBody)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                Text(attachment.formattedSize)
                    .font(settings.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            Button {
                let url = AttachmentStorage.url(for: attachment.filename)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(settings.fontSM)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            Button { onRemoveAttachment(attachment) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(settings.fontSM)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.foreground.opacity(0.03))
        )
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        Button(action: { onPickFiles() }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 13, weight: .regular))
                Text(localAttachments.isEmpty ? "Drop files here or click to browse" : "Add more files")
                    .font(settings.fontSM)
            }
            .foregroundColor(Theme.current.foregroundMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, localAttachments.isEmpty ? Spacing.lg : Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Theme.current.foreground.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(
                        Theme.current.foregroundMuted.opacity(0.16),
                        style: StrokeStyle(lineWidth: BorderWidth.normal, dash: [5, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadImage(_ attachment: RecordingAttachment) -> NSImage? {
        let url = AttachmentStorage.url(for: attachment.filename)
        return NSImage(contentsOf: url)
    }
}

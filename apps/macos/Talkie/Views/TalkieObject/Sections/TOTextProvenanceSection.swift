//
//  TOTextProvenanceSection.swift
//  Talkie
//
//  Displays provenance receipts for text that was offered to this object from
//  non-user sources (OCR, paste, workflow). Never auto-applied to canonical text.
//  Each segment has explicit Insert / Copy / Dismiss actions.
//

import AppKit
import SwiftUI
import TalkieKit

struct TOTextProvenanceSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    var onInsert: (ProvenanceSegment) -> Void = { _ in }
    var onDismiss: (ProvenanceSegment) -> Void = { _ in }

    private var segments: [ProvenanceSegment] {
        recording.assets?.textProvenance ?? []
    }

    var body: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                VStack(spacing: Spacing.xs) {
                    ForEach(segments) { segment in
                        segmentRow(segment)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            Text("TEXT PROVENANCE")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("\(segments.count)")
                .font(settings.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(Theme.current.foreground.opacity(0.08))
                .clipShape(Capsule())

            Spacer()

            Text("Receipts — insert or dismiss. Canonical text stays yours.")
                .font(settings.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func segmentRow(_ segment: ProvenanceSegment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                sourceBadge(segment.source)

                if let detail = segment.sourceDetail, !detail.isEmpty {
                    Text(detail)
                        .font(settings.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Text(segment.timestamp.formatted(.relative(presentation: .named)))
                    .font(settings.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                if segment.appliedAt != nil {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(settings.fontXS)
                        Text("Applied")
                            .font(settings.fontXS)
                    }
                    .foregroundColor(settings.resolvedAccentColor)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(segment.originalText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(settings.fontXS)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundMuted)
                .help("Copy")

                Button { onInsert(segment) } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "text.insert")
                            .font(settings.fontXS)
                        Text("Insert")
                            .font(settings.fontXSMedium)
                    }
                    .foregroundColor(settings.resolvedAccentColor)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(settings.resolvedAccentColor.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help("Append to canonical text")

                Button { onDismiss(segment) } label: {
                    Image(systemName: "trash")
                        .font(settings.fontXS)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundMuted)
                .help("Dismiss receipt")
            }

            Text(segment.originalText)
                .font(settings.contentFontBody)
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
                .lineLimit(6)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.foreground.opacity(0.03))
        )
    }

    private func sourceBadge(_ source: ProvenanceSegment.Source) -> some View {
        let label: String = {
            switch source {
            case .ocr: return "OCR"
            case .paste: return "PASTE"
            case .dictation: return "DICTATION"
            case .userEdit: return "EDIT"
            case .workflow: return "WORKFLOW"
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(Tracking.wide)
            .foregroundColor(Theme.current.foreground)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.current.foreground.opacity(0.1))
            )
    }
}

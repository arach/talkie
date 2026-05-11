//
//  TOHeaderSection.swift
//  Talkie
//
//  Header section — title, type badge, metadata row, edit controls.
//  Always present for every TalkieObject.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct TOHeaderSection: View {
    let recording: TalkieObject
    let settings: SettingsManager

    var isEditing: Bool = false
    var isAlwaysEditable: Bool = false
    @Binding var editedTitle: String
    @FocusState.Binding var titleFieldFocused: Bool

    var onToggleEdit: () -> Void = {}
    var onCancelEdit: () -> Void = {}
    var onSaveEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenInCompose: (() -> Void)? = nil
    var isDirty: Bool = false
    var onTitleChange: (() -> Void)? = nil

    private let repository = TalkieObjectRepository()
    private var metadataFont: Font { settings.fontSM }
    private var headerFont: Font {
        settings.fontTitleMedium
    }

    // MARK: - Body

    var body: some View {
        if isAlwaysEditable {
            // Notes: no title header — the NoteComposeCard first line IS the title.
            EmptyView()
        } else {
            // Memos, dictations, segments: show title + controls
            HStack(alignment: .top, spacing: Spacing.sm) {
                if isEditing {
                    TextField("Title", text: $editedTitle)
                        .font(headerFont)
                        .foregroundColor(Theme.current.foreground)
                        .textFieldStyle(.plain)
                        .focused($titleFieldFocused)
                        .onChange(of: editedTitle) { _, _ in onTitleChange?() }
                } else {
                    Text(headerTitle)
                        .font(headerFont)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isEditing {
                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") { onCancelEdit() }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Button("Save") { onSaveEdit() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!isDirty)
                    }
                } else {
                    HStack(spacing: Spacing.xs) {
                        if let onOpenInCompose {
                            Button(action: onOpenInCompose) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Theme.current.foreground.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Open in Compose")
                        }

                        Button(action: { onToggleEdit() }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.current.foreground.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Edit")
                    }
                }
            }
        }
    }

    // Metadata row removed — now in TOMetadataRow

    // MARK: - Computed

    private var headerTitle: String {
        if recording.isDictation {
            return formatDateProminent(recording.createdAt)
        }

        if let title = recording.title, !title.isEmpty {
            return title
        }

        switch recording.type {
        case .note:
            return "Untitled Note"
        case .memo:
            return "Untitled Memo"
        case .segment:
            return "Untitled Segment"
        case .dictation:
            return formatDateProminent(recording.createdAt)
        case .selection:
            return formatDateProminent(recording.createdAt)
        case .capture:
            return "Untitled Capture"
        }
    }

    private var provenanceIcon: String {
        if recording.isDictation {
            return "mic.fill"
        } else {
            switch recording.source {
            case .iphone: return "iphone"
            case .watch: return "applewatch"
            case .mac: return "desktopcomputer"
            case .live: return "mic.fill"
            }
        }
    }

    // MARK: - Type Badge

    @State private var showingTypePicker = false

    private var typeBadgePill: some View {
        let typeColor: Color = switch recording.type {
        case .memo: .blue
        case .dictation: .cyan
        case .note: .orange
        case .segment: .gray
        case .selection: .teal
        case .capture: .pink
        }

        return Menu {
            ForEach(TalkieObjectType.allCases, id: \.self) { recordingType in
                Button {
                    changeType(to: recordingType)
                } label: {
                    Label(recordingType.displayName, systemImage: recordingType.icon)
                }
                .disabled(recording.type == recordingType)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: recording.type.icon)
                    .font(settings.fontXS)

                Text(recording.type.displayName)
                    .font(settings.fontXSMedium)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundColor(typeColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(typeColor.opacity(0.15))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var promotedBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "arrow.up.circle.fill")
                .font(settings.fontXS)
            Text("Promoted")
                .font(settings.fontXSMedium)
        }
        .foregroundColor(.green.opacity(0.8))
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(Capsule().fill(Color.green.opacity(0.1)))
    }

    private var metadataDivider: some View {
        Text("\u{00B7}")
            .font(metadataFont)
            .foregroundColor(Theme.current.foregroundMuted)
    }

    private var overflowMenu: some View {
        Menu {
            if let onOpenInCompose {
                Button(action: onOpenInCompose) {
                    Label("Open in Compose", systemImage: "square.and.pencil")
                }
                Divider()
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.current.foreground.opacity(0.08))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Actions

    private func changeType(to newType: TalkieObjectType) {
        guard newType != recording.type else { return }
        Task {
            do {
                var updated = recording
                updated.type = newType
                updated.lastModified = Date()

                switch (recording.type, newType) {
                case (.note, .memo), (.dictation, .memo):
                    updated.promotedAt = Date()
                    updated.cloudSyncedAt = nil
                case (.memo, .note), (.memo, .dictation):
                    updated.cloudSyncedAt = nil
                default:
                    break
                }

                try await repository.saveRecording(updated)
                await RecordingsViewModel.shared.loadRecordings()
                log.info("Changed recording \(recording.id) type from \(recording.type.rawValue) to \(newType.rawValue)")
            } catch {
                log.error("Failed to change type: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Formatting

    private func formatDateProminent(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE 'at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        }

        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Metadata Row

/// Structured metadata cells aligned with the secondary band (filter bar height).
/// Each cell is a discrete chip showing one facet of the recording's identity.
struct TOMetadataRow: View {
    let recording: TalkieObject
    let settings: SettingsManager

    @State private var copiedRefID = false

    private var typeColor: Color {
        switch recording.type {
        case .memo: .blue
        case .dictation: .cyan
        case .note: .orange
        case .segment: .gray
        case .selection: .teal
        case .capture: .pink
        }
    }

    private var sourceIcon: String {
        switch recording.source {
        case .mac: "desktopcomputer"
        case .iphone: "iphone"
        case .watch: "applewatch"
        case .live: "mic.fill"
        }
    }

    private var sourceLabel: String {
        recording.source.displayName
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Type cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: recording.type.icon)
                    Text(recording.type.displayName)
                }
                .foregroundColor(typeColor)
            }

            cellDivider

            // Source cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                    Text(sourceLabel)
                }
            }

            cellDivider

            // Date cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(formatDate(recording.createdAt))
                }
            }

            // Duration cell — only for types with audio, not notes
            if !recording.isNote && recording.duration > 0 {
                cellDivider

                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(recording.duration))
                            .monospacedDigit()
                    }
                }
            }

            // Word count cell
            if recording.wordCount > 0 {
                cellDivider

                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                        Text("\(recording.wordCount) words")
                    }
                }
            }

            cellDivider

            // Ref cell — truncated UUID, click to copy full ID
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recording.id.uuidString, forType: .string)
                copiedRefID = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedRefID = false }
            } label: {
                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: copiedRefID ? "checkmark" : "number")
                        Text(recording.id.uuidString.prefix(8).lowercased())
                            .monospaced()
                    }
                    .foregroundColor(copiedRefID ? .green : Theme.current.foregroundMuted)
                }
            }
            .buttonStyle(.plain)
            .help("Copy full ID")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RecordingsHeaderLayout.secondaryBandHeight)
    }

    // MARK: - Cell Components

    private func metadataCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(settings.fontXS)
            .foregroundColor(Theme.current.foregroundSecondary)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Theme.current.foregroundMuted.opacity(0.3))
            .frame(width: BorderWidth.thin, height: 12)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d, h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }

        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

//
//  RecentlyDeletedView.swift
//  Talkie
//
//  Recently Deleted — surfaces soft-deleted memos / notes / dictations
//  so users can restore or permanently remove them. Without this
//  surface the only way to recover a soft-deleted record is through
//  the Cloud Manager (Sync Panel), which is buried in Settings and
//  only loosely associated with "I just deleted that — give it back."
//
//  Loads `TalkieObjectRepository.fetchPendingDeletions()` and renders
//  each as a one-row entry. Two per-row actions:
//    • Restore — clears `deletedAt` via `restoreRecording(id:)`
//    • Delete Permanently — confirmation alert, then
//      `hardDeleteRecording(id:)`
//
//  Channel-tag chrome borrows ScopeLibraryView's vocabulary without
//  the inspector column, so the page reads as a flat trash list.
//

import SwiftUI
import TalkieKit

// MARK: - Local font helper
//
// ScopeLibraryView/ScopeLibraryEmptyState both keep a fileprivate
// font helper because the bundled Cormorant family has slight
// PostScript-name variants across builds. Duplicating here so this
// surface stays self-contained.
private enum RecentlyDeletedFont {
    static func display(size: CGFloat) -> Font {
        for name in ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"] {
            #if os(macOS)
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            #endif
        }
        return .system(size: size, weight: .regular, design: .serif)
    }
}

// MARK: - RecentlyDeletedView

struct RecentlyDeletedView: View {
    private let repository = TalkieObjectRepository()

    @State private var items: [TalkieObject] = []
    @State private var isLoading: Bool = true
    @State private var pendingHardDelete: TalkieObject?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactScopePageHeader(
                title: "Recently Deleted",
                subtitle: "Memos and notes you've removed"
            )
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScopeRule(.subtle)
                .padding(.horizontal, 32)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .task { await reload() }
        .alert(
            "Delete Permanently?",
            isPresented: Binding(
                get: { pendingHardDelete != nil },
                set: { if !$0 { pendingHardDelete = nil } }
            ),
            presenting: pendingHardDelete
        ) { target in
            Button("Delete Permanently", role: .destructive) {
                Task { await hardDelete(target) }
            }
            Button("Cancel", role: .cancel) {
                pendingHardDelete = nil
            }
        } message: { target in
            Text("\"\(rowTitle(for: target))\" will be removed for good. This cannot be undone.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                BrailleSpinner(size: 18)
                    .foregroundColor(ThemedScopeInk.faint)
                Text("Loading…")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ThemedScopeInk.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ThemedScopeInk.faint)
            Text("Nothing here. Deleted items appear after you remove them from the library.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ThemedScopeInk.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    RecentlyDeletedRow(
                        recording: item,
                        onRestore: { Task { await restore(item) } },
                        onDeletePermanently: { pendingHardDelete = item }
                    )

                    ScopeRule(.subtle)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await repository.fetchPendingDeletions()
            // Exclude `.segment` children — they aren't user-visible
            // anywhere else in the app and would clutter the list.
            items = fetched.filter { $0.type != .segment }
        } catch {
            items = []
        }
    }

    private func restore(_ item: TalkieObject) async {
        do {
            try await repository.restoreRecording(id: item.id)
            await reload()
        } catch {
            // Surface failure quietly — repository logs the underlying
            // error. We deliberately don't toast here to keep this view
            // self-contained; users can rerun the action if the row
            // doesn't disappear.
            await reload()
        }
    }

    private func hardDelete(_ item: TalkieObject) async {
        pendingHardDelete = nil
        do {
            try await repository.hardDeleteRecording(id: item.id)
            await reload()
        } catch {
            await reload()
        }
    }

    // MARK: - Title heuristic (mirrors ScopeLibraryRow)

    private func rowTitle(for recording: TalkieObject) -> String {
        if let title = recording.title, !title.isEmpty { return title }
        if let preview = recording.transcriptPreview, !preview.isEmpty { return preview }
        return "(untitled)"
    }
}

// MARK: - Row

private struct RecentlyDeletedRow: View {
    let recording: TalkieObject
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ChannelLabel(
                channelLetter,
                color: channelColor,
                strokeColor: ScopeEdge.normal
            )
            .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ThemedScopeInk.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(chromeLine)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ThemedScopeInk.subtle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Restore this item to the library")

                Button(action: onDeletePermanently) {
                    Label("Delete Permanently", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help("Remove this item for good")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background {
            if isHovered {
                ScopeCanvas.canvasOverlay
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    // MARK: - Row helpers (mirrors ScopeLibraryRow)

    private var rowTitle: String {
        if let title = recording.title, !title.isEmpty { return title }
        if let preview = recording.transcriptPreview, !preview.isEmpty { return preview }
        return "(untitled)"
    }

    private var channelLetter: String {
        switch recording.type {
        case .memo: return "M"
        case .dictation: return "D"
        case .note: return "N"
        case .capture: return "C"
        case .selection: return "S"
        case .segment: return "·"
        }
    }

    private var channelColor: Color {
        switch recording.type {
        case .memo: return ScopeKind.memo
        case .dictation: return ScopeKind.dict
        case .note: return ScopeKind.note
        case .capture, .selection: return ScopeKind.capture
        default: return ScopeInk.subtle
        }
    }

    /// Type · deleted-at · duration | word count. Matches the
    /// vocabulary of `ScopeLibraryRow.chromeLine` so the page reads
    /// as the same family of rows.
    private var chromeLine: String {
        var parts: [String] = []
        parts.append(recording.type.displayName.uppercased())
        if let deletedAt = recording.deletedAt {
            parts.append("DELETED \(relative(deletedAt))")
        }
        if recording.duration > 0 {
            parts.append(formatDuration(recording.duration))
        }
        if recording.wordCount > 0 {
            parts.append("\(recording.wordCount)W")
        }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "0:\(String(format: "%02d", secs))"
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date()).uppercased()
    }
}

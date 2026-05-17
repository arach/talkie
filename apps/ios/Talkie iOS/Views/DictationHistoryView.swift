//
//  DictationHistoryView.swift
//  Talkie iOS
//
//  Simple views for keyboard dictation history.
//

import SwiftUI
import CoreData
import TalkieMobileKit

// MARK: - Dictation Row

struct DictationRow: View {
    let dictation: KeyboardDictation
    @State private var showCopied = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d h:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            rowTypeBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(dictation.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if let duration = dictation.durationSeconds, duration > 0 {
                        Text(formatDuration(duration))
                        Text("  \u{00B7}  ").foregroundColor(.textTertiary.opacity(0.5))
                    }
                    Text(formatTimestamp(dictation.timestamp))
                    Spacer()
                }
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            }

            // Copy — minimal secondary target
            Button(action: copyText) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(showCopied ? .success : .textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var rowTypeBadge: some View {
        Image(systemName: "character.cursor.ibeam")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .frame(width: 28, height: 28)
            .background(Color.surfaceSecondary)
            .clipShape(Circle())
    }

    private func copyText() {
        UIPasteboard.general.string = dictation.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }
}

// MARK: - Dictation Detail View

struct DictationDetailView: View {
    let dictation: KeyboardDictation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showCopiedFeedback = false
    @State private var didPromote = false
    var onPromoted: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Main text
                        Text(dictation.text)
                            .font(.body)
                            .foregroundColor(.textPrimary)
                            .textSelection(.enabled)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(12)

                        // Metadata
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            metadataRow(icon: "clock", label: "Created", value: formatFullDate(dictation.timestamp))
                            metadataRow(icon: "text.word.spacing", label: "Words", value: "\(dictation.wordCount)")
                            if let duration = dictation.durationSeconds {
                                metadataRow(icon: "waveform", label: "Duration", value: formatDuration(duration))
                            }
                            if let context = dictation.appContext {
                                metadataRow(icon: "keyboard", label: "Source", value: context)
                            }
                        }
                        .padding(Spacing.md)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(12)

                        // Save as Memo button
                        Button(action: promoteToMemo) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: didPromote ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                                Text(didPromote ? "Saved as Memo" : "Save as Memo")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(didPromote ? .success : .accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(didPromote ? Color.success.opacity(0.1) : Color.accentColor.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .disabled(didPromote)

                        Spacer()
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            SpeechSynthesisService.shared.toggleReadout(dictation.text)
                        } label: {
                            Image(systemName: SpeechSynthesisService.shared.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(SpeechSynthesisService.shared.isSpeaking ? .orange : .accentColor)
                        }

                        Button(action: copyText) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                Text(showCopiedFeedback ? "Copied" : "Copy")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showCopiedFeedback ? .success : .accentColor)
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
        }
    }

    private func copyText() {
        UIPasteboard.general.string = dictation.text
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)

        withAnimation {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func promoteToMemo() {
        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()

        let words = dictation.text.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        memo.title = title.count < dictation.text.count ? title + "…" : title

        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(dictation.timestamp.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        memo.addSystemTranscript(
            content: dictation.text,
            fromMacOS: false,
            engine: "keyboard_dictation"
        )

        do {
            try viewContext.save()
            PersistenceController.refreshWidgetData(context: viewContext)

            KeyboardDictationStore.shared.delete(dictation.id)
            onPromoted?()

            withAnimation { didPromote = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            AppLogger.app.error("Failed to promote dictation to memo: \(error)")
        }
    }
}

// MARK: - Dictation List Section (for homepage)

struct DictationListSection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var dictations: [KeyboardDictation] = []
    @State private var selectedDictation: KeyboardDictation?
    @State private var displayLimit = 10
    @State private var promotedId: UUID?
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        let displayedDictations = Array(dictations.prefix(displayLimit))
        let hasMore = dictations.count > displayLimit

        VStack(spacing: 0) {
            // Header
            HStack {
                TalkieEyebrow(text: "Dictations")

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(themeManager.colors.tableHeaderBackground)

            // List - always show List for consistent layout
            List {
                if dictations.isEmpty {
                    // Empty state as a list row for consistent height
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.textTertiary)
                        TalkieEyebrow(text: "No Dictations", tint: .ink, showLeader: false)
                        Text("Use the keyboard to add dictations")
                            .font(.bodySmall)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(themeManager.colors.tableCellBackground)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(displayedDictations) { dictation in
                        DictationRow(dictation: dictation)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(themeManager.colors.tableCellBackground)
                            .listRowSeparatorTint(themeManager.colors.tableDivider)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDictation = dictation
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    promoteToMemo(dictation)
                                } label: {
                                    Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteDictation(dictation)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                    }

                    // Load More button
                    if hasMore {
                        Button(action: {
                            withAnimation {
                                displayLimit += 10
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Spacer()
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Load \(min(10, dictations.count - displayLimit)) more")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .foregroundColor(themeManager.colors.textSecondary)
                            .padding(.vertical, 14)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(themeManager.colors.tableCellBackground)
                        .listRowSeparatorTint(themeManager.colors.tableDivider)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(themeManager.colors.tableCellBackground)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(themeManager.colors.tableBorder, lineWidth: 0.5)
        )
        .onAppear {
            loadDictations()
        }
        .sheet(item: $selectedDictation) { dictation in
            DictationDetailView(dictation: dictation) {
                withAnimation {
                    dictations.removeAll { $0.id == dictation.id }
                }
            }
        }
    }

    private func loadDictations() {
        KeyboardDictationStore.shared.reload()
        dictations = KeyboardDictationStore.shared.all()
    }

    private func promoteToMemo(_ dictation: KeyboardDictation) {
        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()
        memo.title = deriveMemoTitle(from: dictation.text)
        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(dictation.timestamp.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        // Add the dictation text as the transcript
        memo.addSystemTranscript(
            content: dictation.text,
            fromMacOS: false,
            engine: "keyboard_dictation"
        )

        do {
            try viewContext.save()
            PersistenceController.refreshWidgetData(context: viewContext)

            // Remove from dictation store
            KeyboardDictationStore.shared.delete(dictation.id)
            withAnimation {
                dictations.removeAll { $0.id == dictation.id }
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            AppLogger.app.error("Failed to promote dictation to memo: \(error)")
        }
    }

    private func deriveMemoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count < text.count ? title + "…" : title
    }

    private func deleteDictation(_ dictation: KeyboardDictation) {
        KeyboardDictationStore.shared.delete(dictation.id)
        withAnimation {
            dictations.removeAll { $0.id == dictation.id }
        }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

#Preview {
    DictationListSection()
}

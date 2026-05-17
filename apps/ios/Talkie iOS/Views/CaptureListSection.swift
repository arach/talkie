//
//  CaptureListSection.swift
//  Talkie iOS
//
//  Horizontal scrolling capture cards on the home screen.
//

import SwiftUI
import TalkieMobileKit

// MARK: - Capture Card

struct CaptureCard: View {
    let capture: Capture

    @ObservedObject private var theme = ThemeManager.shared

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

    private var channelCode: String {
        switch capture.sourceType {
        case "photo": return "P"
        case "url":   return "U"
        case "text":  return "T"
        default:      return "C"
        }
    }

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: 0) {
            // Channel + title
            HStack(alignment: .top, spacing: 6) {
                TalkieChannelLabel(code: channelCode)
                Text(capture.title ?? capture.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 8)

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: sourceIcon)
                        .font(.system(size: 9, weight: .medium))
                    Text(capture.sourceType)
                    Text(chrome.eyebrowLeader)
                        .foregroundColor(theme.colors.textTertiary.opacity(0.5))
                    Text("\(capture.wordCount)w")
                }
                .font(.system(size: 10))
                .foregroundColor(theme.colors.textTertiary)

                HStack(spacing: 5) {
                    Image(systemName: capture.syncedToMac ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 8))
                        .foregroundColor(capture.syncedToMac ? theme.colors.success : theme.colors.textTertiary.opacity(0.5))

                    Text(formatTimestamp(capture.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(theme.colors.textTertiary)
                }
            }
        }
        .padding(12)
        .frame(width: 164, height: 112, alignment: .topLeading)
        .bezelChassis(padding: 0, corner: CornerRadius.md)
    }

    private var sourceIcon: String {
        switch capture.sourceType {
        case "photo": return "photo"
        case "url": return "link"
        case "text": return "doc.text"
        default: return "tray.and.arrow.down"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }
}

// MARK: - Capture Row (for list contexts)

struct CaptureRow: View {
    let capture: Capture

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
                Text(capture.title ?? capture.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(sourceLabel)
                    Text("  ·  ").foregroundColor(.textTertiary.opacity(0.5))
                    Text(formatTimestamp(capture.timestamp))
                    Spacer()
                }
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var rowTypeBadge: some View {
        Image(systemName: sourceIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .frame(width: 28, height: 28)
            .background(Color.surfaceSecondary)
            .clipShape(Circle())
    }

    private var sourceIcon: String {
        switch capture.sourceType {
        case "photo": return "photo"
        case "url": return "link"
        case "text": return "doc.text"
        default: return "tray.and.arrow.down"
        }
    }

    private var sourceLabel: String {
        switch capture.sourceType {
        case "photo": return "Photo"
        case "url": return "Link"
        case "text": return "Text"
        default: return "Imported"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }
}

// MARK: - Capture List Section

struct CaptureListSection: View {
    @Binding var selectedCapture: Capture?
    @State private var captures: [Capture] = []
    @State private var isSyncing = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        VStack(spacing: 0) {
            // Header
            HStack {
                TalkieEyebrow(text: "Captures")

                Spacer()

                if !captures.isEmpty {
                    let unsyncedCount = captures.filter { !$0.syncedToMac }.count
                    if unsyncedCount > 0 {
                        Button {
                            syncAll()
                        } label: {
                            HStack(spacing: 4) {
                                if isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                Text(isSyncing ? "Syncing…" : "\(unsyncedCount) pending")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(chrome.accent)
                        }
                        .disabled(isSyncing)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if captures.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(theme.colors.textTertiary)
                    TalkieEyebrow(text: "No Captures", tint: .ink, showLeader: false)
                    Text("Share content from other apps")
                        .font(.bodySmall)
                        .foregroundColor(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(captures) { capture in
                            CaptureCard(capture: capture)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCapture = capture
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteCapture(capture)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .onAppear {
            loadCaptures()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadCaptures()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            loadCaptures()
        }
    }

    private func loadCaptures() {
        CaptureStore.shared.reload()
        captures = CaptureStore.shared.all()
    }

    private func syncAll() {
        guard !isSyncing else { return }
        isSyncing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            defer {
                isSyncing = false
                loadCaptures()
            }

            // Try to connect if not already connected
            if BridgeManager.shared.status != .connected && BridgeManager.shared.isPaired {
                await BridgeManager.shared.retry()
            }

            guard BridgeManager.shared.status == .connected else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }

            CaptureSyncService.shared.syncIfConnected()
            // Give the async sync a moment to complete
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func deleteCapture(_ capture: Capture) {
        CaptureStore.shared.delete(capture.id)
        withAnimation {
            captures.removeAll { $0.id == capture.id }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

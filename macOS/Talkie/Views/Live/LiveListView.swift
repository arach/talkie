//
//  LiveListView.swift
//  Talkie
//
//  View for displaying TalkieLive utterances with promote and view actions.
//

import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveListView")

// MARK: - Live List View

struct LiveListView: View {
    @ObservedObject private var dataStore = LiveDataStore.shared
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedUtterance: LiveUtterance?
    @State private var searchText: String = ""
    @State private var showInspector: Bool = true
    @State private var filterStatus: LivePromotionStatus? = nil

    // Column widths
    @State private var timestampWidth: CGFloat = 120
    @State private var textWidth: CGFloat = 350
    @State private var appWidth: CGFloat = 120
    @State private var statusWidth: CGFloat = 80

    private var filteredUtterances: [LiveUtterance] {
        var results = dataStore.utterances

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.text.lowercased().contains(query) ||
                ($0.appName?.lowercased().contains(query) ?? false)
            }
        }

        // Filter by status
        if let status = filterStatus {
            results = results.filter { $0.promotionStatus == status }
        }

        return results
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                if !dataStore.isAvailable {
                    unavailableView
                } else if dataStore.utterances.isEmpty {
                    emptyView
                } else {
                    // Table header
                    tableHeaderView

                    Divider()

                    // Table content
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredUtterances) { utterance in
                                LiveTableRow(
                                    utterance: utterance,
                                    isSelected: selectedUtterance?.id == utterance.id,
                                    onSelect: { selectedUtterance = utterance },
                                    onPromote: { promoteToMemo(utterance) },
                                    onViewInLive: { openInLive(utterance) },
                                    timestampWidth: timestampWidth,
                                    textWidth: textWidth,
                                    appWidth: appWidth,
                                    statusWidth: statusWidth
                                )

                                Rectangle()
                                    .fill(Theme.current.divider.opacity(0.25))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .background(Theme.current.background)
                }
            }
            .frame(maxWidth: .infinity)

            // Inspector panel
            if showInspector, let selected = selectedUtterance {
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(width: 1)

                LiveInspectorView(
                    utterance: selected,
                    onPromote: { promoteToMemo(selected) },
                    onViewInLive: { openInLive(selected) }
                )
                .frame(width: 320)
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 8) {
            Text("Live Utterances")
                .font(SettingsManager.shared.fontSM)
                .foregroundColor(Theme.current.foreground)

            Text("\(filteredUtterances.count)")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            // Filter picker
            Menu {
                Button("All") { filterStatus = nil }
                Divider()
                Button("Needs Action") { filterStatus = .none }
                Button("Promoted to Memo") { filterStatus = .memo }
                Button("Commands") { filterStatus = .command }
                Button("Ignored") { filterStatus = .ignored }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterStatus?.displayName ?? "All")
                }
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontXS)
                    .frame(width: 120)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.current.backgroundTertiary)
            .cornerRadius(4)

            // Refresh button
            Button(action: { dataStore.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(SettingsManager.shared.fontXS)
            }
            .buttonStyle(.plain)
            .help("Refresh (last: \(dataStore.lastRefreshAgo))")

            // Inspector toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInspector.toggle() } }) {
                Image(systemName: "sidebar.right")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(showInspector ? .blue : Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
            .help(showInspector ? "Hide Details" : "Show Details")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.current.backgroundSecondary)
    }

    // MARK: - Table Header

    private var tableHeaderView: some View {
        HStack(spacing: 0) {
            Text("TIME")
                .frame(width: timestampWidth, alignment: .leading)

            Text("CONTENT")
                .frame(width: textWidth, alignment: .leading)

            Text("APP")
                .frame(width: appWidth, alignment: .leading)

            Text("STATUS")
                .frame(width: statusWidth, alignment: .leading)

            Spacer()

            Text("ACTIONS")
                .frame(width: 80, alignment: .trailing)
        }
        .font(Theme.current.fontXSBold)
        .foregroundColor(Theme.current.foregroundMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.current.backgroundSecondary)
    }

    // MARK: - Empty States

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(SettingsManager.shared.fontDisplay)
                .foregroundColor(.orange.opacity(0.5))

            Text("TALKIE LIVE NOT FOUND")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.secondary)

            Text("TalkieLive database not available.\nMake sure TalkieLive has been run at least once.")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.badge.mic")
                .font(SettingsManager.shared.fontDisplay)
                .foregroundColor(.secondary.opacity(0.3))

            Text("NO LIVE UTTERANCES")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.secondary)

            Text("Use TalkieLive to capture voice utterances")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func promoteToMemo(_ utterance: LiveUtterance) {
        logger.info("[LiveListView] Promoting utterance \(utterance.id) to memo")

        // Create a new VoiceMemo from the Live utterance
        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()
        memo.title = utterance.preview
        memo.transcription = utterance.text
        memo.createdAt = utterance.createdAt
        memo.duration = utterance.durationSeconds ?? 0
        memo.originDeviceId = "mac-live"
        memo.sortOrder = -Int32(Date().timeIntervalSince1970)

        do {
            try viewContext.save()
            logger.info("[LiveListView] Created memo from Live utterance: \(memo.id?.uuidString ?? "nil")")

            // TODO: Update TalkieLive database to mark as promoted
            // This requires write access - for now we just create the memo

            // Post notification for sync
            NotificationCenter.default.post(name: .talkieSyncStarted, object: nil)
        } catch {
            logger.error("[LiveListView] Failed to create memo: \(error.localizedDescription)")
        }
    }

    private func openInLive(_ utterance: LiveUtterance) {
        logger.info("[LiveListView] Opening utterance \(utterance.id) in TalkieLive")

        // Open TalkieLive app with deep link to the utterance
        let url = URL(string: "talkielive://utterance/\(utterance.id)")!

        if !NSWorkspace.shared.open(url) {
            // Fallback: just open TalkieLive
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jdi.talkie.live") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            }
        }
    }
}

// MARK: - Table Row

struct LiveTableRow: View {
    let utterance: LiveUtterance
    let isSelected: Bool
    let onSelect: () -> Void
    let onPromote: () -> Void
    let onViewInLive: () -> Void

    let timestampWidth: CGFloat
    let textWidth: CGFloat
    let appWidth: CGFloat
    let statusWidth: CGFloat

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Timestamp
            Text(utterance.relativeTime)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: timestampWidth, alignment: .leading)

            // Content preview
            Text(utterance.preview)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)
                .frame(width: textWidth, alignment: .leading)

            // App name
            Text(utterance.appName ?? "—")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .lineLimit(1)
                .frame(width: appWidth, alignment: .leading)

            // Status
            HStack(spacing: 4) {
                Image(systemName: utterance.promotionStatus.icon)
                    .font(.system(size: 10))
                Text(utterance.promotionStatus.displayName)
                    .font(SettingsManager.shared.fontXS)
            }
            .foregroundColor(statusColor)
            .frame(width: statusWidth, alignment: .leading)

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if utterance.canPromote {
                    Button(action: onPromote) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help("Promote to Memo")
                }

                Button(action: onViewInLive) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)
                .help("View in TalkieLive")
            }
            .frame(width: 80, alignment: .trailing)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Theme.current.backgroundTertiary : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        switch utterance.promotionStatus {
        case .none: return Theme.current.foregroundSecondary
        case .memo: return .green
        case .command: return .purple
        case .ignored: return .gray
        }
    }
}

// MARK: - Inspector View

struct LiveInspectorView: View {
    let utterance: LiveUtterance
    let onPromote: () -> Void
    let onViewInLive: () -> Void

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var copied = false
    @State private var promoteHovered = false
    @State private var liveHovered = false

    private var audioURL: URL? {
        guard let filename = utterance.audioFilename else { return nil }
        // Check App Group container first
        let fm = FileManager.default
        if let groupContainer = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jdi.talkie") {
            let groupPath = groupContainer
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("Audio", isDirectory: true)
                .appendingPathComponent(filename)
            if fm.fileExists(atPath: groupPath.path) {
                return groupPath
            }
        }
        // Fallback to local
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let localPath = appSupport
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("Audio", isDirectory: true)
                .appendingPathComponent(filename)
            if fm.fileExists(atPath: localPath.path) {
                return localPath
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with icon and time
                HStack(spacing: 10) {
                    // Live pulse indicator
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE UTTERANCE")
                            .font(.techLabel)
                            .foregroundColor(.secondary)

                        Text(utterance.relativeTime)
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    // Status badge
                    HStack(spacing: 4) {
                        Image(systemName: utterance.promotionStatus.icon)
                            .font(.system(size: 10))
                        Text(utterance.promotionStatus.displayName)
                            .font(SettingsManager.shared.fontXS)
                    }
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                }

                // Transcript Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TRANSCRIPT")
                            .font(.techLabel)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Copy button
                        Button(action: copyTranscript) {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .medium))
                                if copied {
                                    Text("Copied")
                                        .font(SettingsManager.shared.fontXS)
                                }
                            }
                            .foregroundColor(copied ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(copied ? Color.green.opacity(0.15) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(utterance.text)
                        .font(SettingsManager.shared.contentFontBody)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }

                // Audio Playback Card
                if audioURL != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYBACK")
                            .font(.techLabel)
                            .foregroundColor(.secondary)

                        LiveAudioPlayerCard(
                            isPlaying: isPlaying,
                            currentTime: currentTime,
                            duration: duration > 0 ? duration : (utterance.durationSeconds ?? 0),
                            onTogglePlayback: togglePlayback,
                            onSeek: seekTo
                        )
                    }
                }

                // Context Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("CONTEXT")
                        .font(.techLabel)
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        contextRow(icon: "app.fill", label: "App", value: utterance.appName ?? "—")
                        Divider().opacity(0.5)
                        contextRow(icon: "macwindow", label: "Window", value: utterance.windowTitle ?? "—")
                        Divider().opacity(0.5)
                        contextRow(icon: "timer", label: "Duration", value: utterance.durationString ?? "—")
                        Divider().opacity(0.5)
                        contextRow(icon: "text.word.spacing", label: "Words", value: utterance.wordCount.map { "\($0)" } ?? "—")
                        Divider().opacity(0.5)
                        contextRow(icon: "waveform", label: "Model", value: utterance.whisperModel ?? "—")
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer().frame(height: 8)

                // Action Buttons
                VStack(spacing: 10) {
                    if utterance.canPromote {
                        // Promote to Memo - Primary action
                        Button(action: onPromote) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(promoteHovered ? 0.3 : 0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "arrow.up.doc.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Promote to Memo")
                                        .font(Theme.current.fontBodyMedium)
                                        .foregroundColor(.primary)
                                    Text("Save as permanent voice memo")
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(promoteHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(promoteHovered ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { promoteHovered = $0 }
                    }

                    // Open in TalkieLive - Secondary action
                    Button(action: onViewInLive) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(liveHovered ? 0.3 : 0.2))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.orange)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open in TalkieLive")
                                    .font(Theme.current.fontBodyMedium)
                                    .foregroundColor(.primary)
                                Text("View full history & details")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(liveHovered ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(liveHovered ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { liveHovered = $0 }
                }

                Spacer()
            }
            .padding(16)
        }
        .background(Theme.current.backgroundSecondary)
        .onChange(of: utterance.id) { _, _ in
            // Reset audio state when utterance changes
            stopPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Context Row

    @ViewBuilder
    private func contextRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .leading)

            Text(value)
                .font(SettingsManager.shared.fontSM)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch utterance.promotionStatus {
        case .none: return .secondary
        case .memo: return .green
        case .command: return .purple
        case .ignored: return .gray
        }
    }

    // MARK: - Actions

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(utterance.text, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }

    // MARK: - Audio Playback

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            stopPlaybackTimer()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
            startPlaybackTimer()
            isPlaying = true
        } else {
            guard let url = audioURL else { return }

            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                startPlaybackTimer()
                isPlaying = true
            } catch {
                logger.error("[LiveInspector] Failed to play audio: \(error.localizedDescription)")
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = audioPlayer {
                currentTime = player.currentTime
                if !player.isPlaying && currentTime >= duration - 0.1 {
                    stopPlayback()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopPlaybackTimer()
        isPlaying = false
        currentTime = 0
    }

    private func seekTo(_ progress: Double) {
        guard let player = audioPlayer else { return }
        let time = progress * player.duration
        player.currentTime = time
        currentTime = time
    }
}

// MARK: - Live Audio Player Card

struct LiveAudioPlayerCard: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void

    @State private var isPlayButtonHovered = false

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: onTogglePlayback) {
                ZStack {
                    Circle()
                        .fill(playButtonBackground)
                        .frame(width: 40, height: 40)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(playButtonForeground)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .onHover { isPlayButtonHovered = $0 }

            // Waveform + timeline
            VStack(spacing: 6) {
                // Simple progress bar with glow
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 4)

                        // Playhead
                        if progress > 0 {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                                .shadow(color: .accentColor.opacity(0.5), radius: 3)
                                .offset(x: geo.size.width * progress - 5)
                        }
                    }
                }
                .frame(height: 10)

                // Time row
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(formatTime(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var playButtonBackground: Color {
        if isPlaying { return Color.accentColor }
        if isPlayButtonHovered { return Color.accentColor.opacity(0.3) }
        return Color.accentColor.opacity(0.2)
    }

    private var playButtonForeground: Color {
        if isPlaying { return .white }
        return .accentColor
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    LiveListView()
        .frame(width: 1000, height: 600)
}

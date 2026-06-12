//
//  ClipThumbnailView.swift
//  Talkie
//
//  Thumbnail for a video clip with play overlay.
//  Tap toggles between thumbnail and expanded inline player.
//  Generates thumbnail from the first available video frame.
//

import SwiftUI
import AVFoundation
import AVKit
import TalkieKit

// MARK: - Clip Thumbnail Size

enum ClipThumbnailSize {
    case compact   // 80pt
    case standard  // 120pt
    case large     // 200pt

    var points: CGFloat {
        switch self {
        case .compact: return 80
        case .standard: return 120
        case .large: return 200
        }
    }

    var expandedWidth: CGFloat {
        switch self {
        case .compact: return 200
        case .standard: return 300
        case .large: return 400
        }
    }

    var thumbnailGeneratorSize: CGFloat {
        switch self {
        case .compact: return 160
        case .standard: return 240
        case .large: return 400
        }
    }

    var playButtonSize: CGFloat {
        switch self {
        case .compact: return 28
        case .standard: return 34
        case .large: return 40
        }
    }

    var playIconSize: CGFloat {
        switch self {
        case .compact: return 12
        case .standard: return 14
        case .large: return 16
        }
    }
}

// MARK: - Clip Thumbnail View

struct ClipThumbnailView: View {
    let clip: RecordingClip
    var size: ClipThumbnailSize = .standard

    @State private var thumbnail: NSImage?
    @State private var isExpanded = false

    private var fileURL: URL {
        VideoClipStorage.videosDirectory
            .appendingPathComponent(clip.filename)
    }

    private var displaySize: CGFloat { size.points }

    /// Aspect ratio from clip metadata (width/height), default 16:9
    private var aspectRatio: CGFloat {
        guard let w = clip.width, let h = clip.height, w > 0, h > 0 else { return 16.0 / 9.0 }
        return CGFloat(w) / CGFloat(h)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedPlayer
            } else {
                thumbnailView
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .task(id: clip.filename) { await generateThumbnail() }
        .onDisappear {
            thumbnail = nil
            isExpanded = false
        }
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        Button { withAnimation { isExpanded = true } } label: {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: displaySize, height: displaySize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: displaySize, height: displaySize)
                }

                // Play overlay
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size.playButtonSize, height: size.playButtonSize)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: size.playIconSize))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )

                // Duration label
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(clip.durationMs))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }
                    .padding(4)
                }
            }
            .frame(width: displaySize, height: displaySize)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Player

    private var expandedPlayer: some View {
        let expandedWidth = size.expandedWidth
        let expandedHeight = expandedWidth / aspectRatio

        return VStack(spacing: 0) {
            InlineClipPlayer(url: fileURL)
                .frame(width: expandedWidth, height: expandedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Collapse button
            Button {
                withAnimation { isExpanded = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                    Text(formatDuration(clip.durationMs))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.vertical, 4)
                .frame(width: expandedWidth)
                .background(Theme.current.backgroundTertiary)
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnail() async {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if let nsImage = await VideoFrameThumbnailer.thumbnailAsync(
            for: url,
            maxSize: size.thumbnailGeneratorSize
        ) {
            guard !Task.isCancelled else { return }
            await MainActor.run { self.thumbnail = nsImage }
        } else {
            Log(.ui).debug("Failed to generate clip thumbnail for \(url.lastPathComponent)")
        }
    }

    // MARK: - Formatting

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m\(seconds % 60)s"
    }
}

// MARK: - Inline Clip Player

struct InlineClipPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: url)
        player.isMuted = true

        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false

        // Loop playback
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var observer: Any?

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

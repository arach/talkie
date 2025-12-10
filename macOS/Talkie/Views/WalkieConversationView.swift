//
//  WalkieConversationView.swift
//  Talkie macOS
//
//  Displays the Walkie conversation thread for a memo.
//  Shows AI responses and user replies in a chat-like format.
//

import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")
struct WalkieConversationView: View {
    let memoId: String

    @State private var walkies: [Walkie] = []
    @State private var isLoading = false
    @State private var isExpanded = true
    @State private var playingWalkieId: String?
    @State private var audioPlayer: AVAudioPlayer?

    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(settings.fontSM)
                        .foregroundColor(.secondary)

                    Text("CONVERSATION")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(.secondary)

                    if !walkies.isEmpty {
                        Text("(\(walkies.count))")
                            .font(.techLabelSmall)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(settings.fontXS)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.techLabelSmall)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
                } else if walkies.isEmpty {
                    // Empty state
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("No responses yet")
                            .font(settings.fontSM)
                            .foregroundColor(.secondary)

                        Text("Run a workflow with speech output to start a conversation")
                            .font(.techLabelSmall)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                } else {
                    // Conversation messages
                    VStack(spacing: Spacing.sm) {
                        ForEach(walkies) { walkie in
                            WalkieBubble(
                                walkie: walkie,
                                isPlaying: playingWalkieId == walkie.id,
                                onPlay: { playWalkie(walkie) }
                            )
                        }
                    }
                }
            }
        }
        .task(id: memoId) {
            await loadWalkies()
        }
    }

    private func loadWalkies() async {
        isLoading = true
        defer { isLoading = false }

        do {
            walkies = try await WalkieService.shared.fetchConversation(for: memoId)
        } catch {
            logger.debug("Failed to load walkies: \(error)")
        }
    }

    private func playWalkie(_ walkie: Walkie) {
        Task {
            // Stop current playback if same walkie
            if playingWalkieId == walkie.id {
                audioPlayer?.stop()
                playingWalkieId = nil
                return
            }

            // Stop any current playback
            audioPlayer?.stop()

            do {
                let audioURL = try await WalkieService.shared.downloadAudio(for: walkie)

                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                        audioPlayer?.prepareToPlay()
                        audioPlayer?.play()
                        playingWalkieId = walkie.id

                        // Monitor playback completion
                        Task {
                            while audioPlayer?.isPlaying == true {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                            }
                            await MainActor.run {
                                playingWalkieId = nil
                            }
                        }
                    } catch {
                        logger.debug("Playback error: \(error)")
                    }
                }
            } catch {
                logger.debug("Download error: \(error)")
            }
        }
    }
}

// MARK: - Walkie Message Bubble

struct WalkieBubble: View {
    let walkie: Walkie
    let isPlaying: Bool
    let onPlay: () -> Void

    @ObservedObject private var settings = SettingsManager.shared

    private var isFromUser: Bool { walkie.sender == .user }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Avatar
            if !isFromUser {
                walkieAvatar
            }

            VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
                // Header: sender + time
                HStack(spacing: 6) {
                    if !isFromUser, let workflow = walkie.workflowName {
                        Text(workflow)
                            .font(.techLabelSmall)
                            .foregroundColor(.secondary)
                    } else {
                        Text(isFromUser ? "You" : "Talkie")
                            .font(.techLabelSmall)
                            .foregroundColor(.secondary)
                    }

                    Text(timeAgo(walkie.createdAt))
                        .font(.techLabelSmall)
                        .foregroundColor(.secondary.opacity(0.7))
                }

                // Message bubble with play button
                HStack(spacing: Spacing.sm) {
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(isFromUser ? .white.opacity(0.9) : .accentColor)
                    }
                    .buttonStyle(.plain)

                    // Transcript
                    Text(walkie.transcript)
                        .font(settings.fontSM)
                        .foregroundColor(isFromUser ? .white : .primary)
                        .lineLimit(4)
                        .multilineTextAlignment(isFromUser ? .trailing : .leading)
                }
                .padding(Spacing.sm)
                .background(isFromUser ? Color.accentColor : Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // TTL indicator
                if walkie.expiresAt.timeIntervalSinceNow < 86400 {
                    Text("Expires \(timeAgo(walkie.expiresAt, future: true))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)

            if isFromUser {
                userAvatar
            }
        }
    }

    private var walkieAvatar: some View {
        Circle()
            .fill(Color.secondary.opacity(0.1))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            )
    }

    private var userAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            )
    }

    private func timeAgo(_ date: Date, future: Bool = false) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    WalkieConversationView(memoId: "test-memo-id")
        .frame(width: 400, height: 300)
        .padding()
}

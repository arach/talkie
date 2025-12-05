//
//  WalkieConversationView.swift
//  Talkie iOS
//
//  Walkie conversation thread UI - ephemeral chat within a Talkie
//
//  Like Slack threads: Main channel = Talkies (structured, actionable)
//                      Thread replies = Walkies (quick chatter, refinement)
//

import SwiftUI

/// A single Walkie message bubble
struct WalkieBubble: View {
    let walkie: Walkie
    let onPlay: () -> Void
    let isPlaying: Bool

    private var isFromUser: Bool { walkie.sender == .user }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // AI avatar on left, user on right
            if !isFromUser {
                walkieAvatar
            }

            VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
                // Header: sender + time
                HStack(spacing: 6) {
                    if !isFromUser, let workflow = walkie.workflowName {
                        Text(workflow)
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary)
                    } else {
                        Text(isFromUser ? "You" : "Talkie")
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary)
                    }

                    Text(timeAgo(walkie.createdAt))
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary.opacity(0.7))
                }

                // Message bubble
                HStack(spacing: Spacing.sm) {
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(isFromUser ? .white.opacity(0.9) : .active)
                    }

                    // Transcript
                    Text(walkie.transcript)
                        .font(.bodySmall)
                        .foregroundColor(isFromUser ? .white : .textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(isFromUser ? .trailing : .leading)
                }
                .padding(Spacing.sm)
                .background(isFromUser ? Color.active : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.md)

                // TTL indicator (faint)
                if walkie.expiresAt.timeIntervalSinceNow < 86400 {  // Less than 24 hours
                    Text("Expires \(timeAgo(walkie.expiresAt, future: true))")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)

            if isFromUser {
                userAvatar
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var walkieAvatar: some View {
        Circle()
            .fill(Color.surfaceSecondary)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.active)
            )
    }

    private var userAvatar: some View {
        Circle()
            .fill(Color.active.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.active)
            )
    }

    private func timeAgo(_ date: Date, future: Bool = false) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if future {
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// The full conversation thread for a memo
struct WalkieConversationView: View {
    let memoId: String
    @StateObject private var walkieService = WalkieService.shared
    @State private var walkies: [Walkie] = []
    @State private var isExpanded = true
    @State private var isLoading = false
    @State private var showReplyRecorder = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with expand/collapse
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("CONVERSATION")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textSecondary)

                    if !walkies.isEmpty {
                        Text("(\(walkies.count))")
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.active)
                        Text("Loading...")
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
                } else if walkies.isEmpty {
                    // Empty state
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 24))
                            .foregroundColor(.textTertiary.opacity(0.5))

                        Text("No responses yet")
                            .font(.bodySmall)
                            .foregroundColor(.textTertiary)

                        Text("Run a workflow to start a conversation")
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                } else {
                    // Conversation messages
                    VStack(spacing: Spacing.md) {
                        ForEach(walkies) { walkie in
                            WalkieBubble(
                                walkie: walkie,
                                onPlay: { playWalkie(walkie) },
                                isPlaying: walkieService.currentWalkie?.id == walkie.id && walkieService.isPlaying
                            )
                        }
                    }

                    // Reply button
                    Button(action: { showReplyRecorder = true }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text("Reply")
                                .font(.techLabel)
                        }
                        .foregroundColor(.active)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.active.opacity(0.1))
                        .cornerRadius(CornerRadius.full)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, Spacing.sm)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .task {
            await loadWalkies()
        }
        .refreshable {
            await loadWalkies()
        }
        .sheet(isPresented: $showReplyRecorder) {
            WalkieReplyRecorderView(
                memoId: memoId,
                parentWalkieId: walkies.last?.id,
                onComplete: {
                    showReplyRecorder = false
                    Task { await loadWalkies() }
                },
                onCancel: {
                    showReplyRecorder = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func loadWalkies() async {
        isLoading = true
        defer { isLoading = false }

        do {
            walkies = try await walkieService.fetchWalkies(for: memoId)
        } catch {
            print("Failed to load walkies: \(error)")
        }
    }

    private func playWalkie(_ walkie: Walkie) {
        Task {
            if walkieService.currentWalkie?.id == walkie.id && walkieService.isPlaying {
                walkieService.stop()
            } else {
                await walkieService.play(walkie)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        WalkieConversationView(memoId: "test-memo-id")
    }
    .background(Color.surfacePrimary)
}

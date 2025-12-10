//
//  PendingActionsView.swift
//  Talkie macOS
//
//  Shows currently running workflows/actions.
//  Provides visibility into background processing.
//

import SwiftUI

struct PendingActionsView: View {
    @StateObject private var pendingManager = PendingActionsManager.shared
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(settings.fontSM)
                    .foregroundColor(.secondary)

                Text("PENDING ACTIONS")
                    .font(.techLabel)
                    .foregroundColor(.secondary)

                Spacer()

                if pendingManager.hasActiveActions {
                    Text("\(pendingManager.activeCount)")
                        .font(.techLabelSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)

            Divider()
                .opacity(0.5)

            // Content
            if pendingManager.pendingActions.isEmpty {
                // Empty state
                VStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No pending actions")
                        .font(settings.fontBody)
                        .foregroundColor(.secondary)

                    Text("Workflows and actions will appear here while running")
                        .font(settings.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                // List of pending actions
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pendingManager.pendingActions) { action in
                            PendingActionRow(action: action)
                            Divider()
                                .opacity(0.3)
                                .padding(.leading, 52)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .background(settings.tacticalBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pending Action Row

struct PendingActionRow: View {
    let action: PendingAction

    private let settings = SettingsManager.shared
    @State private var elapsed: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Workflow icon with spinner overlay
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(settings.surfaceAlternate)
                    .frame(width: 36, height: 36)

                Image(systemName: action.workflowIcon)
                    .font(settings.fontBody)
                    .foregroundColor(.accentColor)

                // Spinner ring around icon
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(elapsed * 60))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: elapsed)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                // Workflow name
                Text(action.workflowName)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Memo title
                Text(action.memoTitle)
                    .font(settings.fontSM)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Current step or progress
                HStack(spacing: Spacing.xs) {
                    if let step = action.currentStep {
                        Text(step)
                            .font(settings.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    if action.totalSteps > 1 {
                        Text("(\(action.stepIndex + 1)/\(action.totalSteps))")
                            .font(.monoXSmall)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }

            Spacer()

            // Elapsed time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatElapsed(elapsed))
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)

                // Progress bar (if multi-step)
                if action.totalSteps > 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(settings.surfaceAlternate)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: geo.size.width * action.progress)
                        }
                    }
                    .frame(width: 50, height: 4)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .onReceive(timer) { _ in
            elapsed = action.elapsed
        }
        .onAppear {
            elapsed = action.elapsed
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%d:%02d", mins, secs)
        } else {
            let hours = Int(seconds) / 3600
            let mins = (Int(seconds) % 3600) / 60
            return String(format: "%d:%02d:%02d", hours, mins, Int(seconds) % 60)
        }
    }
}

// MARK: - Compact Status Bar Badge

/// A compact badge for showing in status bar or other places
struct PendingActionsBadge: View {
    @StateObject private var pendingManager = PendingActionsManager.shared

    var body: some View {
        if pendingManager.hasActiveActions {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)

                Text("\(pendingManager.activeCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
    }
}

// MARK: - Preview

#Preview {
    PendingActionsView()
        .frame(width: 400, height: 500)
}

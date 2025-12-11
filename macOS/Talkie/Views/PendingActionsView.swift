//
//  PendingActionsView.swift
//  Talkie macOS
//
//  Shows currently running workflows/actions and recent history.
//  Provides visibility into background processing with retry capability.
//

import SwiftUI
import CoreData

struct PendingActionsView: View {
    @StateObject private var pendingManager = PendingActionsManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(settings.fontSM)
                    .foregroundColor(.secondary)

                Text("ACTIONS")
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

                if pendingManager.failedCount > 0 {
                    Text("\(pendingManager.failedCount)")
                        .font(.techLabelSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Theme.current.surface1)

            Divider()
                .opacity(0.5)

            // Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active actions
                    if !pendingManager.pendingActions.isEmpty {
                        SectionHeader(title: "RUNNING", icon: "play.circle.fill", color: .accentColor)

                        ForEach(pendingManager.pendingActions) { action in
                            PendingActionRow(action: action)
                            Divider()
                                .opacity(0.3)
                                .padding(.leading, 52)
                        }
                    }

                    // Recent actions (failed first, then completed)
                    if !pendingManager.recentActions.isEmpty {
                        // Failed actions
                        let failedActions = pendingManager.failedActions
                        if !failedActions.isEmpty {
                            SectionHeader(title: "FAILED", icon: "xmark.circle.fill", color: .red)

                            ForEach(failedActions) { action in
                                RecentActionRow(action: action, onRetry: { retryAction(action) })
                                Divider()
                                    .opacity(0.3)
                                    .padding(.leading, 52)
                            }
                        }

                        // Completed actions
                        let completedActions = pendingManager.recentActions.filter { !$0.status.isFailed }
                        if !completedActions.isEmpty {
                            SectionHeader(title: "RECENT", icon: "checkmark.circle.fill", color: .green)

                            ForEach(completedActions.prefix(10)) { action in
                                RecentActionRow(action: action, onRetry: nil)
                                Divider()
                                    .opacity(0.3)
                                    .padding(.leading, 52)
                            }
                        }
                    }

                    // Empty state
                    if pendingManager.pendingActions.isEmpty && pendingManager.recentActions.isEmpty {
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.4))

                            Text("No actions yet")
                                .font(settings.fontBody)
                                .foregroundColor(.secondary)

                            Text("Workflows will appear here while running")
                                .font(settings.fontSM)
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.lg)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                    }
                }
                .padding(.top, Spacing.xs)
            }

            // Clear history button
            if !pendingManager.recentActions.isEmpty {
                Divider()
                    .opacity(0.5)

                Button(action: { pendingManager.clearAllRecentActions() }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(settings.fontXS)
                        Text("Clear History")
                            .font(settings.fontXS)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.plain)
                .background(Theme.current.surface1)
            }
        }
        .background(settings.tacticalBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryAction(_ action: RecentAction) {
        guard let workflowId = action.workflowId, let memoId = action.memoId else {
            return
        }

        // Find the workflow and memo
        Task {
            // Load workflow
            guard let workflow = WorkflowManager.shared.workflows.first(where: { $0.id == workflowId }) else {
                await SystemEventManager.shared.log(.error, "Retry failed", detail: "Workflow not found")
                return
            }

            // Load memo
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
            fetchRequest.fetchLimit = 1

            do {
                let memos = try viewContext.fetch(fetchRequest)
                guard let memo = memos.first else {
                    await SystemEventManager.shared.log(.error, "Retry failed", detail: "Memo not found")
                    return
                }

                // Clear the failed action from history
                await MainActor.run {
                    pendingManager.clearRecentAction(id: action.id)
                }

                // Re-run the workflow
                await SystemEventManager.shared.log(.workflow, "Retrying: \(workflow.name)", detail: "Memo: \(memo.title ?? "Untitled")")
                _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: viewContext)

            } catch {
                await SystemEventManager.shared.log(.error, "Retry failed", detail: error.localizedDescription)
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    private let settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(settings.fontXS)
                .foregroundColor(color)

            Text(title)
                .font(.techLabelSmall)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(settings.surfaceAlternate.opacity(0.5))
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

// MARK: - Recent Action Row

struct RecentActionRow: View {
    let action: RecentAction
    let onRetry: (() -> Void)?

    private let settings = SettingsManager.shared
    @State private var isHovering = false
    @State private var showError = false

    private var isFailed: Bool {
        action.status.isFailed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                // Workflow icon with status indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFailed ? Color.red.opacity(0.15) : settings.surfaceAlternate)
                        .frame(width: 36, height: 36)

                    Image(systemName: action.workflowIcon)
                        .font(settings.fontBody)
                        .foregroundColor(isFailed ? .red : .green)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    // Workflow name
                    Text(action.workflowName)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(isFailed ? .red : .primary)
                        .lineLimit(1)

                    // Memo title
                    Text(action.memoTitle)
                        .font(settings.fontSM)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // Time ago
                    Text(timeAgo(action.completedAt))
                        .font(settings.fontXS)
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Spacer()

                // Duration and retry button
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDuration(action.duration))
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)

                    if isFailed && onRetry != nil {
                        Button(action: { onRetry?() }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Retry")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            // Error message (expandable)
            if isFailed, let errorMessage = action.status.errorMessage {
                Button(action: { showError.toggle() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: showError ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Error details")
                            .font(settings.fontXS)
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.leading, 52)
                    .padding(.bottom, Spacing.xs)
                }
                .buttonStyle(.plain)

                if showError {
                    Text(errorMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, Spacing.md)
                        .padding(.leading, 40)
                        .padding(.bottom, Spacing.sm)
                        .textSelection(.enabled)
                }
            }
        }
        .background(isHovering ? settings.surfaceAlternate.opacity(0.3) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%dm %ds", mins, secs)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
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

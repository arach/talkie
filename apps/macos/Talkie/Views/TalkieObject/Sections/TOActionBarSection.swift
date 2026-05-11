//
//  TOActionBarSection.swift
//  Talkie
//
//  Note-level and document-level actions.
//  Notes: "Attach Memo" popover + workflows.
//  Memos/Dictations: copy, notes, record, pinned workflows.
//  Includes inline recording UI when recording is in progress.
//

import SwiftUI
import TalkieKit

struct TOActionBarSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    var pinnedWorkflows: [Workflow] = []
    var processingWorkflowIDs: Set<UUID> = []
    var onCopy: () -> Void = {}
    var onExecuteWorkflow: (Workflow) -> Void = { _ in }
    var onShowWorkflowPicker: () -> Void = {}
    var onStartRecording: () -> Void = {}
    var onContinueMemo: () -> Void = {}

    @State private var showAttachMemoPopover = false
    @State private var recentMemos: [TalkieObject] = []

    private let repository = TalkieObjectRepository()

    var body: some View {
        let controller = MemoRecordingController.shared
        let isRecordingForThis = controller.targetNoteId == recording.id
        let isContinuingThis = controller.continuingMemoId == recording.id
        let showRecordPill = !recording.hasAudio && (recording.isNote || recording.isMemo)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            if (isRecordingForThis || isContinuingThis) && controller.state.isRecording {
                inlineRecordingUI(controller: controller)
            } else if (isRecordingForThis || isContinuingThis) && controller.state.isProcessing {
                processingUI(controller: controller)
            } else if recording.isNote {
                noteActions
            } else {
                standardActions(showRecordPill: showRecordPill)
            }
        }
    }

    // MARK: - Note Actions (concept-level: what to do WITH the note)

    private var noteActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ACTIONS")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.sm) {
                // Attach Memo — primary CTA with popover
                Button {
                    Task {
                        recentMemos = (try? await repository.fetchRecordings(
                            sortBy: .createdAt, ascending: false, limit: 8,
                            filters: [.type(.memo)]
                        )) ?? []
                    }
                    showAttachMemoPopover = true
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "mic.badge.plus")
                            .font(settings.fontXS)
                        Text("Attach Memo")
                            .font(settings.fontXSMedium)
                    }
                    .foregroundColor(settings.resolvedAccentColor)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(settings.resolvedAccentColor.opacity(0.1)))
                    .overlay(Capsule().stroke(settings.resolvedAccentColor.opacity(0.2), lineWidth: BorderWidth.thin))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAttachMemoPopover) {
                    attachMemoPopover
                }

                // Pinned workflows
                ForEach(pinnedWorkflows) { workflow in
                    actionPill(
                        icon: workflow.icon ?? "bolt.fill",
                        label: workflow.name,
                        isProcessing: processingWorkflowIDs.contains(workflow.id)
                    ) {
                        onExecuteWorkflow(workflow)
                    }
                }

                // Workflow picker
                actionPill(icon: "bolt.fill", label: "Workflows") {
                    onShowWorkflowPicker()
                }
            }
        }
    }

    // MARK: - Standard Actions (Memos & Dictations)

    private func standardActions(showRecordPill: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                if showRecordPill {
                    actionPill(icon: "mic.badge.plus", label: "Memo", color: .red) {
                        onStartRecording()
                    }
                }

                actionPill(icon: "doc.on.doc", label: "Copy") {
                    onCopy()
                }

                ForEach(pinnedWorkflows) { workflow in
                    actionPill(
                        icon: workflow.icon ?? "bolt.fill",
                        label: workflow.name,
                        isProcessing: processingWorkflowIDs.contains(workflow.id)
                    ) {
                        onExecuteWorkflow(workflow)
                    }
                }

                actionPill(icon: "bolt.fill", label: "Workflows") {
                    onShowWorkflowPicker()
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    // MARK: - Attach Memo Popover

    private var attachMemoPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ATTACH MEMO")
                    .font(settings.fontXSMedium)
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            // Record new
            Button {
                showAttachMemoPopover = false
                onStartRecording()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Record New Memo")
                            .font(settings.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Start recording and attach to this note")
                            .font(settings.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Recent memos
            if recentMemos.isEmpty {
                HStack {
                    Spacer()
                    Text("No memos yet")
                        .font(settings.fontSM)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Spacer()
                }
                .padding(.vertical, Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("RECENT MEMOS")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(recentMemos) { memo in
                                memoRow(memo)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
        .frame(width: 300)
        .background(Theme.current.background)
    }

    private func memoRow(_ memo: TalkieObject) -> some View {
        Button {
            showAttachMemoPopover = false
            // TODO: Link existing memo to this note (parent-child relationship)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(memo.displayTitle)
                        .font(settings.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(formatMemoDate(memo.createdAt))
                            .font(settings.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if memo.duration > 0 {
                            Text("·")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(formatDuration(memo.duration))
                                .font(settings.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundColor(settings.resolvedAccentColor)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatMemoDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Inline Recording UI

    private func inlineRecordingUI(controller: MemoRecordingController) -> some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red.opacity(Double(i) < Double(controller.audioLevel * 5) ? 0.8 : 0.2))
                        .frame(width: 3, height: CGFloat(8 + i * 3))
                }
            }

            Text(formatElapsed(controller.elapsedTime))
                .font(.monoSmall)
                .foregroundColor(.red)

            Spacer()

            Button {
                controller.stopRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(settings.fontXS)
                    Text("Stop")
                        .font(settings.fontSMMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)

            Button {
                controller.cancelRecordingForNote()
            } label: {
                Image(systemName: "xmark")
                    .font(settings.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: ComponentSize.tiny, height: ComponentSize.tiny)
                    .background(
                        Circle().fill(Theme.current.foreground.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Processing UI

    private func processingUI(controller: MemoRecordingController) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(controller.processingSteps) { step in
                HStack(spacing: Spacing.sm) {
                    switch step.status {
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(settings.fontSM)
                            .foregroundColor(.green)
                    case .inProgress:
                        BrailleSpinner(size: 12)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .font(settings.fontSM)
                            .foregroundColor(.red)
                    case .pending:
                        Image(systemName: "circle")
                            .font(settings.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Text(step.title)
                        .font(step.status == .inProgress ? settings.fontSMMedium : settings.fontSM)
                        .foregroundColor(Theme.current.foreground)

                    if let subtitle = step.subtitle {
                        Text(subtitle)
                            .font(settings.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Theme.current.foreground.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Theme.current.foreground.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Action Pill

    private func actionPill(icon: String, label: String, color: Color? = nil, isProcessing: Bool = false, action: @escaping () -> Void) -> some View {
        let resolvedColor = color ?? Theme.current.foregroundSecondary
        return Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if isProcessing {
                    BrailleSpinner(size: 10)
                } else {
                    Image(systemName: icon)
                        .font(settings.fontXS)
                }
                Text(label)
                    .font(settings.fontXSMedium)
                    .lineLimit(1)
            }
            .foregroundColor(resolvedColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(resolvedColor.opacity(0.1)))
            .overlay(
                Capsule()
                    .stroke(resolvedColor.opacity(0.18), lineWidth: BorderWidth.thin)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time - Double(Int(time))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

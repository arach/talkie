//
//  TOSharedComponents.swift
//  Talkie
//
//  Shared visual components used by TalkieObject section views.
//  Extracted from RecordingDetail.swift during TalkieObject refactor.
//

import SwiftUI
import ImageIO
import TalkieKit

// MARK: - Theme-aware Scope detail tokens
//
// The editorial detail layouts keep the Scope typography/composition, but
// their colors must follow the active Talkie theme. Scope still receives
// the canonical cool-gray canvas/ink via Theme.current because the Scope
// preset maps those values there; dark themes receive their own readable
// surfaces, text, rules, and accents.

@MainActor
enum ThemedScopeCanvas {
    static var canvas: Color { Theme.current.background }
    static var canvasAlt: Color { Theme.current.surface1 }
    static var surface: Color { Theme.current.surface2 }
}

@MainActor
enum ThemedScopeInk {
    static var primary: Color { Theme.current.foreground }
    static var dim: Color { Theme.current.foreground.opacity(0.82) }
    static var muted: Color { Theme.current.foregroundSecondary }
    static var faint: Color { Theme.current.foregroundMuted }
    static var subtle: Color { Theme.current.foregroundMuted.opacity(0.72) }
}

@MainActor
enum ThemedScopeEdge {
    static var strong: Color { Theme.current.foreground.opacity(0.24) }
    static var normal: Color { Theme.current.foreground.opacity(0.16) }
    static var faint: Color { Theme.current.foreground.opacity(0.10) }
    static var subtle: Color { Theme.current.foreground.opacity(0.07) }
}

@MainActor
enum ThemedScopeAccent {
    static var amber: Color {
        SettingsManager.shared.isScopeTheme ? ScopeAmber.solid : Color.accentColor
    }

    static var brass: Color {
        SettingsManager.shared.isScopeTheme ? ScopeBrass.solid : Color.accentColor
    }

    static var tint: Color {
        amber.opacity(SettingsManager.shared.isScopeTheme ? 0.06 : 0.14)
    }

    static var tintSubtle: Color {
        amber.opacity(SettingsManager.shared.isScopeTheme ? 0.04 : 0.08)
    }

    static var memo: Color {
        SettingsManager.shared.isScopeTheme ? ScopeKind.memo : Color.accentColor
    }

    static var dictation: Color {
        SettingsManager.shared.isScopeTheme ? ScopeKind.dict : Color.accentColor
    }

    static var note: Color {
        SettingsManager.shared.isScopeTheme ? ScopeKind.note : Theme.current.foregroundSecondary
    }

    static var capture: Color {
        SettingsManager.shared.isScopeTheme ? ScopeKind.capture : Theme.current.foregroundSecondary
    }

    static func kind(for type: TalkieObjectType) -> Color {
        switch type {
        case .memo: return memo
        case .dictation: return dictation
        case .note: return note
        case .capture, .selection: return capture
        case .segment: return ThemedScopeInk.faint
        }
    }
}

struct ThemedScopeRule: View {
    var role: ScopeRule.Role
    var axis: Axis.Set

    init(_ role: ScopeRule.Role = .row, axis: Axis.Set = .horizontal) {
        self.role = role
        self.axis = axis
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(
                width: axis == .vertical ? thickness : nil,
                height: axis == .horizontal ? thickness : nil
            )
    }

    private var color: Color {
        switch role {
        case .section:
            return Theme.current.foreground.opacity(0.18)
        case .row:
            return Theme.current.foreground.opacity(0.12)
        case .subtle:
            return Theme.current.foreground.opacity(0.08)
        case .action:
            return ThemedScopeAccent.brass.opacity(0.72)
        }
    }

    private var thickness: CGFloat {
        role == .action ? 1.5 : 1
    }
}

// MARK: - Attachment Thumbnail

struct AttachmentThumbnail: View {
    let screenshot: RecordingScreenshot

    @State private var image: NSImage?

    private var fileURL: URL {
        ScreenshotStorage.screenshotsDirectory
            .appendingPathComponent(screenshot.filename)
    }

    var body: some View {
        Button { NSWorkspace.shared.open(fileURL) } label: {
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 90)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Theme.current.foreground.opacity(0.06))
                        .frame(width: 140, height: 90)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(Theme.current.foregroundMuted)
                        )
                }

                // Timestamp badge
                Text(formatTimestamp(screenshot.timestampMs))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Theme.current.foreground.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: screenshot.filename) {
            image = await loadThumbnail()
        }
        .onDisappear { image = nil }
    }

    private func loadThumbnail() async -> NSImage? {
        let url = fileURL
        return await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }

    private func formatTimestamp(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Large Attachment View (full-width for media notes)

struct LargeAttachmentView: View {
    let screenshot: RecordingScreenshot

    @State private var image: NSImage?

    private var fileURL: URL {
        ScreenshotStorage.screenshotsDirectory
            .appendingPathComponent(screenshot.filename)
    }

    var body: some View {
        Button { NSWorkspace.shared.open(fileURL) } label: {
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Theme.current.foreground.opacity(0.06))
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.current.foregroundMuted)
                        )
                }

                // Metadata overlay
                HStack(spacing: 6) {
                    if screenshot.timestampMs > 0 {
                        Text(formatTimestamp(screenshot.timestampMs))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                    }

                    if let w = screenshot.width, let h = screenshot.height {
                        Text("\(w)×\(h)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
                .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.foreground.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: screenshot.filename) {
            image = await loadImage()
        }
        .onDisappear { image = nil }
    }

    private func loadImage() async -> NSImage? {
        let url = fileURL
        return await Task.detached {
            NSImage(contentsOf: url)
        }.value
    }

    private func formatTimestamp(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Workflow Picker

struct WorkflowPickerSheet: View {
    let memo: MemoModel
    let onSelect: (Workflow) -> Void
    let onCancel: () -> Void

    private let workflowService = WorkflowService.shared
    @State private var selectedWorkflow: Workflow?
    @State private var searchText = ""

    private var availableWorkflows: [Workflow] {
        workflowService.workflows.filter { workflow in
            workflow.id != WorkflowDefinition.heyTalkieWorkflowId && workflow.isEnabled
        }
    }

    private var filteredWorkflows: [Workflow] {
        if searchText.isEmpty {
            return availableWorkflows
        }

        let query = searchText.lowercased()
        return availableWorkflows.filter {
            $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(Theme.current.fontTitleBold)
                    Text(memo.title ?? "Untitled Memo")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                TextField("Search workflows...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.current.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            Divider()

            if availableWorkflows.isEmpty {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "flowchart")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.strong))

                    Text("No Workflows")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Create a workflow in Settings -> Workflows")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredWorkflows.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.current.fontTitle)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.strong))
                    Text("No matching workflows")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedWorkflow) {
                    ForEach(filteredWorkflows) { workflow in
                        WorkflowPickerRow(workflow: workflow)
                            .tag(workflow)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(workflow)
                            }
                            .onTapGesture {
                                selectedWorkflow = workflow
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("\(filteredWorkflows.count) workflow\(filteredWorkflows.count == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    guard let selectedWorkflow else { return }
                    onSelect(selectedWorkflow)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWorkflow == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(Spacing.lg)
        }
        .frame(width: 450, height: 450)
        .background(SettingsManager.shared.surfaceInput)
    }
}

struct WorkflowPickerRow: View {
    let workflow: Workflow

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: workflow.icon)
                .font(Theme.current.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Performance Context Card

// Was previously `#if DEBUG`-gated when the card lived behind a hidden
// developer toggle. Now ships in release — the call site in
// TODictationContextSection.swift renders unconditionally so users can
// see processing metrics. Removing the gate fixed a release-build link
// error (cannot find PerfContextCard in scope) introduced when the use
// site was un-DEBUG'd but the definition wasn't.
struct PerfContextCard: View {
    let perf: PerformanceMetrics
    let audio: AudioMetrics?
    let routing: RoutingInfo?

    @State private var showPopover = false
    @State private var isCommandHeld = false
    @State private var isHovered = false
    @State private var eventMonitor: Any?

    private var engineMs: Int { perf.engineMs ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("PROCESSING")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)

                Text(formatMs(engineMs))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.foreground.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(
                    (isHovered && isCommandHeld) ? Color.green.opacity(0.5) : Color.green.opacity(0.2),
                    lineWidth: 0.5
                )
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering && isCommandHeld {
                showPopover = true
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            perfPopoverContent
        }
        .onAppear { setupModifierMonitor() }
        .onDisappear { removeModifierMonitor() }
    }

    private var perfPopoverContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundColor(.green)
                Text("Performance Breakdown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let endToEnd = perf.endToEndMs {
                    perfRow(label: "End-to-end", value: endToEnd, color: .orange, isTotal: true)
                }
                if let engine = perf.engineMs {
                    perfRow(label: "Transcription", value: engine, color: .green)
                }
                if let inApp = perf.inAppMs {
                    perfRow(label: "In-app processing", value: inApp, color: .blue)
                }

                if let endToEnd = perf.endToEndMs, let engine = perf.engineMs, let inApp = perf.inAppMs {
                    let overhead = endToEnd - engine - inApp
                    if overhead > 0 {
                        perfRow(label: "Overhead", value: overhead, color: .gray)
                    }
                }
            }

            if let audio = audio, (audio.peakAmplitude != nil || audio.averageAmplitude != nil) {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUDIO")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if let peak = audio.peakAmplitude {
                        metricRow(label: "Peak amplitude", value: String(format: "%.2f", peak))
                    }
                    if let avg = audio.averageAmplitude {
                        metricRow(label: "Avg amplitude", value: String(format: "%.2f", avg))
                    }
                }
            }

            if let routing = routing, routing.mode != nil || routing.wasRouted != nil {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("ROUTING")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if let mode = routing.mode {
                        metricRow(label: "Mode", value: mode)
                    }
                    if let routed = routing.wasRouted {
                        metricRow(label: "Routed", value: routed ? "Yes" : "No")
                    }
                }
            }

            if let sessionId = perf.sessionId {
                Divider()
                metricRow(label: "Session", value: String(sessionId.prefix(12)) + "...")
            }
        }
        .padding(Spacing.md)
        .frame(width: 260)
    }

    private func perfRow(label: String, value: Int, color: Color, isTotal: Bool = false) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 11, weight: isTotal ? .semibold : .regular))
                .foregroundColor(Theme.current.foreground.opacity(0.8))

            Spacer()

            Text(formatMs(value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foreground.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
        }
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private func setupModifierMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let cmd = event.modifierFlags.contains(.command)
            if isCommandHeld != cmd {
                isCommandHeld = cmd
                if cmd && isHovered {
                    showPopover = true
                }
            }
            return event
        }
    }

    private func removeModifierMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Workflow Run Row

struct WorkflowRunRow: View {
    let run: WorkflowRunModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: run.workflowIcon ?? "bolt.fill")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.accentColor)
            }

            Text(run.workflowName)
                .font(Theme.current.fontBodyMedium)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            if run.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.green)
            } else if run.status == .failed {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.red)
            } else {
                BrailleSpinner(size: 10)
            }

            Text(formatTimeAgo(run.runDate))
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.current.foreground.opacity(0.05),
                                Theme.current.foreground.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(
                    LinearGradient(
                        colors: [
                            Theme.current.foreground.opacity(0.1),
                            Theme.current.foreground.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h ago"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Transcript Card

struct RecordingTranscriptCard: View {
    let text: String
    let recording: TalkieObject
    @Binding var showJSON: Bool
    let isEditing: Bool
    @Binding var editedTranscript: String
    let isRetranscribing: Bool
    let onTranscriptChange: () -> Void
    let onRetranscribe: (String) -> Void
    /// Optional seek hook fired when a paragraph timestamp is clicked.
    /// Takes absolute seconds from audio start.
    var onTimestampSeek: ((Double) -> Void)? = nil
    /// Current playback time, threaded through to DocumentBody so the
    /// "now playing" paragraph gets a subtle reading highlight.
    var currentTime: TimeInterval = 0

    private let settings = SettingsManager.shared
    private let quickOpenService = QuickOpenService.shared
    private var isTechnical: Bool { TechnicalStyle.isActive }

    @State private var copied = false
    @State private var toolTrayHovered = false
    @State private var copyChipHovered = false

    private var hasTranscriptionData: Bool {
        recording.timedTranscription != nil || recording.isMemo || recording.isDictation || recording.isSelection
    }

    /// Right-margin metadata aside groups. Only surface useful-but-not-
    /// core technical particulars — model + confidence, perf timings, and
    /// (for dictations) the originating app context. Notes/captures
    /// don't get an aside; their content sits in the gallery instead.
    private var documentMetadataGroups: [DocumentMetadataGroup] {
        guard recording.isMemo || recording.isDictation || recording.isSelection else { return [] }
        var groups: [DocumentMetadataGroup] = []

        // Transcription: model (brass accent) + peak amplitude (proxy for confidence)
        var transcription: [DocumentMetadataRow] = []
        if let model = recording.transcriptionModel, !model.isEmpty {
            transcription.append(.init(label: "model", value: prettyModel(model), accent: true))
        }
        if let peak = recording.metadata?.audio?.peakAmplitude {
            transcription.append(.init(label: "peak", value: formatAmplitude(peak)))
        }
        if !transcription.isEmpty {
            groups.append(.init(title: "Transcription", rows: transcription))
        }

        // Timing: end-to-end + in-app
        var timing: [DocumentMetadataRow] = []
        if let endToEnd = recording.metadata?.performance?.endToEndMs {
            timing.append(.init(label: "end-to-end", value: formatMs(endToEnd)))
        }
        if let inApp = recording.metadata?.performance?.inAppMs {
            timing.append(.init(label: "in-app", value: formatMs(inApp)))
        }
        if !timing.isEmpty {
            groups.append(.init(title: "Timing", rows: timing))
        }

        // Context (dictations): captured-in app, terminal cwd. Quiet, gray.
        if recording.isDictation || recording.isSelection {
            var context: [DocumentMetadataRow] = []
            if let appName = recording.metadata?.app?.name, !appName.isEmpty {
                context.append(.init(label: "captured in", value: appName))
            }
            if let cwd = recording.metadata?.context?.terminalWorkingDir, !cwd.isEmpty {
                context.append(.init(label: "cwd", value: shortPath(cwd)))
            }
            if !context.isEmpty {
                groups.append(.init(title: "Context", rows: context))
            }
        }

        return groups
    }

    private func prettyModel(_ raw: String) -> String {
        // "parakeet:v3" → "Parakeet v3", "whisper:openai_whisper-small" → "Whisper small"
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return raw }
        let family = parts[0].prefix(1).uppercased() + parts[0].dropFirst()
        let variant = parts[1]
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return "\(family) \(variant)"
    }

    private func formatAmplitude(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.2f s", Double(ms) / 1000.0)
    }

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        let collapsed = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        if collapsed.count <= 24 { return collapsed }
        return "…" + collapsed.suffix(22)
    }

    // Document mode: default read view, no card chrome. The transcript
    // reads as an editorial document sitting on the chiffon paper —
    // serif lead, paragraph breaks, marginal rule, end slug.
    //
    // Boxed mode: editing or JSON. The card chrome returns so the user
    // sees they're inside a control surface.
    private var documentMode: Bool { !isEditing && !showJSON }

    var body: some View {
        VStack(spacing: 0) {
            // Top strip:
            //  - editing mode: nothing (the TextEditor owns the surface).
            //  - JSON mode: dismissal row with a BACK TO TEXT affordance.
            //  - document mode: a flush-right TEXT/JSON toggle so the
            //    affordance lives on the card whose body it changes
            //    (was previously in the masthead's action row, which read
            //    as detached chrome).
            // JSON entry now lives in the top action row (it's a
            // whole-payload view, not a transcript-section affordance).
            // In document mode the transcript shows no top strip; JSON
            // mode still gets its dismissal row with the easy copy.
            if !isEditing && showJSON {
                jsonDismissalRow
            }

            contentArea

            // Tool tray (Quick Open into Notion / ChatGPT / Notes / etc.)
            // demoted for now — re-add when the affordance lands in the
            // side rail Actions block, where it belongs alongside the
            // other content actions instead of floating below the body.
        }
        .clipShape(RoundedRectangle(cornerRadius: documentMode ? 0 : (isTechnical ? CornerRadius.card : CornerRadius.md)))
        .overlay {
            if documentMode {
                EmptyView()
            } else {
                // Notes are always editable — use subtle border, not accent highlight
                let showAccent = isEditing && !recording.isNote
                if isTechnical {
                    RoundedRectangle(cornerRadius: CornerRadius.card)
                        .strokeBorder(
                            showAccent ? Color.accentColor.opacity(0.4) : TechnicalStyle.borderLevel1,
                            lineWidth: settings.currentBorderWidth
                        )
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke((showAccent ? Color.accentColor : Theme.current.foreground).opacity(showAccent ? 0.28 : 0.12), lineWidth: showAccent ? 1 : BorderWidth.thin)
                }
            }
        }
    }

    // MARK: - JSON dismissal row
    //
    // Replaces the old persistent TEXT/JSON tab pair. Only renders when
    // the user has actively flipped to JSON via the overflow menu;
    // gives them a one-tap path back to the editorial text view.

    /// Reusable affordance chip for the section-rule treatment — a mono label
    /// + glyph that's subtle by default and lights up to brass on hover (or a
    /// custom tint, e.g. green for a "copied" confirm). The shared look keeps
    /// COPY · JSON a matched pair and makes the rule read as structure.
    private func sectionRuleChip(
        icon: String,
        label: String,
        hovered: Bool,
        tint: Color?,
        action: @escaping () -> Void,
        hover: @escaping (Bool) -> Void,
        help: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .regular))
                Text(label)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundColor(
                tint ?? (hovered
                    ? ThemedScopeAccent.brass
                    : Theme.current.foregroundSecondary.opacity(0.62))
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(hovered ? ThemedScopeAccent.brass.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(
                                hovered
                                    ? ThemedScopeAccent.brass.opacity(0.35)
                                    : Theme.current.foreground.opacity(0.10),
                                lineWidth: 0.5
                            )
                    )
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hover(hovering)
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(help)
    }

    private var jsonDismissalRow: some View {
        HStack(spacing: 8) {
            Text("· JSON")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.8)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.62))
            ThemedScopeRule(.subtle)
            // Easy copy lives here, inside JSON mode — copyContent() copies
            // renderJSON() while showJSON is true, so this grabs the JSON.
            sectionRuleChip(
                icon: copied ? "checkmark" : "doc.on.doc",
                label: copied ? "COPIED" : "COPY",
                hovered: copyChipHovered,
                tint: copied ? Color.green.opacity(0.8) : nil,
                action: copyContent,
                hover: { copyChipHovered = $0 },
                help: "Copy JSON"
            )
            Button {
                withAnimation(.easeOut(duration: 0.12)) { showJSON = false }
            } label: {
                Text("← BACK TO TEXT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundColor(ThemedScopeAccent.brass)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .help("Return to editorial text view")

            Spacer(minLength: 8)

            studioCopyButton
        }
        .padding(.horizontal, documentMode ? 0 : Spacing.md)
        .padding(.vertical, documentMode ? 6 : Spacing.sm)
        .background(
            documentMode
                ? Color.clear
                : (isTechnical ? TechnicalStyle.surface1 : Theme.current.foreground.opacity(0.02))
        )
    }

    private var studioCopyButton: some View {
        Button(action: copyContent) {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .regular))
                Text(copied ? "COPIED" : "COPY JSON")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundStyle(
                copied
                    ? Color.green.opacity(0.78)
                    : Theme.current.foregroundSecondary.opacity(0.68)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.current.foreground.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.current.foreground.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Copy JSON to clipboard")
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isEditing {
                    TextEditor(text: $editedTranscript)
                        .font(settings.contentFontBody)
                        .foregroundColor(Theme.current.foreground)
                        .scrollContentBackground(.hidden)
                        .lineSpacing(4)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
                        .onChange(of: editedTranscript) { _, _ in onTranscriptChange() }
                } else if showJSON {
                    jsonContent
                } else {
                    DocumentBody(
                        text: text,
                        duration: recording.duration,
                        wordCount: recording.wordCount,
                        // metadataGroups intentionally omitted — TOMarginRail
                        // (rendered at TalkieView.scrollContent level) now
                        // owns the right-margin metadata aside. Passing
                        // groups here would produce a second right column
                        // alongside the rail.
                        segments: recording.assets?.segments,
                        onSeek: onTimestampSeek,
                        currentTime: currentTime
                    )
                }
            }
            .background {
                if documentMode {
                    Color.clear
                } else {
                    Rectangle()
                        .fill(Theme.current.foreground.opacity((isEditing && !recording.isNote) ? 0.06 : 0.04))
                }
            }
            .contextMenu {
                Button {
                    copyContent()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if recording.hasAudio {
                    Divider()

                    Menu {
                        Section("Parakeet") {
                            Button("V3 (25 languages, fast)") {
                                onRetranscribe("parakeet:v3")
                            }
                            Button("V2 (English, most accurate)") {
                                onRetranscribe("parakeet:v2")
                            }
                        }

                        Section("Whisper") {
                            Button("Small (balanced)") {
                                onRetranscribe("whisper:openai_whisper-small")
                            }
                            Button("Large V3 (best quality)") {
                                onRetranscribe("whisper:distil-whisper_distil-large-v3")
                            }
                        }
                    } label: {
                        if isRetranscribing {
                            Label("Retranscribing...", systemImage: "waveform")
                        } else {
                            Label("Retranscribe...", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRetranscribing)
                }
            }

        }
    }

    private var copyButton: some View {
        Button(action: copyContent) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(settings.fontSM)
                .foregroundColor(copied ? .green : Theme.current.foregroundSecondary)
                .frame(width: ComponentSize.tiny, height: ComponentSize.tiny)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.current.foreground.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private var jsonContent: some View {
        // Min-height + max-height bracket: short payloads render at
        // their natural height with a floor (so the card always has
        // visible JSON when toggled — the previous bare ScrollView
        // could collapse to zero inside a `.fixedSize`-free VStack and
        // looked like clicking the toggle did nothing). Tall payloads
        // get a scrollable cap.
        let isScope = SettingsManager.shared.isScopeTheme
        return ScrollView {
            SyntaxHighlightedJSON(json: renderJSON())
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 280, maxHeight: 520)
        .background {
            // In Scope mode, give the JSON panel its own surface lift
            // (a cool-cream card) with a subtle ink hairline. Reads as
            // an editorial code panel sitting on the page instead of a
            // dark slab dropped in from a different theme.
            if isScope {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(ScopeEdge.faint, lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Tool Tray

    private var toolTray: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()

            ForEach(quickOpenService.enabledTargets) { target in
                toolTrayButton(target: target)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, isTechnical ? 6 : 8)
        .background {
            if documentMode {
                Color.clear
            } else if isTechnical {
                TechnicalStyle.surface1
            } else {
                Rectangle()
                    .fill(Theme.current.foreground.opacity(0.02))
            }
        }
        .onHover { toolTrayHovered = $0 }
    }

    private func toolTrayButton(target: QuickOpenTarget) -> some View {
        Button {
            quickOpenService.open(content: currentContent, in: target)
        } label: {
            Group {
                if let bundleId = target.bundleId {
                    AppIconView(bundleIdentifier: bundleId, size: 18)
                        .opacity(target.isInstalled ? 1.0 : 0.4)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.current.foreground.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .opacity(target.isInstalled ? 1.0 : 0.5)
        .help("Open in \(target.name)")
    }

    // MARK: - Helpers

    private var currentContent: String {
        showJSON ? renderJSON() : text
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentContent, forType: .string)

        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
        }
    }

    private func renderJSON() -> String {
        var entries: [(String, String)] = []

        entries.append(("id", "\"\(recording.id.uuidString)\""))
        entries.append(("type", "\"\(recording.type.rawValue)\""))

        if let title = recording.title, !title.isEmpty {
            entries.append(("title", "\"\(escapeJSON(title))\""))
        }

        entries.append(("createdAt", "\"\(recording.createdAt.iso8601)\""))

        if let modified = recording.lastModified {
            entries.append(("lastModified", "\"\(modified.iso8601)\""))
        }

        entries.append(("duration", String(format: "%.2f", recording.duration)))
        entries.append(("wordCount", "\(recording.wordCount)"))
        entries.append(("source", "\"\(recording.source.rawValue)\""))

        if let deviceId = recording.sourceDeviceId {
            entries.append(("sourceDeviceId", "\"\(escapeJSON(deviceId))\""))
        }

        if let audioURL = recording.audioURL {
            entries.append(("audioFilePath", "\"\(escapeJSON(audioURL.path))\""))
        }
        entries.append(("hasAudio", recording.hasAudio ? "true" : "false"))

        entries.append(("transcriptionStatus", "\"\(recording.transcriptionStatus.rawValue)\""))

        if let model = recording.transcriptionModel {
            entries.append(("transcriptionModel", "\"\(escapeJSON(model))\""))
        }

        entries.append(("text", "\"\(escapeJSON(text))\""))

        if let notes = recording.notes, !notes.isEmpty {
            entries.append(("notes", "\"\(escapeJSON(notes))\""))
        }

        if let summary = recording.summary, !summary.isEmpty {
            entries.append(("summary", "\"\(escapeJSON(summary))\""))
        }

        if let tasks = recording.tasks, !tasks.isEmpty {
            entries.append(("tasks", "\"\(escapeJSON(tasks))\""))
        }

        if let reminders = recording.reminders, !reminders.isEmpty {
            entries.append(("reminders", "\"\(escapeJSON(reminders))\""))
        }

        if let syncedAt = recording.cloudSyncedAt {
            entries.append(("cloudSyncedAt", "\"\(syncedAt.iso8601)\""))
        }

        entries.append(("autoProcessed", recording.autoProcessed ? "true" : "false"))

        if let appContext = recording.appContext {
            if let bundleId = appContext.bundleId {
                entries.append(("appBundleId", "\"\(escapeJSON(bundleId))\""))
            }
            if let name = appContext.name {
                entries.append(("appName", "\"\(escapeJSON(name))\""))
            }
        }

        if let perf = recording.performanceMetrics, let engineMs = perf.engineMs {
            entries.append(("latencyMs", "\(engineMs)"))
        }

        // Include raw metadataJSON fields (captures: sourceURL, sourceType, etc.)
        if let metaJSON = recording.metadataJSON,
           let metaData = metaJSON.data(using: .utf8),
           let metaDict = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            for (key, value) in metaDict.sorted(by: { $0.key < $1.key }) {
                if let strVal = value as? String {
                    entries.append((key, "\"\(escapeJSON(strVal))\""))
                } else if let numVal = value as? NSNumber {
                    entries.append((key, "\(numVal)"))
                }
            }
        }

        let screenshots = recording.screenshots
        if !screenshots.isEmpty {
            entries.append(("screenshotCount", "\(screenshots.count)"))
            let items = screenshots.map { ss in
                "{ \"filename\": \"\(escapeJSON(ss.filename))\", \"timestampMs\": \(ss.timestampMs), \"captureMode\": \"\(escapeJSON(ss.captureMode))\" }"
            }
            entries.append(("screenshots", "[\(items.joined(separator: ", "))]"))
        }

        let clips = recording.clips
        if !clips.isEmpty {
            entries.append(("clipCount", "\(clips.count)"))
            let clipItems = clips.map { c in
                "{ \"filename\": \"\(escapeJSON(c.filename))\", \"timestampMs\": \(c.timestampMs), \"durationMs\": \(c.durationMs) }"
            }
            entries.append(("clips", "[\(clipItems.joined(separator: ", "))]"))
        }

        var lines: [String] = ["{"]
        for (i, entry) in entries.enumerated() {
            let comma = i < entries.count - 1 ? "," : ""
            lines.append("  \"\(entry.0)\": \(entry.1)\(comma)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Document Body
//
// The transcript rendered as an editorial document — not a wall of mono
// in a card, but paragraphs on the page. Lead paragraph in serif
// display at a larger size; subsequent paragraphs in the body sans at
// comfortable measure. Brass marginal rule on the left, end-of-document
// slug at the bottom.
//
// Mirrors design/studio/components/studies/MacMemoDetail.tsx Body().

struct DocumentMetadataRow {
    let label: String
    let value: String
    var accent: Bool = false
}

struct DocumentMetadataGroup {
    let title: String
    let rows: [DocumentMetadataRow]
}

struct DocumentBody: View {
    let text: String
    let duration: TimeInterval
    let wordCount: Int
    /// Optional right-margin metadata aside. Renders the editor's caption
    /// — grouped technical particulars — alongside the body in a 1fr/220pt
    /// grid. Mirrors studio Body() aside.
    var metadataGroups: [DocumentMetadataGroup] = []
    /// Optional opener cue rendered before the lead paragraph (e.g.
    /// "0:00 ·"). Renders in brass mono caps, inline with the lead.
    var leadCue: String? = nil
    /// Word-level timing data (from WhisperKit / Parakeet). When
    /// present we chunk the transcript by speech pauses and stamp each
    /// paragraph with its start time. When nil we fall back to text-
    /// based splitting (double newline → single newline → one blob).
    var segments: TimedTranscription? = nil
    /// Tap-the-timestamp seek hook. Takes absolute seconds from audio
    /// start. When nil, paragraph timestamps render as static labels.
    var onSeek: ((Double) -> Void)? = nil
    /// Current playback time (seconds from audio start). When > 0 and
    /// timings are available, the paragraph containing this time is
    /// rendered with a subtle "now playing" treatment so the reader
    /// can follow along with audio.
    var currentTime: TimeInterval = 0

    @State private var hoveredParagraphIndex: Int? = nil

    /// A single paragraph with its optional start timestamp (seconds
    /// from audio start) for stamping the margin.
    struct Paragraph {
        let text: String
        let startSeconds: Double?
    }

    /// Chunk the transcript into paragraphs. Strategy ladder:
    ///   1. Honor explicit `\n\n` breaks if the source already has them.
    ///   2. Use word-level timings (`segments.words`) to detect pauses
    ///      and break on them. Enforces min/max word counts so we don't
    ///      get either choppy fragments or wall-of-text blocks.
    ///   3. Fall back to `\n` splits or one paragraph.
    /// Chunk the transcript into paragraphs. We chunk against the
    /// canonical `text` field (which always reads cleanly) and never
    /// reconstruct prose from `segments.words` — engines can emit
    /// sub-word BPE tokens (`"Br"` `"oad"` `"ly"`) that shatter into
    /// `"Br oad ly"` when joined naïvely. `words` is used solely to
    /// stamp paragraph start times.
    private var paragraphs: [Paragraph] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Explicit double-newline breaks
        let byDouble = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if byDouble.count > 1 {
            return attachTimings(to: byDouble)
        }

        // 2. Single-newline split
        let bySingle = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if bySingle.count > 1 {
            return attachTimings(to: bySingle)
        }

        // 3. Sentence-count chunking on the canonical text
        if wordCount >= Self.minWordCountForChunking {
            return attachTimings(to: sentenceChunkTexts(trimmed))
        }
        return [Paragraph(text: trimmed, startSeconds: nil)]
    }

    /// Split text into paragraph-sized chunks at sentence boundaries.
    /// softTarget / hardCap are tuned by total wordCount so long memos
    /// don't fragment into 100+ thin paragraphs.
    private func sentenceChunkTexts(_ text: String) -> [String] {
        let tokens = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard tokens.count >= Self.minWordCountForChunking else { return [text] }

        let enders: Set<Character> = [".", "!", "?"]
        var out: [String] = []
        var buffer: [String] = []

        for token in tokens {
            buffer.append(token)
            let endsSentence = token.last.map { enders.contains($0) } ?? false
            let count = buffer.count

            if (count >= softTarget && endsSentence) || count >= hardCap {
                out.append(buffer.joined(separator: " "))
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            out.append(buffer.joined(separator: " "))
        }
        return out.isEmpty ? [text] : out
    }

    /// Given paragraph texts, attach a `startSeconds` to each.
    /// Strategy:
    ///   - When `segments.words` is available, map cumulative text-
    ///     tokens → word index → words[idx].start. Engine word arrays
    ///     may emit sub-word fragments, so the index can drift; we
    ///     proportionally rescale via `words.count / textTokenCount`
    ///     to stay aligned in aggregate.
    ///   - Else estimate proportionally against `duration`.
    ///   - Else nil (no timing knowable).
    private func attachTimings(to texts: [String]) -> [Paragraph] {
        guard !texts.isEmpty else { return [] }

        let words = segments?.words ?? []
        let totalTextTokens = max(wordCount, 1)
        let scale: Double = words.isEmpty
            ? 0
            : Double(words.count) / Double(totalTextTokens)

        var cumulativeTokens = 0
        var out: [Paragraph] = []

        for chunk in texts {
            var start: Double? = nil
            if !words.isEmpty {
                let mappedIdx = min(Int(Double(cumulativeTokens) * scale), words.count - 1)
                start = words[max(mappedIdx, 0)].start
            } else if duration > 0, wordCount > 0 {
                start = Double(cumulativeTokens) / Double(wordCount) * duration
            }
            out.append(Paragraph(text: chunk, startSeconds: start))
            cumulativeTokens += chunk
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
        }
        return out
    }

    // Heuristic constants. Targets scale with total word count so long
    // memos don't fragment into 100+ thin paragraphs; targets are
    // computed lazily based on `wordCount` rather than fixed.
    private static let minWordCountForChunking = 60
    private static let pauseThreshold: Double = 1.2      // seconds

    private var softTarget: Int {
        switch wordCount {
        case ..<200:      return 60
        case 200..<1000:  return 90
        case 1000..<5000: return 160
        default:          return 240
        }
    }

    private var hardCap: Int {
        switch wordCount {
        case ..<200:      return 120
        case 200..<1000:  return 200
        case 1000..<5000: return 320
        default:          return 480
        }
    }

    // Compact rendering threshold — long transcripts get a smaller body
    // font so the wall of text reads as a scannable column rather than
    // a flood. Lead paragraph (in masthead) keeps its larger size for
    // the editorial hierarchy.
    private var isCompact: Bool { wordCount > 400 }
    private var bodyFontSize: CGFloat { isCompact ? 12 : 14 }
    private var bodyLineSpacing: CGFloat { isCompact ? 5 : 8 }
    private var paragraphSpacing: CGFloat { isCompact ? 14 : 20 }

    private var formattedDuration: String {
        let total = max(Int(duration.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        for name in ["Newsreader-Regular", "Newsreader"] {
            #if os(macOS)
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            #endif
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// Whether the masthead is rendering a standfirst that consumes
    /// paragraphs[0]. Mirrors TOHeaderSection.leadParagraph's threshold
    /// — long memos skip the standfirst so the body owns the whole
    /// transcript. Keep this in sync with TOHeaderSection.
    private var leadInMasthead: Bool { wordCount <= 400 }

    /// Whether the body has visible content. For short memos, body
    /// renders paragraphs 2…n (masthead has paragraph 1). For long
    /// memos, body renders all paragraphs.
    private var hasBodyContent: Bool {
        if leadInMasthead { return paragraphs.count > 1 }
        return !paragraphs.isEmpty
    }

    var body: some View {
        // For single-paragraph recordings the lead lives in the masthead
        // and the body has nothing to say. Render only the aside (or
        // nothing) — no orphan marginal rule, no end slug floating in
        // whitespace.
        //
        // Horizontal padding is supplied by the parent (TalkieView's
        // `recipeSections` 36pt body gutter) — DON'T add internal
        // horizontal padding or content double-indents to 72pt.
        Group {
            if hasBodyContent {
                HStack(alignment: .top, spacing: 40) {
                    documentColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !metadataGroups.isEmpty {
                        metadataAside
                            .frame(width: 220, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            } else if !metadataGroups.isEmpty {
                HStack(alignment: .top, spacing: 40) {
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                    metadataAside
                        .frame(width: 220, alignment: .leading)
                }
                .padding(.top, 0)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var documentColumn: some View {
        // Short memos: lead lives in the masthead's standfirst, body
        // renders paragraphs 2…n.
        // Long memos: masthead skips the standfirst, body owns every
        // paragraph including the first.
        let rest = leadInMasthead ? Array(paragraphs.dropFirst()) : paragraphs
        let seconds = computedDisplaySeconds(for: rest)
        let boundaries = boundaryIndices(seconds: seconds)

        let nowPlayingIdx = currentParagraphIndex(seconds: seconds)
        return VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(rest.enumerated()), id: \.offset) { idx, p in
                paragraphRow(
                    index: idx,
                    paragraph: p,
                    seconds: seconds[idx],
                    isBoundary: boundaries.contains(idx),
                    isNowPlaying: nowPlayingIdx == idx
                )
            }
            endSlug
                .padding(.top, 12)
                .padding(.leading, 56) // align with paragraph text
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One continuous marginal rule for the whole document, rather
        // than per-paragraph segments — the old per-row stroke read as
        // a series of dashes once paragraph density rose. Positioned
        // just after the 36pt timestamp gutter (+ 12pt gap = 48pt).
        .overlay(alignment: .leading) {
            ThemedScopeRule(.action, axis: .vertical)
                .opacity(0.35)
                .frame(width: 1)
                .padding(.leading, 48)
        }
    }

    /// One paragraph row: [timestamp gutter | spacer for rule | body].
    /// The marginal rule itself is rendered as a single continuous
    /// overlay by the parent `documentColumn`; this row just leaves
    /// the gutter+rule space empty. Timestamp is shown when (a) the
    /// paragraph crosses a 5-minute bucket boundary, or (b) the row
    /// is hovered, or (c) it's the currently-playing paragraph.
    /// Click → seek.
    @ViewBuilder
    private func paragraphRow(
        index: Int,
        paragraph p: Paragraph,
        seconds: Double?,
        isBoundary: Bool,
        isNowPlaying: Bool
    ) -> some View {
        let isHovered = hoveredParagraphIndex == index
        let shouldShowStamp = isBoundary || isHovered || isNowPlaying

        HStack(alignment: .top, spacing: 12) {
            timestampSlot(
                seconds: seconds,
                visible: shouldShowStamp,
                prominent: isBoundary || isNowPlaying
            )
            .frame(width: 36, alignment: .trailing)
            .padding(.top, 4)

            // Spacer column where the continuous rule lives. Same
            // width (1pt) as the rule so layout matches what we'd get
            // with per-row rules.
            Color.clear.frame(width: 1)

            Text(p.text)
                .font(.system(size: bodyFontSize, weight: .regular))
                .lineSpacing(bodyLineSpacing)
                .foregroundColor(Theme.current.foreground.opacity(isNowPlaying ? 0.98 : 0.78))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredParagraphIndex = index
            } else if hoveredParagraphIndex == index {
                hoveredParagraphIndex = nil
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isNowPlaying)
    }

    /// Which paragraph contains `currentTime`. The paragraph at index
    /// i owns the half-open range `[seconds[i], seconds[i+1])`; the
    /// last paragraph owns everything from its start to the end of
    /// the audio. Returns nil when we don't have usable timings.
    private func currentParagraphIndex(seconds: [Double?]) -> Int? {
        guard currentTime > 0 else { return nil }
        var lastValidIdx: Int? = nil
        for (idx, s) in seconds.enumerated() {
            guard let s else { continue }
            if currentTime >= s {
                lastValidIdx = idx
            } else {
                break
            }
        }
        return lastValidIdx
    }

    /// The gutter timestamp. When seek is wired, renders as a button;
    /// otherwise a plain label. Invisible when not boundary + not
    /// hovered (keeps row alignment via a clear placeholder).
    @ViewBuilder
    private func timestampSlot(seconds: Double?, visible: Bool, prominent: Bool) -> some View {
        if let seconds, visible {
            let label = Text(Self.formatTimestamp(seconds))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(
                    ScopeBrass.solid.opacity(prominent ? 0.85 : 0.55)
                )
                .monospacedDigit()
            if let onSeek {
                Button { onSeek(seconds) } label: { label }
                    .buttonStyle(.plain)
                    .help("Seek to \(Self.formatTimestamp(seconds))")
            } else {
                label
            }
        } else {
            // Invisible spacer — keeps the rule and body in a stable
            // column position even when the timestamp is hidden.
            Text("0:00")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .opacity(0)
        }
    }

    /// Per-paragraph seconds. Uses real `startSeconds` when timings are
    /// available; otherwise estimates from cumulative word count vs.
    /// total wordCount × duration.
    private func computedDisplaySeconds(for paragraphs: [Paragraph]) -> [Double?] {
        if paragraphs.contains(where: { $0.startSeconds != nil }) {
            return paragraphs.map { $0.startSeconds }
        }
        guard duration > 0, wordCount > 0 else {
            return Array(repeating: nil, count: paragraphs.count)
        }
        var cumulative = 0
        var out: [Double?] = []
        for p in paragraphs {
            out.append(Double(cumulative) / Double(wordCount) * duration)
            cumulative += p.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
        }
        return out
    }

    /// Indices that cross a 5-minute boundary. First paragraph always
    /// counts as a boundary so the document starts with an anchor.
    private func boundaryIndices(seconds: [Double?]) -> Set<Int> {
        var lastBucket: Int = -1
        var out: Set<Int> = []
        for (i, sec) in seconds.enumerated() {
            guard let s = sec else { continue }
            let bucket = Int(s / 300)  // 300 s = 5 min
            if bucket != lastBucket {
                out.insert(i)
                lastBucket = bucket
            }
        }
        return out
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var endSlug: some View {
        HStack(spacing: 10) {
            ThemedScopeRule(.section)
                .frame(width: 22)
            Text("END · \(formattedDuration) · \(wordCount) WORDS")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.65))
            ThemedScopeRule(.subtle)
        }
    }

    // MARK: - Metadata aside

    private var metadataAside: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(metadataGroups.enumerated()), id: \.offset) { gi, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text("· \(group.title.uppercased())")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(2.2)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.55))

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.label.lowercased())
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .tracking(1.6)
                                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.60))
                                Spacer(minLength: 8)
                                Text(row.value)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(
                                        row.accent
                                            ? ThemedScopeAccent.brass
                                            : Theme.current.foreground
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }

                    if gi < metadataGroups.count - 1 {
                        ThemedScopeRule(.subtle)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Syntax Highlighted JSON

struct SyntaxHighlightedJSON: View {
    let json: String

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    /// Light-Scope palette: dark inks + amber/brass accents on cream
    /// canvas. The pastels used in the dark-theme branch wash out on a
    /// cream surface, so we swap to high-contrast editorial colors that
    /// pair with the rest of the Scope substrate (ink ladder + amber
    /// accent + brass for warmer values).
    private var keyColor: Color {
        isScope ? ScopeAmber.solid : Color(red: 0.6, green: 0.8, blue: 1.0)
    }
    private var stringColor: Color {
        isScope ? ScopeInk.dim : Color(red: 0.8, green: 0.9, blue: 0.7)
    }
    private var numberColor: Color {
        isScope ? ScopeBrass.solid : Color(red: 1.0, green: 0.8, blue: 0.6)
    }
    private var boolColor: Color {
        isScope ? ScopeBrass.deep : Color(red: 0.9, green: 0.7, blue: 0.9)
    }
    private var nullColor: Color {
        isScope ? ScopeInk.subtle : Color(red: 0.7, green: 0.7, blue: 0.7)
    }
    private var bracketColor: Color {
        isScope ? ScopeInk.subtle : Theme.current.foregroundSecondary
    }

    var body: some View {
        Text(attributedJSON)
            .font(.system(size: 11, weight: isScope ? .regular : .light, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedJSON: AttributedString {
        var result = AttributedString()

        var i = json.startIndex
        while i < json.endIndex {
            let char = json[i]

            switch char {
            case "\"":
                let stringStart = i
                i = json.index(after: i)

                while i < json.endIndex {
                    if json[i] == "\\" && json.index(after: i) < json.endIndex {
                        i = json.index(i, offsetBy: 2)
                    } else if json[i] == "\"" {
                        i = json.index(after: i)
                        break
                    } else {
                        i = json.index(after: i)
                    }
                }

                let stringContent = String(json[stringStart..<i])

                var afterString = i
                while afterString < json.endIndex && json[afterString].isWhitespace {
                    afterString = json.index(after: afterString)
                }

                let isKey = afterString < json.endIndex && json[afterString] == ":"

                var attr = AttributedString(stringContent)
                attr.foregroundColor = isKey ? keyColor : stringColor
                result.append(attr)
                continue

            case "{", "}", "[", "]", ":", ",":
                var attr = AttributedString(String(char))
                attr.foregroundColor = bracketColor
                result.append(attr)

            case "t", "f":
                let remaining = String(json[i...])
                if remaining.hasPrefix("true") {
                    var attr = AttributedString("true")
                    attr.foregroundColor = boolColor
                    result.append(attr)
                    i = json.index(i, offsetBy: 3)
                } else if remaining.hasPrefix("false") {
                    var attr = AttributedString("false")
                    attr.foregroundColor = boolColor
                    result.append(attr)
                    i = json.index(i, offsetBy: 4)
                } else {
                    var attr = AttributedString(String(char))
                    attr.foregroundColor = bracketColor
                    result.append(attr)
                }

            case "n":
                let remaining = String(json[i...])
                if remaining.hasPrefix("null") {
                    var attr = AttributedString("null")
                    attr.foregroundColor = nullColor
                    result.append(attr)
                    i = json.index(i, offsetBy: 3)
                } else {
                    var attr = AttributedString(String(char))
                    attr.foregroundColor = bracketColor
                    result.append(attr)
                }

            case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                var numEnd = i
                while numEnd < json.endIndex {
                    let c = json[numEnd]
                    if c.isNumber || c == "." || c == "-" || c == "+" || c == "e" || c == "E" {
                        numEnd = json.index(after: numEnd)
                    } else {
                        break
                    }
                }

                let numStr = String(json[i..<numEnd])
                var attr = AttributedString(numStr)
                attr.foregroundColor = numberColor
                result.append(attr)
                i = json.index(before: numEnd)

            case " ", "\n", "\r", "\t":
                let attr = AttributedString(String(char))
                result.append(attr)

            default:
                var attr = AttributedString(String(char))
                attr.foregroundColor = bracketColor
                result.append(attr)
            }

            i = json.index(after: i)
        }

        return result
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let browseWorkflows = Notification.Name("browseWorkflows")
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void
    var onVolumeChange: ((Float) -> Void)? = nil
    /// When true, the card renders with no internal padding so a wrapping
    /// band can supply its own (used by the full-bleed playback footer).
    var noInternalPadding: Bool = false

    @State private var isPlayButtonHovered = false
    @State private var showVolumeSlider = false
    @State private var volume: Float = SettingsManager.shared.playbackVolume
    private var isTechnical: Bool { TechnicalStyle.isActive }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private var volumeIcon: String {
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onTogglePlayback) {
                ZStack {
                    if isTechnical {
                        Circle()
                            .fill(playButtonBackground)
                            .frame(width: 36, height: 36)
                        Circle()
                            .strokeBorder(
                                isPlayButtonHovered ? TechnicalStyle.borderHover(baseLevel: 1) : TechnicalStyle.borderLevel1,
                                lineWidth: 0.5
                            )
                            .frame(width: 36, height: 36)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(playButtonBackground)
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.current.foreground.opacity(isPlayButtonHovered ? 0.15 : 0.1),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Theme.current.foreground.opacity(isPlaying ? 0.3 : 0.15),
                                        Theme.current.foreground.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                            .frame(width: 36, height: 36)
                    }

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(playButtonForeground)
                }
                .shadow(
                    color: isTechnical ? .clear : (isPlaying ? Color.accentColor.opacity(0.3) : .black.opacity(0.1)),
                    radius: isTechnical ? 0 : (isPlaying ? 6 : 3),
                    y: isTechnical ? 0 : 2
                )
                .scaleEffect(isPlayButtonHovered && !isTechnical ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isPlayButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isPlayButtonHovered)

            VStack(spacing: Spacing.xs) {
                GeometryReader { geo in
                    AudioWaveformBars(progress: progress, isPlaying: isPlaying)
                        .frame(height: 32)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let seekProgress = max(0, min(1, value.location.x / geo.size.width))
                                    onSeek(seekProgress)
                                }
                                .onEnded { value in
                                    let seekProgress = max(0, min(1, value.location.x / geo.size.width))
                                    onSeek(seekProgress)
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                NSCursor.pointingHand.push()
                            case .ended:
                                NSCursor.pop()
                            }
                        }
                }
                .frame(height: 32)

                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text(formatTime(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                if showVolumeSlider {
                    Slider(value: $volume, in: 0...1) { editing in
                        if !editing {
                            SettingsManager.shared.playbackVolume = volume
                            onVolumeChange?(volume)
                        }
                    }
                    .frame(width: 60)
                    .controlSize(.mini)
                    .onChange(of: volume) { _, newValue in
                        AudioPlaybackManager.shared.volume = newValue
                    }
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showVolumeSlider.toggle()
                    }
                }) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Adjust volume")
            }
        }
        .padding(.horizontal, noInternalPadding ? 0 : Spacing.md)
        .padding(.vertical, noInternalPadding ? 0 : Spacing.sm)
        .onAppear {
            volume = SettingsManager.shared.playbackVolume
        }
    }

    private var playButtonBackground: Color {
        if isTechnical {
            if isPlaying { return Color.accentColor.opacity(0.3) }
            if isPlayButtonHovered { return TechnicalStyle.surface2 }
            return TechnicalStyle.surface1
        } else {
            if isPlaying { return Color.accentColor.opacity(0.4) }
            if isPlayButtonHovered { return Theme.current.foreground.opacity(0.08) }
            return Theme.current.foreground.opacity(0.04)
        }
    }

    private var playButtonForeground: Color {
        if isPlaying { return Theme.current.foreground }
        if isPlayButtonHovered { return Theme.current.foreground }
        return Theme.current.foregroundSecondary
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Audio Waveform Bars

private struct AudioWaveformBars: View {
    let progress: Double
    var isPlaying: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isPlaying)) { timeline in
            AudioWaveformBarsContent(
                progress: progress,
                isPlaying: isPlaying,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}

private struct AudioWaveformBarsContent: View {
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval

    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2

    private static func barHeight(for index: Int) -> Double {
        let seed = Double(index) * 1.618
        let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
        return max(0.15, min(1.0, h))
    }

    var body: some View {
        GeometryReader { geo in
            let barCount = max(1, Int(geo.size.width / (Self.barWidth + Self.barSpacing)))

            HStack(spacing: Self.barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    AudioWaveformBar(
                        index: i,
                        totalBars: barCount,
                        baseHeight: Self.barHeight(for: i),
                        progress: progress,
                        isPlaying: isPlaying,
                        time: time,
                        containerHeight: geo.size.height,
                        barWidth: Self.barWidth
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct AudioWaveformBar: View {
    let index: Int
    let totalBars: Int
    let baseHeight: Double
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval
    let containerHeight: CGFloat
    var barWidth: CGFloat = 3

    private var barProgress: Double {
        Double(index) / Double(totalBars)
    }

    private var isPast: Bool {
        barProgress < progress
    }

    private var isCurrent: Bool {
        abs(barProgress - progress) < (1.0 / Double(totalBars))
    }

    private var animatedHeight: Double {
        if isPlaying && isPast {
            return baseHeight + sin(time * 4 + Double(index) * 0.5) * 0.1
        }
        return baseHeight
    }

    private var barColor: Color {
        if isCurrent {
            return .primary
        } else if isPast {
            return .accentColor
        } else {
            return Theme.current.foregroundSecondary.opacity(Opacity.strong)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(barColor)
            .frame(width: barWidth, height: containerHeight * max(0.15, animatedHeight))
    }
}

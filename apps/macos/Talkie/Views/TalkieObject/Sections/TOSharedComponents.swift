//
//  TOSharedComponents.swift
//  Talkie
//
//  Shared visual components used by TalkieObject section views.
//  Extracted from RecordingDetail.swift during TalkieObject refactor.
//

import SwiftUI
import TalkieKit

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
        .task {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
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
        .task {
            image = await loadImage()
        }
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

// MARK: - Performance Context Card (Debug)

#if DEBUG
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
#endif

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

    private let settings = SettingsManager.shared
    private let quickOpenService = QuickOpenService.shared
    private var isTechnical: Bool { TechnicalStyle.isActive }

    @State private var copied = false
    @State private var toolTrayHovered = false

    private var hasTranscriptionData: Bool {
        recording.timedTranscription != nil || recording.isMemo || recording.isDictation || recording.isSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isEditing {
                if hasTranscriptionData {
                    tabToggle
                } else {
                    HStack {
                        Spacer()
                        copyButton
                            .padding(.trailing, Spacing.sm)
                    }
                    .padding(.vertical, Spacing.xs)
                    .background(
                        isTechnical ? TechnicalStyle.surface1 : Theme.current.foreground.opacity(0.02)
                    )
                }
            }

            contentArea

            if !isEditing && (recording.isDictation || recording.hasAudio) {
                toolTray
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isTechnical ? CornerRadius.card : CornerRadius.md))
        .overlay {
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

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack {
            Spacer()

            HStack(spacing: 0) {
                tabButton("Text", icon: "text.alignleft", isSelected: !showJSON) {
                    withAnimation(.easeInOut(duration: 0.15)) { showJSON = false }
                }

                tabButton("JSON", icon: "curlybraces", isSelected: showJSON) {
                    withAnimation(.easeInOut(duration: 0.15)) { showJSON = true }
                }
            }
            .padding(2)
            .background(
                Capsule()
                    .fill(Theme.current.foreground.opacity(0.04))
            )

            Spacer()

            copyButton
                .padding(.trailing, Spacing.sm)
        }
        .padding(.vertical, isTechnical ? Spacing.xs : Spacing.sm)
        .background(
            isTechnical ? TechnicalStyle.surface1 : Theme.current.foreground.opacity(0.02)
        )
    }

    private func tabButton(_ label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(settings.fontXS)
                Text(label)
                    .font(settings.fontXSMedium)
            }
            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.current.foreground.opacity(0.09) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
                    Text(text)
                        .font(settings.contentFontBody)
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                Rectangle()
                    .fill(Theme.current.foreground.opacity((isEditing && !recording.isNote) ? 0.06 : 0.04))
            )
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
        ScrollView {
            SyntaxHighlightedJSON(json: renderJSON())
                .padding(Spacing.md)
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
        .background(
            Group {
                if isTechnical {
                    TechnicalStyle.surface1
                } else {
                    Rectangle()
                        .fill(Theme.current.foreground.opacity(0.02))
                }
            }
        )
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

        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
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

// MARK: - Syntax Highlighted JSON

struct SyntaxHighlightedJSON: View {
    let json: String

    private let keyColor = Color(red: 0.6, green: 0.8, blue: 1.0)
    private let stringColor = Color(red: 0.8, green: 0.9, blue: 0.7)
    private let numberColor = Color(red: 1.0, green: 0.8, blue: 0.6)
    private let boolColor = Color(red: 0.9, green: 0.7, blue: 0.9)
    private let nullColor = Color(red: 0.7, green: 0.7, blue: 0.7)
    private let bracketColor = Theme.current.foregroundSecondary

    var body: some View {
        Text(attributedJSON)
            .font(.system(size: 11, weight: .light, design: .monospaced))
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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

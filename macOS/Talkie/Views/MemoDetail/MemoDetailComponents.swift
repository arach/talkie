//
//  MemoDetailComponents.swift
//  Talkie
//
//  Extracted standalone components from MemoDetailView
//

import SwiftUI
import AVFoundation
import AppKit
import os

struct AIResultSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.techLabel)
                Text(title.uppercased())
                    .font(.techLabel)
            }
            .foregroundColor(Theme.current.foregroundSecondary)

            content()
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Action Button for macOS
struct ActionButtonMac: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isCompleted: Bool
    var runCount: Int = 0  // Number of times this action has been run
    let action: () -> Void

    @State private var triggered = false

    var body: some View {
        Button(action: triggerAction) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    // Main icon
                    Image(systemName: icon)
                        .font(Theme.current.fontTitle)
                        .foregroundColor(triggered ? .accentColor : Theme.current.foregroundSecondary)
                        .frame(width: 20, height: 20)
                        .scaleEffect(triggered ? 1.2 : 1.0)

                    // Triggered flash overlay
                    if triggered {
                        Circle()
                            .fill(Color.accentColor.opacity(Opacity.strong))
                            .frame(width: 32, height: 32)
                            .scaleEffect(triggered ? 1.5 : 0.5)
                            .opacity(triggered ? 0 : 1)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: triggered)

                Text(title)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(triggered ? .accentColor : Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Run count badge
            if runCount > 0 {
                Text("\(runCount)")
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foreground.opacity(Opacity.prominent))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SettingsManager.shared.surfaceSelected)
                    .clipShape(Capsule())
                    .offset(x: -4, y: 4)
            }
        }
    }

    private func triggerAction() {
        // Visual feedback
        withAnimation(.easeOut(duration: 0.15)) {
            triggered = true
        }

        // Reset after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                triggered = false
            }
        }

        // Fire the action (async, non-blocking)
        action()
    }
}

// MARK: - Workflow Run List Item (compact row for selection)
struct WorkflowRunListItem: View {
    let run: WorkflowRun
    let onSelect: () -> Void
    let onNavigateToWorkflow: () -> Void

    @State private var isHovering = false

    private var runDate: Date { run.runDate ?? Date() }
    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var modelInfo: String? { run.modelId }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: workflowIcon)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(SettingsManager.shared.surfaceAlternate)
                    .cornerRadius(CornerRadius.xs)

                // Workflow name (clickable to navigate)
                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)
                        .underline(isHovering)
                }
                .buttonStyle(.plain)

                // Model badge
                if let model = modelInfo {
                    Text(model)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(CornerRadius.xs)
                }

                Spacer()

                // Timestamp
                Text(formatRunDate(runDate))
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))

                // Chevron
                Image(systemName: "chevron.right")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.strong))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isHovering ? SettingsManager.shared.surfaceHover : Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // Static cached formatter
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatRunDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Workflow Run Detail View (full execution details)
struct WorkflowRunDetailView: View {
    let run: WorkflowRun
    let onBack: () -> Void
    let onNavigateToWorkflow: () -> Void
    let onDelete: () -> Void

    private var runDate: Date { run.runDate ?? Date() }
    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var providerName: String? { run.providerName }
    private var modelId: String? { run.modelId }

    private var stepExecutions: [WorkflowExecutor.StepExecution] {
        guard let json = run.stepOutputsJSON,
              let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([WorkflowExecutor.StepExecution].self, from: data)
        else { return [] }
        return steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: Spacing.sm) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)

                Image(systemName: workflowIcon)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)
                }
                .buttonStyle(.plain)

                if let model = modelId {
                    Text(model)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(CornerRadius.xs)
                }

                Spacer()

                Text(formatFullDate(runDate))
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Theme.current.surface1)

            Divider()
                .opacity(Opacity.half)

            // Step-by-step execution
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output if no step data
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("OUTPUT")
                                    .font(Theme.current.fontSMBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Text(output)
                                    .font(SettingsManager.shared.contentFontBody)
                                    .foregroundColor(Theme.current.foreground)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(Spacing.sm)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.current.surface1)
                                    .cornerRadius(CornerRadius.sm)
                            }
                        }
                    } else {
                        ForEach(Array(stepExecutions.enumerated()), id: \.offset) { index, step in
                            StepExecutionCard(step: step, isLast: index == stepExecutions.count - 1)

                            if index < stepExecutions.count - 1 {
                                // Connector between steps
                                HStack {
                                    Spacer()
                                        .frame(width: 14)
                                    VStack(spacing: 2) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            Circle()
                                                .fill(SettingsManager.shared.surfaceAlternate)
                                                .frame(width: 3, height: 3)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(SettingsManager.shared.surfaceInput)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Step Execution Card
struct StepExecutionCard: View {
    let step: WorkflowExecutor.StepExecution
    let isLast: Bool
    private let settings = SettingsManager.shared

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Step header
            HStack(spacing: Spacing.sm) {
                Text("\(step.stepNumber)")
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(settings.resolvedAccentColor)
                    .cornerRadius(CornerRadius.xs)

                Image(systemName: step.stepIcon)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text(step.stepType.uppercased())
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }

            // Input (collapsible)
            if showInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))

                    Text(step.input)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(CornerRadius.xs)
                }
            }

            // Output
            OutputCard(step.output, label: "output → {{\(step.outputKey)}}", isHighlighted: isLast)
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface2)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
        )
    }
}

// MARK: - Browse Workflows Button (special CTA style)
struct BrowseWorkflowsButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.current.fontTitle)
                    .foregroundColor(.accentColor)

                Text("MORE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.accentColor.opacity(isHovering ? Opacity.medium : Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.accentColor.opacity(Opacity.strong), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Browse all workflows")
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let progress: Double
    let isPlaying: Bool

    // Generate pseudo-random but consistent waveform bars
    private let barCount = 60

    private func barHeight(at index: Int) -> CGFloat {
        // Use sine waves with different frequencies to create natural-looking waveform
        let x = Double(index) / Double(barCount)
        let h1 = sin(x * .pi * 3) * 0.3
        let h2 = sin(x * .pi * 7 + 1) * 0.2
        let h3 = sin(x * .pi * 13 + 2) * 0.15
        let h4 = cos(x * .pi * 5) * 0.2
        let base = 0.3 + abs(h1 + h2 + h3 + h4)
        return CGFloat(min(1.0, max(0.15, base)))
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barProgress = Double(index) / Double(barCount)
                    let isPast = barProgress < progress

                    Rectangle()
                        .fill(isPast ? Color.accentColor : Theme.current.foregroundSecondary.opacity(Opacity.strong))
                        .frame(width: max(1, barWidth), height: geometry.size.height * barHeight(at: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Output Card (clean card with copy button)
struct OutputCard: View {
    let content: String
    let label: String?
    var isHighlighted: Bool = false

    @State private var copied = false
    @State private var isExpanded = false

    private var isLong: Bool { content.count > 300 }
    private var displayContent: String {
        if isLong && !isExpanded {
            return String(content.prefix(280)) + "..."
        }
        return content
    }

    init(_ content: String, label: String? = nil, isHighlighted: Bool = false) {
        self.content = content
        self.label = label
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with label and copy button
            if label != nil || true {
                HStack {
                    if let label = label {
                        Text(label.uppercased())
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                    }

                    Spacer()

                    Button(action: copyToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(Theme.current.fontXSMedium)
                                .foregroundColor(copied ? .green : Theme.current.foregroundSecondary.opacity(Opacity.half))
                            if copied {
                                Text("COPIED")
                                    .font(.techLabelSmall)
                            }
                        }
                        .foregroundColor(copied ? .green : Theme.current.foregroundSecondary.opacity(Opacity.half))
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(copied ? SettingsManager.shared.surfaceSuccess : SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            Text(displayContent)
                .font(.bodySmall)
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Expand button for long content
            if isLong {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "SHOW LESS" : "SHOW MORE")
                            .font(.techLabelSmall)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(isHighlighted ? SettingsManager.shared.surfaceSuccess : SettingsManager.shared.borderDefault, lineWidth: isHighlighted ? 1 : 0.5)
        )
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

// MARK: - Transcript Quick Actions Toolbar

/// App definitions for quick actions
struct QuickActionApp: Identifiable {
    let id: String  // Unique identifier for state tracking
    let bundleIdentifier: String?  // nil for path-based apps
    let appPath: String?  // for apps without bundle ID registration
    let displayName: String
    let helpText: String
    let urlScheme: String?  // URL scheme if supported

    // Well-known apps
    static let claude = QuickActionApp(
        id: "claude",
        bundleIdentifier: "com.anthropic.claudefordesktop",
        appPath: "/Applications/Claude.app",
        displayName: "Claude",
        helpText: "Copy transcript and open Claude desktop app",
        urlScheme: "claude://"
    )

    static let chatGPT = QuickActionApp(
        id: "chatgpt",
        bundleIdentifier: "com.openai.chat",
        appPath: "/Applications/ChatGPT.app",
        displayName: "ChatGPT",
        helpText: "Copy transcript and open ChatGPT desktop app",
        urlScheme: "chatgpt://"
    )

    static let obsidian = QuickActionApp(
        id: "obsidian",
        bundleIdentifier: "md.obsidian",
        appPath: "/Applications/Obsidian.app",
        displayName: "Obsidian",
        helpText: "Create new Obsidian note with transcript",
        urlScheme: nil  // Uses special URL scheme with content
    )

    static let macVim = QuickActionApp(
        id: "macvim",
        bundleIdentifier: "org.vim.MacVim",
        appPath: "/Applications/MacVim.app",
        displayName: "MacVim",
        helpText: "Open transcript in MacVim text editor",
        urlScheme: nil
    )

    static let allApps: [QuickActionApp] = [.claude, .chatGPT, .obsidian, .macVim]

    /// Check if app is installed - call once and cache, not during render
    func checkIsInstalled() -> Bool {
        if let bundleID = bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
        if let path = appPath {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    /// Cached list of installed apps - computed once at app launch
    static let installedApps: [QuickActionApp] = {
        allApps.filter { $0.checkIsInstalled() }
    }()
}

struct TranscriptQuickActions: View {
    let transcript: String

    @State private var copiedState: String? = nil  // Track which action just completed
    @State private var feedbackMessage: String? = nil  // Feedback text to show

    private let logger = Logger(subsystem: "jdi.talkie.core", category: "QuickActions")

    var body: some View {
        HStack(spacing: 4) {
            // Copy button (always shown)
            copyButton

            // Divider between copy and apps
            if !QuickActionApp.installedApps.isEmpty {
                Divider()
                    .frame(height: 16)
            }

            // App-specific buttons (only for installed apps)
            ForEach(QuickActionApp.installedApps) { app in
                appButton(for: app)
            }

            // Feedback message inline (no layout shift)
            if let message = feedbackMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
    }

    // MARK: - Button Views

    private var copyButton: some View {
        Button {
            copyToClipboard()
            showFeedback("Copied to clipboard")
            flashState("copy")
        } label: {
            Image(systemName: copiedState == "copy" ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(copiedState == "copy" ? .green : Theme.current.foregroundSecondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Copy transcript to clipboard")
    }

    @ViewBuilder
    private func appButton(for app: QuickActionApp) -> some View {
        Button {
            executeAction(for: app)
            showFeedback("Copied — paste in \(app.displayName)")
            flashState(app.id)
        } label: {
            Group {
                if copiedState == app.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: 20, height: 20)
                } else if let bundleID = app.bundleIdentifier {
                    AppIconView(bundleIdentifier: bundleID, size: 20)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 20, height: 20)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(app.helpText)
    }

    // MARK: - State Management

    private func flashState(_ state: String) {
        copiedState = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedState == state {
                copiedState = nil
            }
        }
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            feedbackMessage = nil
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        logger.debug("Copied transcript to clipboard")
    }

    private func executeAction(for app: QuickActionApp) {
        switch app.id {
        case "claude":
            openInClaude()
        case "chatgpt":
            openInChatGPT()
        case "obsidian":
            openInObsidian()
        case "macvim":
            openInMacVim()
        default:
            copyToClipboard()
        }
    }

    private func openInClaude() {
        copyToClipboard()
        if let url = URL(string: "claude://") {
            NSWorkspace.shared.open(url)
            logger.debug("Opening Claude with transcript")
        }
    }

    private func openInChatGPT() {
        copyToClipboard()
        if let url = URL(string: "chatgpt://") {
            NSWorkspace.shared.open(url)
            logger.debug("Opening ChatGPT with transcript")
        }
    }

    private func openInObsidian() {
        // Obsidian supports creating new notes via URL scheme
        let encodedContent = transcript.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HHmmss"
        let fileName = "Talkie \(dateFormatter.string(from: Date()))"
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Talkie Note"

        if let url = URL(string: "obsidian://new?name=\(encodedName)&content=\(encodedContent)") {
            NSWorkspace.shared.open(url)
            logger.debug("Opening Obsidian with transcript")
        }
    }

    private func openInMacVim() {
        // Write to temp file and open with MacVim
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "talkie-transcript-\(UUID().uuidString.prefix(8)).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try transcript.write(to: fileURL, atomically: true, encoding: .utf8)

            // Try mvim command first, fall back to MacVim.app
            let mvimURL = URL(fileURLWithPath: "/usr/local/bin/mvim")
            let macVimAppURL = URL(fileURLWithPath: "/Applications/MacVim.app")

            if FileManager.default.fileExists(atPath: mvimURL.path) {
                let process = Process()
                process.executableURL = mvimURL
                process.arguments = [fileURL.path]
                try process.run()
            } else if FileManager.default.fileExists(atPath: macVimAppURL.path) {
                NSWorkspace.shared.open([fileURL], withApplicationAt: macVimAppURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                // Fallback: open with default text editor
                NSWorkspace.shared.open(fileURL)
            }
            logger.debug("Opening MacVim with transcript")
        } catch {
            logger.error("Failed to open in MacVim: \(error.localizedDescription)")
            // Fallback to clipboard
            copyToClipboard()
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let browseWorkflows = Notification.Name("browseWorkflows")
}

// MARK: - Workflow Picker Sheet

struct WorkflowPickerSheet: View {
    let memo: VoiceMemo
    let onSelect: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    private let workflowManager = WorkflowManager.shared
    @State private var selectedWorkflow: WorkflowDefinition?
    @State private var searchText = ""

    /// Workflows available to run (exclude system workflows like Hey Talkie)
    private var availableWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { workflow in
            workflow.id != WorkflowDefinition.heyTalkieWorkflowId &&
            workflow.isEnabled
        }
    }

    private var filteredWorkflows: [WorkflowDefinition] {
        if searchText.isEmpty {
            return availableWorkflows
        }
        let query = searchText.lowercased()
        return availableWorkflows.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Search bar
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
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.strong))

                    Text("No Workflows")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Create a workflow in Settings → Workflows")
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
                        WorkflowPickerRow(workflow: workflow, isSelected: selectedWorkflow?.id == workflow.id)
                            .tag(workflow)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(workflow)
                            }
                            .onTapGesture(count: 1) {
                                selectedWorkflow = workflow
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredWorkflows.count) workflow\(filteredWorkflows.count == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    if let workflow = selectedWorkflow {
                        onSelect(workflow)
                    }
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
    let workflow: WorkflowDefinition
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: workflow.icon)
                .font(Theme.current.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 28)

            // Info
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

            // Step count
            Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.vertical, 4)
    }
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
            // Play/Pause button
            Button(action: onTogglePlayback) {
                ZStack {
                    Circle()
                        .fill(playButtonBackground)
                        .frame(width: 36, height: 36)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(playButtonForeground)
                }
            }
            .buttonStyle(.plain)
            .onHover { isPlayButtonHovered = $0 }

            // Waveform + timeline
            VStack(spacing: Spacing.xs) {
                AudioWaveformBars(progress: progress, isPlaying: isPlaying)
                    .frame(height: 32)

                // Time row
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

            // Volume control
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
                        // Live update while dragging
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
        .onAppear {
            volume = SettingsManager.shared.playbackVolume
        }
    }

    private var playButtonBackground: Color {
        if isPlaying { return Color.accentColor.opacity(Opacity.strong) }
        if isPlayButtonHovered { return Color(nsColor: .controlBackgroundColor).opacity(Opacity.prominent) }
        return Color(nsColor: .separatorColor).opacity(Opacity.strong)
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

    // Pre-computed bar heights for consistency
    private static let barHeights: [Double] = {
        var heights: [Double] = []
        for i in 0..<40 {
            let seed = Double(i) * 1.618
            let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
            heights.append(max(0.15, min(1.0, h)))
        }
        return heights
    }()

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<Self.barHeights.count, id: \.self) { i in
                    AudioWaveformBar(
                        index: i,
                        totalBars: Self.barHeights.count,
                        baseHeight: Self.barHeights[i],
                        progress: progress,
                        isPlaying: isPlaying,
                        time: time,
                        containerHeight: geo.size.height
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(width: 3, height: containerHeight * max(0.15, animatedHeight))
    }
}

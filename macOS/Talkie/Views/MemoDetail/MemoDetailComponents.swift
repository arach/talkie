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
            .foregroundColor(.secondary)

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
            VStack(spacing: 6) {
                ZStack {
                    // Main icon
                    Image(systemName: icon)
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(triggered ? .accentColor : .secondary)
                        .frame(width: 20, height: 20)
                        .scaleEffect(triggered ? 1.2 : 1.0)

                    // Triggered flash overlay
                    if triggered {
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .scaleEffect(triggered ? 1.5 : 0.5)
                            .opacity(triggered ? 0 : 1)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: triggered)

                Text(title)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(triggered ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Run count badge
            if runCount > 0 {
                Text("\(runCount)")
                    .font(.techLabelSmall)
                    .foregroundColor(.primary.opacity(0.7))
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
            HStack(spacing: 10) {
                // Icon
                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(SettingsManager.shared.surfaceAlternate)
                    .cornerRadius(4)

                // Workflow name (clickable to navigate)
                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(.primary)
                        .underline(isHovering)
                }
                .buttonStyle(.plain)

                // Model badge
                if let model = modelInfo {
                    Text(model)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }

                Spacer()

                // Timestamp
                Text(formatRunDate(runDate))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.6))

                // Chevron
                Image(systemName: "chevron.right")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? SettingsManager.shared.surfaceHover : Theme.current.surface1)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
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
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)

                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                if let model = modelId {
                    Text(model)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }

                Spacer()

                Text(formatFullDate(runDate))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.6))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.current.surface1)

            Divider()
                .opacity(0.5)

            // Step-by-step execution
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output if no step data
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OUTPUT")
                                    .font(Theme.current.fontSMBold)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(SettingsManager.shared.contentFontBody)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.current.surface1)
                                    .cornerRadius(6)
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
                .padding(16)
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
        VStack(alignment: .leading, spacing: 10) {
            // Step header
            HStack(spacing: 8) {
                Text("\(step.stepNumber)")
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(settings.resolvedAccentColor)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            // Input (collapsible)
            if showInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(4)
                }
            }

            // Output
            OutputCard(step.output, label: "output → {{\(step.outputKey)}}", isHighlighted: isLast)
        }
        .padding(12)
        .background(Theme.current.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(.accentColor)

                Text("MORE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(isHovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
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
                        .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.25))
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
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    Spacer()

                    Button(action: copyToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(Theme.current.fontXSMedium)
                                .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                            if copied {
                                Text("COPIED")
                                    .font(.techLabelSmall)
                            }
                        }
                        .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(copied ? SettingsManager.shared.surfaceSuccess : SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            Text(displayContent)
                .font(.bodySmall)
                .foregroundColor(.primary)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
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
                .foregroundColor(copiedState == "copy" ? .green : .secondary)
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
                        .foregroundColor(.secondary)
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
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)

                TextField("Search workflows...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.current.surface1)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if availableWorkflows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flowchart")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Workflows")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(.secondary)

                    Text("Create a workflow in Settings → Workflows")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredWorkflows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No matching workflows")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
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
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

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
            .padding(16)
        }
        .frame(width: 450, height: 450)
        .background(SettingsManager.shared.surfaceInput)
    }
}

struct WorkflowPickerRow: View {
    let workflow: WorkflowDefinition
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(SettingsManager.shared.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(.primary)

                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Step count
            Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
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
                        .frame(width: 36, height: 36)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(playButtonForeground)
                }
            }
            .buttonStyle(.plain)
            .onHover { isPlayButtonHovered = $0 }

            // Waveform + timeline
            VStack(spacing: 6) {
                AudioWaveformBars(progress: progress, isPlaying: isPlaying)
                    .frame(height: 32)

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
        if isPlaying { return Color.accentColor.opacity(0.25) }
        if isPlayButtonHovered { return Color(nsColor: .controlBackgroundColor).opacity(0.8) }
        return Color(nsColor: .separatorColor).opacity(0.3)
    }

    private var playButtonForeground: Color {
        if isPlaying { return .primary }
        if isPlayButtonHovered { return .primary }
        return .secondary
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
            return .secondary.opacity(0.3)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(barColor)
            .frame(width: 3, height: containerHeight * max(0.15, animatedHeight))
    }
}

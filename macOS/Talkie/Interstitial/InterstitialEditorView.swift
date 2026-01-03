//
//  InterstitialEditorView.swift
//  Talkie
//
//  Floating panel UI for editing transcribed text and applying LLM polish
//  Theme-aware design that adapts to light/dark modes
//

import SwiftUI

struct InterstitialEditorView: View {
    @State var manager: InterstitialManager
    @Environment(SettingsManager.self) private var settings
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isInstructionFocused: Bool
    @State private var customInstruction: String = ""
    @State private var isHoveringCopyArea = false

    // Expandable smart action state
    @State private var expandedActionId: String? = nil
    @State private var editablePrompt: String = ""

    // MARK: - Theme-aware colors

    private var isDark: Bool { settings.isDarkMode }

    // MARK: - Performance-optimized colors (solid, no opacity layers)

    private var panelBackground: Color {
        isDark ? Color(white: 0.1) : Color(white: 0.98)
    }

    private var contentBackground: Color {
        isDark ? Color(white: 0.12) : Color.white
    }

    private var inputBackground: Color {
        isDark ? Color(white: 0.15) : Color(white: 0.95)
    }

    private var borderColor: Color {
        isDark ? Color(white: 0.2) : Color(white: 0.88)
    }

    private var textPrimary: Color {
        isDark ? Color.white : Color(white: 0.1)
    }

    private var textSecondary: Color {
        isDark ? Color(white: 0.7) : Color(white: 0.4)
    }

    private var textMuted: Color {
        isDark ? Color(white: 0.5) : Color(white: 0.55)
    }

    private var accentColor: Color { settings.resolvedAccentColor }

    var body: some View {
        Group {
            switch manager.viewState {
            case .editing:
                editingView
            case .reviewing:
                reviewingView
            }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 900,
               minHeight: 340, idealHeight: 400, maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(panelBackground)
                // Lightweight shadow - single layer, smaller radius
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(borderColor, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Main content area (text + instruction)
            contentArea

            // Footer bar
            footerBar
        }
    }

    // MARK: - Reviewing View (Diff)

    private var reviewingView: some View {
        Group {
            if let diff = manager.currentDiff {
                DiffReviewView(
                    diff: diff,
                    onAccept: { manager.acceptRevision() },
                    onReject: { manager.rejectRevision() }
                )
            } else {
                // Fallback - shouldn't happen, but just in case
                editingView
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                // Model indicator - clickable to expand settings (compact: logo + name)
                modelIndicator

                Spacer()

                // Status indicator - minimal pill
                if manager.isPolishing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 8, height: 8)
                        Text("REVISING")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(inputBackground)
                    )
                }

                // History button (only show if there's history)
                if !manager.revisions.isEmpty {
                    historyButton
                }

                // Dismiss button - clear X
                Button(action: { manager.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textMuted)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(inputBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Expandable LLM settings panel
            if manager.showLLMSettings {
                llmSettingsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: manager.showLLMSettings)
    }

    // MARK: - Model Indicator (compact logo + name)

    private var modelIndicator: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.12)) {
                manager.showLLMSettings.toggle()
            }
        }) {
            HStack(spacing: 6) {
                // Provider logo/icon
                providerIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(providerColor)

                // Model name (short)
                Text(displayModelName)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(textPrimary)
                    .lineLimit(1)

                Image(systemName: manager.showLLMSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(manager.showLLMSettings ? accentColor : borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Model: \(manager.llmModelId ?? "None") • Click to configure")
    }

    private var providerIcon: Image {
        guard let providerId = manager.llmProviderId else {
            return Image(systemName: "cpu")
        }
        switch providerId {
        case "openai": return Image(systemName: "sparkle")
        case "anthropic": return Image(systemName: "brain")
        case "google", "gemini": return Image(systemName: "diamond")
        case "groq": return Image(systemName: "bolt")
        case "mlx": return Image(systemName: "laptopcomputer")
        default: return Image(systemName: "cpu")
        }
    }

    private var providerColor: Color {
        guard let providerId = manager.llmProviderId else { return textMuted }
        switch providerId {
        case "openai": return Color(red: 0.3, green: 0.7, blue: 0.5) // OpenAI green
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35) // Anthropic orange
        case "google", "gemini": return Color(red: 0.3, green: 0.5, blue: 0.9) // Google blue
        case "groq": return Color(red: 0.9, green: 0.4, blue: 0.3) // Groq red
        case "mlx": return Color(red: 0.6, green: 0.4, blue: 0.8) // MLX purple
        default: return textMuted
        }
    }

    // MARK: - History Button

    @State private var showHistory = false

    private var historyButton: some View {
        Button(action: { showHistory.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                Text("\(manager.revisions.count)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(inputBackground)
                    .overlay(
                        Capsule()
                            .stroke(showHistory ? accentColor : borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Edit history (\(manager.revisions.count) edits)")
        .popover(isPresented: $showHistory) {
            historyPopover
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("EDIT HISTORY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(textMuted)
                Spacer()
                Text("\(manager.revisions.count) edits")
                    .font(Theme.current.fontXS)
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            // Timeline or Preview
            if let previewing = manager.previewingRevision {
                revisionPreview(previewing)
            } else {
                // Timeline list
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(manager.revisions.reversed()) { revision in
                            historyRow(revision)
                        }
                    }
                    .padding(Spacing.sm)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 320)
        .background(panelBackground)
    }

    private func historyRow(_ revision: InterstitialManager.Revision) -> some View {
        Button(action: {
            manager.previewRevision(revision)
        }) {
            HStack(spacing: Spacing.sm) {
                // Timeline dot
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    // Instruction (truncated)
                    Text(revision.shortInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(textPrimary)
                        .lineLimit(1)

                    // Metadata
                    HStack(spacing: 6) {
                        Text("\(revision.changeCount) changes")
                            .font(Theme.current.fontXS)
                            .foregroundColor(textMuted)
                        Text("•")
                            .foregroundColor(textMuted)
                        Text(revision.timeAgo)
                            .font(Theme.current.fontXS)
                            .foregroundColor(textMuted)
                    }
                }

                Spacer()

                // View hint
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func revisionPreview(_ revision: InterstitialManager.Revision) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Back button + title
            HStack {
                Button(action: { manager.dismissPreview() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(revision.timeAgo)
                    .font(Theme.current.fontXS)
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            // Instruction
            Text(revision.instruction)
                .font(Theme.current.fontSM)
                .foregroundColor(textPrimary)
                .padding(.horizontal, Spacing.md)

            // Text preview (the result of this revision)
            ScrollView {
                Text(revision.textAfter)
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(inputBackground)
            )
            .padding(.horizontal, Spacing.md)

            // Actions
            HStack(spacing: Spacing.sm) {
                // Copy text
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(revision.textAfter, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(inputBackground)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Use this version
                Button(action: {
                    manager.restoreFromRevision(revision)
                    showHistory = false
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Use This Version")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var displayModelName: String {
        if let model = manager.llmModelId {
            // Shorten common model names
            return model
                .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
                .replacingOccurrences(of: "gpt-4o", with: "4o")
                .replacingOccurrences(of: "claude-3-5-sonnet", with: "sonnet")
                .replacingOccurrences(of: "claude-3-haiku", with: "haiku")
                .replacingOccurrences(of: "gemini-1.5-flash", with: "flash")
                .replacingOccurrences(of: "llama-3.1-70b-versatile", with: "llama-70b")
        }
        return "Select model"
    }

    // MARK: - LLM Settings Panel (expanded state)

    @ViewBuilder
    private var llmSettingsPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Provider + Model selector
            HStack(spacing: Spacing.sm) {
                // Provider picker
                Menu {
                    ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                        Button(action: {
                            manager.llmProviderId = provider.id
                            manager.llmModelId = provider.defaultModelId
                        }) {
                            HStack {
                                Text(provider.name)
                                if manager.llmProviderId == provider.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentProviderName)
                            .font(Theme.current.fontXSMedium)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(inputBackground)
                    )
                }
                .menuStyle(.borderlessButton)

                // Model picker
                Menu {
                    ForEach(availableModels, id: \.id) { model in
                        Button(action: {
                            manager.llmModelId = model.id
                        }) {
                            HStack {
                                Text(model.displayName)
                                if manager.llmModelId == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(manager.llmModelId ?? "Select")
                            .font(Theme.current.fontXSMedium)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(inputBackground)
                    )
                }
                .menuStyle(.borderlessButton)

                Spacer()

                // Temperature slider (compact)
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9))
                        .foregroundColor(textMuted)
                    Text(String(format: "%.1f", manager.llmTemperature))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                        .frame(width: 24)
                    Slider(value: $manager.llmTemperature, in: 0...1, step: 0.1)
                        .frame(width: 60)
                }
            }

            // Row 2: System prompt (view-only, for transparency)
            DisclosureGroup {
                Text(manager.systemPrompt)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(inputBackground)
                    )
            } label: {
                Text("SYSTEM PROMPT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(textMuted)
            }
            .font(Theme.current.fontXS)
            .foregroundColor(textMuted)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private var currentProviderName: String {
        if let id = manager.llmProviderId,
           let provider = LLMProviderRegistry.shared.provider(for: id) {
            return provider.name
        }
        return "Provider"
    }

    private var availableModels: [LLMModel] {
        guard let providerId = manager.llmProviderId else { return [] }
        return LLMProviderRegistry.shared.allModels.filter { $0.provider == providerId }
    }

    // MARK: - Content Area

    // Dictation pill state (floating overlay)
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Text editor with floating dictation pill
            ZStack(alignment: .bottom) {
                TextEditor(text: $manager.editedText)
                    .font(Theme.current.contentFontBody)
                    .foregroundColor(textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.md)
                    .padding(.bottom, 40) // Space for floating pill
                    .focused($isTextFieldFocused)
                    .frame(maxHeight: .infinity)

                // Floating dictation pill (centered at bottom of text area)
                // Uses sliver/expand pattern like TalkieLive - no external opacity/scale needed
                DictationPill(
                    state: $dictationPillState,
                    duration: $dictationDuration,
                    onTap: handleDictationPillTap
                )
                .padding(.bottom, Spacing.sm)
            }

            // Subtle separator
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            // Voice Prompt + Quick Actions (no more DICTATE button here)
            voicePromptArea
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    // No more oscillating opacity/scale - pill handles its own hover state now

    // MARK: - Dictation Pill Actions

    private func handleDictationPillTap() {
        switch dictationPillState {
        case .idle:
            startDictationRecording()
        case .recording:
            stopDictationRecording()
        case .transcribing, .success:
            // Ignore taps during these states
            break
        }
    }

    private func startDictationRecording() {
        do {
            try EphemeralTranscriber.shared.startCapture()
            dictationPillState = .recording
            dictationDuration = 0

            // Start timer
            dictationTimerRef = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    dictationDuration += 0.1
                }
            }
        } catch {
            // Show error briefly
            manager.polishError = error.localizedDescription
        }
    }

    private func stopDictationRecording() {
        dictationTimerRef?.cancel()
        dictationTimerRef = nil

        dictationPillState = .transcribing

        Task {
            do {
                let transcribedText = try await EphemeralTranscriber.shared.stopAndTranscribe()

                // Append to edited text with smart spacing
                if !transcribedText.isEmpty {
                    let needsSpace = !manager.editedText.isEmpty &&
                                     !manager.editedText.hasSuffix(" ") &&
                                     !manager.editedText.hasSuffix("\n")
                    if needsSpace {
                        manager.editedText += " "
                    }
                    manager.editedText += transcribedText
                }

                // Show success briefly
                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle

            } catch {
                // On error, show it and return to idle
                manager.polishError = error.localizedDescription
                dictationPillState = .idle
            }
        }
    }

    // MARK: - Voice Prompt Area (Voice Prompt + Quick Actions)
    // Dictation is now the floating pill on the text area

    private var voicePromptArea: some View {
        VStack(spacing: Spacing.sm) {
            // Row: Voice Prompt + Quick actions
            HStack(spacing: Spacing.sm) {
                // VOICE PROMPT button (talks to LLM)
                voicePromptButton

                Spacer()

                // Quick action chips
                ForEach(SmartAction.builtIn.prefix(2)) { action in
                    quickActionChip(action)
                }

                // More actions
                Button(action: { showMoreActions.toggle() }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textMuted)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(inputBackground)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showMoreActions) {
                    actionsGrid
                }
            }

            // Show transcribed voice instruction (if any)
            if let voiceInstruction = manager.voiceInstruction {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text(voiceInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { manager.voiceInstruction = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Expanded prompt editor
            if let actionId = expandedActionId {
                promptEditorView(actionId: actionId)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.sm)
        .animation(.easeOut(duration: 0.15), value: expandedActionId)
        .animation(.easeOut(duration: 0.15), value: manager.voiceInstruction)
    }

    // MARK: - Instruction Area

    @State private var showMoreActions = false

    private var instructionArea: some View {
        VStack(spacing: Spacing.sm) {
            // Row 1: Voice Prompt (main CTA) + Quick action chips
            HStack(spacing: Spacing.sm) {
                // Main CTA: Voice Prompt - prominent, colorful
                voicePromptButton

                // Quick action chips (2-3 visible)
                ForEach(SmartAction.builtIn.prefix(3)) { action in
                    quickActionChip(action)
                }

                // More actions button
                Button(action: { showMoreActions.toggle() }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(inputBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("More actions")
                .popover(isPresented: $showMoreActions) {
                    actionsGrid
                }

                Spacer()
            }

            // Show transcribed voice instruction (if any)
            if let voiceInstruction = manager.voiceInstruction {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text(voiceInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { manager.voiceInstruction = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Expanded prompt editor (if any action is expanded)
            if let actionId = expandedActionId {
                promptEditorView(actionId: actionId)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.sm)
        .animation(.easeOut(duration: 0.15), value: expandedActionId)
        .animation(.easeOut(duration: 0.15), value: manager.voiceInstruction)
    }

    // MARK: - Quick Action Chip

    private func quickActionChip(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await manager.polishText(instruction: action.defaultPrompt) }
        }) {
            HStack(spacing: 3) {
                Image(systemName: action.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(action.name)
                    .font(Theme.current.fontXS)
            }
            .foregroundColor(textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(inputBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(manager.isPolishing)
        .help(action.name)
    }

    // MARK: - Actions Grid (popover)

    private var actionsGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Search field (placeholder for now)
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
                TextField("Search actions...", text: .constant(""))
                    .textFieldStyle(.plain)
                    .font(Theme.current.fontSM)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(inputBackground)
            )

            // Grid of actions
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                ForEach(SmartAction.builtIn) { action in
                    Button(action: {
                        showMoreActions = false
                        Task { await manager.polishText(instruction: action.defaultPrompt) }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: action.icon)
                                .font(.system(size: 16))
                            Text(action.name)
                                .font(Theme.current.fontXS)
                                .lineLimit(1)
                        }
                        .foregroundColor(textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Customize action
            Button(action: {
                showMoreActions = false
                // Show first action's prompt for editing
                if let first = SmartAction.builtIn.first {
                    expandedActionId = first.id
                    editablePrompt = first.defaultPrompt
                }
            }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Customize prompt...")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .frame(width: 220)
    }

    // MARK: - Voice Prompt Button (talk to AI/LLM)

    @State private var isPulsing = false

    // Clean accent-based styling (no purple gradient)
    private var voicePromptColor: Color { accentColor }

    private var voicePromptButton: some View {
        Button(action: {
            if manager.isRecordingInstruction {
                Task { await manager.stopVoiceInstruction() }
            } else {
                manager.startVoiceInstruction()
            }
        }) {
            HStack(spacing: 6) {
                if manager.isTranscribingInstruction {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                        .tint(.white)
                } else if manager.isRecordingInstruction {
                    // Recording state: stop icon
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    // Idle state: mic with sparkle (voice → AI)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                            .offset(x: 4, y: -2)
                    }
                }

                // Label: "VOICE PROMPT" when idle, "STOP" when recording
                Text(manager.isRecordingInstruction ? "STOP" : (manager.isTranscribingInstruction ? "Processing..." : "VOICE PROMPT"))
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(manager.isRecordingInstruction ? SemanticColor.error : voicePromptColor)
            )
            .shadow(color: (manager.isRecordingInstruction ? SemanticColor.error : voicePromptColor).opacity(0.25), radius: 6, y: 2)
            // Pulsing ring when recording
            .overlay(
                Capsule()
                    .stroke(SemanticColor.error.opacity(isPulsing ? 0.6 : 0), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .disabled(manager.isTranscribingInstruction || manager.isPolishing)
        .help("Speak to tell the AI what to do with your text")
        .onChange(of: manager.isRecordingInstruction) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }

    // MARK: - Prompt Editor

    private func promptEditorView(actionId: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Editable prompt
            TextEditor(text: $editablePrompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 80)
                .padding(Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(inputBackground)
                )

            // Actions row
            HStack {
                // Reset to default
                if let action = SmartAction.action(id: actionId),
                   editablePrompt != action.defaultPrompt {
                    Button(action: {
                        editablePrompt = action.defaultPrompt
                    }) {
                        Text("Reset")
                            .font(Theme.current.fontXS)
                            .foregroundColor(textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Cancel
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        expandedActionId = nil
                    }
                }) {
                    Text("Cancel")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                // Run with this prompt
                Button(action: {
                    Task {
                        await manager.polishText(instruction: editablePrompt)
                    }
                    withAnimation(.easeOut(duration: 0.1)) {
                        expandedActionId = nil
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("Run")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: Spacing.sm) {
            // Left side: Reset button (if text changed) + status
            HStack(spacing: Spacing.xs) {
                // Reset button - subtle
                if manager.editedText != manager.originalText {
                    Button(action: { manager.resetText() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9, weight: .medium))
                            Text("Reset")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Reset to original")
                }

                // Polishing indicator
                if manager.isPolishing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Polishing...")
                            .font(Theme.current.fontXS)
                            .foregroundColor(textMuted)
                    }
                }

                // Error message
                if let error = manager.polishError {
                    Text(error)
                        .font(Theme.current.fontXS)
                        .foregroundColor(SemanticColor.error)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right side: Quick open apps + Replace Selection + Copy
            HStack(spacing: 4) {
                // Quick open apps
                QuickOpenBar(
                    content: manager.editedText,
                    showCopyButton: false,
                    compactMode: true
                )

                // Replace Selection button (only when we have selection context)
                if manager.hasSelectionContext {
                    Button(action: { manager.replaceSelectionAndDismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 10, weight: .medium))
                            Text("Replace")
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(Color.cyan)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Replace selection in source app (⌘↩)")
                }

                // Copy (rightmost - primary action)
                Button(action: { manager.copyToClipboard() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(accentColor)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy (⌘C)")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm + 2)
    }
}

// MARK: - Visual Effect View (for blur/vibrancy)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

#Preview {
    InterstitialEditorView(manager: InterstitialManager.shared)
}

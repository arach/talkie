//
//  ScratchPadView.swift
//  Talkie
//
//  Scratch pad for quick text editing with voice dictation and AI-assisted revision
//  Flow: Talkie → TalkieEngine (direct, no TalkieLive)
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct ScratchPadView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var editorState = VoiceEditorState()
    @FocusState private var isTextFieldFocused: Bool

    // Dictation state (uses EphemeralTranscriber → TalkieEngine directly)
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    // Voice prompt state (for LLM instructions)
    @State private var isRecordingInstruction: Bool = false
    @State private var isTranscribingInstruction: Bool = false
    @State private var isPulsing: Bool = false

    // History popover
    @State private var showHistory = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                headerView
                editorCard

                // Only show quick actions when not reviewing
                if !editorState.isReviewing {
                    quickActionsSection
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(Spacing.lg)
        }
        .background(Theme.current.background)
        .onAppear {
            initializeLLMSettings()
            setupDraftExtensionServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            // Keep server running for background connections
            // DraftExtensionServer.shared.stop()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("DRAFTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("Quick Edit")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.current.foreground)

                if !editorState.text.isEmpty {
                    Text("\(editorState.text.split(separator: " ").count) words")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Text("Type or dictate text, then use AI to polish and transform it")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Editor Card

    private var editorCard: some View {
        VStack(spacing: 0) {
            // Header bar (always visible)
            modelSelectorBar

            Divider()
                .background(Theme.current.divider)

            // Content area: editing or reviewing
            Group {
                switch editorState.mode {
                case .editing:
                    editingContent
                case .reviewing:
                    if let diff = editorState.currentDiff {
                        reviewingContent(diff: diff)
                    } else {
                        editingContent
                    }
                }
            }

            Divider()
                .background(Theme.current.divider)

            // Action bar (always visible, with voice prompt)
            actionBar
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Editing Content (normal text editor)

    private var editingContent: some View {
        ZStack(alignment: .bottom) {
            TextEditor(text: $editorState.text)
                .font(Theme.current.contentFontBody)
                .foregroundColor(Theme.current.foreground)
                .scrollContentBackground(.hidden)
                .padding(Spacing.md)
                .padding(.bottom, 50)
                .focused($isTextFieldFocused)
                .frame(minHeight: 200, maxHeight: 400)

            // Floating dictation pill
            DictationPill(
                state: $dictationPillState,
                duration: $dictationDuration,
                onTap: handleDictationPillTap
            )
            .padding(.bottom, Spacing.sm)
        }
    }

    // MARK: - Reviewing Content (side-by-side diff overlay)

    private func reviewingContent(diff: TextDiff) -> some View {
        VStack(spacing: 0) {
            // Side-by-side diff panes
            HStack(spacing: 0) {
                // Original (left)
                diffPane(
                    title: "ORIGINAL",
                    indicatorColor: SemanticColor.error,
                    content: diff.attributedOriginal(
                        baseColor: Theme.current.foreground,
                        deleteColor: SemanticColor.error
                    )
                )

                // Divider
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(width: 1)

                // Proposed (right)
                diffPane(
                    title: "PROPOSED",
                    indicatorColor: SemanticColor.success,
                    content: diff.attributedProposed(
                        baseColor: Theme.current.foreground,
                        insertColor: SemanticColor.success
                    )
                )
            }
            .frame(minHeight: 200, maxHeight: 400)

            // Voice instruction feedback (what you said)
            if let voiceInstruction = editorState.currentInstruction {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(settings.resolvedAccentColor)

                    Text("You said:")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(voiceInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(settings.resolvedAccentColor.opacity(0.1))
            }

            // Accept/Reject buttons
            HStack(spacing: Spacing.md) {
                // Change count
                Text("\(diff.changeCount) change\(diff.changeCount == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                // Reject
                Button(action: { editorState.rejectRevision() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("REJECT")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(SemanticColor.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .stroke(SemanticColor.error, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                // Accept
                Button(action: { editorState.acceptRevision() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("ACCEPT")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(SemanticColor.success)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func diffPane(title: String, indicatorColor: Color, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pane header
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(Theme.current.backgroundSecondary)

            // Pane content
            ScrollView {
                Text(content)
                    .font(Theme.current.contentFontBody)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Model Selector Bar

    private var modelSelectorBar: some View {
        HStack(spacing: Spacing.sm) {
            modelPicker

            Spacer()

            if editorState.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("REVISING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.current.surface2))
            }

            // History button (only show if there's history)
            if !editorState.revisions.isEmpty {
                historyButton
            }

            if !editorState.text.isEmpty && !editorState.isReviewing {
                Button(action: { editorState.text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Clear text")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - History Button & Popover

    private var historyButton: some View {
        Button(action: { showHistory.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                Text("\(editorState.revisions.count)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Theme.current.foregroundMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Theme.current.surface2)
                    .overlay(
                        Capsule()
                            .stroke(showHistory ? settings.resolvedAccentColor : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Edit history (\(editorState.revisions.count) edits)")
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
                    .foregroundColor(Theme.current.foregroundMuted)
                Spacer()
                Text("\(editorState.revisions.count) edits")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            // Timeline or Preview
            if let previewing = editorState.previewingRevision {
                revisionPreview(previewing)
            } else {
                // Timeline list
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(editorState.revisions.reversed()) { revision in
                            historyRow(revision)
                        }
                    }
                    .padding(Spacing.sm)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 320)
        .background(Theme.current.background)
    }

    private func historyRow(_ revision: Revision) -> some View {
        Button(action: {
            editorState.previewRevision(revision)
        }) {
            HStack(spacing: Spacing.sm) {
                // Timeline dot
                Circle()
                    .fill(settings.resolvedAccentColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(revision.shortInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(revision.changeCount) changes")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("•")
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text(revision.timeAgo)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                Spacer()

                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
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

    private func revisionPreview(_ revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Back button + title
            HStack {
                Button(action: { editorState.dismissPreview() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(settings.resolvedAccentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(revision.timeAgo)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            // Instruction
            Text(revision.instruction)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .padding(.horizontal, Spacing.md)

            // Text preview
            ScrollView {
                Text(revision.textAfter)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Theme.current.surface2)
            )
            .padding(.horizontal, Spacing.md)

            // Actions
            HStack(spacing: Spacing.sm) {
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
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Theme.current.surface2)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    editorState.restoreFromRevision(revision)
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
                            .fill(settings.resolvedAccentColor)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }

    private func filteredModels(for providerId: String) -> [LLMModel] {
        LLMProviderRegistry.shared.recommendedModels(for: providerId)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                let models = filteredModels(for: provider.id)
                if !models.isEmpty {
                    Menu(provider.name) {
                        ForEach(models, id: \.id) { model in
                            Button(action: {
                                editorState.providerId = provider.id
                                editorState.modelId = model.id
                            }) {
                                HStack {
                                    Text(model.displayName)
                                    if editorState.modelId == model.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                providerIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(providerColor)

                Text(displayModelName)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Theme.current.surface2)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var providerIcon: Image {
        guard let providerId = editorState.providerId else {
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
        guard let providerId = editorState.providerId else { return Theme.current.foregroundMuted }
        switch providerId {
        case "openai": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "google", "gemini": return Color(red: 0.3, green: 0.5, blue: 0.9)
        case "groq": return Color(red: 0.9, green: 0.4, blue: 0.3)
        case "mlx": return Color(red: 0.6, green: 0.4, blue: 0.8)
        default: return Theme.current.foregroundMuted
        }
    }

    private var displayModelName: String {
        if let model = editorState.modelId {
            return model
                .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
                .replacingOccurrences(of: "gpt-4o", with: "4o")
                .replacingOccurrences(of: "claude-3-5-sonnet", with: "sonnet")
                .replacingOccurrences(of: "claude-3-haiku", with: "haiku")
                .replacingOccurrences(of: "gemini-1.5-flash", with: "flash")
        }
        return "Select model"
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            voicePromptButton

            // Selection hint - shows when text is selected
            if editorState.isTransformingSelection {
                Text("Selection")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .stroke(Theme.current.foregroundMuted.opacity(0.3), lineWidth: 1)
                    )
                    .help("Commands will apply to selected text only")
            }

            ForEach(SmartAction.builtIn.prefix(3)) { action in
                quickActionChip(action)
            }

            Spacer()

            if let error = editorState.error {
                Text(error)
                    .font(Theme.current.fontXS)
                    .foregroundColor(SemanticColor.error)
                    .lineLimit(1)
            }

            // Save to Memo button
            Button(action: saveToMemo) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(editorState.text.isEmpty ? Theme.current.foregroundMuted : Theme.current.foreground)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(Theme.current.surface2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Save as Memo")

            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(editorState.text.isEmpty ? Theme.current.foregroundMuted : settings.resolvedAccentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var voicePromptButton: some View {
        Button(action: toggleVoicePrompt) {
            HStack(spacing: 6) {
                if isTranscribingInstruction {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                        .tint(.white)
                } else if isRecordingInstruction {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                            .offset(x: 4, y: -2)
                    }
                }

                Text(isRecordingInstruction ? "STOP" : "COMMAND")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isRecordingInstruction ? SemanticColor.error : settings.resolvedAccentColor)
            )
            .overlay(
                Capsule()
                    .stroke(SemanticColor.error.opacity(isPulsing ? 0.6 : 0), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .disabled(editorState.isProcessing || editorState.text.isEmpty)
        .help("Speak to tell AI what to do with your text")
        .onChange(of: isRecordingInstruction) { _, isRecording in
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

    private func quickActionChip(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
        }) {
            HStack(spacing: 3) {
                Image(systemName: action.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(action.name)
                    .font(Theme.current.fontXS)
            }
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(Theme.current.surface2)
            )
        }
        .buttonStyle(.plain)
        .disabled(editorState.isProcessing || editorState.text.isEmpty)
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.current.foregroundMuted)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                ForEach(SmartAction.builtIn) { action in
                    actionCard(action)
                }
            }
        }
    }

    private func actionCard(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
        }) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(settings.resolvedAccentColor)

                Text(action.name)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(editorState.isProcessing || editorState.text.isEmpty)
    }

    // MARK: - Actions

    private func initializeLLMSettings() {
        Task { @MainActor in
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                editorState.providerId = resolved.provider.id
                editorState.modelId = resolved.modelId
            }
        }
    }

    /// Start the Draft Extension API server and wire up command handlers
    private func setupDraftExtensionServer() {
        let server = DraftExtensionServer.shared

        // Start the WebSocket server
        server.start()

        // Handle incoming commands from connected renderers
        server.onUpdate = { [weak editorState] content in
            editorState?.text = content
        }

        server.onRefine = { [weak editorState] instruction, constraints in
            guard let state = editorState else { return }

            // If constraints provided, modify system prompt temporarily
            if let constraints = constraints {
                var modifiedPrompt = state.systemPrompt
                if let maxLength = constraints.maxLength {
                    modifiedPrompt += "\n\nIMPORTANT: Keep your response under \(maxLength) characters."
                }
                if let style = constraints.style {
                    modifiedPrompt += "\n\nStyle: \(style)"
                }
                if let format = constraints.format {
                    modifiedPrompt += "\n\nFormat: \(format)"
                }
                let originalPrompt = state.systemPrompt
                state.systemPrompt = modifiedPrompt
                await state.requestRevision(instruction: instruction)
                state.systemPrompt = originalPrompt
            } else {
                await state.requestRevision(instruction: instruction)
            }
        }

        server.onAccept = { [weak editorState] in
            editorState?.acceptRevision()
        }

        server.onReject = { [weak editorState] in
            editorState?.rejectRevision()
        }

        server.onSave = { [weak editorState] destination in
            guard let state = editorState else { return }
            if destination == "clipboard" {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.text, forType: .string)
                log.info("Draft copied to clipboard via extension API")
            } else if destination == "memo" {
                // TODO: Implement save to memo
                log.info("Save to memo requested via extension API")
            }
        }

        // Voice capture via Talkie's audio pipeline
        server.onCaptureStart = {
            do {
                try EphemeralTranscriber.shared.startCapture()
                log.info("Started voice capture via extension API")
            } catch {
                log.error("Failed to start capture via extension API: \(error)")
            }
        }

        server.onCaptureStop = {
            do {
                let text = try await EphemeralTranscriber.shared.stopAndTranscribe()
                log.info("Captured via extension API: \(text.prefix(50))...")
                return text
            } catch {
                log.error("Failed to transcribe via extension API: \(error)")
                return nil
            }
        }

        log.info("Draft Extension API server configured on port 7847")
    }

    // MARK: - Dictation (Talkie → Engine via EphemeralTranscriber)

    private func handleDictationPillTap() {
        switch dictationPillState {
        case .idle:
            startDictationRecording()
        case .recording:
            stopDictationRecording()
        case .transcribing, .success:
            break
        }
    }

    private func startDictationRecording() {
        do {
            try EphemeralTranscriber.shared.startCapture()
            dictationPillState = .recording
            dictationDuration = 0

            dictationTimerRef = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    dictationDuration += 0.1
                }
            }
        } catch {
            log.error("Dictation start failed: \(error)")
            editorState.error = error.localizedDescription
        }
    }

    private func stopDictationRecording() {
        dictationTimerRef?.cancel()
        dictationTimerRef = nil
        dictationPillState = .transcribing

        Task {
            do {
                let transcribedText = try await EphemeralTranscriber.shared.stopAndTranscribe()

                if !transcribedText.isEmpty {
                    let needsSpace = !editorState.text.isEmpty && !editorState.text.hasSuffix(" ") && !editorState.text.hasSuffix("\n")
                    if needsSpace {
                        editorState.text += " "
                    }
                    editorState.text += transcribedText
                }

                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle
            } catch {
                log.error("Dictation transcribe failed: \(error)")
                editorState.error = error.localizedDescription
                dictationPillState = .idle
            }
        }
    }

    // MARK: - Voice Prompt (for LLM instructions)

    private func toggleVoicePrompt() {
        if isRecordingInstruction {
            Task { await stopVoicePrompt() }
        } else {
            startVoicePrompt()
        }
    }

    private func startVoicePrompt() {
        guard !isRecordingInstruction else { return }

        do {
            try EphemeralTranscriber.shared.startCapture()
            isRecordingInstruction = true
        } catch {
            log.error("Voice prompt capture failed: \(error)")
            editorState.error = error.localizedDescription
        }
    }

    private func stopVoicePrompt() async {
        guard isRecordingInstruction else { return }

        isRecordingInstruction = false
        isTranscribingInstruction = true

        do {
            let instruction = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribingInstruction = false

            if !instruction.isEmpty {
                await editorState.requestRevision(instruction: instruction)
            }
        } catch {
            log.error("Voice prompt transcribe failed: \(error)")
            isTranscribingInstruction = false
            editorState.error = error.localizedDescription
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editorState.text, forType: .string)
    }

    private func saveToMemo() {
        guard !editorState.text.isEmpty else { return }

        Task {
            // Create a new memo from the scratch pad text
            let memo = MemoModel(
                id: UUID(),
                createdAt: Date(),
                lastModified: Date(),
                title: extractTitle(from: editorState.text),
                duration: 0,  // No audio
                sortOrder: 0,
                transcription: editorState.text,
                notes: nil,
                summary: nil,
                tasks: nil,
                reminders: nil,
                audioFilePath: nil,
                waveformData: nil,
                isTranscribing: false,
                isProcessingSummary: false,
                isProcessingTasks: false,
                isProcessingReminders: false,
                autoProcessed: false,
                originDeviceId: "scratch-pad",
                macReceivedAt: Date(),
                cloudSyncedAt: nil,
                pendingWorkflowIds: nil
            )

            do {
                let repository = LocalRepository()
                try await repository.saveMemo(memo)

                // Clear scratch pad after successful save
                await MainActor.run {
                    editorState.text = ""
                    editorState.clearHistory()
                }
            } catch {
                log.error("Memo save failed: \(error)")
                await MainActor.run {
                    editorState.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Extract a title from the first line or first few words
    private func extractTitle(from text: String) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(8).joined(separator: " ")
        if words.count > 50 {
            return String(words.prefix(47)) + "..."
        }
        return words
    }
}

#Preview {
    ScratchPadView()
        .frame(width: 800, height: 600)
}

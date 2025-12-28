//
//  ScratchPadView.swift
//  Talkie
//
//  Scratch pad for quick text editing with voice dictation and AI polish
//  Flow: Talkie → TalkieEngine (direct, no TalkieLive)
//

import SwiftUI

struct ScratchPadView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var polishState = TextPolishState()
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
                if !polishState.isReviewing {
                    quickActionsSection
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(Spacing.lg)
        }
        .background(Theme.current.background)
        .onAppear {
            initializeLLMSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("SCRATCH PAD")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("Quick Edit")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.current.foreground)

                if !polishState.text.isEmpty {
                    Text("\(polishState.text.split(separator: " ").count) words")
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
                switch polishState.viewState {
                case .editing:
                    editingContent
                case .reviewing:
                    if let diff = polishState.currentDiff {
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
            TextEditor(text: $polishState.text)
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
            if let voiceInstruction = polishState.voiceInstruction {
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
                Button(action: { polishState.rejectChanges() }) {
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
                Button(action: { polishState.acceptChanges() }) {
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

            if polishState.isPolishing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("POLISHING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.current.surface2))
            }

            // History button (only show if there's history)
            if !polishState.editHistory.isEmpty {
                historyButton
            }

            if !polishState.text.isEmpty && !polishState.isReviewing {
                Button(action: { polishState.text = "" }) {
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
                Text("\(polishState.editHistory.count)")
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
        .help("Edit history (\(polishState.editHistory.count) edits)")
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
                Text("\(polishState.editHistory.count) edits")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            // Timeline or Preview
            if let previewing = polishState.previewingSnapshot {
                snapshotPreview(previewing)
            } else {
                // Timeline list
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(polishState.editHistory.reversed()) { snapshot in
                            historyRow(snapshot)
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

    private func historyRow(_ snapshot: EditSnapshot) -> some View {
        Button(action: {
            polishState.previewSnapshot(snapshot)
        }) {
            HStack(spacing: Spacing.sm) {
                // Timeline dot
                Circle()
                    .fill(settings.resolvedAccentColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.shortInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(snapshot.changeCount) changes")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("•")
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text(snapshot.timeAgo)
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

    private func snapshotPreview(_ snapshot: EditSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Back button + title
            HStack {
                Button(action: { polishState.dismissPreview() }) {
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

                Text(snapshot.timeAgo)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            // Instruction
            Text(snapshot.instruction)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .padding(.horizontal, Spacing.md)

            // Text preview
            ScrollView {
                Text(snapshot.textAfter)
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
                    NSPasteboard.general.setString(snapshot.textAfter, forType: .string)
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
                    polishState.restoreFromSnapshot(snapshot)
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

    private var modelPicker: some View {
        Menu {
            ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                Menu(provider.name) {
                    ForEach(LLMProviderRegistry.shared.allModels.filter { $0.provider == provider.id }, id: \.id) { model in
                        Button(action: {
                            polishState.providerId = provider.id
                            polishState.modelId = model.id
                        }) {
                            HStack {
                                Text(model.displayName)
                                if polishState.modelId == model.id {
                                    Image(systemName: "checkmark")
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
        guard let providerId = polishState.providerId else {
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
        guard let providerId = polishState.providerId else { return Theme.current.foregroundMuted }
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
        if let model = polishState.modelId {
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

            ForEach(SmartAction.builtIn.prefix(3)) { action in
                quickActionChip(action)
            }

            Spacer()

            if let error = polishState.polishError {
                Text(error)
                    .font(Theme.current.fontXS)
                    .foregroundColor(SemanticColor.error)
                    .lineLimit(1)
            }

            // Save to Memo button
            Button(action: saveToMemo) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(polishState.text.isEmpty ? Theme.current.foregroundMuted : Theme.current.foreground)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(Theme.current.surface2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(polishState.text.isEmpty)
            .help("Save as Memo")

            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(polishState.text.isEmpty ? Theme.current.foregroundMuted : settings.resolvedAccentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(polishState.text.isEmpty)
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

                Text(isRecordingInstruction ? "STOP" : "VOICE")
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
        .disabled(polishState.isPolishing || polishState.text.isEmpty)
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
            Task { await polishState.polish(instruction: action.defaultPrompt) }
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
        .disabled(polishState.isPolishing || polishState.text.isEmpty)
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
            Task { await polishState.polish(instruction: action.defaultPrompt) }
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
        .disabled(polishState.isPolishing || polishState.text.isEmpty)
    }

    // MARK: - Actions

    private func initializeLLMSettings() {
        Task { @MainActor in
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                polishState.providerId = resolved.provider.id
                polishState.modelId = resolved.modelId
            }
        }
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
            polishState.polishError = error.localizedDescription
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
                    let needsSpace = !polishState.text.isEmpty && !polishState.text.hasSuffix(" ") && !polishState.text.hasSuffix("\n")
                    if needsSpace {
                        polishState.text += " "
                    }
                    polishState.text += transcribedText
                }

                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle
            } catch {
                polishState.polishError = error.localizedDescription
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
            polishState.polishError = error.localizedDescription
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
                await polishState.polish(instruction: instruction)
            }
        } catch {
            isTranscribingInstruction = false
            polishState.polishError = error.localizedDescription
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(polishState.text, forType: .string)
    }

    private func saveToMemo() {
        guard !polishState.text.isEmpty else { return }

        Task {
            // Create a new memo from the scratch pad text
            let memo = MemoModel(
                id: UUID(),
                createdAt: Date(),
                lastModified: Date(),
                title: extractTitle(from: polishState.text),
                duration: 0,  // No audio
                sortOrder: 0,
                transcription: polishState.text,
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
                let repository = GRDBRepository()
                try await repository.saveMemo(memo)

                // Clear scratch pad after successful save
                await MainActor.run {
                    polishState.text = ""
                    polishState.clearHistory()
                }
            } catch {
                await MainActor.run {
                    polishState.polishError = "Failed to save: \(error.localizedDescription)"
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

//
//  ScratchPadView.swift
//  Talkie
//
//  Embedded scratch pad for quick text editing with AI polish
//  Adapted from InterstitialEditorView for use in the main navigation
//

import SwiftUI

struct ScratchPadView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var text: String = ""
    @State private var isPolishing: Bool = false
    @State private var polishError: String?
    @FocusState private var isTextFieldFocused: Bool

    // LLM settings
    @State private var showLLMSettings: Bool = false
    @State private var llmProviderId: String?
    @State private var llmModelId: String?
    @State private var llmTemperature: Double = 0.3

    // Dictation state
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    // Voice prompt state
    @State private var isRecordingInstruction: Bool = false
    @State private var isTranscribingInstruction: Bool = false
    @State private var isPulsing: Bool = false

    private var isDark: Bool { settings.isDarkMode }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                headerView

                // Main editor card
                editorCard

                // Quick actions
                quickActionsSection

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
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("Quick Edit")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.current.foreground)

                if !text.isEmpty {
                    Text("\(text.split(separator: " ").count) words")
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
            // Model selector bar
            modelSelectorBar

            Divider()
                .background(Theme.current.divider)

            // Text editor with dictation pill
            ZStack(alignment: .bottom) {
                TextEditor(text: $text)
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

            Divider()
                .background(Theme.current.divider)

            // Action bar
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

    // MARK: - Model Selector Bar

    private var modelSelectorBar: some View {
        HStack(spacing: Spacing.sm) {
            // Provider/Model picker
            modelPicker

            Spacer()

            // Status
            if isPolishing {
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

            // Clear button
            if !text.isEmpty {
                Button(action: { text = "" }) {
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

    private var modelPicker: some View {
        Menu {
            ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                Menu(provider.name) {
                    ForEach(LLMProviderRegistry.shared.allModels.filter { $0.provider == provider.id }, id: \.id) { model in
                        Button(action: {
                            llmProviderId = provider.id
                            llmModelId = model.id
                        }) {
                            HStack {
                                Text(model.displayName)
                                if llmModelId == model.id {
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
        guard let providerId = llmProviderId else {
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
        guard let providerId = llmProviderId else { return Theme.current.foregroundMuted }
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
        if let model = llmModelId {
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
            // Voice prompt button
            voicePromptButton

            // Quick polish actions
            ForEach(SmartAction.builtIn.prefix(3)) { action in
                quickActionChip(action)
            }

            Spacer()

            // Error message
            if let error = polishError {
                Text(error)
                    .font(Theme.current.fontXS)
                    .foregroundColor(SemanticColor.error)
                    .lineLimit(1)
            }

            // Copy button
            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(text.isEmpty ? Theme.current.foregroundMuted : settings.resolvedAccentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
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
        .disabled(isPolishing || text.isEmpty)
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
            Task { await polishText(instruction: action.defaultPrompt) }
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
        .disabled(isPolishing || text.isEmpty)
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(Tracking.wide)
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
            Task { await polishText(instruction: action.defaultPrompt) }
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
        .disabled(isPolishing || text.isEmpty)
    }

    // MARK: - Actions

    private func initializeLLMSettings() {
        Task { @MainActor in
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                llmProviderId = resolved.provider.id
                llmModelId = resolved.modelId
            }
        }
    }

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
            polishError = error.localizedDescription
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
                    let needsSpace = !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n")
                    if needsSpace {
                        text += " "
                    }
                    text += transcribedText
                }

                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle
            } catch {
                polishError = error.localizedDescription
                dictationPillState = .idle
            }
        }
    }

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
            polishError = error.localizedDescription
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
                await polishText(instruction: instruction)
            }
        } catch {
            isTranscribingInstruction = false
            polishError = error.localizedDescription
        }
    }

    private func polishText(instruction: String) async {
        guard !isPolishing, !text.isEmpty else { return }

        isPolishing = true
        polishError = nil

        do {
            let registry = LLMProviderRegistry.shared

            let resolved: (provider: LLMProvider, modelId: String)
            if let providerId = llmProviderId,
               let provider = registry.provider(for: providerId),
               let modelId = llmModelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
            } else {
                polishError = "No LLM provider configured"
                isPolishing = false
                return
            }

            let systemPrompt = """
                You are helping edit transcribed speech. Apply the user's instruction to transform the text.
                Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
                """

            let prompt = """
                \(systemPrompt)

                Instruction: \(instruction)

                Text:
                \(text)
                """

            let options = GenerationOptions(
                temperature: llmTemperature,
                maxTokens: 2048
            )

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            text = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            polishError = error.localizedDescription
        }

        isPolishing = false
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    ScratchPadView()
        .frame(width: 800, height: 600)
}

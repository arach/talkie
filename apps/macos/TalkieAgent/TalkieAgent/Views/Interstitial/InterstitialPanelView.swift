//
//  InterstitialPanelView.swift
//  TalkieAgent
//
//  SwiftUI view for the floating interstitial editor panel
//

import SwiftUI
import TalkieKit

struct InterstitialPanelView: View {
    @Bindable var state: InterstitialState
    let onDismiss: () -> Void
    let onCopy: () -> Void
    let onReplaceSelection: () -> Void

    @FocusState private var isTextFieldFocused: Bool
    @State private var showMoreActions = false
    @State private var showHistory = false
    @State private var isPulsing = false
    @State private var selectedRange: NSRange?
    @State private var isHoveringCopyButton = false

    // MARK: - Theme Colors

    private var isDark: Bool {
        // Check system appearance
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

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

    private var accentColor: Color { .blue }

    var body: some View {
        Group {
            switch state.viewState {
            case .editing:
                editingView
            case .reviewing:
                reviewingView
            }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 900,
               minHeight: 340, idealHeight: 400, maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(panelBackground)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .confirmationDialog(
            "What would you like to do?",
            isPresented: $state.showDismissConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                onDismiss()
            }
            Button("Don't Ask Again", role: .destructive) {
                InterstitialPanelController.shared.dontAskAgainAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 0) {
            headerBar
            contentArea
            footerBar
        }
    }

    // MARK: - Reviewing View (Diff)

    private var reviewingView: some View {
        Group {
            if let diff = state.currentDiff {
                InterstitialDiffView(
                    diff: diff,
                    onAccept: { state.acceptRevision() },
                    onReject: { state.rejectRevision() }
                )
            } else {
                editingView
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Status indicator when polishing
            if state.isPolishing {
                HStack(spacing: 4) {
                    BrailleSpinner(size: 10)
                    Text("REVISING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(inputBackground))
            }

            Spacer()

            if !state.revisions.isEmpty {
                historyButton
            }

            Button {
                InterstitialPanelController.shared.requestDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(inputBackground))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Model Indicator

    private var modelIndicator: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) {
                state.showLLMSettings.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                providerIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(providerColor)

                Text(displayModelName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)

                Image(systemName: state.showLLMSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(state.showLLMSettings ? accentColor : borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Model: \(state.llmModelId ?? "None") - Click to configure")
    }

    private var providerIcon: Image {
        guard let providerId = state.llmProviderId else {
            return Image(systemName: "cpu")
        }
        switch providerId {
        case "openai": return Image(systemName: "sparkle")
        case "anthropic": return Image(systemName: "brain")
        case "google", "gemini": return Image(systemName: "diamond")
        case "groq": return Image(systemName: "bolt")
        default: return Image(systemName: "cpu")
        }
    }

    private var providerColor: Color {
        guard let providerId = state.llmProviderId else { return textMuted }
        switch providerId {
        case "openai": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "google", "gemini": return Color(red: 0.3, green: 0.5, blue: 0.9)
        case "groq": return Color(red: 0.9, green: 0.4, blue: 0.3)
        default: return textMuted
        }
    }

    private var displayModelName: String {
        if let model = state.llmModelId {
            return model
                .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
                .replacingOccurrences(of: "gpt-4o", with: "4o")
                .replacingOccurrences(of: "claude-3-5-sonnet", with: "sonnet")
                .replacingOccurrences(of: "claude-3-haiku", with: "haiku")
                .replacingOccurrences(of: "gemini-1.5-flash", with: "flash")
                .replacingOccurrences(of: "llama-3.3-70b-versatile", with: "llama-70b")
        }
        return "Select model"
    }

    // MARK: - History Button

    private var historyButton: some View {
        Button { showHistory.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                Text("\(state.revisions.count)")
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
        .help("Edit history (\(state.revisions.count) edits)")
        .popover(isPresented: $showHistory) {
            historyPopover
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EDIT HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                Spacer()
                Text("\(state.revisions.count) edits")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.revisions.reversed()) { revision in
                        historyRow(revision)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 320)
        .background(panelBackground)
    }

    private func historyRow(_ revision: InterstitialRevision) -> some View {
        Button {
            state.previewRevision(revision)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(revision.shortInstruction)
                        .font(.system(size: 12))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(revision.changeCount) changes")
                            .font(.system(size: 10))
                            .foregroundColor(textMuted)
                        Text("•")
                            .foregroundColor(textMuted)
                        Text(revision.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(textMuted)
                    }
                }

                Spacer()

                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - LLM Settings Panel

    @ViewBuilder
    private var llmSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                        Button(provider.name) {
                            state.llmProviderId = provider.id
                            state.llmModelId = LLMProviderRegistry.shared.defaultModelId(for: provider.id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentProviderName)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(inputBackground)
                    )
                }
                .menuStyle(.borderlessButton)

                Menu {
                    ForEach(availableModels, id: \.id) { model in
                        Button(model.displayName) {
                            state.llmModelId = model.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.llmModelId ?? "Select")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(inputBackground)
                    )
                }
                .menuStyle(.borderlessButton)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var currentProviderName: String {
        if let id = state.llmProviderId,
           let provider = LLMProviderRegistry.shared.provider(for: id) {
            return provider.name
        }
        return "Provider"
    }

    private var availableModels: [LLMModel] {
        guard let providerId = state.llmProviderId else { return [] }
        return LLMProviderRegistry.shared.recommendedModels(for: providerId)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                TalkieTextEditor(
                    text: $state.editedText,
                    selectedRange: $selectedRange,
                    font: .systemFont(ofSize: 14),
                    textColor: NSColor(textPrimary),
                    insertionPointColor: NSColor(accentColor)
                )
                .padding(12)
                .padding(.bottom, 40)
                .frame(maxHeight: .infinity)

                InterstitialDictationPill(
                    isRecording: state.isRecordingDictation,
                    isTranscribing: state.isTranscribingDictation,
                    audioLevel: state.dictationAudioLevel,
                    onTap: handleDictationTap
                )
                .padding(.bottom, 8)
            }

            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            voicePromptArea
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func handleDictationTap() {
        Task {
            if state.isRecordingDictation {
                await InterstitialPanelController.shared.stopDictation()
            } else if !state.isTranscribingDictation {
                InterstitialPanelController.shared.startDictation()
            }
        }
    }

    // MARK: - Voice Prompt Area

    private var voicePromptArea: some View {
        VStack(spacing: 8) {
            // Top row: Model picker + Voice Prompt (LLM controls together)
            HStack(spacing: 8) {
                modelIndicator

                voicePromptButton

                Spacer()

                // Quick actions inline
                ForEach(SmartAction.builtIn.prefix(2)) { action in
                    quickActionChip(action)
                }

                Button {
                    showMoreActions.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(inputBackground))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showMoreActions) {
                    actionsGrid
                }
            }

            // LLM settings (expandable)
            if state.showLLMSettings {
                llmSettingsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Voice command preview (when captured)
            if let voiceCommand = state.voiceCommand {
                HStack(spacing: 4) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text(voiceCommand)
                        .font(.system(size: 12))
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        state.voiceCommand = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(8)
        .animation(.easeOut(duration: 0.15), value: state.voiceCommand)
        .animation(.easeOut(duration: 0.15), value: state.showLLMSettings)
    }

    private func quickActionChip(_ action: SmartAction) -> some View {
        Button {
            Task { await state.polishText(instruction: action.defaultPrompt) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.name)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(inputBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isPolishing)
        .help(action.name)
    }

    private var actionsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(SmartAction.builtIn) { action in
                    Button {
                        showMoreActions = false
                        Task { await state.polishText(instruction: action.defaultPrompt) }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: action.icon)
                                .font(.system(size: 16))
                            Text(action.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .foregroundColor(textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private var voicePromptButton: some View {
        Button {
            Task {
                if state.isRecordingCommand {
                    await InterstitialPanelController.shared.stopVoiceCommand()
                } else {
                    InterstitialPanelController.shared.startVoiceCommand()
                }
            }
        } label: {
            HStack(spacing: 6) {
                if state.isTranscribingCommand {
                    BrailleSpinner(size: 12)
                        .foregroundColor(.white)
                } else if state.isRecordingCommand {
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

                Text(state.isRecordingCommand ? "STOP" : (state.isTranscribingCommand ? "Processing..." : "VOICE PROMPT"))
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(state.isRecordingCommand ? Color.red : accentColor)
            )
            .shadow(color: (state.isRecordingCommand ? Color.red : accentColor).opacity(0.25), radius: 6, y: 2)
            .overlay(
                Capsule()
                    .stroke(Color.red.opacity(isPulsing ? 0.6 : 0), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isTranscribingCommand || state.isPolishing)
        .help("Speak to tell the AI what to do with your text")
        .onChange(of: state.isRecordingCommand) { _, isRecording in
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

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 8) {
            // Left side: Reset button and status
            HStack(spacing: 8) {
                if state.editedText != state.originalText {
                    Button {
                        state.resetText()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .medium))
                            Text("Reset")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(inputBackground))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to original")
                }

                if let error = state.polishError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(error == "No changes proposed" ? textMuted : .red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right side: Action buttons
            HStack(spacing: 8) {
                // Bounce to main app Notes screen
                Button {
                    InterstitialPanelController.shared.bounceToCompose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .medium))
                        Text("Notes")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(inputBackground))
                }
                .buttonStyle(.plain)
                .disabled(state.editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Open in Talkie Notes")

                if state.hasSelectionContext {
                    Button {
                        onReplaceSelection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 10, weight: .medium))
                            Text("Replace Selection")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.cyan))
                    }
                    .buttonStyle(.plain)
                    .help("Replace selection in source app (⌘↩)")
                }

                // Copy only (keep panel open)
                copyOnlyButton

                // Primary CTA: Copy and Close
                copyAndCloseButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Copy Only Button

    private var copyOnlyButton: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                Text("Copy")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(inputBackground))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help("Copy to clipboard (⇧⌘C)")
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.editedText, forType: .string)

        // Brief visual feedback - could add a toast/checkmark here in the future
    }

    // MARK: - Copy and Close Button

    private var copyAndCloseButton: some View {
        Button {
            InterstitialPanelController.shared.copyAndDismiss()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(isHoveringCopyButton ? "Copy and Close  ⌘↩" : "Copy and Close")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(accentColor)
            )
            .animation(.easeOut(duration: 0.1), value: isHoveringCopyButton)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .onHover { hovering in
            isHoveringCopyButton = hovering
        }
        .help("Copy to clipboard and close (⌘↩)")
    }
}

//
//  ScopeDraftsScreen.swift
//  Talkie macOS
//
//  Cream-phosphor Compose — the place where voice captures get shaped
//  into outputs. Built around the metaphor of an instrument bench:
//  paper editor up top (write/dictate), dark "signal monitor" showing
//  the pipeline stage, and channel-tagged smart actions below.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  AppNavigation branches on theme and renders DraftsScreen() for every
//  other theme.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Scope display fonts
// Mirrors the helper in ScopeHomeView. Cormorant Garamond is the
// homepage's `--font-display-modern`. Falls back to system serif if
// the font isn't installed.
private enum ScopeFont {
    private static let regularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let mediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]

    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumCandidates : regularCandidates) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }
}

// MARK: - Pipeline stages

/// The four stages of the compose pipeline — used to light up the
/// signal monitor and tell the user what's happening.
private enum ComposeStage: Int, CaseIterable {
    case capture, transcript, revise, ship

    var label: String {
        switch self {
        case .capture:    return "CAPTURE"
        case .transcript: return "TRANSCRIPT"
        case .revise:     return "REVISE"
        case .ship:       return "SHIP"
        }
    }

    var pin: String {
        switch self {
        case .capture:    return "S1"
        case .transcript: return "S2"
        case .revise:     return "S3"
        case .ship:       return "S4"
        }
    }
}

// MARK: - ScopeDraftsScreen

struct ScopeDraftsScreen: View {
    @Environment(SettingsManager.self) private var settings
    @State private var editorState = VoiceEditorState()
    @FocusState private var isTextFieldFocused: Bool

    // Dictation state (EphemeralTranscriber → TalkieEngine)
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    // Voice prompt (LLM instruction capture)
    @State private var isRecordingInstruction: Bool = false
    @State private var isTranscribingInstruction: Bool = false
    @State private var pendingInstruction: String?

    // Source memo/dictation (when navigated from a recording)
    @State private var sourceRecordingId: UUID?

    private var availableActions: [SmartAction] {
        SmartAction.combinedActionsForDrafts(appPreset: nil)
    }

    private var dictationOwnsCapture: Bool {
        dictationPillState == .recording || dictationPillState == .transcribing
    }

    private var instructionOwnsCapture: Bool {
        isRecordingInstruction || isTranscribingInstruction
    }

    private var dictationPillDisabled: Bool {
        !dictationOwnsCapture && instructionOwnsCapture
    }

    private var voicePromptDisabled: Bool {
        if isRecordingInstruction { return false }
        if isTranscribingInstruction { return true }
        return editorState.isProcessing || editorState.text.isEmpty || dictationOwnsCapture
    }

    /// Which stage of the pipeline is currently active. Drives the
    /// glowing pin in the signal monitor.
    private var activeStage: ComposeStage {
        if dictationOwnsCapture { return .capture }
        if editorState.isProcessing || isTranscribingInstruction || isRecordingInstruction {
            return editorState.isProcessing ? .revise : .transcript
        }
        if editorState.isReviewing { return .revise }
        if !editorState.text.isEmpty { return .ship }
        return .capture
    }

    private var wordCount: Int {
        editorState.text.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                signalMonitor
                editorBay
                actionRail
                ownershipStrip
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initializeLLMSettings()
            consumeNavigationParams()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: NavigationState.shared.params["initialText"] as? String) { _, newValue in
            if newValue != nil {
                consumeNavigationParams()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Compose", color: ScopeAmber.solid)
                Spacer()
                if let sourceId = sourceRecordingId {
                    Button {
                        NavigationState.shared.navigateToMemo(sourceId)
                    } label: {
                        HStack(spacing: 6) {
                            Text("←")
                                .font(.system(size: 11))
                            Text("SOURCE")
                                .font(ScopeType.channel)
                                .tracking(ScopeType.Tracking.wide)
                        }
                        .foregroundStyle(ScopeAmber.solid)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(ScopeEdge.normal, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open source recording")
                }
            }

            heroHeadline
                .font(ScopeFont.display(size: 46))
                .foregroundStyle(ScopeInk.primary)
                .tracking(-0.8)
                .lineSpacing(-2)

            Text(heroSubhead)
                .font(.system(size: 13))
                .foregroundStyle(ScopeInk.muted)
                .frame(maxWidth: 560, alignment: .leading)

            ScopeDivider().padding(.top, 4)
        }
    }

    /// Two-tone serif headline — the verb stays primary, the object
    /// turns muted-italic. Reads like an instruction etched on glass.
    @ViewBuilder
    private var heroHeadline: some View {
        if editorState.text.isEmpty {
            (
                Text("Speak it. ")
                    .foregroundColor(ScopeInk.primary)
                +
                Text("Shape it.")
                    .foregroundColor(ScopeInk.muted)
                    .italic()
            )
        } else if editorState.isReviewing {
            (
                Text("Review the ")
                    .foregroundColor(ScopeInk.primary)
                +
                Text("revision.")
                    .foregroundColor(ScopeInk.muted)
                    .italic()
            )
        } else {
            (
                Text("\(wordCount) ")
                    .foregroundColor(ScopeInk.primary)
                +
                Text(wordCount == 1 ? "word on the table." : "words on the table.")
                    .foregroundColor(ScopeInk.muted)
                    .italic()
            )
        }
    }

    private var heroSubhead: String {
        if editorState.text.isEmpty {
            return "Dictate, type, or paste. Then steer with your voice — \"make it tighter,\" \"more formal,\" \"bullet it.\""
        }
        if editorState.isReviewing {
            return "Accept the change with ⌘↩, reject with ⎋. Your text returns to its prior state if rejected."
        }
        if editorState.isProcessing {
            return "Routing through the model. The diff will land here when it's ready."
        }
        return "Speak a command to revise. Use a smart action to one-shot a transform. Save as memo or copy out."
    }

    // MARK: - Signal monitor (dark bichromatic strip)

    /// The instrument bay: dark panel with four stage pins. Active
    /// stage glows amber. Right-hand chrome shows the loaded model
    /// and a live duration counter when applicable.
    private var signalMonitor: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(ScopePanel.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ScopePanel.Edge.normal, lineWidth: 1)
                )
            GraticuleBackground(pitch: 24, color: ScopePanel.traceFaint, opacity: 0.55)
                .mask(RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 0) {
                monitorHeader
                monitorPipeline
            }
        }
        .frame(height: 110)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private var monitorHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: editorState.isProcessing ? ScopePanel.trace : ScopePanel.trace.opacity(0.55), size: 6)
            Text("SIGNAL · TALKIE.COMPOSE")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text(monitorChromeRight)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    private var monitorChromeRight: String {
        var parts: [String] = []
        if let provider = resolvedProviderName?.uppercased() {
            parts.append(provider)
        }
        if let model = resolvedModelName {
            parts.append(model.uppercased())
        }
        if dictationOwnsCapture {
            let ds = String(format: "%.1fS", dictationDuration)
            parts.append(ds)
        }
        if parts.isEmpty { parts.append("NO MODEL LOADED") }
        return parts.joined(separator: " · ")
    }

    private var monitorPipeline: some View {
        HStack(spacing: 0) {
            ForEach(Array(ComposeStage.allCases.enumerated()), id: \.offset) { idx, stage in
                stagePin(stage, isActive: stage == activeStage)
                if idx < ComposeStage.allCases.count - 1 {
                    pipelineConnector(isLit: stage.rawValue < activeStage.rawValue)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    private func stagePin(_ stage: ComposeStage, isActive: Bool) -> some View {
        let isPast = stage.rawValue < activeStage.rawValue
        let trace = isActive ? ScopePanel.trace : (isPast ? ScopePanel.trace.opacity(0.50) : ScopePanel.inkSubtle)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(stage.pin)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(trace)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(isActive ? ScopePanel.Edge.strong : ScopePanel.Edge.subtle, lineWidth: 0.5)
                    )
                if isActive {
                    PhosphorDot(color: ScopePanel.trace, size: 5)
                        .shadow(color: ScopePanel.traceGlow, radius: 4)
                }
            }
            Text(stage.label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(isActive ? ScopePanel.ink : (isPast ? ScopePanel.inkMuted : ScopePanel.inkFaint))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ScopeMotion.crossfade, value: isActive)
    }

    private func pipelineConnector(isLit: Bool) -> some View {
        LinearGradient(
            colors: [
                isLit ? ScopePanel.trace.opacity(0.10) : ScopePanel.traceFaint,
                isLit ? ScopePanel.trace : ScopePanel.traceFaint,
                isLit ? ScopePanel.trace.opacity(0.10) : ScopePanel.traceFaint,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 24, height: 1)
        .shadow(color: isLit ? ScopePanel.traceGlow : .clear, radius: 3)
        .padding(.horizontal, 4)
    }

    // MARK: - Editor bay

    /// The paper editor — sits on `ScopeCanvas.surface` with a graticule
    /// underlay so it reads as instrument-paper, not a flat card. Header
    /// row carries channel chrome (CH-IN model selector, word count
    /// readout); footer row carries voice prompt and quick chips.
    private var editorBay: some View {
        VStack(spacing: 0) {
            editorChromeBar

            ZStack {
                Rectangle().fill(ScopeEdge.faint).frame(height: 1)
            }
            .frame(height: 1)

            // Editor / review surface
            Group {
                if editorState.isReviewing, let diff = editorState.currentDiff {
                    reviewingContent(diff: diff)
                } else {
                    editingContent
                }
            }

            // Command feedback strip (shows when a voice prompt is in flight)
            if pendingInstruction != nil || editorState.isProcessing {
                Rectangle().fill(ScopeEdge.faint).frame(height: 1)
                commandFeedbackBar
            }

            Rectangle().fill(ScopeEdge.faint).frame(height: 1)

            actionBar
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
                GraticuleBackground(pitch: 24, color: ScopeTrace.faint, opacity: 0.35)
                    .mask(RoundedRectangle(cornerRadius: 6))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.normal, lineWidth: 1)
        )
    }

    /// Top chrome row of the editor bay — model picker on the left
    /// (styled as a channel tag), word count + clear on the right.
    private var editorChromeBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("CH-IN")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                modelPicker
            }

            Spacer()

            if !editorState.text.isEmpty {
                Text("\(wordCount) WORDS")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }

            if editorState.isProcessing {
                HStack(spacing: 6) {
                    PhosphorDot(color: ScopeAmber.solid, size: 5)
                    Text("REVISING")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                        .phosphorGlow(radius: 3, opacity: 0.32)
                }
            }

            if editorState.currentNoteId != nil {
                Button(action: startNewNote) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("NEW")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                    }
                    .foregroundStyle(ScopeInk.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(ScopeEdge.normal, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Start a new note")
            }

            if !editorState.text.isEmpty && !editorState.isReviewing {
                Button(action: { editorState.text = "" }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ScopeInk.faint)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Clear text")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Editor surface — TalkieTextEditor wrapped in the floating
    /// dictation pill. Cream paper, serif-ish body via system font;
    /// dictation pill remains the standard floating component.
    private var editingContent: some View {
        ZStack(alignment: .bottom) {
            TalkieTextEditor(
                text: $editorState.text,
                selectedRange: $editorState.selectedRange,
                font: NSFont.systemFont(ofSize: 14 * settings.contentFontSize.scale),
                textColor: NSColor(ScopeInk.primary),
                insertionPointColor: NSColor(ScopeAmber.solid)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.bottom, 50)
            .frame(minHeight: 240, maxHeight: .infinity)
            .overlay {
                if editorState.text.isEmpty {
                    placeholderText
                }
            }

            if editorState.isTransformingSelection {
                selectionIndicator
            }

            DictationPill(
                state: $dictationPillState,
                duration: $dictationDuration,
                onTap: handleDictationPillTap
            )
            .disabled(dictationPillDisabled)
            .padding(.bottom, 10)
        }
    }

    /// Phantom placeholder — fades in when the editor is empty.
    /// Sits behind the text editor so it doesn't intercept taps.
    private var placeholderText: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start typing, or tap the dictation pill.")
                        .font(.system(size: 14))
                        .foregroundStyle(ScopeInk.subtle)
                    HStack(spacing: 6) {
                        Text("NO SIGNAL")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                        PhosphorDot(color: ScopeAmber.solid.opacity(0.55), size: 4)
                        Text("WAITING FOR INPUT")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var selectionIndicator: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 9))
                    Text("SELECTION")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                }
                .foregroundStyle(ScopeAmber.solid)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(ScopeAmber.solid.opacity(0.5), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: - Reviewing diff

    private func reviewingContent(diff: TextDiff) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                diffPane(
                    title: "ORIGINAL",
                    pin: "A",
                    content: diff.attributedOriginal(
                        baseColor: ScopeInk.primary,
                        deleteColor: Color(red: 0.72, green: 0.32, blue: 0.18)
                    )
                )

                Rectangle()
                    .fill(ScopeEdge.normal)
                    .frame(width: 1)

                diffPane(
                    title: "PROPOSED",
                    pin: "B",
                    content: diff.attributedProposed(
                        baseColor: ScopeInk.primary,
                        insertColor: Color(red: 0.20, green: 0.48, blue: 0.28)
                    )
                )
            }
            .frame(minHeight: 220, maxHeight: 400)

            if let voiceInstruction = editorState.currentInstruction {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeAmber.solid)
                    Text("YOU SAID")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                    Text(voiceInstruction)
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeInk.dim)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ScopeAmber.tintSubtle)
                .overlay(alignment: .top) {
                    Rectangle().fill(ScopeEdge.faint).frame(height: 1)
                }
            }

            HStack(spacing: 12) {
                Text("\(diff.changeCount) CHANGE\(diff.changeCount == 1 ? "" : "S")")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)

                Spacer()

                Button(action: { editorState.rejectRevision() }) {
                    HStack(spacing: 4) {
                        Text("⎋")
                            .font(.system(size: 10))
                        Text("REJECT")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                    }
                    .foregroundStyle(ScopeInk.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(ScopeEdge.normal, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: { editorState.acceptRevision() }) {
                    HStack(spacing: 4) {
                        Text("⌘↩")
                            .font(.system(size: 9, design: .monospaced))
                        Text("ACCEPT")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                    }
                    .foregroundStyle(ScopePanel.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ScopeAmber.solid)
                    )
                    .shadow(color: ScopeAmber.glow, radius: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func diffPane(title: String, pin: String, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ChannelLabel(pin, color: ScopeAmber.solid, strokeColor: ScopeEdge.normal)
                Text(title)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.muted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ScopeCanvas.canvasAlt.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(ScopeEdge.faint).frame(height: 1)
            }

            ScrollView {
                Text(content)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Command feedback

    private var commandFeedbackBar: some View {
        HStack(spacing: 10) {
            if editorState.isProcessing {
                BrailleSpinner(size: 11)
                    .foregroundColor(ScopeAmber.solid)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.32)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(pendingInstruction ?? editorState.currentInstruction ?? "Processing…")
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeInk.dim)
                    .lineLimit(1)
                if let provider = editorState.lastUsedProvider ?? resolvedProviderName,
                   let model = editorState.lastUsedModel ?? resolvedModelName {
                    Text("\(provider.uppercased()) · \(model.uppercased())")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }

            Spacer()

            if editorState.isProcessing {
                Button(action: { editorState.cancelGeneration() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeInk.faint)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Cancel generation")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ScopeAmber.tintSubtle)
    }

    // MARK: - Action bar (bottom of editor bay)

    private var actionBar: some View {
        HStack(spacing: 8) {
            voicePromptButton

            ForEach(availableActions.prefix(3)) { action in
                scopeActionChip(action)
            }

            Spacer()

            if let err = editorState.error {
                Text(err.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(Color(red: 0.72, green: 0.32, blue: 0.18))
                    .lineLimit(1)
            }

            Button(action: saveToMemo) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("SAVE")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                }
                .foregroundStyle(editorState.text.isEmpty ? ScopeInk.subtle : ScopeInk.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(ScopeEdge.normal, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Save as Memo")

            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("COPY")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                }
                .foregroundStyle(editorState.text.isEmpty ? ScopeInk.subtle : ScopePanel.bg)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(editorState.text.isEmpty ? ScopeCanvas.canvasAlt : ScopeAmber.solid)
                )
                .shadow(color: editorState.text.isEmpty ? .clear : ScopeAmber.glow, radius: 3)
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var voicePromptButton: some View {
        Button(action: toggleVoicePrompt) {
            HStack(spacing: 6) {
                if isTranscribingInstruction {
                    BrailleSpinner(size: 10)
                        .foregroundColor(ScopePanel.ink)
                } else if isRecordingInstruction {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(isRecordingInstruction ? "STOP" : "COMMAND")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
            }
            .foregroundStyle(isRecordingInstruction ? ScopePanel.ink : ScopePanel.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecordingInstruction
                          ? Color(red: 0.72, green: 0.32, blue: 0.18)
                          : ScopePanel.bg)
            )
            .shadow(color: isRecordingInstruction ? Color(red: 0.72, green: 0.32, blue: 0.18).opacity(0.5) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .disabled(voicePromptDisabled)
        .help("Speak to tell the model what to do with your text")
    }

    private func scopeActionChip(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
        }) {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(action.name.uppercased())
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
            }
            .foregroundStyle(ScopeInk.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(editorState.isProcessing || editorState.text.isEmpty)
    }

    // MARK: - Action rail (full grid below editor)

    /// A wider grid of smart actions. Each cell mirrors the homepage
    /// capture-mode card shape but at a smaller size — icon badge,
    /// channel pin, name, hint copy.
    private var actionRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Transforms")
                Spacer()
                Text("ONE-SHOT REVISIONS")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Array(availableActions.enumerated()), id: \.element.id) { idx, action in
                    ActionCell(
                        action: action,
                        channel: String(format: "T-%02d", idx + 1),
                        disabled: editorState.isProcessing || editorState.text.isEmpty,
                        onTap: {
                            Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Ownership strip

    /// Small architectural footer — your text → your model → your output.
    /// Echoes the homepage's "U1 → U2 → U3" ownership row.
    private var ownershipStrip: some View {
        HStack(spacing: 14) {
            ownershipNode(pin: "P1", label: "Your words", detail: "local · this device")
            SignalPath(color: ScopeAmber.solid, width: 24)
            ownershipNode(pin: "P2", label: "Your model", detail: resolvedModelName?.uppercased() ?? "PICK A MODEL")
            SignalPath(color: ScopeAmber.solid, width: 24)
            ownershipNode(pin: "P3", label: "Your output", detail: "copy · memo · ship")
        }
        .padding(.top, 6)
    }

    private func ownershipNode(pin: String, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            ChannelLabel(pin)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                Text(detail)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Model picker

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
                                editorState.setLLMSelection(providerId: provider.id, modelId: model.id)
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
            HStack(spacing: 5) {
                Text(displayModelName.uppercased())
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.30)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(ScopeAmber.solid.opacity(0.7))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(ScopeAmber.solid.opacity(0.30), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var displayModelName: String {
        if let model = editorState.modelId {
            return model
                .replacingOccurrences(of: "claude-opus-4-6", with: "opus 4.6")
                .replacingOccurrences(of: "claude-sonnet-4-6", with: "sonnet 4.6")
                .replacingOccurrences(of: "claude-sonnet-4-5-20250929", with: "sonnet 4.5")
                .replacingOccurrences(of: "claude-haiku-4-5-20251001", with: "haiku 4.5")
                .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
                .replacingOccurrences(of: "gpt-4o", with: "4o")
                .replacingOccurrences(of: "claude-3-5-sonnet", with: "sonnet")
                .replacingOccurrences(of: "claude-3-haiku", with: "haiku")
                .replacingOccurrences(of: "gemini-1.5-flash", with: "flash")
        }
        return "Select model"
    }

    private var resolvedProviderName: String? {
        if let providerId = editorState.providerId {
            return LLMProviderRegistry.shared.provider(for: providerId)?.name
        }
        return LLMProviderRegistry.shared.providers.first?.name
    }

    private var resolvedModelName: String? {
        if let modelId = editorState.modelId {
            return modelId
        }
        if let provider = LLMProviderRegistry.shared.providers.first {
            return LLMConfig.shared.providers[provider.id]?.defaultModel
        }
        return nil
    }

    // MARK: - Lifecycle / navigation params

    private func initializeLLMSettings() {
        Task { @MainActor in
            await editorState.initializeLLMSettings()
        }
    }

    private func consumeNavigationParams() {
        guard let initialText = NavigationState.shared.params["initialText"] as? String,
              !initialText.isEmpty else { return }

        editorState.reset()
        editorState.text = initialText
        sourceRecordingId = NavigationState.shared.params["sourceRecordingId"] as? UUID
        NavigationState.shared.params.removeValue(forKey: "initialText")
        NavigationState.shared.params.removeValue(forKey: "sourceRecordingId")
        log.info("Compose (scope) opened with \(initialText.count) chars\(sourceRecordingId != nil ? " from recording \(sourceRecordingId!.uuidString.prefix(8))" : "")")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isTextFieldFocused = true
        }
    }

    private func startNewNote() {
        editorState.reset()
        sourceRecordingId = nil
        isTextFieldFocused = true
    }

    // MARK: - Dictation (Talkie → Engine)

    private func handleDictationPillTap() {
        switch dictationPillState {
        case .idle:
            guard !instructionOwnsCapture else { return }
            startDictationRecording()
        case .recording:
            stopDictationRecording()
        case .transcribing, .success:
            break
        }
    }

    private func startDictationRecording() {
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .draftsDictation)
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
                let result = try await EphemeralTranscriber.shared.stopAndTranscribePersistent()

                if !result.text.isEmpty {
                    let noteId = editorState.currentNoteId ?? UUID()
                    if editorState.currentNoteId == nil {
                        editorState.currentNoteId = noteId
                    }

                    let segmentId = UUID()
                    let audioFilename = "\(segmentId.uuidString).m4a"
                    let destURL = AudioStorage.audioDirectory.appendingPathComponent(audioFilename)
                    do {
                        try FileManager.default.moveItem(at: result.audioURL, to: destURL)
                    } catch {
                        try? FileManager.default.copyItem(at: result.audioURL, to: destURL)
                        try? FileManager.default.removeItem(at: result.audioURL)
                    }

                    let repo = TalkieObjectRepository()
                    let existingCount = try await repo.countSegments(forNoteId: noteId)

                    let segment = TalkieObject.newSegment(
                        parentId: noteId,
                        segmentIndex: existingCount,
                        text: result.text,
                        duration: dictationDuration,
                        audioFilename: audioFilename,
                        transcriptionModel: nil
                    )
                    try await repo.saveRecording(segment)

                    let needsSpace = !editorState.text.isEmpty
                        && !editorState.text.hasSuffix(" ")
                        && !editorState.text.hasSuffix("\n")
                    if needsSpace { editorState.text += " " }
                    editorState.text += result.text

                    log.info("Scope dictation segment saved: \(result.text.count) chars")
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

    // MARK: - Voice prompt (LLM instruction)

    private func toggleVoicePrompt() {
        if isRecordingInstruction {
            Task { await stopVoicePrompt() }
        } else {
            guard !dictationOwnsCapture else { return }
            startVoicePrompt()
        }
    }

    private func startVoicePrompt() {
        guard !isRecordingInstruction else { return }
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .draftsCommand)
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
                pendingInstruction = instruction
                await editorState.requestRevision(instruction: instruction)
                pendingInstruction = nil
            }
        } catch {
            log.error("Voice prompt transcribe failed: \(error)")
            isTranscribingInstruction = false
            pendingInstruction = nil
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
            await editorState.promoteNoteToMemo()
        }
    }
}

// MARK: - Action cell

private struct ActionCell: View {
    let action: SmartAction
    let channel: String
    let disabled: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isHovered ? ScopeEdge.strong : ScopeEdge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 18, color: ScopeTrace.faint, opacity: 0.35)
                    .mask(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        iconBadge
                        Spacer()
                        Text(channel)
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }

                    Text(action.name)
                        .font(ScopeFont.display(size: 15))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                        .tracking(-0.2)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text("APPLY")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                        Text("→")
                            .font(.system(size: 10))
                            .foregroundStyle(ScopeInk.faint)
                    }
                }
                .padding(10)
            }
            .frame(height: 92)
            .offset(y: isHovered && !disabled ? -2 : 0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(ScopeAmber.tintSubtle)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(ScopeEdge.normal, lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 2, opacity: 0.28)
            )
    }
}

#Preview {
    ScopeDraftsScreen()
        .frame(width: 1000, height: 800)
}

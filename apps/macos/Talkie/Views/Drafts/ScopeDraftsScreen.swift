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
// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.

// MARK: - Stage disc (V2 typeset pipeline marker)

private enum StageDiscState {
    case done, active, pending
}

private struct StageDisc: View {
    let state: StageDiscState

    var body: some View {
        let size: CGFloat = 9
        switch state {
        case .done:
            Circle()
                .fill(ScopeAmber.solid)
                .frame(width: size, height: size)
        case .active:
            // Ring + half-fill — matches the studio mock's SVG: outline
            // circle with the right semicircle filled.
            ZStack {
                Circle()
                    .stroke(ScopeAmber.solid, lineWidth: 1.2)
                Path { p in
                    let half = size / 2
                    p.move(to: CGPoint(x: half, y: 0))
                    p.addArc(
                        center: CGPoint(x: half, y: half),
                        radius: half - 0.6,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90),
                        clockwise: false
                    )
                    p.closeSubpath()
                }
                .fill(ScopeAmber.solid)
            }
            .frame(width: size, height: size)
        case .pending:
            Circle()
                .stroke(ScopeInk.faint.opacity(0.45), lineWidth: 1)
                .frame(width: size, height: size)
        }
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
    @Environment(\.navigationState) private var navigationState
    @Environment(SettingsManager.self) private var settings
    @State private var editorState = VoiceEditorState()
    @FocusState private var isTextFieldFocused: Bool

    // Dictation state (DictationInput → TalkieEngine)
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
        VStack(spacing: 0) {
            hero

            // Pinned workbench — V2 strips the card chrome so the
            // signal header, editor page, and action bar all stack as
            // sibling sections on cream paper (not nested in a bay).
            VStack(alignment: .leading, spacing: 18) {
                signalMonitor
                editorBay
                    .frame(minHeight: 420, maxHeight: .infinity)
                actionBar
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Scrollable accessory rail — transforms + ownership byline
            // sit below the fold. The pinned workbench eats the rest.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    actionRail
                    ownershipStrip
                }
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .onAppear {
            initializeLLMSettings()
            consumeNavigationParams()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: navigationState.params["initialText"] as? String) { _, newValue in
            if newValue != nil {
                consumeNavigationParams()
            }
        }
    }

    // MARK: - Header strip
    //
    // Universal 44pt top band — title "Drafts", trailing chrome carries
    // word count / readiness, optional ← SOURCE pill when navigated from
    // a memo.

    private var hero: some View {
        ScopeTopBand(
            title: "Drafts",
            chrome: headerChrome
        ) {
            if let sourceId = sourceRecordingId {
                Button {
                    navigationState.navigateToMemo(sourceId)
                } label: {
                    Text("← SOURCE")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                }
                .buttonStyle(.plain)
                .help("Open source recording")
                .accessibilityLabel("Open source recording \(sourceId.uuidString.prefix(8))")
            }
        }
    }

    private var headerChrome: String {
        if editorState.text.isEmpty { return "READY" }
        if editorState.isReviewing { return "REVIEWING REVISION" }
        return wordCount == 1 ? "1 WORD" : "\(wordCount) WORDS"
    }

    // MARK: - Signal header (typeset, cream paper)

    /// V2 — the dark instrument panel is gone. The signal header is now
    /// a typeset row on cream paper: eyebrow + italic byline on the
    /// left, model picker + word count on the right; a hairline; then
    /// the pipeline as a quiet row of typeset stage discs.
    ///
    /// Mirrors `design/studio/components/studies/MacCompose.tsx`
    /// `SignalHeader` exactly.
    private var signalMonitor: some View {
        VStack(alignment: .leading, spacing: 0) {
            monitorHeader

            Rectangle()
                .fill(ScopeInk.faint.opacity(0.18))
                .frame(height: 0.5)
                .padding(.top, 12)

            monitorPipeline
                .padding(.top, 12)
        }
    }

    private var monitorHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("· COMPOSE · D-0024 ·")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)

            Text(monitorByline)
                .font(ScopeType.display(size: 13).italic())
                .foregroundStyle(ScopeInk.faint)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                modelPicker
                Text(wordCountChrome)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                    .monospacedDigit()
            }
        }
    }

    private var monitorByline: String {
        if dictationOwnsCapture {
            return String(format: "live dictation · %.1fs", dictationDuration)
        }
        if editorState.isProcessing {
            return "revising · model in flight"
        }
        if editorState.text.isEmpty {
            return "open · awaiting first capture"
        }
        return "open · in progress"
    }

    private var wordCountChrome: String {
        if editorState.text.isEmpty { return "0 WORDS" }
        return wordCount == 1 ? "1 WORD" : "\(wordCount) WORDS"
    }

    private var monitorPipeline: some View {
        HStack(spacing: 12) {
            ForEach(Array(ComposeStage.allCases.enumerated()), id: \.offset) { idx, stage in
                stagePin(stage, isActive: stage == activeStage)
                if idx < ComposeStage.allCases.count - 1 {
                    pipelineConnector(isLit: stage.rawValue < activeStage.rawValue)
                }
            }

            Spacer(minLength: 12)

            Text("⌃⇧⌘R · revise")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
    }

    /// V2 — typeset stage marker. Filled amber disc for done, ring-with-
    /// half-fill for active, hollow ink ring for pending. Label sits to
    /// the right and inherits the same state-driven contrast.
    private func stagePin(_ stage: ComposeStage, isActive: Bool) -> some View {
        let isPast = stage.rawValue < activeStage.rawValue
        let state: StageDiscState = isActive ? .active : (isPast ? .done : .pending)
        let labelColor: Color = isActive
            ? ScopeAmber.solid
            : (isPast ? ScopeInk.primary : ScopeInk.faint)
        let weight: Font.Weight = isActive ? .semibold : .regular

        return HStack(spacing: 8) {
            StageDisc(state: state)

            Text(stage.label.capitalized)
                .font(.system(size: 10, weight: weight, design: .monospaced))
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(labelColor)
        }
        .animation(ScopeMotion.crossfade, value: isActive)
    }

    /// V2 — thin amber hairline when the next stage is reached, otherwise
    /// a faint ink hairline. No gradient, no glow.
    private func pipelineConnector(isLit: Bool) -> some View {
        Rectangle()
            .fill(isLit ? ScopeAmber.solid.opacity(0.5) : ScopeInk.faint.opacity(0.32))
            .frame(width: 32, height: 0.5)
    }

    // MARK: - Editor page (V2)

    /// V2 — no card chrome. The editor is a sheet of paper bracketed by
    /// hairlines, with a brass marginal rule down the left of the text.
    /// No graticule, no rounded corners, no card border. Mirrors
    /// `MacMemoDetail` document body so the editorial language stays
    /// consistent across surfaces.
    private var editorBay: some View {
        VStack(spacing: 0) {
            editorChromeBar

            // Top page rule
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.18))
                .frame(height: 0.5)
                .padding(.top, 8)

            // Editor / review surface — marginal rule lives inside.
            Group {
                if editorState.isReviewing, let diff = editorState.currentDiff {
                    reviewingContent(diff: diff)
                } else {
                    editingContent
                }
            }
            .padding(.top, 14)

            // Command feedback strip (shows when a voice prompt is in
            // flight). Sits inside the page, between the body and the
            // bottom rule.
            if pendingInstruction != nil || editorState.isProcessing {
                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.10))
                    .frame(height: 0.5)
                commandFeedbackBar
            }

            // Bottom page rule
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.18))
                .frame(height: 0.5)
                .padding(.top, 6)
        }
    }

    /// V2 — the editor chrome row sits ABOVE the page rules as a typeset
    /// slug, not as a chrome strip with its own background. Model picker
    /// has moved up to the signal header; this row carries the draft
    /// title slug and a couple of contextual actions.
    private var editorChromeBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("· DRAFT")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(Color.hex("9A6A22"))

            Text(editorSlugTitle)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if editorState.isProcessing {
                HStack(spacing: 6) {
                    PhosphorDot(color: ScopeAmber.solid, size: 5)
                    Text("REVISING")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                }
            }

            if editorState.currentNoteId != nil {
                Button(action: startNewNote) {
                    Text("NEW DRAFT")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                }
                .buttonStyle(.plain)
                .help("Start a new draft")
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
    }

    /// Quiet slug text — first line of the draft or a placeholder. Lives
    /// inline with the chrome row so it reads as a typeset draft byline.
    private var editorSlugTitle: String {
        let trimmed = editorState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "untitled draft" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let snippet = firstLine.prefix(64)
        return snippet.lowercased()
    }

    /// V2.1 — editor surface as a sheet of paper. Brass marginal rule
    /// on the left of the text column (matches `MacMemoDetail.documentBody`),
    /// a subtle paper background tint so the writing area has a visible
    /// boundary, and the dictation pill floating at the bottom-center
    /// (kept after user feedback — the pill was the right affordance,
    /// the typeset hint was an over-correction).
    private var editingContent: some View {
        ZStack(alignment: .bottom) {
            // Bounded paper sheet. The tint now spans the FULL width so the
            // writing area reads as one contained surface against the cream
            // canvas, and the brass marginal rule sits ON its left edge as a
            // true margin. (It used to float 18pt left of the sheet with
            // bare canvas between them — which read as a stray vertical line
            // sitting at its own placement, disconnected from everything.)
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(ScopeCanvas.surface.opacity(0.7))

                TalkieTextEditor(
                    text: $editorState.text,
                    selectedRange: $editorState.selectedRange,
                    font: NSFont.systemFont(ofSize: 14 * settings.contentFontSize.scale),
                    textColor: NSColor(ScopeInk.primary),
                    insertionPointColor: NSColor(ScopeAmber.solid)
                )
                .padding(.leading, 26)
                .padding(.trailing, 14)
                .padding(.top, 14)
                .padding(.bottom, 56)
                .frame(minHeight: 240, maxHeight: .infinity)

                if editorState.isTransformingSelection {
                    selectionIndicator
                }
            }
            .overlay(alignment: .leading) {
                // Brass marginal rule — now the sheet's own left edge.
                Rectangle()
                    .fill(Color.hex("9A6A22").opacity(0.42))
                    .frame(width: 1.5)
            }
            .padding(.horizontal, 4)

            // Floating dictation pill — bottom-center, the previous
            // affordance the user explicitly asked back for.
            DictationPill(
                state: $dictationPillState,
                duration: $dictationDuration,
                onTap: handleDictationPillTap
            )
            .disabled(dictationPillDisabled)
            .padding(.bottom, 10)
        }
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
        HStack(spacing: 6) {
            voicePromptButton

            Spacer()

            if let err = editorState.error {
                Text(err.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(Color(red: 0.72, green: 0.32, blue: 0.18))
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }

            Button(action: saveToMemo) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("SAVE")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                }
                .foregroundStyle(editorState.text.isEmpty ? ScopeInk.subtle : ScopeInk.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(editorState.text.isEmpty ? Color.clear : ScopeCanvas.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(editorState.text.isEmpty ? ScopeEdge.faint : ScopeEdge.normal, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Save as Memo")

            Button(action: copyToClipboard) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("COPY")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                }
                .foregroundStyle(editorState.text.isEmpty ? ScopeInk.subtle : ScopePanel.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(editorState.text.isEmpty ? ScopeCanvas.canvasAlt : ScopeAmber.solid)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(editorState.text.isEmpty ? ScopeEdge.faint : ScopeAmber.solid.opacity(0.85), lineWidth: 0.5)
                )
                .shadow(color: editorState.text.isEmpty ? .clear : ScopeAmber.glow, radius: 4)
            }
            .buttonStyle(.plain)
            .disabled(editorState.text.isEmpty)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Primary voice-command affordance. V2.1 — bigger, more contrasty
    /// per user note that it's the loudest verb in the action bar and
    /// should read like it. Sits next to the smart-action chips and
    /// brackets the row on the left.
    private var voicePromptButton: some View {
        let recordingRed = Color(red: 0.72, green: 0.32, blue: 0.18)
        let isActive = isRecordingInstruction || isTranscribingInstruction

        return Button(action: toggleVoicePrompt) {
            HStack(spacing: 8) {
                if isTranscribingInstruction {
                    BrailleSpinner(size: 12)
                        .foregroundColor(ScopeAmber.solid)
                } else if isRecordingInstruction {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(isRecordingInstruction ? "STOP" : "COMMAND")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(ScopeType.Tracking.wide)

                Text("⌃⇧⌘C")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(
                        isRecordingInstruction
                            ? ScopePanel.ink.opacity(0.55)
                            : ScopeAmber.solid.opacity(0.55)
                    )
            }
            .foregroundStyle(
                isRecordingInstruction
                    ? ScopePanel.ink
                    : (voicePromptDisabled ? ScopeInk.subtle : ScopeAmber.solid)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isRecordingInstruction
                            ? recordingRed
                            : ScopeAmber.solid.opacity(0.12)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isRecordingInstruction
                            ? recordingRed.opacity(0.85)
                            : ScopeAmber.solid.opacity(0.72),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isRecordingInstruction ? recordingRed.opacity(0.45) : (isActive ? ScopeAmber.glow : .clear),
                radius: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(voicePromptDisabled)
        .help("Voice instruction → revise")
    }

    // MARK: - Action list (V2 — typeset two-column, no cards)

    /// V2 — drops the white-card grid in favor of a typeset list. Each
    /// row is `serif name | flexible hint | APPLY →`, two columns on
    /// wide canvases, one column when narrow. Whole row lifts on hover
    /// with an amber tint; APPLY arrow only appears on hover. Reads as
    /// a menu of operations in a notebook, not a control panel.
    private var actionRail: some View {
        // V2.1 — only truly inactive states (model in flight) gray the
        // rows. A draft with no text yet leaves the rows visually active
        // so the action menu always reads as a live affordance; the tap
        // is a no-op when there's no text to operate on.
        let disabled = editorState.isProcessing
        let count = availableActions.count
        let half = (count + 1) / 2
        let leftCol = Array(availableActions.prefix(half))
        let rightCol = Array(availableActions.dropFirst(half))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("· SMART ACTIONS")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)

                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.18))
                    .frame(height: 0.5)

                Text("\(count) operations · pick one to apply")
                    .font(ScopeType.display(size: 13).italic())
                    .foregroundStyle(ScopeInk.faint)
            }

            HStack(alignment: .top, spacing: 28) {
                actionColumn(actions: leftCol, disabled: disabled)
                actionColumn(actions: rightCol, disabled: disabled)
            }
        }
        // The columns use maxWidth:.infinity, so without a cap the rail
        // sprawls edge-to-edge on wide windows. Bound it so the menu reads
        // as a compact two-column list left-anchored under the editor.
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private func actionColumn(actions: [SmartAction], disabled: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(actions, id: \.id) { action in
                ActionListRow(
                    action: action,
                    disabled: disabled,
                    onTap: {
                        guard !editorState.text.isEmpty else { return }
                        Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ownership byline (V2)

    /// V2 — the P1/P2/P3 boxed signal-path strip collapses to a single
    /// italic line. The two model nodes are brass amber; the device /
    /// output anchors are ink-strong. Reads as an editorial colophon
    /// rather than instrument panel chrome.
    private var ownershipStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.10))
                .frame(height: 0.5)
                .padding(.bottom, 10)

            ownershipByline
        }
        .padding(.top, 4)
    }

    private var ownershipByline: some View {
        let brass = Color.hex("9A6A22")
        let hostname = Host.current().localizedName ?? "Mac"
        let asrName = prettyASRModel(settings.liveTranscriptionModelId)
        let providerName = resolvedProviderName ?? "local"
        let modelName = resolvedModelName ?? "no model selected"

        let italicFont = ScopeType.display(size: 14).italic()
        let mediumFont = ScopeType.display(size: 14, weight: .medium)

        // Build the line in a single AttributedString so the typography
        // flows as one editorial colophon — italic faint for connective
        // tissue, brass for technology names, ink for the host + output
        // anchors.
        func italic(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = ScopeInk.faint
            a.font = italicFont
            return a
        }
        func ink(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = ScopeInk.primary
            a.font = mediumFont
            return a
        }
        func brassed(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = brass
            a.font = mediumFont
            return a
        }

        var text = italic("recorded on ")
        text.append(ink(hostname))
        text.append(italic(" via "))
        text.append(brassed(asrName))
        text.append(italic(", edits via "))
        text.append(brassed(providerName))
        text.append(italic(" · "))
        text.append(brassed(modelName))
        text.append(italic(", filed to "))
        text.append(ink("Library · Notes"))
        text.append(italic("."))

        return Text(text)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pretty-print an ASR model id like "parakeet:v3" → "Parakeet v3".
    /// Mirrors the heuristic in `TOSharedComponents.prettyModel` so the
    /// two surfaces agree on how to spell model names.
    private func prettyASRModel(_ raw: String) -> String {
        let parts = raw.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return raw.capitalized }
        let family = parts[0].capitalized
        let version = parts[1]
        return "\(family) \(version)"
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
        guard let initialText = navigationState.params["initialText"] as? String,
              !initialText.isEmpty else { return }

        editorState.reset()
        editorState.text = initialText
        sourceRecordingId = navigationState.params["sourceRecordingId"] as? UUID
        navigationState.params.removeValue(forKey: "initialText")
        navigationState.params.removeValue(forKey: "sourceRecordingId")
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
        guard !DictationInput.shared.isPreparing else { return }

        Task {
            do {
                try await DictationInput.shared.startCapture(purpose: .draftsDictation)
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
    }

    private func stopDictationRecording() {
        dictationTimerRef?.cancel()
        dictationTimerRef = nil
        dictationPillState = .transcribing

        Task {
            do {
                let result = try await DictationInput.shared.stopAndTranscribePersistent()

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
        guard !isRecordingInstruction, !DictationInput.shared.isPreparing else { return }

        Task {
            do {
                try await DictationInput.shared.startCapture(purpose: .draftsCommand)
                isRecordingInstruction = true
            } catch {
                log.error("Voice prompt capture failed: \(error)")
                editorState.error = error.localizedDescription
            }
        }
    }

    private func stopVoicePrompt() async {
        guard isRecordingInstruction else { return }
        isRecordingInstruction = false
        isTranscribingInstruction = true

        do {
            let instruction = try await DictationInput.shared.stopAndTranscribe()
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
                            .stroke(strokeColor, lineWidth: 1)
                    )
                GraticuleBackground(
                    pitch: 18,
                    color: ScopeTrace.faint,
                    opacity: disabled ? 0.20 : 0.35
                )
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
                        .font(ScopeType.display(size: 15))
                        .foregroundStyle(disabled ? ScopeInk.muted : ScopeInk.primary)
                        .lineLimit(1)
                        .tracking(-0.2)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text(disabled ? "OFFLINE" : "APPLY")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                        if !disabled {
                            Text("→")
                                .font(.system(size: 10))
                                .foregroundStyle(ScopeInk.faint)
                        }
                    }
                }
                .padding(10)
            }
            .frame(height: 92)
            .offset(y: isHovered && !disabled ? -2 : 0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var strokeColor: Color {
        if disabled { return ScopeEdge.faint }
        return isHovered ? ScopeEdge.strong : ScopeEdge.normal
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(disabled ? Color.clear : ScopeAmber.tintSubtle)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(disabled ? ScopeEdge.subtle : ScopeEdge.normal, lineWidth: 0.5)
            )
            .overlay(
                Group {
                    if disabled {
                        Image(systemName: action.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ScopeInk.faint)
                    } else {
                        Image(systemName: action.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ScopeAmber.solid)
                            .phosphorGlow(radius: 2, opacity: 0.28)
                    }
                }
            )
    }
}

// MARK: - Action list row (V2)

/// Typeset action row used by the V2 actionRail. Renders name + an
/// `APPLY →` hover affordance on a single typeset row, no card chrome.
private struct ActionListRow: View {
    let action: SmartAction
    let disabled: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(action.name)
                    .font(ScopeType.display(size: 15))
                    .foregroundStyle(disabled ? ScopeInk.muted : ScopeInk.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(disabled ? "OFFLINE" : "APPLY →")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(disabled ? ScopeInk.subtle : ScopeAmber.solid)
                    .opacity(hovered || disabled ? 1 : 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(hovered && !disabled ? ScopeAmber.tintSubtle : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.10))
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

#Preview {
    ScopeDraftsScreen()
        .frame(width: 1000, height: 800)
}

# Compose → SwiftUI port spec (M2)

**Status:** drafted while Codex builds Phase 0
**Depends on:** M1 (Home) landing so the entry-point pattern is
proven; this port doesn't strictly require M1 but the Home → Compose
nav from the PICK UP card is the most natural way to reach it.
**Branch:** `feat/ios-compose-m2` (cut from master after M1 merges).
**Target file** (Claude writes; Codex scaffolds + bridges):

- `apps/ios/Talkie iOS/Views/Next/ComposeNextView.swift`
- (optional, if the diff renderer grows past inline view code)
  `apps/ios/Talkie iOS/Views/Next/DiffInline.swift`

**Visual reference:** `http://localhost:3000/compose` — state picker
at top toggles between idle / dictating / voice command / generating
/ diff. Each state renders the same document (a sample Conference
Bio) with state-specific overlays.

**Design rationale:** see `design/studio/app/compose/NOTES.md`. Key
moves: Compose is for **turns on existing text**, NOT chat. Voice
command is a transformation request ("tighten the second paragraph"),
not a prompt to a chatbot. Model output rendered as inline diff;
user accepts or discards.

---

## State model

Compose extends the shell's `ShellChrome` state with its own
document-level state. They're orthogonal: ShellChrome handles "is
the universal voice button summoned"; ComposeState handles "what
mode is this document in."

```swift
enum ComposeState: Equatable {
    case idle           // doc shown, caret blinking, ready
    case dictating      // mic hot, new text appearing at cursor
    case listening      // voice command being captured (instruction)
    case generating     // model running; subtle spinner
    case diff           // model returned a transformation; review
}
```

Transition triggers (M2 wires real handlers; Phase 0/M1 stub them):

- `.idle` → `.dictating` — tap mic in toolbar (or some inline mic
  affordance — not the shell's voice button, which is for voice
  commands)
- `.dictating` → `.idle` — release mic / tap to stop dictation;
  appended text is committed
- `.idle` → `.listening` — long-press the shell's voice button
  (`ShellChrome.longPressBegan`); this is the routing point where
  the existing shell gesture maps into "voice command" mode IF
  ComposeNextView is the current screen
- `.listening` → `.generating` — release shell voice button
  (`ShellChrome.longPressEnded` fires the captured-audio handler;
  ComposeNextView's handler sets state to `.generating` and kicks
  off the AI provider call)
- `.generating` → `.diff` — model returns the transformation
- `.diff` → `.idle` — Accept (apply transformation) or Discard
  (drop it)

---

## Composition

```
┌────────────────────────────────────────┐
│ status bar                             │
├────────────────────────────────────────┤
│ ‹ Bio    · COMPOSE WITH       ⋯        │   ← Header
│          ✦ Sonnet 4.6 ▾                │
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ Art is the founder of Talkie, an   │ │
│ │ everywhere-capture system that     │ │
│ │ turns voice into structured        │ │
│ │ artifacts.                         │ │   ← Document body
│ │                                    │ │     (state-driven overlays)
│ │ Previously at Notion (design) and  │ │
│ │ Linear (notifications). He's been  │ │
│ │ building voice-first software      │ │
│ │ since 2014.                        │ │
│ └────────────────────────────────────┘ │
│                                        │
│ — quick row (shorter / polish / connect / fix) — │
│                                        │
│ [voice cmd] [cursor pad] [keyboard]    │  ← Action tray
│                                        │
│      ●  shell voice button (lives in shell, not here) │
└────────────────────────────────────────┘
```

State-specific overlay variations:

- **idle**: just caret blinking inside body
- **dictating**: live italic-amber appended text at cursor +
  recording indicator
- **listening**: amber strip below the body — "Listening" smallcap +
  italic transcript of captured command
- **generating**: muted body + below it a card with spinner + model
  name + "iterating · ~3s"
- **diff**: inline strikethrough on removed text + amber-highlighted
  additions + Accept/Discard chips replace the action tray

---

## File: `ComposeNextView.swift`

```swift
import SwiftUI

struct ComposeNextView: View {
    let documentID: String   // from PICK UP / Library / wherever

    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @StateObject private var compose: ComposeStore   // Codex wires

    @State private var state: ComposeState = .idle

    init(documentID: String, store: ComposeStore? = nil) {
        self.documentID = documentID
        // ComposeStore loads the doc, owns the inline-dictation +
        // voice-command + diff pipelines.
        _compose = StateObject(wrappedValue: store ?? ComposeStore(documentID: documentID))
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposeHeader(modelLabel: compose.modelLabel) {
                // back action — pop / dismiss
            }

            DocumentBody(
                document: compose.document,
                state: state,
                dictationPreview: compose.livePartialTranscript,
                voiceCommand: compose.lastCommandTranscript,
                generatingETA: compose.generatingETA,
                diff: compose.pendingDiff
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state != .diff {
                QuickTransforms(
                    muted: state == .generating || state == .listening,
                    onTap: { trigger in compose.applyTransform(trigger) }
                )
            }

            ActionTray(
                state: state,
                onAccept: { applyDiff() },
                onDiscard: { discardDiff() },
                onRefine: { compose.discardDiff(); state = .listening }
            )
        }
        .onAppear { wireUp() }
        .onChange(of: compose.state) { _, new in
            state = new
        }
    }

    private func wireUp() {
        // Route shell's listening events to ComposeStore's voice command pipeline.
        // M2 detail: ShellChrome.longPressBegan/Ended already mutate ShellChrome.state.
        // Here we observe ShellChrome.state changes and, when current screen IS Compose,
        // pipe them into ComposeStore. Probably done via an environment Combine pipeline
        // or NotificationCenter — Codex picks the cleanest wiring.
    }

    private func applyDiff() {
        compose.acceptDiff()
        // Diff transitions state back to .idle via @Published.
    }

    private func discardDiff() {
        compose.discardDiff()
    }
}
```

### `ComposeHeader`

Centered "· COMPOSE WITH / ✦ Sonnet 4.6 ▾" (model is the hero). Back
button replaces Done top-left ("‹ Bio" — implies the parent context).
Overflow `⋯` top-right. No "Send" — there are no prompts.

```swift
private struct ComposeHeader: View {
    let modelLabel: String     // "Sonnet 4.6"
    let onBack: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Bio")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("· COMPOSE WITH")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.92)
                    .foregroundStyle(theme.colors.textTertiary)

                Button(action: {
                    // TODO: model picker sheet
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                        Text(modelLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                            .tracking(-0.3)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
```

### `DocumentBody` — state-driven rendering

```swift
private struct DocumentBody: View {
    let document: ComposeStore.Document
    let state: ComposeState
    let dictationPreview: String?
    let voiceCommand: String?
    let generatingETA: String?
    let diff: ComposeStore.Diff?

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            cardSurface

            VStack(alignment: .leading, spacing: 12) {
                if state == .diff, let diff {
                    DiffInline(document: document, diff: diff)
                } else {
                    ForEach(document.paragraphs.indices, id: \.self) { idx in
                        ParagraphView(
                            text: document.paragraphs[idx],
                            isLast: idx == document.paragraphs.count - 1,
                            dictationPreview: idx == document.paragraphs.count - 1 ? dictationPreview : nil,
                            showCaret: state == .idle && idx == document.paragraphs.count - 1
                        )
                    }
                }

                if state == .listening, let voiceCommand {
                    ListeningStrip(commandText: voiceCommand)
                }
                if state == .generating {
                    GeneratingStrip(eta: generatingETA ?? "~3s")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 8)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
            )
    }
}

private struct ParagraphView: View {
    let text: String
    let isLast: Bool
    let dictationPreview: String?
    let showCaret: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (
                Text(text)
                    .foregroundStyle(theme.colors.textPrimary)
                +
                (dictationPreview.map {
                    Text(" \($0)")
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .italic()
                } ?? Text(""))
            )
            .font(.system(size: 15))
            .lineSpacing(4)
            .tracking(-0.07)

            if showCaret {
                BlinkingCaret(color: theme.currentTheme.chrome.accent)
            }
        }
    }
}

private struct BlinkingCaret: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1.5, height: 14)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
            .padding(.leading, 1)
    }
}

private struct ListeningStrip: View {
    let commandText: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            ListeningWaveformDots(color: theme.currentTheme.chrome.accent)
                .frame(width: 16, height: 12)
            Text("LISTENING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("\u{201C}\(commandText)\u{2026}\u{201D}")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.currentTheme.chrome.accentTint)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: 0.5)
                )
        )
    }
}

private struct GeneratingStrip: View {
    let eta: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.6)
            Text("Sonnet 4.6 · iterating")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Text(eta)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
                )
        )
    }
}
```

### `DiffInline`

Renders the diff inline: original paragraphs with deleted spans
struck through (red-tinted) and added spans highlighted (amber).
SwiftUI `Text` concatenation handles this; for paragraph-level diffs
the spans are flat and easy. For sentence-level (M2 default) we
operate on the paragraph that changed.

```swift
struct DiffInline: View {
    let document: ComposeStore.Document
    let diff: ComposeStore.Diff

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.paragraphs.indices, id: \.self) { idx in
                paragraphView(idx: idx)
            }
            statusRow
        }
    }

    private func paragraphView(idx: Int) -> some View {
        let spans = diff.spans(forParagraph: idx)
        return spans.reduce(Text("")) { acc, span in
            acc + spanText(span)
        }
        .font(.system(size: 15))
        .lineSpacing(4)
        .tracking(-0.07)
    }

    private func spanText(_ span: ComposeStore.Diff.Span) -> Text {
        switch span.kind {
        case .keep:
            return Text(span.text)
                .foregroundStyle(theme.colors.textPrimary)
        case .remove:
            return Text(span.text)
                .strikethrough(true, color: Color.red.opacity(0.5))
                .foregroundStyle(theme.colors.textTertiary)
        case .add:
            return Text(span.text)
                .foregroundStyle(theme.colors.textPrimary)
                .underline(true, color: theme.currentTheme.chrome.accentStrong)
                // Background highlight via attributedString in a real
                // implementation; SwiftUI Text doesn't expose bg per
                // span natively — alternative: split paragraph at span
                // boundaries and render each as a separate background-
                // colored view inline via HStack with alignment .baseline.
        }
    }

    private var statusRow: some View {
        HStack {
            Text("- \(diff.removedCount)")
                .foregroundStyle(Color.red.opacity(0.85))
            Text("+ \(diff.addedCount)")
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Spacer()
            Text("v2 · just now")
                .foregroundStyle(theme.colors.textTertiary)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(1.5)
        .padding(.top, 4)
    }
}
```

Note: SwiftUI's `Text` doesn't expose per-span background colors
natively. Two options:
- (a) Use `AttributedString` with `BackgroundColor` attribute —
  works as of iOS 15 but per-attribute background is limited;
- (b) Render paragraph as `HStack(spacing: 0)` of one Text per span
  with a `.background()` on the add spans. More flexibility, more
  code. **M2 default: option (b).** Per-span backgrounds are
  necessary for the design.

### `QuickTransforms`

Four chip buttons — Shorter / Polish / Connect / Fix grammar.
Tapping kicks off a transformation immediately (skips the voice
command capture; the chip's label IS the command).

```swift
private struct QuickTransforms: View {
    let muted: Bool
    let onTap: (ComposeStore.QuickTransform) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("· QUICK")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textTertiary)
            ForEach(ComposeStore.QuickTransform.allCases, id: \.self) { t in
                Button(action: { onTap(t) }) {
                    Text(t.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(theme.colors.cardBackground)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(muted ? 0.5 : 1)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 0.5),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
```

### `ActionTray`

Two modes:
- Normal (idle / dictating / listening / generating): voice cmd
  · cursor pad · keyboard
- Diff: Discard · Refine command · Accept

```swift
private struct ActionTray: View {
    let state: ComposeState
    let onAccept: () -> Void
    let onDiscard: () -> Void
    let onRefine: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if state == .diff {
            HStack(spacing: 8) {
                actionChip(label: "Discard", active: false, action: onDiscard)
                actionChip(label: "Refine command", active: false, action: onRefine)
                actionChip(label: "Accept", active: true, action: onAccept)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
            HStack {
                trayButton(systemImage: "waveform.path.ecg.rectangle") { /* voice cmd */ }
                Spacer()
                cursorPad
                Spacer()
                trayButton(systemImage: "keyboard") { /* keyboard */ }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // helper: actionChip + trayButton + cursorPad — see component
    // sketches in design/studio/components/studies/Compose.tsx
}
```

---

## `ComposeStore` — service bridge (Codex writes this)

```swift
@MainActor
final class ComposeStore: ObservableObject {
    @Published var document: Document
    @Published var state: ComposeState = .idle
    @Published var livePartialTranscript: String?
    @Published var lastCommandTranscript: String?
    @Published var pendingDiff: Diff?
    @Published var generatingETA: String?

    let modelLabel: String   // e.g. "Sonnet 4.6" — from active model setting

    struct Document {
        let id: String
        var paragraphs: [String]
    }

    struct Diff {
        let removedCount: Int
        let addedCount: Int
        func spans(forParagraph: Int) -> [Span]

        struct Span {
            enum Kind { case keep, remove, add }
            let kind: Kind
            let text: String
        }
    }

    enum QuickTransform: CaseIterable {
        case shorter, polish, connect, fixGrammar

        var label: String {
            switch self {
            case .shorter: return "Shorter"
            case .polish:  return "Polish"
            case .connect: return "Connect"
            case .fixGrammar: return "Fix grammar"
            }
        }

        var instruction: String {
            switch self {
            case .shorter: return "Make this shorter by ~30%, preserve key claims."
            case .polish:  return "Polish for tone and rhythm; keep voice."
            case .connect: return "Strengthen connections between paragraphs."
            case .fixGrammar: return "Fix grammar and typos; no other edits."
            }
        }
    }

    init(documentID: String) {
        // Codex wires:
        // - load Document from Persistence
        // - subscribe to inline-dictation partials from AudioRecorderManager
        // - own the AI provider call (existing TalkieAIProvider services)
        // - compute Diff from old vs new text (line/word-level diff;
        //   simplest cheap approach: paragraph-level replace; richer
        //   later)
    }

    func applyTransform(_ t: QuickTransform) {
        // state = .generating
        // call AI with t.instruction + current document text
        // on response: pendingDiff = computeDiff(old, new), state = .diff
    }

    func voiceCommandReceived(_ utterance: String) {
        // state = .generating
        // call AI with utterance + current document text
        // same as applyTransform path
    }

    func acceptDiff() {
        guard let diff = pendingDiff else { return }
        // apply diff to document
        pendingDiff = nil
        state = .idle
    }

    func discardDiff() {
        pendingDiff = nil
        state = .idle
    }
}
```

### Wiring contract for Codex

1. **`ShellChrome.longPressEnded` → `ComposeStore.voiceCommandReceived`**
   — the wiring point where the global "long-press the voice
   button" gesture becomes "send this transcript to Compose's voice
   command pipeline" IF Compose is the current screen. Codex
   chooses the mechanism (NotificationCenter, Combine pipeline,
   environment subject); document the choice.
2. **`AudioRecorderManager`** — Compose's inline dictation (the
   mic in the body, not the shell button) hooks into the existing
   recorder + Whisper pipeline. Codex picks whether to instantiate
   a new recorder per Compose instance or share the singleton.
3. **AI provider routing** — use whatever provider is selected via
   `TalkieAIProviderResolver` / `TalkieAIProviderCredentialIngestor`.
   The voice command + current document text become the prompt;
   the response is parsed as the transformed text.
4. **Diff computation** — for M2 keep it simple: a Swift
   implementation of LCS or just `CollectionDifference` between the
   two token streams. Paragraph-level granularity is acceptable as
   a starting point; richer span-level later.

---

## Cut criteria for M2

- [ ] ComposeNextView renders a real document loaded via Persistence
- [ ] Tap mic in body → state goes to `.dictating`; partial
      transcript appears in italic amber at the cursor
- [ ] Release → text committed into the paragraph; state = `.idle`
- [ ] Long-press shell voice button while in Compose → `.listening`
      (with the captured command in italic in the strip)
- [ ] Release shell voice button → `.generating` → `.diff`
- [ ] Diff renders inline strikethrough + amber-highlighted adds
- [ ] Accept applies the transformation; Discard drops it; both
      return to `.idle`
- [ ] Quick transforms work as fast-paths to `.generating` directly
- [ ] Screenshots match the studio mock at
      `http://localhost:3000/compose` (cycle the state picker for
      side-by-side comparison)

---

## Out of scope for M2

- **Model picker UI** — header shows the active model name; tapping
  it does nothing in M2. Picker sheet is its own thing.
- **Cursor pad real functionality** — chip is visible; tapping
  does nothing (or shows a "soon" indicator). Real cursor nav is a
  later refinement.
- **Keyboard interaction** — keyboard chip dismisses to system
  keyboard; that's it. No custom dictation keyboard etc.
- **Multi-paragraph diffs** — M2 handles one-paragraph-at-a-time
  diffs cleanly; multi-paragraph reorganizations are a follow-up.
- **Undo/redo stack** — Accept commits; undo is system-provided.
  No custom history.

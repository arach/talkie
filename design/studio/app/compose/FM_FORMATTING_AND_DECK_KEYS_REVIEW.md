# Compose review — Apple Foundation Models formatting + deck-style keys

Advisory only, no source changed. Line refs are to files at time of review.

Scope:
- `apps/ios/Talkie iOS/Views/Next/ComposeNextView.swift`
- `apps/ios/Talkie iOS/Views/Next/ComposeStore.swift`
- `apps/ios/Talkie iOS/Models/OnDeviceAIService.swift`
- `apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift` (donor for the key look)

Sibling docs already cover the toolbar/bezel geometry — `BEZEL_REVIEW.md` (fold the
toolbar into the card, kill the box-in-a-box) and `COMPOSE_REFINEMENTS.md` (stop the
double-translucent slab). **This doc does not repeat them.** It adds (a) the Foundation
Models formatting architecture, which neither covers, and (b) the *material* the keys
should adopt from the deck's `keycapSurface`, which the bezel docs leave open.

---

## First principles

Two different problems are being conflated under "refine compose":

1. **"Format this memo" is a document-scoped, structure-preserving transform** — not a
   paragraph rewrite. Its value is: fix capitalization/punctuation, delete verbal filler,
   insert paragraph breaks at topic shifts — *without changing wording*. The current
   pipeline (`revisedParagraph` → `targetParagraphIndex`, ComposeStore L527/L609) picks the
   **single longest paragraph** and rewrites it. Wrong mental model on two axes: wrong
   *scope* (one paragraph, not the doc) and wrong *intent* (rewrite, not clean-up). That is
   why the diff reads as a meaningless total rewrite.

2. **The floating keys read as a gray slab** because they're translucent caps inside a
   *second* translucent container, stacked over live text. The deck's keys read as discrete
   dark objects because they are **opaque, chamfered, and lifted by a two-layer shadow with
   no wrapping slab** (`keycapSurface`, DeckMirrorNext L587–645).

Apple Foundation Models (on-device ~3B, `SystemLanguageModel.default`) is an *excellent*
fit for #1 and a poor fit for creative rewriting: formatting/filler-removal is low-entropy,
so hallucination risk is low, and it's free + private + offline. So the design principle is
**scope FM to the format command; leave heavier rewrites on Mac/Direct.**

---

## Q1 — Architecture for FM formatting of long memos

**Not** a silent fallback inside quick transforms, and **not** just a new provider row.
Model it as **one new document-scoped command + one new engine**, because scope and engine
are orthogonal:

- **New intent: `formatDocument()`** — a dedicated command that operates on
  `documentBodyText` (the whole doc), bypassing `targetParagraphIndex`/`revisedParagraph`
  entirely. Surface it three ways:
  - a **"Format" chip** in the quick-transform row (next to Shorter/Polish/Connect, the
    `QuickTransform` enum, ComposeStore L348);
  - **voice-command routing**: in `voiceCommandReceived` (L235), detect format-intent
    tokens (`format`, `clean up`, `clean this up`, `tidy`, `fix the formatting`,
    `paragraph breaks`) *before* falling through to `targetParagraphIndex`, and branch to
    `formatDocument()`;
  - optionally a memo-detail action ("Format transcript").

- **New engine: `RevisionPath.apple`** (add to the enum at ComposeStore L327). Title
  "Apple", `systemImage` "sparkles". But format should prefer on-device **regardless of the
  selected path** when `OnDeviceAIService.shared.isAvailable` — because it's the right tool
  for this job — and fall back to the currently-selected Mac/Direct path when FM is
  unavailable or the user explicitly pins a cloud model. Keep `.apple` as an explicit,
  pinnable route so power users can force on-device for *all* transforms.

**Chunking** (FM input+output is small — the app already caps at 2000–4000 chars, e.g.
OnDeviceAIService L63/L168):
- Split on **paragraph boundaries** (`document.paragraphs`), greedily packing into
  ~1200–1500-char windows. If a single paragraph exceeds the cap, sub-split on sentence
  boundaries.
- Format each chunk **independently** — safe here precisely because formatting is *local*
  (filler + casing + breaks need no cross-chunk context, unlike summarization).
- Run **sequentially** (or a TaskGroup of width ≤2). Don't hammer one
  `LanguageModelSession` with N parallel requests on-device.
- Re-join with `\n\n` and route the result back through `updateDocumentBodyText` so the
  `paragraphs(from:) == inverse(joined)` invariant (ComposeStore L784–796) is preserved.

**Diff UX** — this is where "useful, not a total rewrite" is won or lost, and it's **50%
prompt, 50% diff scoping**:
- Compute the diff **paragraph-aligned**, not one giant string compare. `ComposeInlineDiff`
  bails to `matches == nil → isBroadRewrite = true` once the LCS matrix exceeds
  `maxMatrixCells = 1_500_000` (ComposeNextView L1660, L1692). A 900-word memo diffed
  whole-doc is 900×900 ≈ 810k (ok), but ~1225 words squared blows the cap → the diff
  **degrades to the broad-rewrite look even when formatting was surgical.** Align original
  vs formatted paragraph-by-paragraph and diff each pair; each matrix stays tiny and
  unchanged runs dominate → filler deletions + inserted breaks highlight cleanly.
- The `hasStructureChange` branch (L1688) already treats added `\n`/breaks as structural —
  good; keep the word-level marking on by keeping overlap high (prompt discipline below).

---

## Q2 — API shape

### OnDeviceAIService (mirror the existing flag-gated pattern)

```swift
/// Structure-preserving formatting of a (possibly long) voice memo, on-device.
/// Fixes casing/punctuation, removes verbal filler, and inserts paragraph
/// breaks at topic shifts WITHOUT rewording or adding content. Chunks by
/// paragraph so long memos fit the on-device context window.
func formatMemo(_ text: String) async throws -> String {
    guard FeatureFlags.aiMemoFormattingEnabled else { throw OnDeviceAIError.notAvailable }
    #if canImport(FoundationModels)
    guard isAvailable else { throw OnDeviceAIError.notAvailable }
    let chunks = Self.formatChunks(text, maxChars: 1500)   // paragraph-greedy
    guard !chunks.isEmpty else { throw OnDeviceAIError.noTranscript }

    isProcessing = true
    defer { isProcessing = false }

    var out: [String] = []
    for chunk in chunks {
        let session = LanguageModelSession(instructions: Self.memoFormatSystemPrompt)
        let resp = try await session.respond(
            to: chunk,
            options: FoundationModels.GenerationOptions(temperature: 0.2)  // deterministic
        )
        out.append(resp.content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return out.joined(separator: "\n\n")
    #else
    throw OnDeviceAIError.notAvailable
    #endif
}

static let memoFormatSystemPrompt = """
You clean up raw voice-transcribed text. Your ONLY job is formatting:
- Fix capitalization, punctuation, and obvious transcription slips.
- Remove filler words (um, uh, like, you know, I mean, kind of, sort of,
  basically) ONLY where they add nothing.
- Insert paragraph breaks between distinct topics.
Do NOT summarize, reword, reorder, translate, or add any content.
Preserve the speaker's wording and meaning exactly.
Return ONLY the cleaned text — no preamble, no notes.
"""
```

Add `FeatureFlags.aiMemoFormattingEnabled` alongside the others (FeatureFlags.swift L37+).

### ComposeStore

```swift
// Diff gains a scope so acceptDiff knows how to apply it (see Q4 — this is a
// correctness must-fix, not a nicety).
struct Diff {
    enum Scope { case paragraph, document }
    let scope: Scope           // NEW — default .paragraph at existing call sites
    let original: String
    let proposed: String
    let removedCount, addedCount, unchangedCount: Int
}

func formatDocument() {
    commandTask?.cancel()
    lastCommandTranscript = "Format this memo"
    pendingDiff = nil
    state = .generating
    generatingETA = "~5s"
    commandTask = Task { @MainActor [weak self] in
        guard let self else { return }
        let original = self.documentBodyText
        let proposed = await self.formattedDocument(original: original)   // FM, then fallback
        guard !Task.isCancelled, self.state == .generating else { return }
        guard proposed != original, self.passesFormatSanity(original, proposed) else {
            self.state = .idle; return       // no-op / rejected → don't show a bogus diff
        }
        self.pendingDiff = Self.makeDiff(scope: .document, original: original, proposed: proposed)
        self.state = .diff
    }
}
```

`formattedDocument` = try `OnDeviceAIService.shared.formatMemo` when FM available; else
send the *whole body* to Mac/Direct with the format instruction (reuse
`BridgeManager.composeRevision` / `ComposeLocalRevisionService.revise`, but scope =
"Document"); else `localRevision`. `passesFormatSanity` = reject if word-level overlap
< ~0.6 (guards against the model rewording despite instructions — see Q4).

`acceptDiff` (L267) must branch on `diff.scope`: `.document` → `updateDocumentBodyText(diff.proposed)`
(whole-body replace, lossless), `.paragraph` → existing `document.replacing(...)`.

---

## Q3 — What the keys should borrow from DeckMirrorNext

The deck keys read discrete/dark/crisp for four concrete reasons, all in `keycapSurface`
(DeckMirrorNext L587–645). The compose keys (`deckKeyBackground`, ComposeNextView
L1481–1492) do the opposite on every one:

| Property | Deck `keycapSurface` | Compose `deckKeyBackground` today | Change |
|---|---|---|---|
| Fill | **opaque** `theme.colors.cardBackground` | `.ultraThinMaterial` + `actionTint` (~ink·0.06·0.58 ≈ invisible) | Opaque `cardBackground` fill |
| Finish | chamfer gradient (white 0.16 → clear → black 0.12) | none | Add the same chamfer overlay |
| Lift | **two** shadows: ambient (r7–13, y4–9) + contact (r2–3, y1–2) | none | Add both layers |
| Resting edge | **no hairline** (reads by finish, not outline) | `edgeFaint` hairline on every key | Drop the border |
| Corner | radius 10 continuous | `CornerRadius.sm` | Match at 10 |
| Press/active | `scaleEffect(1.02)` + amber ring when armed | none | Add scale; mic already goes amber |

Concrete moves:

1. **Delete the wrapping `toolbarBackground`** (L1494) — the deck wraps *nothing* around
   its command keys (Relief keybed = `Color.clear`, DeckMirrorNext L563). The wrapping slab
   *is* the "gray slab." Let each key stand on the text; keep only `EditorBottomChromeFade`
   for legibility. (`BEZEL_REVIEW.md` reaches the same "no box-in-a-box" conclusion from the
   geometry side — this is the material side of it.)

2. **Rewrite `deckKeyBackground` to reuse `keycapSurface`'s treatment.** Cleanest: lift
   `keycapSurface(active:activeColor:isEmpty:)` into a small shared
   `DeckKeycapBackground` (or a `View.deckKeycap()` modifier) in a shared file so compose
   and deck render *identically* — this is the "studio→Swift visual parity" habit applied
   across two surfaces. If you don't want to share yet, inline the same four layers.

3. **`InlineMicButton` (L1351)** — keep it the amber-armed centerpiece (already matches the
   deck's dictation tile). Give its *idle* circle the same keycap material: opaque
   `cardBackground` circle + chamfer + the two-layer lift, instead of
   `actionTint.opacity(0.62)`. Dictating state already flips to `chrome.accent` — leave it.

4. **Fade treatment** — the reason the fade exists is that translucent keys float over
   scrolling text. Once keys are **opaque**, text can't bleed through them, so the fade only
   needs to darken the *gaps between* keys. Keep `EditorBottomChromeFade` but you can soften
   its final band (it currently ramps `cardBackground` to 0.34/0.28, L1134–1144); the keys
   now carry their own ground. Opaque-dark-over-text reads *quieter* than translucent-gray
   precisely because it stops sampling the text behind it.

Net: the keys become discrete dark caps with a soft lift — the deck's "button roll" — and
the gray slab disappears with the wrapper.

---

## Q4 — Must-fix risks / edge cases

1. **`acceptDiff` silently no-ops on a document-scope diff.** Today it does
   `document.paragraphs.firstIndex(of: diff.original)` + `replacing` (L269, L310). For a
   whole-doc format, `diff.original` is the joined body, which is not any single paragraph →
   `firstIndex` returns nil → **the format is dropped with no error.** The `Diff.scope`
   branch in Q2 is the fix. This is the single highest-risk item.
2. **Losslessness.** Route the formatted body through `updateDocumentBodyText`, never
   hand-splice paragraphs — `paragraphs(from:)` must stay the exact inverse of
   `joined("\n\n")` or you reopen the "can't type space/enter" bug (ComposeStore L784–796).
3. **FM rewording despite the prompt.** Low temp + strict prompt reduce it, but add a hard
   guard (`passesFormatSanity`, overlap ≥ ~0.6). If it fails, treat as failure → fall back or
   abort with a quiet message; never present a low-overlap "format" as a diff. This is the
   literal defense of "diff stays useful, not a meaningless total rewrite."
4. **Diff matrix cap forces the broad-rewrite look on long memos** (`maxMatrixCells`, L1660
   / L1692). Paragraph-aligned diffing (Q1) keeps every matrix small so surgical edits stay
   word-marked. Without this, a *correct* format still *looks* like a rewrite.
5. **Availability / offline / simulator.** `isAvailable` is false when Apple Intelligence is
   off, the device is unsupported, or on the sim. `checkAvailability` runs once in `init`
   (L28) — re-check on demand before formatting (the watch path already does, L182–184).
   The Format chip should disable-with-reason or transparently route to Mac/Direct, never
   fail silently or crash.
6. **Chunk-seam artifacts.** Chunk on paragraph/sentence boundaries only; a mid-sentence
   split can duplicate or drop a break at the seam. Re-join deterministically with `\n\n`.
7. **Latency on long memos.** Sequential 3B calls over many chunks take seconds; keep the
   `GeneratingStrip` ETA honest (L1083) and consider per-chunk progress. Work is already
   async off the store's `@MainActor` via `session.respond`.
8. **Shared `isProcessing` singleton flag** (OnDeviceAIService L24) — auto-title and format
   can collide and stomp each other's flag. Minor, but don't gate UI on it globally.
9. **Trivially short memos.** Guard a minimum length before offering Format; formatting a
   one-line note yields a no-op diff.
10. **Revision history scope.** `recordRevision` labels scope from paragraph index (L679–694).
    A document format should record scope "Document" so restore/undo round-trips the whole
    body, not one paragraph.
11. **Light themes.** Opaque `cardBackground` caps are *light* on Scope/paper themes
    (cardBackground #FFF/#F8F6F1). "Discrete dark" is a dark-theme reading; use the tokens
    (don't hardcode dark) so the keycap stays theme-correct and still reads as discrete.

---

## Q5 — Checks that prove it

- **Availability matrix:** real device, Apple Intelligence ON → Format runs on-device
  (provider label "Apple", no network). AI OFF / simulator → graceful fallback or
  disabled-with-reason, no crash, no silent drop.
- **Long multi-topic memo (>1500 chars):** "format this memo" → diff is mostly *shared*
  text with filler struck and paragraph breaks inserted; `review.isBroadRewrite == false`
  and unchanged-ratio high. Explicitly test a ~1300-word memo to confirm the matrix cap no
  longer forces the broad-rewrite look (regression on risk #4).
- **Apply / persist / undo:** Accept updates **all** paragraphs (not one), persists across
  reload, records revision scope "Document", and `restoreRevision` round-trips the full body.
- **Losslessness regression:** after a format, typing spaces/newlines still works
  (paragraphs invariant, risk #2).
- **Sanity guard:** feed a deliberately over-eager instruction and confirm a low-overlap
  result is rejected rather than shown (risk #3).
- **Visual parity:** screenshot the compose key row beside the deck key row — same radius,
  chamfer, and two-layer lift; keys read as discrete dark caps; no wrapping slab; text
  legible behind the fade. (Same walk-every-element parity pass used for other ports.)
- **Perf:** measure format latency on a ~500-word memo; UI stays responsive, ETA shown.
```

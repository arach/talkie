# Compose refinements — styling / interaction advice

Scope: `apps/ios/Talkie iOS/Views/Next/ComposeNextView.swift` (+ `OnDeviceAIService.swift`).
Advisory only — no source changed. Line refs are to `ComposeNextView.swift` at time of review.

---

## 1. Minimize the floating keys overlay (`ComposeFloatingTools`, ~L1398–1500)

**What actually occludes the text today** — two layers, not the keys:
- `EditorBottomChromeFade` (L1126) fades the card bg up to **0.94 opaque** and caps it with a solid `Rectangle` at 0.94. That's a near-solid block under the bar.
- `toolbarBackground` (L1486) stacks `.ultraThinMaterial` **and then** `cardBackground.opacity(0.72)` on top. The 0.72 fill defeats the material's blur → it reads as occlusion, not translucency.

To get "blur the text behind, don't hide it," fix those two before touching key sizes.

**Toolbar background — let the blur do the work:**
```swift
private var toolbarBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.ultraThinMaterial)                         // blur = the effect
        .overlay(                                          // faint tint only, not a mask
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.cardBackground.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint.opacity(0.7),
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)   // was 0.22 / r12 / y6
}
```
Tint 0.72 → **~0.18–0.25**, corner 18 → **14**, shadow r12→**6**. If legibility over busy text suffers, step material `.ultraThinMaterial → .thinMaterial` rather than raising the tint.

**Chrome fade — soften so text shows through under the bar:**
Lower the gradient's terminal stops and drop (or thin) the solid tail:
```swift
colors: [ cardBackground.opacity(0),
          cardBackground.opacity(0.22),
          cardBackground.opacity(0.38) ]   // was 0 / 0.78 / 0.94
// and delete the trailing solid Rectangle (or height 38 → ~12 at 0.38)
```

**Shrink each key a touch** (keeps its own background, just smaller):
- icon keys `frame(32×30)` → **28×26**, icon font `12` → **11** (`iconButton`, L1450)
- `space` key `frame(46×30)` → **40×26**, font `11` → **10.5** (`spaceButton`, L1463)
- mic `frame(38×38)` → **32–34**, glyph `15` → **13** (`InlineMicButton`, L1380)
- cluster `spacing 7 → 6`, keycap tint `actionTint.opacity(0.86)` → **~0.6** so blur bleeds between keys.

**Shrink overall footprint:** in `body` (L1440) collapse the doubled horizontal padding — you currently do `.padding(.horizontal,12)` then background then `.padding(.horizontal,12)` again. Keep vertical `8 → 6` and make the outer inset larger (`.padding(.horizontal, 20)`) so the bar reads as a smaller floating island, not a full-width slab.

Gotcha: the theme already flips keycap luminance per background — re-check both light and dark themes after dropping the tint; material + dark-on-dark can go muddy.

---

## 2. Post-version layout defaults collapsed, expands on interaction (`RevisionHistoryRollup`, ~L1959)

**The machinery already exists** — `RevisionPreviewMode { minimized, compact, expanded }` (L1927), `RevisionMiniPreview` (single-line v1→v2 + restore, L2118) vs `RevisionDiffPreview` (BEFORE/AFTER panes, L2170), a segmented `RevisionPreviewModeControl`, and the spring at L2058. Three targeted changes:

**a. Default to the smallest form.** `@State private var previewMode = .compact` (L1964) → **`.minimized`**.

**b. Show NO preview pane until a chip is tapped.** Today `selectedIndex` falls back to `0` when `selectedRevisionID == nil` (L1969) so a pane always renders. Make nil selection mean *collapsed*:
```swift
@State private var selectedRevisionID: UUID? = nil
// preview block:
if let sel = selectedRevisionID,
   let idx = revisions.firstIndex(where: { $0.id == sel }) {
    // render mini/diff for idx, wrapped in the transition below
}
```
Collapsed state = header row + horizontal version chips only (~36–40pt tall). That returns the most text space.

**c. "Interacting slides up / expands."** On chip tap, set selection *and* lift the mode; tapping the already-selected chip collapses back:
```swift
Button {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
        if selectedRevisionID == revision.id {
            selectedRevisionID = nil            // tap again → collapse
        } else {
            selectedRevisionID = revision.id
            previewMode = .compact              // reveal before/after
        }
    }
}
```
The preview already carries `.transition(.opacity.combined(with: .move(edge: .top)))` (L2043/2052) — keep it; just make sure the `.animation(..., value:)` container also keys on `selectedRevisionID`, not only `previewMode`, or the first open won't animate. Progression: chip tap → compact diff; the existing expand control (⤢) → full `.expanded`; tap chip again → collapsed.

**d. Reclaimed height flows to the editor automatically** — the rollup sits in the parent `VStack` between the card and `QuickTransforms` (ComposeNextView L93), and `DocumentBody`'s card holds `.layoutPriority(1)` + `maxHeight:.infinity`, so a shorter rollup grows the writing surface with no other change.

Gotchas:
- `beforeText(for:)` / `versionNumber(for:)` (L2061–2079) assume a valid index — keep them behind the `if let idx` guard.
- Animate selection and mode in one `withAnimation` block so the slide reads as a single motion, not two pops.
- Keep the mode control visible even when collapsed so the user can jump straight to expanded.

---

## 3. Smaller compose body font (`Coordinator.bodyFont`, L708)

Single source of truth — `setDocumentText`, `applyTypingAttributes`, and the placeholder all read this one computed prop, so one edit propagates:
```swift
private static var bodyFont: UIFont {
    UIFontMetrics(forTextStyle: .body)
        .scaledFont(for: .systemFont(ofSize: 16, weight: .regular))  // was 18
}
```
Recommend **16pt** (17 if 16 feels tight for long-form; don't go below 15 — cramped). Keep Dynamic Type. Nudge `typingAttributes` `lineSpacing 6 → 5` (L717) to hold the ~1.35–1.4 line-height ratio; placeholder follows automatically since it reuses `bodyFont`.

---

## 4. Apple Intelligence for quick edits — realistic, and already half-wired

**Yes.** `apps/ios/Talkie iOS/Models/OnDeviceAIService.swift` already links Apple's **Foundation Models** framework (`LanguageModelSession`, `SystemLanguageModel.default.availability`, `GenerationOptions`) for on-device titles/summaries/tasks. The same pattern powers Compose's quick edits — no new dependency.

**Two Apple surfaces, pick per use:**

**A. Foundation Models (`LanguageModelSession`) — the realistic programmatic API.** iOS 26+, on-device ~3B model. Drive your own **Shorter / Polish / Connect** chips and the free-form **"Command"** instruction with it:
```swift
let session = LanguageModelSession(instructions:
    "Rewrite the user's text per the instruction. Return only the rewritten text.")
let out = try await session.respond(
    to: "Instruction: \(instruction)\n\nText:\n\(selectedText)",
    options: .init(temperature: 0.3)).content
```
Feed `out` into the existing diff/version pipeline (`ComposeStore.pendingDiff` → revisions). Free, private, offline, fast for short text — fits "quick edit" exactly. Model it as a **local provider route** alongside Direct API / Mac Bridge (the header picker at L779 already treats these as routes, not just models). Gate on `SystemLanguageModel.default.availability == .available` (needs an Apple-Intelligence-capable device with it enabled) and fall back to the configured cloud model otherwise.
- Use `@Generable` guided generation if you want a structured `{ rewritten, summaryOfChange }` payload.
- `respond(...)` supports streaming for a live preview.
- Limits: ~4k-token context, English-centric, quality below GPT-5.5/Claude, possible content-filter refusals — so keep cloud as the quality tier and on-device as the instant/offline default.

**B. Writing Tools — free system menu, but not scriptable.** The editor is a real `UITextView`, so Rewrite / Proofread / Summarize / tone changes are available for free from the **selection edit menu** (iOS 18+/26). Tune with `textView.writingToolsBehavior = .complete/.limited/.none` and `writingToolsAllowedInputOptions`. **Caveat:** there is no fully public API to *trigger* Writing Tools on a range from your own button — it's user-invoked. Also verify it isn't suppressed: the editor empties `inputAssistantItem` groups and installs an empty `inputView` to kill the system keyboard (L403, L430); the selection-menu Writing Tools path still works, but confirm on-device.

**Recommendation:** power the custom quick-edit buttons with surface **A** (extend `OnDeviceAIService` with a `rewrite(text:instruction:)` and add an "On-device · Apple Intelligence" route to `ComposeStore`), and let surface **B** ride for free as the native selection menu. Don't try to script Writing Tools.

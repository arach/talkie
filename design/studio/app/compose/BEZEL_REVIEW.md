# Compose surface — bezel + revision styling review

Scope: `apps/ios/Talkie iOS/Views/Next/ComposeNextView.swift`
Trigger: floating editor toolbar + fade reads as a box-in-a-box; revision stack adds too many outlines.
Goal: fold the toolbar/fade **into** the editor card as a bottom bezel, collapse nested outlines, keep revision iterations legible.

---

## 1. Diagnosis — where the "too many boxes" come from

Walking the idle/dictating render (the screenshot state), the bottom of the editor card stacks **four** independent bordered/filled layers on top of the card itself:

| Layer | Source | Draws |
|---|---|---|
| Editor card | `DocumentBody.cardSurface` (L1115) | fill + `edgeFaint` border, `chromeCorner+6` |
| Fade band | `EditorBottomChromeFade` (L1126) | gradient → solid `cardBackground` rectangle |
| Floating pill | `ComposeFloatingTools.toolbarBackground` (L1486) | **ultraThinMaterial + cardBackground.72 + edgeFaint border + drop shadow**, radius 18, inset 12pt |
| 7 deck keys | `deckKeyBackground` (L1477) ×6 + space | each an `actionTint` fill + `edgeFaint` border |

Plus the `InlineMicButton` circle (fill + border + shadow). So the eye counts: card border → shadowed pill border → 7 key borders → mic border, all inside a ~50pt strip. That is the cognitive load Arach is naming. The `.ultraThinMaterial` is doing nothing useful here — nothing scrolls *behind* the card, so the blur just muddies an already-dark surface and buys a shadow that reads as "second window."

The fade exists **only because** the pill is translucent and floats over live-scrolling text (see the mic scroll-away, `scrollViewDidScroll` L569 + `isMicVisible`). Make the bezel opaque and structural and the fade's whole reason for existing disappears.

---

## 2. Core move — bezel takes the shape of the card

Stop overlaying the toolbar in the ZStack. Make it the **bottom row of a VStack that IS the card**, sharing the card's fill and bottom corners, separated by a single hairline — exactly the pattern `ComposeHeader` already uses for its bottom edge (L881–886).

Restructure `DocumentBody.body` from `ZStack { cardSurface; VStack{editor; Spacer}; fade; tools }` to:

```swift
VStack(spacing: 0) {
    contentRegion                                   // editor OR diff, flexible
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    if state == .idle || state == .dictating {
        Rectangle()                                 // one hairline, same as header
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
        ComposeEditorBezel(state: state, onMic: onMic)   // NO bg/border/shadow of its own
    }
}
.background(cardSurface)                             // the ONE fill + border
.clipShape(RoundedRectangle(cornerRadius: theme.currentTheme.chrome.chromeCorner + 6, style: .continuous))
.padding(.top, 6)
```

The bezel body keeps the current ZStack (mic pinned to true center so it stays aligned with the cursor pad in `ActionTray` — preserve that), but drops its background entirely:

```swift
ZStack {
    InlineMicButton(state: state, action: onMic)    // the single filled "hero"
    HStack {
        clipboardCluster                            // select · cut · copy
        Spacer(minLength: 16)
        insertCluster                               // space · paste · newline
    }
}
.padding(.horizontal, 14)                           // match the editor's 14pt inset
.padding(.vertical, 10)
// no .background(toolbarBackground), no outer .padding(.horizontal, 12)
```

Net result at the card bottom: **card border + one hairline + one filled mic.** Down from ~10 outlines to 2 lines and 1 fill.

### Delete alongside it
- `EditorBottomChromeFade` (L1126–1147) — gone; the opaque bezel replaces it.
- `toolbarBackground` (L1486–1499) — gone (material, second fill, border, shadow all go with it).
- Scroll-away mic machinery: `scrollViewDidScroll`/`setMicVisible` (L569–588), the `isMicVisible` `@Binding` threaded through `ComposeNextDocumentEditor` (L239, L269) and its `@State` (L1034), plus the `opacity/scaleEffect/offset/animation` block (L1105–1109). A fixed bezel never covers text, so hide-on-scroll is dead weight. *(This is the one change that touches the editor's signature — everything else is local to `DocumentBody`.)*

---

## 3. De-chip the keys

Inside a bezel the keys don't each need a chip — the bezel is the container. Drop `deckKeyBackground` from `iconButton`/`spaceButton` and let the icons stand as plain glyphs; `CardPressStyle` already gives press feedback, which replaces the persistent outline as the affordance:

```swift
private func iconButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(theme.chrome.action)
            .frame(width: 34, height: 32)           // touch target, no fill/border
            .contentShape(Rectangle())
    }
    .buttonStyle(CardPressStyle())
    .accessibilityLabel(label)
}
```

Keep the mic filled — one filled control anchoring the row is good hierarchy — but **drop its drop-shadow** in idle (L1381–1387); shadows imply "floating," which is the opposite of a flush bezel. Keep the accent glow only in `.dictating` (it's a live-state signal, not chrome).

---

## 4. Revisions — "managed, not cluttered"

`RevisionHistoryRollup` (L1959) currently stacks three bordered zones below the card: the **chip row** (each version = a bordered card, L2016), the **size segmented control** (`RevisionPreviewModeControl`, its own bordered widget, L2106), and the **preview card** (`RevisionDiffPreview`, a bordered card wrapping two more tinted `RevisionTextPane`s, L2233). That's borders three deep for one feature.

Three targeted cuts, cheapest first:

1. **Borderless version chips → tabs.** In the `ForEach` chip (L2016–2026) drop the `RoundedRectangle` fill+border; signal selection with the accent `v#` label + weight (it already recolors on select, L2002). The row then reads as tabs, not a shelf of cards. Removes up to 10 borders in one edit.

2. **Un-wrap the diff preview.** The two `RevisionTextPane`s already carry their own tinted before/after fills (L2266–2270) — they don't need the outer card border. Drop the wrapping `RoundedRectangle` on `RevisionDiffPreview` (L2233–2241); let the tinted panes sit directly on the page with the header row and provider line above/below. One border layer gone; before/after still clearly delineated by their red/accent tints.

3. **Tame the size control.** `RevisionPreviewModeControl` is the "revision size control" Arach flags. Two options, in order of preference:
   - Make it **borderless** — three inline icon toggles (accent for active, `Color.clear` bg), drop the wrapping rounded-rect (L2106–2114). It stops reading as a separate widget in the section header.
   - Or make it **contextual** — only render it inside the selected preview's header (next to Restore), not in the top `· REVISIONS` strip, so the header is just label + `CURRENT v#`.

Keep the tinted before/after pattern itself — it's the right idiom and matches `DiffInline`'s `DiffTextPane` (L1561). The problem was never the panes; it was the cards around them.

---

## 5. Code-level gotchas

- **`contentBottomInset: 92` (L1063).** Sized to clear the *floating* pill. With a structural bezel the scroll region ends at the divider, so 92 leaves a dead gap — drop it to ~12–16 (enough that the last line isn't jammed against the hairline). Don't leave it at 92.
- **Clip vs. caret.** `.clipShape` on the card is required for the bezel to inherit the bottom corners. Safe here because text is inset 14pt horizontally, so the clip never touches the caret or selection handles. Verify the UITextView scroll indicator doesn't get clipped oddly at the very bottom corner (usually fine).
- **Don't double-darken.** If you keep *any* fade for taste, don't also make the bezel opaque `cardBackground` — you'll get a visible darker band where they overlap. It's one or the other; the recommendation is opaque bezel, no fade.
- **`layoutPriority(1)` + trailing `Spacer` (L1070, L1089).** Both are workarounds for the editor sharing height with a `Spacer` inside the old ZStack/VStack. Converting to a clean `VStack { content; divider; bezel }` gives the bezel intrinsic height and the editor `maxHeight: .infinity` — you can delete the `Spacer(minLength: 0)` and the `layoutPriority` hack. Simplification, not just cosmetics.
- **State gating.** Keep the bezel gated to `.idle`/`.dictating` (as the floating tools are now, L1097). In `.diff`/`.generating`/`.listening` the card should have clean bottom corners with no bezel — the VStack simply omits the divider+bezel branch, which is already how the `if` reads.
- **Mic ↔ cursor-pad alignment.** The mic is ZStack-centered specifically to line up with the `ActionTray` cursor pad below (comment at L1405–1408, pad at L2601). Preserve the ZStack centering when you strip the background — don't switch to an HStack-with-Spacers layout or it drifts left again.
- **Material removal is a real win, not a regression.** `.ultraThinMaterial` (L1489) blurs whatever is *behind* the view; nothing scrolls behind the card, so it never blurred anything — it only tinted. Removing it loses no depth cue.

---

## 6. Before / after (bottom-of-card outline count)

| | Idle bezel | Revisions block |
|---|---|---|
| Now | card + fade + shadowed material pill + 7 key borders + mic border | chip cards (×N) + segmented control + preview card + 2 pane fills |
| After | card + 1 hairline + 1 filled mic | borderless tabs + 2 tinted panes + minimal size toggle |

The through-line: **decide which elements are containers (get a border) and which are contents (fill/spacing/typography only).** Right now almost every subview draws its own `strokeBorder(edgeFaint)`; the fix is one border per zone — card, and tinted diff panes — and nothing nested inside earns another.

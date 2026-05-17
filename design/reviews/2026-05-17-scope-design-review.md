# Talkie — Scope theme design review

**Date:** 2026-05-17
**Reviewer:** preframe-mira (Claude vision)
**Source:** `/Users/art/dev/talkie/design/screenshots/2026-05-17/` (13 screens, 01 skipped)
**Theme commits:** `cb80b72` (Scope: Library + Stats), `9fb75b0` (Scope theme: cream-paper oscilloscope aesthetic)
**Intent:** tight design memo. Not a code patch. Operator triages before any SwiftUI changes.

> **Vocabulary:** I refer to the section-label style of `• CONTENT` / `• DETAILS` / `• QUICK COMMANDS` (lowercase amber smallcaps with a leading bullet) as the **"channel label"** — it is the strongest brand signal in the system after the brass palette. Same for the **`T01` / `A01`** badges on `13-memo-detail-actions`: I call these **"channel badges."** Both should be promoted to first-class type primitives.

---

## 02 — `library-memos-scope-view`

**Works.** Amber pill on the Memos tab is the right hit of accent. Mono titles + cream rows feel editorial without being precious. `3/3` counter top-right is a quiet, on-brand status.

**Off.** ~55% of the screen is white void below the third row, with the search bar marooned at the bottom. All three rows show `232 KB` — looks like seed data, but at thumbnail scale it reads as visual noise that the eye treats as content. Row leading-icon (mic) is the same for all three rows, so it carries no information.

**Moves (ranked):**
1. **Fill the void with the oscilloscope.** A faint cream-paper grid or a single horizontal hairline baseline below the last row turns "empty list" into "the chassis." This is the highest-leverage move in the entire app.
2. **Make the leading icon variant by source** — waveform for dictation, ⌘ for keyboard, link for clipped item. Eliminates the redundant-mic problem.
3. **Inline a transcript preview line** (1 line, secondary color) below each title. Doubles row information density without adding rows.
4. **Anchor the search bar with a hairline above it** so it stops feeling marooned.

---

## 03 — `capture-list-items`

**Works.** Tab affordance is unambiguous — Items selected, others recede. `Text` and `Link` type labels are a good idea.

**Off.** Type labels are gray and weak. If amber is the accent system, `Text` and `Link` are exactly the moments amber should appear. Also: two items + huge void. Same problem as 02, worse because there are fewer rows.

**Moves (ranked):**
1. **Promote type labels to amber channel badges** (e.g. `· TEXT`, `· LINK`) — they become the row's identity, not metadata.
2. **Section grouping** (`· TODAY`, `· THIS WEEK`) as channel labels between rows. Cheap structural fill.
3. **Type tag could become tiny brass corner mark** on the leading icon tile rather than a separate metadata line.
4. **Empty-state hint at bottom of the void** ("nothing else clipped today") in mono, low-contrast.

---

## 04 — `capture-detail`

**Works.** Channel labels (`• CONTENT`, `• DETAILS`) are the cleanest expression of the system; right-aligned details create a natural two-column read. Compose / Ask paired tiles are restrained. Amber "Retry" pulls the eye correctly to a stale sync state.

**Off.** The `On-device voice` play row is a plain gray bar — completely generic. This is the single most ironic miss in the app: a voice product with an audio scrubber that has no waveform, no brass, no oscilloscope. Also: the `Mac Sync — Retry` row mixes warning state into otherwise neutral details, tonally jarring.

**Moves (ranked):**
1. **Audio scrubber gets the oscilloscope trace.** A horizontal brass scanline over cream paper, with a vertical playhead. This is THE place to put the brand identity to work.
2. **Hoist sync status out of `• DETAILS`** into its own row above the action tiles, with a status chip. Keep `• DETAILS` neutral.
3. **Compose / Ask tiles get a brass corner detail** (1px L-shape, same hue as section dots) so they read as instruments, not buttons.
4. **`• CONTENT` body in a slightly warmer cream than the page** so the captured text reads as paper-on-paper.

---

## 05 — `ai-commands-sheet`

**Works.** Chip row of Quick Commands (Two Key Points / Summarize / Explain / Relate) is the right pattern. `• QUICK COMMANDS` channel label is consistent.

**Off.** The `API ▾` model picker is centered alone — feels orphaned. Send-arrow button is faint gray; when the input is empty that's fine, but at first encounter it reads as broken. The rightmost chip is cut off with no scroll affordance (no gradient fade, no dot row).

**Moves (ranked):**
1. **Send button takes amber fill when the input is non-empty.** Default state can stay gray. This is a one-state change with big perceived-affordance return.
2. **Model picker becomes a small chip-row member, left-aligned**, sibling to Quick Commands. Removes the orphan.
3. **Horizontal scroll affordance** on Quick Commands: either a 12px brass fade on the right edge, or a tiny `· ·` dot pair indicating more.
4. **`Speak when ready` toggle row** could use the same channel-label treatment above it for parity (`• AFTER COMMAND`) rather than a bare row.

---

## 06 — `capture-shortcuts-launcher`

**Works.** Record Memo as the hero tile (red mic) is the right hierarchy. 2×2 grid of secondary actions is fine.

**Off.** The four secondary tile icons (Dictation orange, Capture blue, Scan Handwriting green, Scan QR teal) are the **single biggest palette violation** in the app. They're rainbow iOS icons in a brass-and-cream world. Also `ON THIS IPHONE` lacks the leading-dot bullet — breaks channel-label consistency.

**Moves (ranked):**
1. **Re-skin tile icons to monochrome brass on neutral fill.** Differentiate by glyph shape, not hue. This single change makes the launcher look intentional instead of inherited from a different app.
2. **Add the leading-dot bullet** to `· ON THIS IPHONE`.
3. **Record Memo tile carries a thin amber waveform texture** behind the mic — quietly previews what tapping does.
4. **Add a third row or footer** (`· FROM OTHER APPS`, share-extension hint) to anchor the bottom and earn the height.

---

## 07 — `capture-compose-new-capture`

**Works.** Textarea-first is correct. Cancel/Save header is conventional and readable. `Or Import From` is a sensible secondary surface.

**Off.** The dictate mic inside the textarea is a small dim circle dead center — it doesn't communicate "tap to dictate," and it competes with the empty textarea's hint text. Import tiles use generic gray system icons (camera, photos, compass) — no amber, no oscilloscope. `OR IMPORT FROM` again missing the leading-dot.

**Moves (ranked):**
1. **Mic gets a small brass ring + subtle pulse** so the primary "dictate now" affordance reads as primary.
2. **Import-tile icons re-skinned** to single-weight brass strokes; keep the gray background tile.
3. **`· OR IMPORT FROM`** with the leading-dot bullet for consistency.
4. **Footer hairline + a "recent capture" peek** below the import tiles uses the void without forcing the user to scroll.

---

## 08 — `settings-main`

**Works.** Section labels (`• ACCOUNT`, `• APPEARANCE`, `• KEYBOARD & DICTATION`, `• COMPANION`, `• AI & VOICE`) carry the system. Right-aligned state annotations (`No Mac`, `Inactive`, `Needs setup`) are scannable. The amber "Needs setup" dot is a good unified warning signal.

**Off.** The top filter chips (`AI / Companion / Dictation / Recording`) read as Twitter-era pills inside an otherwise oscilloscope-disciplined app. Inline segmented control inside the Appearance row (light/dark/system, three small pills) is too compressed to read. The Companion description block is dense.

**Moves (ranked):**
1. **Filter chips → thin amber underline tab nav** matching the Library tabs. Single navigation grammar across the app.
2. **Pull the inline mode-segment out of the Appearance row** — let Appearance be a tappable row that reveals the expanded picker (which is exactly what 09 already does). Currently both states are shown, which is redundant.
3. **Unify state annotations as small status chips** (`· NEEDS SETUP`, `· INACTIVE`, `· NO MAC`) using the channel-label vocabulary — they currently mix dots, plain text, and amber badges inconsistently.
4. **Pinned "Quick toggles" row at the top** (after the section nav) for the 2–3 settings users actually toggle.

---

## 09 — `theme-picker-appearance-expanded`

**Works.** Expanded Appearance pattern (big mode pills + descriptive theme rows) is the strongest interaction in the settings stack. Brass checkmark on `Scope` is the brand moment.

**Off.** Theme thumbnail tiles to the left of each row name are **almost invisible** — they look like blank cards. The whole purpose of the picker (visual differentiation between Midnight / Tactical / Ghost / Scope) is missing. Also: the NAME / DURATION list of memos visible at the bottom looks like the next section bleeding through the scroll — visually it reads as broken layout, even if it's intentional content below the picker. The three mode pills at top (System / Light / Dark) look like a single cluster but selection state is unclear at thumbnail size.

**Moves (ranked):**
1. **Theme thumbnails carry an actual mini-render** of the theme — Scope = cream paper with brass smallcap, Midnight = near-black with one accent, Tactical = high-contrast pair, Ghost = soft mute. This screen exists specifically for users to see these differences.
2. **Selected theme row gets a faint cream-paper tint behind it**, not just the brass check. Reinforces the relationship.
3. **Mode pill selected state** needs a stronger border or amber underline so System vs Light vs Dark is unambiguous at-a-glance.
4. **Whatever is at the bottom of the scroll** (NAME / DURATION memos) needs more vertical separation from the picker — at minimum a section break / channel label, ideally pushed off-screen until scrolled.

---

## 10 — `keyboard-settings`

**Works.** The cleanest screen in the app. Section structure (`• SETUP INSTRUCTIONS`, `• PREFERENCES`, `• CUSTOMIZE`, `• TESTING`) is exemplary; if this grammar were applied to 06 and 08, the app would feel 30% more unified.

**Off.** The `Keyboard Off` status pill at top is the only chrome that tells the user the keyboard isn't enabled — it should carry more weight. Preference-row icons (light-bulb, hand, `Aa`, grid) are mixed weights (some line, some filled).

**Moves (ranked):**
1. **`Keyboard Off` pill embeds a live status LED** (small filled dot matching the LED Indicators preference). Becomes a visual cue, not a label.
2. **Standardize preference-row icons to single weight** (thin line, brass-on-neutral) so the column reads as a calibrated stack of instruments.
3. **`Open Settings` external-link icon** picks up a brass tint to signal it leaves the app.
4. **Thin amber hairline above `• TESTING`** to separate "what the keyboard is" from "let me try it."

---

## 11 — `keyboard-configurator-customize-slots`

**Works.** This is the **most oscilloscope-native screen in the app.** Black command bar at top (with mode tabs `· SHORT · 123 · #+= · 😀 · MIN`), black keyboard footer (`COPY · PASTE · DICTATE · SPACE · ENTER`), cream paper middle. The mode-tab dot prefix matches the channel-label vocabulary perfectly. If a designer ever asks "what is Talkie's voice," screenshot this header.

**Off.** The middle of the screen is **completely empty.** The instruction (`· TAP A SLOT TO CONFIGURE` + "Select any key below to customize what it does") points at nothing — there's no slot UI visible until you tap the footer keys. The user has to figure out that the entire bottom black bar is the configurable surface. The back chevron floats unmoored top-left without a sibling.

**Moves (ranked):**
1. **Mirror the keyboard layout in the middle of the screen** — disabled-state preview of the slots, so the user sees what they're about to configure before they tap. Even non-interactive, this resolves the "tap what?" confusion.
2. **Oscilloscope paper grid** in the empty cream area. Same fix as 02, even more justified here since the screen is literally a chassis.
3. **A small finger-tap animation or static glyph** between the instructions and the keyboard footer connecting the two visually.
4. **Back chevron** lives in a corner cluster (back + screen title), or move screen title left next to it. Currently the title is centered which orphans the back affordance.

---

## 12 — `compose-type-editor`

**Works.** The header `COMPOSE WITH ✦ Choose model ▾` with the brass sparkle is a strong identity moment. Textarea-first is correct.

**Off.** `Choose model` placeholder is gray-italic — it reads as disabled / unset on first scan, not as "pick one." The arrow-pad in the middle of the bottom action bar (a 4-arrow diamond inside a circle) is genuinely cryptic; without a label or context it could be cursor nav, joystick, anything. Mic at the bottom of the textarea is a plain circle.

**Moves (ranked):**
1. **Pre-select a default model and show its name** (`Claude Sonnet 4.6 ▾`) instead of the gray placeholder. The dropdown still works; the empty state just doesn't read as broken.
2. **Label the arrow-pad** with a tiny mono caption (`· NAV` or `· CURSOR`) — same channel-label vocabulary.
3. **Mic button picks up brass tint** when the textarea has focus and is empty (the moment dictation is the highest-leverage action).
4. **Inside the empty textarea, a 2-line low-contrast hint** that distinguishes Compose from Dictate ("write or paste — then run any model").

---

## 13 — `memo-detail-actions`

**Works.** **The brand signature lives here.** The `T01 · TRANSCRIPT` badge and `A01 · ACTIONS` channel header are the strongest typographic moment in the app — terminal/oscilloscope channels in miniature. Brass play button on the audio row is on-message. The chip row (`Read / Ask / Note / Share / Remi…`) is well-paced.

**Off.** The two AGENT and CLI tiles dominate the lower half of the screen **while disabled** — they're the largest UI elements on the screen and they do nothing. The `DELETE MEMO` button is a soft-pink fill that breaks the brass-amber palette discipline (this is the second palette breach in the app, after 06's rainbow icons). Chip-row glyphs are mixed weights/fills.

**Moves (ranked):**
1. **Collapse disabled AGENT / CLI tiles into a single compact "PAIR MAC TO UNLOCK" card** when no Mac is paired. Restore the screen real estate to the transcript. Promote the tiles back to full-size only after pairing.
2. **`DELETE MEMO` becomes a brass-outlined row** with a small warning glyph, OR moves into an overflow `· · ·` menu. Lose the pink — it's the wrong palette entirely.
3. **Standardize chip-row icons** to single-weight strokes (line, not filled).
4. **Channel badges become a first-class type primitive.** `T01` / `A01` should appear elsewhere — e.g. `· C01 CAPTURE` on the capture detail screen — making this typographic move a system, not a one-off.

---

## 14 — `recording-capture-sheet`

**Works.** **This is the showcase screen.** `· STATION` card with "5 signals on deck." copy is gorgeous. The `· LIVE · ACTION BUS` dark-tile dashboard (MEMOS 3 · TYPE 0 · GRAB 2 on dark cream with amber labels) is the brand at full strength. Bottom recording sheet with brass stop button is iconic. `· RECENT · 5` section header pattern is consistent.

**Off.** The "waveform" inside the recording sheet is a field of **scattered dots / sparkle** — random, decorative. For a voice product, on the recording screen, this should be an actual oscilloscope trace. It's the most important place in the entire app for the oscilloscope motif to be literal, and it's the only place where the motif fails. Also: the `DETAILS` expandable card is plain gray body text — generic relative to the Action Bus tile above it. `ESC` and `· REC` at top of the sheet are tiny and could carry more weight.

**Moves (ranked):**
1. **Replace the dot-sparkle with a real oscilloscope line.** Horizontal scanline trace, brass on cream, animated to actual audio amplitude. Single highest-impact visual change in the app.
2. **`DETAILS` card adopts the dark-tile / amber-label treatment** of the Action Bus above it. Consistent voice in the recording flow.
3. **Active-recording accent on screen edge** — a thin 1px amber pulse running around the visible safe area while recording. Currently nothing tells you "you are recording" except the timer and stop button.
4. **`ESC` pill becomes more affordant** — currently passive text. Either tappable-styled pill or `· ESC` with the channel-label dot.

---

# Top-5 cross-cutting opportunities

1. **Make the oscilloscope visible, not just named.** The aesthetic exists in palette and copy but rarely in geometry. Concrete moves: (a) faint cream-paper grid behind hero screens, (b) hairline horizontal rules at section breaks, (c) a real oscilloscope trace on the recording sheet (`14`) and audio scrubber (`04`), (d) a scanline-style baseline behind list voids (`02`, `03`, `11`). All low-cost, all multiplicative.

2. **Burn the palette breaches.** Two non-brand colors are loud right now: the multi-color tile icons on `06-shortcuts-launcher`, and the pink `DELETE MEMO` on `13-memo-detail-actions`. Reduce to **one accent (brass amber) + one warning (rust orange) + neutrals**. No greens, blues, teals, pinks anywhere — let the cream paper do the chromatic work.

3. **Promote the channel-label and channel-badge vocabulary to a typographic system.** The `· CONTENT` / `· DETAILS` smallcaps style and the `T01` / `A01` badges are the strongest brand signals in the app and they're applied inconsistently. Codify: every section label uses leading-dot smallcaps amber; every list-counter or status chip can use a channel badge. Apply ruthlessly to 06's `ON THIS IPHONE`, 08's filter chips, 09's `NAME / DURATION`, 13's chip-row labels.

4. **Solve the vertical-void problem.** Screens 02, 03, 07, 11, 12 leave huge cream voids that read as "the app has nothing." The oscilloscope motif gives a legitimate way to fill the void without adding noise: faint grids, baselines, paper grain. This is also the cheapest perceived-quality lift available — no new screens, no new flows, just a treatment pass over empty regions.

5. **Disabled and empty states are a design surface, not a default.** The biggest UI on `13-memo-detail-actions` (AGENT/CLI tiles when no Mac) is dead pixels at thumbnail scale. The recording sheet (`14`) has no "you are recording" environmental cue. The launcher (`06`) has no recents. Each of these is an opportunity to either compact aggressively (collapse disabled tiles into a single pair-mac card) or to use the surface for the next-best action. Treat empty/disabled as a deliberate layout state with its own design, not as the default state with a gray overlay.

---

# Triage recommendation

If forced to pick three moves that ship this sprint:

1. **Audio scrubber + recording-sheet oscilloscope trace** (`04`, `14`). Highest brand return, contained scope.
2. **Channel-label / channel-badge codification pass** across the app. Cheap, zero-risk, multiplicative — fixes 06, 08, 09, 13 in one pass.
3. **Theme thumbnail render fix** (`09`). The expanded theme picker is currently shipping with the thumbnails essentially blank; one of its main jobs (let me see what Scope looks like vs Midnight) is broken.

Everything else can wait for the next pass without the app feeling stale.

# TLK-034 — Deck-owned channel creation + lane assignment without pins

**Status:** implemented; signed build installed and launched on device
**Date:** 2026-07-29
**Reviewer:** session-ms6gq6m3-kw07yr
**Studio**: /eng/tlk-034
**Approved composition:** `design/screenshots/tlk-034-new-task-signal-path.png`
**Supersedes:** `docs/specs/tlk-034-lane-pin-row-layout-review.md` — that review reached the right
layout conclusions (socket 13, project-first sheet, one trailing control) but kept **pin**
vocabulary throughout (`Pin 4`, "Pin to lane", `pin.fill`). Pin is the wrong metaphor and this
document replaces that vocabulary everywhere. Every other conclusion in the prior doc still holds.

**Scope guard:** no broad redesign. The paper/graphite/cream instrument language, the 16-key keybed
grid, and the six-lane model are all preserved. Everything below either fills a socket the deck
already reserved, moves an existing view, or renames existing strings.

---

## 0. The two defects, stated precisely

**Defect A — job conflation.** Creating a channel is a *project-first* act that produces a new
channel. Browsing and binding is a *lane-first* act that consumes existing channels. Today creation
is a `+` in the mapper's `.topBarLeading` toolbar (`CodexLaneMapperView.swift:36-40`) opening a
nested sheet whose `onCreated` closure calls `dismiss()` on the mapper too
(`CodexLaneMapperView.swift:53-58`). So "create" silently closes the browser you were in. The
create path is also buried two navigation levels below the surface the user actually operates.

**Defect B — wrong metaphor.** `pin` / `pin.fill` (`CodexLaneMapperView.swift:288`) and the strip
header "Pin to lane" (`:65`) describe *favoriting* — keep this at the top, mark this important. A
lane is none of that: it is one of six numbered hardware slots, and binding is **assignment** —
"put this channel in slot 4". The user reading pin as "keep at top" is reading it correctly; the
icon is lying.

The screenshot makes Defect B's cost concrete. The row *Diagnose request send error* shows an amber
`Lane 5` capsule in its title cluster **and** an outline (unfilled) pin in the trailing rail,
because the pin fills only when `boundLane == targetLane` and the target is 4. The row reads as
simultaneously bound and unbound. That is duplicated state with two different meanings rendered as
one visual contradiction.

---

## 1. Command Deck button — exact placement, label, icon

### Placement

`CodexCommandDeckSurface.swift:208-214`, keybed row 4:

```swift
GridRow {
    openSocket(index: 13)      // ← becomes the NEW key
    captureKey
        .gridCellColumns(2)    // keys 14–15, HOLD TO TALK
    openSocket(index: 16)      // ← stays an open socket
}
.frame(height: 78)
```

Replace `openSocket(index: 13)` with a real keycap. Use the existing factory unchanged:

```swift
actionKey(
    index: 13,
    label: "New Task",
    icon: "square.badge.plus",
    isEnabled: store.canCreateChannel && !store.isCreatingTask,
    isActive: showingNewTask,
    isEmphasized: true,
    action: { showingNewTask = true }
)
```

**Why 13 and not a toolbar, FAB, or header button:**

- It is the deck's own reserved real estate. Socket 13 is already drawn as an empty keycap in the
  instrument grammar, so the create affordance costs **zero new chrome** — the constraint that
  matters most here.
- Row 4 is the bottom row, the thumb row. 13 sits immediately left of the two-column
  `HOLD TO TALK` key, so the hand path is literally `NEW → TALK`: create a channel, then speak into
  it without moving.
- Key indices ascend left-to-right, so 13 (create) precedes 14–15 (speak). The numbering already
  encodes the temporal order of the flow.
- Row 4 keys are 78pt tall — the tallest in the bed. "Prominent" is satisfied by physical size and
  position rather than by adding a floating button that would break the instrument metaphor.

If right-thumb reach beats reading order in device testing, socket 16 is the only acceptable
alternative. **Do not fill both** — an empty socket is part of this deck's visual language, and
filling 16 purely for symmetry adds an action nobody asked for.

### Icon rationale

`square.badge.plus` — one rectangle with a plus badge. This is internally consistent with the
Mapper key at index 2, which uses `rectangle.3.group`: **rectangles mean channels** on this deck.
Three rectangles = browse many; one rectangle with a plus = make one. It also stays legible at the
factory's 12pt `.medium` weight inside a 25pt circle, which compound glyphs like
`plus.rectangle.on.folder` do not.

Label is `"New Task"`; the persistent accent treatment distinguishes it from utility keys while its
socket, keycap form, and typography keep it inside the Command Deck's instrument language.

### Sheet ownership

The deck owns the state and the presentation, alongside its existing `showingMapper` /
`showingHistory` / `showingStatus`:

```swift
@State private var showingNewTask = false
...
.sheet(isPresented: $showingNewTask) {
    CodexNewChannelSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
}
```

The mapper never presents creation again.

### Enablement gate

`createTask` already rejects a project whose `hostID != loadedHostID`
(`CodexLaneStore.swift:285-291`), but `loadedHostID` is `private` and unpublished
(`CodexLaneStore.swift:77`), so the key cannot read it. Add:

```swift
@Published private(set) var canCreateChannel = false   // set wherever loadedHostID is assigned
```

set in the initializer (`:88`) and the host-change path (`:184`). Without this the NEW key is
always live and a tap on an unpaired phone dead-ends inside the sheet.

### Two more entry points that must change with it

1. **Console empty state.** `CodexCommandDeckSurface.swift:1164` reads
   `"Open Mapper to choose an exact Codex channel."` — on a fresh install there is nothing to
   choose. Make it offer both paths: `"Create a channel, or open Mapper to choose an existing one."`
   with the two words as buttons. Same for `:1174`-era copy
   `"Pick a lane above, or open Mapper to choose an exact channel."`
2. **Accessibility-size variant.** `accessibilityLaneTransport`
   (`CodexCommandDeckSurface.swift:1504`) exposes a `Label("Map", systemImage: "rectangle.3.group")`
   button. It needs a `Label("New", systemImage: "square.badge.plus")` peer, or creation vanishes
   entirely at accessibility text sizes.

---

## 2. Creation sheet — hierarchy and interaction

### Approved visual direction — Signal Path

The creation sheet extends the Command Deck's instrument language with a compact
three-stage rail: **PROJECT → TASK → TALK**. PROJECT is lit while the user makes
the only decision. Creation advances the signal to TASK, then TALK, and the
sheet dismisses onto the newly selected task underneath.

Keep the project list flat and grouped. Selection is one amber leading trace
plus a checkmark, not a new card or a second summary panel. The generated study
is a hierarchy reference, not a pixel specification: use native SwiftUI
typography and controls, keep Default model to one quiet footer line, and do not
duplicate the selected project above the bottom action.

Extract `CodexNewTaskView` out of `CodexLaneMapperView.swift:300-407` into its own file,
`apps/ios/Talkie iOS/Codex/CodexNewTaskView.swift`. It takes no `onCreated` closure;
it dismisses itself.

### Hierarchy, top to bottom

```
┌─ Cancel ──────── New Codex Task ─────────────── ┐   inline title, .cancellationAction only
│                                                  │
│  IN YOUR LANES                                   │   ← hero. projects already on lanes,
│    talkie              ~/dev/talkie        ①③    │      trailing lane numerals
│    openscout           ~/dev/openscout       ②   │
│                                                  │
│  RECENT                                          │   ← remaining catalog projects,
│    arach.dev           ~/dev/arach.dev           │      most-recent first
│    grab                ~/dev/grab           ✓    │
│    …                                             │
│                                                  │
│  MODEL — DEFAULT                                 │   ← demoted footer band, not a section
│  Uses the Codex model and execution settings     │      header, not first
│  configured on your Mac.                         │
│                                                  │
├──────────────────────────────────────────────────┤
│        Create Task in grab                       │   ← safeAreaInset bottom bar,
└──────────────────────────────────────────────────┘      appears only once a project is picked
```

**The single most important change is the ordering.** Today the list opens with
`Section("Configuration")` containing `LabeledContent("Model", value: "Default")`
(`CodexLaneMapperView.swift:312-317`) — a read-only row the user cannot act on, occupying the
position of maximum attention, above the only decision they actually make. The constraint is
"default model only," so the model line is a *reassurance*, not a control. Reassurances go at the
bottom, in caption weight, after the choice.

### Row content

Both sections already derive from `store.projects` → `deriveProjects` (`CodexLaneStore.swift:320`),
which puts lane tasks first and dedupes by `canonicalWorkingDirectory`. Keep that. Per row:

- Project name — `.body.weight(.medium)`, primary ink.
- Path — caption, tertiary ink, `.lineLimit(1)`, `.truncationMode(.middle)`. Render `~`-relative,
  not the raw absolute `cwd` the current code shows (`:388`). Add a `compactPath` computed property
  to `CodexProjectSummary` mirroring `CodexTaskSummary.compactPath` (`CodexLane.swift:79-86`).
- Trailing: lane numerals for projects in the "In Your Lanes" group; a `checkmark.circle.fill` in
  accent when selected.
- Whole row `.contentShape(.rect)`, `.buttonStyle(.plain)`.

### Interaction

**Selection commits nothing.** Tapping a row selects it; `Create` is a separate, explicit act.
Creating spawns a real task on the Mac and there is no undo, so one-tap-creates-immediately is the
wrong trade even though it is faster.

**Primary CTA is a bottom bar, not the toolbar.**

```swift
.safeAreaInset(edge: .bottom) {
    if let project = selectedProject {
        Button { create(project) } label: {
            Text(store.isCreatingTask ? "Creating…" : "Create Task in \(project.name)")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isCreatingTask)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

Naming the destination in the button — *Create Task in grab* — is what makes this a purpose-built
flow rather than a generic form. It also puts the commit under the thumb, consistent with the deck.
Tradeoff worth stating: `.confirmationAction` in the toolbar is the more conventional HIG slot.
The bottom bar wins here because the destination name does not fit in a toolbar button, and because
the sheet has exactly one action. **Do not ship both** — two Create buttons is worse than either.

**Catalog lifecycle — this is a real bug introduced by moving the entry point.** `catalog` is only
kept fresh by `beginCatalogUpdates()`, and today the mapper is its *only* caller
(`CodexLaneMapperView.swift:49/51`). Launched from the deck, the sheet would show lane projects
only — and nothing at all on a fresh install, since `deriveProjects` returns `[]` without a host.
The sheet must drive its own lifecycle:

```swift
.task { store.beginCatalogUpdates() }
.onDisappear { store.endCatalogUpdates() }
```

**States:**

| State | Presentation |
|---|---|
| Loading, no projects yet | centered `ProgressView`, not an empty list |
| Loaded, no projects | `"No projects yet. Open a folder in Codex on your Mac first."` |
| Creating | bottom bar shows `Creating…` + spinner; list `.disabled(true)`; **Cancel also disabled** — an in-flight create cannot be recalled |
| Create failed | sheet stays open, selection preserved, error in the footer band slot |

Replace the current full-screen `ProgressView("Creating task…")` material overlay
(`CodexLaneMapperView.swift:355-361`): it covers the project the user just chose at the exact
moment they want that choice confirmed.

**Search:** attach `.searchable` with **local** `@State` when `store.projects.count` exceeds one
screen. Do **not** reuse `store.searchQuery` (`CodexLaneStore.swift:66`) — it is the mapper's
filter, and typing in the sheet would silently re-filter the mapper behind it.

**Idempotency:** keep `creationID = UUID()` regenerated `.onChange(of: selectedProjectID)`
(`:363-365`). It is the create request's idempotency key and the current behavior is correct.

**Failure channel:** `createTask` writes failures into `catalogFailure`
(`CodexLaneStore.swift:306`), the same property the mapper's catalog fetch uses. Consequences: a
stale catalog error renders in the sheet as though creation failed, and a creation error persists
into the mapper. Add a separate `@Published private(set) var creationFailure: CodexLaneFailure?`.

---

## 3. Transition sequence after Create

The store already does the right thing, which makes the transition almost free:
`createTask` merges the new task into `catalog` and calls `selectChannel(task)`
(`CodexLaneStore.swift:301-302`) **before** returning. So the deck updates *underneath* the sheet,
and the sheet slides away to reveal an already-correct deck. No navigation, no push, no reload.

Exact sequence:

1. **Tap Create** → `UIImpactFeedbackGenerator(style: .light)`. Bottom bar label swaps to
   `Creating…` with an inline spinner. List disables. Cancel disables.
2. **`await store.createTask(in:creationID:)`.** On success: catalog merged, `selectedChannel` =
   new task, `activeLaneNumber` = `nil` (it has no lane).
3. **`.sensoryFeedback(.success, trigger:)`**, then `dismiss()`. **Only this sheet.** The mapper is
   not in the stack anymore — this is what removing the nesting buys.
4. **Deck reveal.** The console identity line already shows the new title. Animate it in with
   `.animation(.spring(response: 0.32, dampingFraction: 0.74), value: store.selectedTask?.id)` —
   the same spring the deck already uses for `outputRoute` at `:394`, so the motion vocabulary
   stays consistent. The console foot line already reads `HOLD TALK TO SPEAK INTO THIS TASK`
   because `selectedTask != nil` (`:1178`). Nothing to change there.
5. **Close the honesty gap.** The new channel has no lane, so the lane spine lights nothing — which
   currently reads as "nothing is selected," directly contradicting the console. Add a `NO LANE`
   micro-chip to the console identity row whenever `selectedTask != nil && activeLaneNumber == nil`,
   in the same 9pt monospaced style as the other console micro-labels, tappable to open the mapper
   with `targetLane` pre-set to the first free lane. This names the state instead of leaving a
   blank, and offers the natural next step without forcing it.
6. **Do not auto-assign a lane.** Assigning the new channel to the first free lane — or worse,
   evicting an existing binding — would make creation destructive to state the user configured by
   hand. Creation produces a *selected, laneless* channel. That is the correct and already-implemented
   semantic; keep it.
7. **On failure:** stay in the sheet, keep the selection, render `creationFailure` inline. Never
   dismiss on failure — dismissing would return the user to the deck with no channel and no
   explanation.
8. **On cancel:** no state change. `selectedChannel` is untouched.

Optional flourish: `matchedGeometryEffect` from the chosen project row to the console identity line.
It reads beautifully when it works and is fragile across a sheet boundary. Ship the spring first.

---

## 4. Mapper row interaction and wording — no pins

### Vocabulary

The verb is **assign**. The state is **assigned**. Changing it is **move**. Removing it is **clear**.
The noun is **lane**. There is no pin, no star, no favorite, no bookmark anywhere in this surface.

### The control is a lane chip, not an icon

Replace the pin glyph with the **numeral itself**, in the same rounded-rect chip already used by
the lane strip (`CodexLaneMapperView.swift:117-145`). This removes the metaphor entirely rather than
swapping one metaphor for another: you are putting this channel into numbered slot N, and the
control shows the number of the slot.

One 44×44 trailing button per row, three states:

| State | Chip | Action | Accessibility label |
|---|---|---|---|
| Not assigned to any lane | outlined, target numeral, tertiary ink | `assign(task, to: targetLane)` | `"Assign to lane 4"` |
| Assigned to the target lane | filled **accent**, target numeral | `clearLane(targetLane)` | `"Assigned to lane 4. Double tap to clear."` |
| Assigned to another lane N | filled **neutral**, numeral N | `assign(task, to: targetLane)` (move) | `"Assigned to lane 5. Double tap to move to lane 4."` |

Accent vs. neutral fill is the whole disambiguation: accent means "this row satisfies the lane you
are currently filling," neutral means "bound, but elsewhere." Both are unambiguously *bound*, which
the pin could never express.

**Delete the `Lane N` capsule from the title cluster** (`:223-232`). The chip is now the single
source of that truth. This is what resolves the screenshot's contradiction — there is exactly one
place binding state is rendered, and it cannot disagree with itself. It also returns horizontal
space to the title, project, branch, and path, all of which currently truncate.

### Row body

The whole left region stays one button → `selectChannel(task); dismiss()` (`:210-213`). It is
currently missing an accessibility label entirely, so VoiceOver reads the concatenated subviews:

```swift
.accessibilityLabel("\(task.title), \(task.projectName)")
.accessibilityHint("Selects this channel")
.accessibilityAddTraits(store.selectedTask?.id == task.id ? .isSelected : [])
```

Keep `Selected` in the title cluster. Selection and assignment are genuinely different axes and the
row must be able to show both.

### Strip and copy

| Location | Now | Becomes |
|---|---|---|
| `CodexLaneMapperView.swift:65` | `"Pin to lane"` | `"Assign to lane"` |
| `:101` | `"Lane 4 is empty — use Pin on a channel below."` | `"Lane 4 is empty. Tap 4 on any channel below to assign it."` |
| `:288` | `Image(systemName: "pin.fill" / "pin")` | lane-numeral chip (above) |
| `:295` | `"Pin \(task.title) to lane \(targetLane)"` | per the state table above |
| `:5` (file header) | `"optionally pins them to numbered lanes"` | `"optionally assigns them to numbered lanes"` |
| `CodexLaneBar.swift:234` | `"Unpinned"` | `"No lane"` |
| `CodexCommandDeckSurface.swift:1561` | `"Unpinned channel"` | `"Channel without a lane"` |
| `:1570` | `"Unpinned, \(projectName)"` | `"No lane, \(projectName)"` |
| `CodexLane.swift:137` | `isPinnedToLane` | `isAssignedToLane` |
| `CodexLane.swift:329` (doc) | `"has not been pinned"` | `"has not been assigned"` |
| `CodexLaneStore.swift:327` | `pinnedPaths` | `assignedPaths` |
| `:397` (doc) | `"without pinning"` | `"without assigning"` |

The new empty-state string names the exact gesture rather than an abstract affordance, which is the
part the old copy got wrong even before the metaphor problem.

**Leave `BridgeClient.swift` / `BridgeManager.swift` alone.** Their `encryptionPinned`,
`isEncryptionPinned`, `clearEncryptionPin` etc. are TLS/encryption pinning — correct, unrelated
usage of the word.

### Hit targets

Lane strip chips are `36×36` (`:126`), below the 44pt minimum. Grow the visual to 38 and wrap in a
44×44 `.contentShape(.rect)`. Add per-chip accessibility:
`"Lane 3, empty"` / `"Lane 3, Diagnose request send error"`, with `.isSelected` on the target.

### Target auto-advance

`assign` currently advances `targetLane` to the next free lane (`:284-286`). Keep it — it is the
fast path for filling a bed of six — but note the hazard: advancing renumbers the chip on *every
unassigned row at once*, under the user's finger. Make the change perceptible rather than silent:
`.contentTransition(.numericText())` on the chip numerals, plus an
`AccessibilityNotification.Announcement("Assigned to lane 4. Target is now lane 5.")`.

### Store correctness

`assign(_:to:)` (`CodexLaneStore.swift:347-360`) writes `lanes[number]` and never removes the same
`task.id` from other slots, while `boundLane` resolves with `.first` (`CodexLaneMapperView.swift:207`).
So a task can occupy two lanes while the row reports only the lower-numbered one. Clear any other
lane holding that `task.id` before writing.

## 5. Must-fix vs. optional polish

### Must-fix

| # | Change | Location |
|---|---|---|
| 1 | Delete the `New Task` toolbar item, `showingNewTask` state, and nested creation sheet | `CodexLaneMapperView.swift:18, 36-40, 53-58` |
| 2 | Add the NEW keycap at socket 13, deck-owned `showingNewTask` + `.sheet` | `CodexCommandDeckSurface.swift:209` |
| 3 | Extract `CodexNewTaskView.swift`; drive `beginCatalogUpdates`/`endCatalogUpdates` from it — otherwise deck-launched creation has no projects | new file |
| 4 | Invert sheet hierarchy: projects first, `Model — Default` demoted to a caption footer | `CodexLaneMapperView.swift:311-326` |
| 5 | Add `creationFailure` separate from `catalogFailure` | `CodexLaneStore.swift:65, 306` |
| 6 | Add `@Published canCreateChannel` so the NEW key can gate on a paired Mac | `CodexLaneStore.swift:77, 88, 184` |
| 7 | Remove `pin`/`pin.fill` and every user-facing Pin/Unpinned string per the table in §4 | mapper, deck, lane bar, model |
| 8 | Collapse duplicated binding state into one trailing lane chip with three states | `CodexLaneMapperView.swift:206-297` |
| 9 | Add accessibility label + hint to the row's primary select button | `CodexLaneMapperView.swift:210-280` |
| 10 | Lane chips to ≥44pt hit targets, with accessibility labels | `CodexLaneMapperView.swift:117-145` |
| 11 | `assign(_:to:)` must clear the same `task.id` from any other lane | `CodexLaneStore.swift:347-360` |
| 12 | Console `NO LANE` chip when a channel is selected with no lane (the post-create state) | `CodexCommandDeckSurface.swift:1178` region |
| 13 | Deck empty-state copy offers Create alongside Mapper | `CodexCommandDeckSurface.swift:1164` |
| 14 | Accessibility-size transport gets a `New` peer next to `Map` | `CodexCommandDeckSurface.swift:1504` |

Items 3, 5, 6, and 11 are correctness, not taste. 3 and 6 are regressions that moving the entry
point *introduces*; 5 and 11 are pre-existing.

### Optional polish

- Bottom `safeAreaInset` CTA reading `Create Task in <name>` (recommended over a toolbar Create, but
  a plain `.confirmationAction` ships correctly).
- `compactPath` on `CodexProjectSummary` so paths render `~`-relative.
- Local `.searchable` in the creation sheet once project lists exceed a screen.
- `.contentTransition(.numericText())` + VoiceOver announcement on target auto-advance.
- `.swipeActions(edge: .trailing)` — "Assign to 4" / "Clear" — as a second discoverable path.
- Rename internal store symbols `unpinnedInFlightRequestCount`, `deliverToUnpinnedChannel`,
  `waitForUnpinnedTurnJob` and the `pinned`/`unpinned` locals in `CodexChannelStoreTests.swift`, so
  the vocabulary cannot leak back in.
- `matchedGeometryEffect` from the project row to the console identity line.
- Fix the floating search field overlapping the final list row (visible in the screenshot) with a
  bottom content inset.
- Update `docs/specs/tlk-034-codex-task-creation-watch-dispatch.md`, which still describes creation
  as "opens the catalogue and chooses New Task" — the deck-entry change invalidates that step.

---

## Appendix — files inspected

- `/Users/arach/Downloads/Screenshot 2026-07-29 at 3.07.30 PM.png`
- `apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift` (1797 lines)
- `apps/ios/Talkie iOS/Codex/CodexLaneMapperView.swift` (408 lines)
- `apps/ios/Talkie iOS/Codex/CodexLaneStore.swift` (1339 lines)
- `apps/ios/Talkie iOS/Codex/CodexLane.swift` (378 lines)
- `apps/ios/Talkie iOS/Codex/CodexLaneBar.swift`, `apps/ios/TalkieTests/CodexChannelStoreTests.swift`
  (vocabulary sweep)
- `docs/specs/tlk-034-lane-pin-row-layout-review.md` (superseded on vocabulary)

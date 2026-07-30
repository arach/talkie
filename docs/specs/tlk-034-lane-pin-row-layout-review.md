# Review: Integrate Codex channel lane pinning into the channel row

**Status**: Review only — no code changes
**Date**: 2026-07-29
**Scope**: `CodexLaneMapperView` row layout + pin/select interaction; New Task entry-point separation from channel picker
**Evidence**: physical screenshot `~/Downloads/Screenshot 2026-07-29 at 3.07.30 PM.png`, `CodexLaneMapperView.swift`, `CodexCommandDeckSurface.swift`, `CodexLaneStore.createTask` / `assign`, TLK-034
**Product correction (Arach)**: New Task must not live inside the Codex Channels picker. Channel browsing/pinning and task creation are separate jobs.

---

## First principles

Two intents live on this screen. They must stay distinct.

| Intent | Meaning | Frequency | Outcome |
| --- | --- | --- | --- |
| **Select channel** | “Speak / dispatch to this exact Codex task *now*.” | Primary | `selectChannel` + dismiss |
| **Pin to lane** | “Bind this exact task to numbered shortcut *N* for later.” | Secondary | `assign(task, to: targetLane)`; stay on screen |

Product law (TLK-034 / `CodexLane.swift`):

- A **channel** is the unbounded exact task identity.
- A **lane** is one of six stable numbered shortcuts that *may* pin one channel.
- Creating a task never auto-pins. Pinning never replaces selection semantics.

The top strip correctly owns *which lane is being filled* (`targetLane`). The list owns *which channel is chosen or bound*. The bug is geometric, not conceptual: the row implements pin as a second full-height sibling column, so content and utility compete.

---

## Evidence of the current defect

### Screenshot

- Target lane **4** is selected in the strip; helper text says lane 4 is empty.
- Every channel row shows an isolated trailing pin glyph, vertically centered against multi-line content.
- Pinned rows also show a **Lane N** capsule in the title cluster, so pin state is communicated twice with different shapes (capsule vs icon column).
- Long branch paths (`codex/codex-…emium-device`) already truncate; the pin column steals trailing width on the same visual band as metadata.

### Code (`CodexLaneMapperView.taskRow`)

```206:296:apps/ios/Talkie iOS/Codex/CodexLaneMapperView.swift
private func taskRow(_ task: CodexTaskSummary) -> some View {
    let boundLane = store.sortedLanes.first { $0.task.id == task.id }?.number

    return HStack(alignment: .center, spacing: 10) {
        Button { store.selectChannel(task); dismiss() } label: {
            // title + Lane capsule + Selected + activity
            // project / branch / path / preview
        }
        .buttonStyle(.plain)

        Button {
            store.assign(task, to: targetLane)
            // auto-advance target to next free lane
        } label: {
            Image(systemName: boundLane == targetLane ? "pin.fill" : "pin")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Pin \(task.title) to lane \(targetLane)")
    }
}
```

Concrete issues:

1. **Split row model** — content `Button` + trailing pin `Button` forces a utility column.
2. **Dual pin UI** — `Lane N` capsule (title row) *and* pin icon (column).
3. **Weak pin state** — filled pin only when `boundLane == targetLane`; a row pinned to Lane 5 still shows outline pin while target is 4 (screenshot: “Diagnose request send error” has Lane 5 + outline pin).
4. **A11y gap** — only pin has a label; select is an unlabeled plain button wrapping the whole content block.
5. **Reassign/unpin on row** — pin always assigns to `targetLane`; clear only exists on the strip for the current target (`Clear`).

---

## Answers

### 1. Correct interaction model

**Model: target-then-bind, with select as the primary list action.**

1. User picks **target lane** in the top strip (1–6). That is the only place lane *identity for writing* is chosen.
2. User scans the infinite catalog (search, pagination unchanged).
3. **Tap row body** → select exact channel → dismiss. Fast path for “work on this now.”
4. **Tap pin control on row** → assign that channel to `targetLane` → stay open → optionally auto-advance to next free lane (current behavior is good).
5. **Clear** remains a lane-level action on the strip (or equivalent on the pin control when already pinned to target), not a second row column.

Do **not**:

- Make the whole row pin (destroys fast select).
- Make pin the primary trailing chevron-style action (elevates secondary intent).
- Put pin only in a context menu with no visible state (discoverability fails for a core mapper job).

### 2. Exact row layout (no separate icon column)

**Collapse pin into the existing title-trailing state control. Remove the sibling pin column.**

Recommended structure (single selectable surface + one integrated control):

```text
┌─────────────────────────────────────────────────────────┐
│ Title (2 lines max)     [Pin control]  activity        │  ← title cluster
│ 📁 project   ⑂ branch (middle-truncate)                │
│ path (middle-truncate)              Task shortID        │
│ preview (1 line)                                        │
└─────────────────────────────────────────────────────────┘
```

SwiftUI shape:

```swift
// Conceptual — not applied
ZStack(alignment: .topTrailing) {
    Button { select + dismiss } label: {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lineLimit(2)
                Spacer(minLength: 8)
                // reserve trailing space so title never underlaps the control
                Color.clear.frame(width: pinControlWidth, height: 1)
            }
            // metadata rows unchanged
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)

    pinControl // overlay in title trailing area, not full-row column
}
```

**Pin control** (one control, three visual states — see §3):

- Prefer a **capsule**, not SF Symbol alone — matches existing “Lane N” identity and stays legible next to activity time.
- Hit target: ≥ 44×44 via `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(.rect)`, even if the painted capsule is ~22–28pt tall.
- Place it in the **title row trailing cluster**, before or instead of the current free-floating pin column; keep `activityLabel` immediately beside it (same baseline group as today).
- **Do not** put a pin glyph on the metadata/branch line — that line is already under pressure.

Optional progressive disclosure (only if capsule still feels heavy):

- Keep visible capsule for pinned rows.
- For unpinned rows, show a quieter `Pin · \(targetLane)` text capsule (same geometry) so the control is always present but not an icon rail.

Avoid for this narrow pass:

- Full `swipeActions` as the *only* pin path (hidden; mapper’s job is explicit pinning).
- `contextMenu` as the only pin path.
- Nested `Menu` of all six lanes on every row (duplicates the strip; breaks target-then-bind).

### 3. How states should read

| State | Painted control | Meaning | Tap behavior |
| --- | --- | --- | --- |
| **Unpinned** | Outline capsule: `Pin 4` (uses current `targetLane`) | Not bound; ready to bind to the active target | `assign(task, to: targetLane)`; auto-advance free lane if desired |
| **Pinned to target lane** | Filled accent capsule: `Lane 4` (+ optional small pin.fill) | This row *is* the binding for the strip’s selected lane | Prefer **Clear / unpin** that lane (symmetric with strip `Clear`), *or* no-op with haptic if you want pin to be assign-only — pick one; today pin re-assigns the same task which is silent no-op-ish |
| **Pinned to another lane** | Filled neutral/secondary capsule: `Lane 5` | Bound, but not to the strip target | Tap = **reassign** to `targetLane` (move binding). Must clear the previous lane number in store so one task is not double-bound |

**Visual hierarchy notes:**

- “Selected” (current dispatch channel) stays a separate status word/capsule near the title; do not overload pin state for selection.
- Activity time stays tertiary monospaced; never compete with the pin capsule for accent color.
- Screenshot failure mode to fix: Lane 5 capsule + outline pin while target is 4 reads as “pinned and also not pinned.” One control ends that.

**Store note (related, not layout):** `assign` currently overwrites `lanes[number]` only and does not remove the same `task.id` from other lane slots. Reassign-from-row should clear the prior binding so `boundLane` and Watch snapshot stay single-valued.

### 4. Accessibility and touch targets

**Required**

| Control | Min target | Label | Traits / hints |
| --- | --- | --- | --- |
| Row select | Full content area, ≥ 44pt tall (already padded) | `"Select \(title)"` | Button; hint: `"Uses this Codex channel for the next dispatch"` |
| Pin / lane capsule | ≥ 44×44 hit box | Unpinned: `"Pin \(title) to lane \(targetLane)"` · On target: `"Remove \(title) from lane \(n)"` (if clear) or `"Lane \(n), pinned"` · Other: `"Move \(title) from lane \(n) to lane \(targetLane)"` | Button |
| Lane strip chips | **Currently 36×36** (`laneChip` frame) — raise to ≥ 44×44 or pad hit area | `"Lane \(n)"` + empty/filled + selected-as-target | Selected: `.isSelected` |
| Strip Clear | ≥ 44pt height | `"Clear lane \(targetLane)"` | Button |

**Also**

- Prefer `accessibilityElement(children: .contain)` on the row so VoiceOver gets two actions in order: Select, then Pin — not one merged blob.
- Optional `accessibilityAction` / custom actions if you keep a single visual row but want “Pin to lane N” without moving focus to a tiny control.
- Dynamic Type: capsule uses `.font(.caption.weight(.semibold))` or scaled metric; do not hard-lock width so “Lane 6” / large content sizes still fit.
- Reduce Motion: no required animation; keep instant assign feedback (capsule morph is enough).

### 5. What must remain unchanged

- Six stable numbered lanes; strip does not scroll away as the only lane UI (strip can stay fixed above the list).
- Exact-channel selection on row body + dismiss.
- Infinite catalog, cursor pagination (`loadNextCatalogPageIfNeeded`), pull-to-refresh, search.
- **Project-first New Task semantics and Default model** (but **not** the mapper-toolbar entry — see § New Task separation).
- Lane semantics: pin does not auto-activate deck lane; `assign` does not change active lane (store comment already states this).
- Visual identity: dark Command Deck palette, accent gold, existing typography hierarchy, folder/branch labels, path + short task id, preview line.
- No new information architecture for the mapper itself (no multi-select, no per-row lane picker menu of 1–6 as primary UI).
- Dirty worktree left intact (review only).

---

## New Task separation (product correction)

### Jobs are different

| Job | Screen | Question answered |
| --- | --- | --- |
| **Map / browse channels** | Codex Channels picker (`CodexLaneMapperView`) | Which *existing* exact task do I select or pin to a lane? |
| **Create task** | Dedicated New Task sheet | In which *project* should Codex start a new thread? |

Pinning and browsing assume a catalog of work that already exists. Creation *produces* a channel. Nesting Create inside Browse forces users through the wrong mental model and steals toolbar weight from Done / search.

### Current defect (code)

```35:58:apps/ios/Talkie iOS/Codex/CodexLaneMapperView.swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button("New Task", systemImage: "plus") {
            showingNewTask = true
        }
    }
    ToolbarItem(placement: .topBarTrailing) {
        Button("Done") { dismiss() }
    }
}
// ...
.sheet(isPresented: $showingNewTask) {
    CodexNewTaskView {
        showingNewTask = false
        dismiss()  // also closes the mapper
    }
}
```

Screenshot confirms the **+** sits in the channels nav bar. TLK-034 still says “opens the catalogue and chooses New Task” — that product line should flip when this ships: create from the **deck**, not from the catalogue.

`createTask` already does the right post-create store work: merge into catalog, `selectChannel(task)`, **do not** pin lanes. The entry surface is wrong; the store contract is fine.

### (a) Where New Task belongs on the main Codex deck

**Primary recommendation: keybed key on open socket 13** (left of Hold-to-Talk, `CodexCommandDeckSurface` row 4).

Evidence of free real estate:

```208:214:apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift
GridRow {
    openSocket(index: 13)          // empty today
    captureKey                     // cols 14–15
        .gridCellColumns(2)
    openSocket(index: 16)          // empty today
}
```

Why socket **13**, not 16 or the Mapper row:

1. **Adjacency to talk** — Create sets `selectedTask`, then the user holds Talk. Left-of-capture is the natural “prepare destination → speak” hand path.
2. **Does not dilute Mapper** — Mapper (key 2) stays “browse / pin existing.” New is not a sub-mode of Mapper.
3. **Does not steal row-1 peers** — Spaces / History / Read / Copy / Refresh keep their jobs.
4. **Instrument language** — empty sockets already exist as reserved deck positions; filling 13 with a real keycap matches the surface thesis (“precise instruments,” not more chrome in the console lid).

**Control spec**

- Label: `NEW` (or `TASK` if `NEW` collides with other deck copy)
- Icon: `plus` or `square.badge.plus`
- Action: present `CodexNewTaskView` as a **deck-owned sheet** (`@State showingNewTask` on `CodexCommandDeckSurface`), never nested under the mapper sheet
- Enabled when bridge/host can create (same host guard as store); disabled while `isCreatingTask` if the sheet is already open
- A11y: `"New Codex task"` / hint `"Creates a new task in a project on your Mac"`

**Secondary / empty-state (optional, not sufficient alone)**

- Console empty destination copy may *mention* New Task, but must not be the only entry.
- Empty-lane taps already open **Mapper** (`lanePickerButton` → `onShowMapper`). Keep that: empty lane means “bind something,” not “create.” Creation is project-first, not lane-first.

**Do not**

- Keep `+` in `CodexLaneMapperView` toolbar
- Open New Task only from mapper empty list
- Put New Task inside Spaces
- Auto-pin the new task to the active empty lane (violates TLK-034: create never replaces a lane binding)

**Post-create navigation**

| Step | Behavior |
| --- | --- |
| Success | `createTask` selects the new channel (unpinned); dismiss **only** the New Task sheet; land on deck ready to Talk |
| Failure | Stay on New Task sheet; show failure inline (existing `catalogFailure` path is OK if scoped/cleared carefully) |
| Cancel | Dismiss New Task; selection unchanged |

Today’s nested `onCreated` also dismisses the mapper — that coupling dies with separation.

### (b) Visual + interaction thesis for a dedicated New Task sheet

**Thesis:** This is a **project instrument**, not a settings form and not a second channel catalog. The user is choosing *where* Codex should open a thread on the Mac. Everything else is secondary confirmation.

**Structure (top → bottom)**

1. **Title** — `New Codex Task` (keep). Leading Cancel, trailing Create (disabled until project selected).
2. **Hero step: Project** — single clear question: “Which project?”
   - Section **In Your Lanes** first (projects already represented by pins — fastest path for ongoing work).
   - Section **Recent Projects** next (host-deduped by cwd — existing `deriveProjects`).
   - Each row: project **name** primary, **cwd** secondary (middle truncate), selected = accent check / selected keycap treatment.
   - Large row hit targets (≥ 44pt). Optional search only if project lists grow long — not required for v1.
3. **Confirm band: Configuration** — demoted, not the opener.
   - One row: **Model → Default** (read-only `LabeledContent`).
   - One caption: Talkie uses the Mac’s current Codex model and execution settings; no override fields.
   - Do **not** add approval/sandbox/model pickers here.
4. **No lane controls** on this sheet. No “pin to lane N.” Pinning is Mapper’s job after the channel exists.
5. **Creating state** — blocking progress affordance (existing overlay is fine; prefer sheet-native disabled Create + inline progress so Cancel remains reachable if desired).
6. **Failure** — orange notice with combined message/hint; do not silent-dismiss.

**Design language**

- Match Command Deck chrome: panel background, monospaced micro-labels for section headers if the deck does that elsewhere, accent for selection — not a plain system-only Form if the rest of Codex is instrumented.
- Prefer slightly taller project rows (card-like list rows) over dense Settings lists so path truncation and selection read at a glance on phone.
- Keep one primary CTA (**Create**). No secondary “Create and pin” — that re-merges jobs.

**Preserve from current `CodexNewTaskView`**

- Project-first selection (lanes projects → recent)
- Default model, no model field on the wire (`createTask` omits model)
- Client `creationID` reset when project changes
- Create disabled without selection / while creating
- Success → select unpinned channel

**Promote for design quality**

- Extract `CodexNewTaskView` from private nested type in `CodexLaneMapperView.swift` to its own file owned by the deck presentation path
- Deck presents the sheet; mapper knows nothing about creation
- Update TLK-034 create flow step 1 from “opens catalogue → New Task” to “deck New key → project sheet”

### Mapper after the split

Channels picker toolbar becomes:

- Leading: **empty** (or only a non-create utility if truly needed later)
- Trailing: **Done**
- Body: lane strip + channel list + search only

Empty catalog copy can say there are no recent tasks and that **New** on the deck creates one — without embedding a create button that reopens the merged job.

---

## Findings by severity

### High

1. **Trailing pin column splits every row into content + utility rail**
   Evidence: screenshot pin column; `HStack` + second `Button` in `taskRow`.
   Fix: remove column; integrate pin into title-trailing capsule.

2. **Pin state is shown twice and can disagree**
   Evidence: screenshot “Lane 5” + outline pin while target is 4; code fills pin only when `boundLane == targetLane`.
   Fix: one control, three states (§3).

3. **New Task is nested inside the channel picker**
   Evidence: mapper toolbar `+`; nested `CodexNewTaskView` sheet; product correction from Arach.
   Fix: remove plus from mapper; present New Task from deck keybed socket 13; keep project-first / Default model.

### Medium

4. **Select path has no accessibility label**
   Evidence: content `Button` has no `.accessibilityLabel`.
   Fix: label + optional hint; keep children ordered.

5. **Lane chips are 36pt**
   Evidence: `frame(width: 36, height: 36)` on strip.
   Fix: 44pt minimum hit targets (visual may stay compact with padding).

6. **Reassign may leave dual lane bindings**
   Evidence: `assign` writes one slot, never clears other slots with same `task.id`; `boundLane` uses `first`.
   Fix: when pinning, clear any other lane holding that task id (behavior fix adjacent to layout).

7. **TLK-034 create step still routes through the catalogue**
   Evidence: spec “opens the Codex task catalogue and chooses New Task.”
   Fix: doc update when implementing deck entry.

### Low

8. **Copy still says “use Pin on a channel below”** while the control becomes an inline capsule — update empty-lane helper string to match the control name (`Pin 4` / `Lane N`).
9. **Auto-advance of `targetLane` after pin** is good for batch filling; keep it. Ensure VoiceOver announces the new target if focus remains on the list.
10. **`CodexNewTaskView` is private and co-located with the mapper** — extract when moving presentation ownership to the deck.

---

## Concrete SwiftUI recommendation (implementation sketch)

### Row pin integration

1. Delete the trailing pin `Button` sibling in `taskRow`.
2. Replace the read-only `if let boundLane { Text("Lane \(boundLane)") … }` with a single `lanePinControl(task:boundLane:)`.
3. Control label text:
   - unpinned → `"Pin \(targetLane)"`
   - pinned → `"Lane \(boundLane)"`
4. Style: outline vs `theme.colors.accent` fill; other-lane uses secondary fill / non-accent stroke so target-lane fill remains the strongest.
5. Action:
   - unpinned / other-lane → `assign` (and clear previous binding for that task).
   - pinned-to-target → `clearLane(targetLane)` **or** leave as assign-only; recommend clear for symmetry with strip.
6. Add accessibility labels on select + pin; bump strip chip hit targets.

### New Task separation

1. Remove leading toolbar `New Task` / `plus` from `CodexLaneMapperView`.
2. Remove `showingNewTask` and nested sheet from the mapper.
3. On `CodexCommandDeckSurface`: `@State showingNewTask`; replace `openSocket(index: 13)` with `actionKey(... label: "New", icon: "plus", action: { showingNewTask = true })`.
4. `.sheet(isPresented: $showingNewTask) { CodexNewTaskView { showingNewTask = false } }` — success dismisses create only; selection already set by store.
5. Extract/promote `CodexNewTaskView`; polish project-first layout; keep Default model band secondary.
6. Do not auto-pin; do not open mapper after create unless the user later chooses Mapper.

---

## Out of scope for this refinement

- Watch UI, bridge contracts, task creation idempotency mechanics.
- Redesigning the lane strip into a different IA.
- Replacing select-with-dismiss with stay-open multi-select.
- Adding per-row menus of all six lanes.
- Model / approval / sandbox overrides on create.

---

## Decision summary

**Mapper:** Keep target-then-bind. One title-trailing capsule for pin state; kill the trailing icon column.

**Create:** Separate job. **New** lives on the Command Deck keybed (recommended: open socket **13**, left of Talk). Channels picker is browse + pin only — **no plus in its nav bar**. Dedicated New Task sheet stays **project-first**, **Model = Default**, creates an **unpinned** selected channel, then returns to the deck to talk.

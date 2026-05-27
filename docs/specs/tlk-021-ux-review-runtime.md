# TLK-021 — Agent Home UX/Aesthetic Pass

**Reviewer**: talkie-card-g-2q154m.codex-walkie-executor-runtime.air-local (project-native runtime)
**Date**: 2026-05-25
**Branch**: codex/walkie-executor-runtime
**Sibling review**: `docs/specs/tlk-021-review-claude.md` (architecture/spec)
**Studio canon**: `design/studio/components/studies/MacAgentHome.tsx`, route `/mac-agent-home`
**Surface under review**: `apps/macos/TalkieAgent/TalkieAgent/Views/Home/*`

Architecture/IPC is covered in the claude sibling review. This pass is strictly UX/aesthetic
against the current rendered surface and how it should map to iPhone.

## TL;DR

1. Pick a hero per turn — the **returned summary** — and collapse the raw executor output beneath it.
2. Kill the label stack. Today a single completed turn carries ~9 competing eyebrows/pills. Target: 4.
3. Drop "CH 01" as a visible label. Channel codes are routing metadata, not topic titles.
4. Make Continue / Copy / Send-to-iPhone **persistent**, not hover-revealed.
5. The empty state needs starter chips, not a marketing card.
6. iPhone is a **capture/command/report-back** surface for the same Mac conversations, tagged by `source`. Not a separate assistant world.

## 1. Visual hierarchy — label competition

### What's wrong
A completed turn currently surfaces *all of these labels simultaneously*:

| Label | Source |
|---|---|
| Section header title `GENERAL` + `LIVE` | `AgentHomeExecutorTraceView.swift:50, 866` |
| Header subtitle `Conversation surface · …` | `AgentHomeView.swift:209` |
| `CH-01` channel chip | `AgentHomeExecutorTraceView.swift:184` |
| Timestamp + identity `openai · gpt-5.5` | `:187, :191` |
| `DONE` status pill | `:202` |
| Eyebrow `YOU SAID` | `:158` |
| Eyebrow `TALKIE · ACK` | `:166` |
| Thread row `Agent branch returned` | `AgentHomeActivityStore.swift:343, AgentHomeExecutorTraceView.swift:374` |
| Eyebrow `EXECUTOR · RESULT` | `AgentHomeExecutorTraceView.swift:554` |
| Eyebrow `TALKIE · RETURNED SUMMARY` | `:611` |

Trunk + node + halo + chip + pill + eyebrow + branch-row + card-eyebrow + card-eyebrow is too much
visual scaffolding for one user→agent→reply unit. The structure is correct (Studio canon already
proved this layout works) but Swift over-labels every layer.

### Target hierarchy
Per turn, three readable bands:

1. **Author band** — author mark + relative time + ONE topic chip + invisible `turn id` (a11y only). Drop channel chip + status pill in the same row.
2. **Said band** — transcript (no eyebrow needed; the author mark already says "user said this") + a quoted-italic ack underneath without an eyebrow.
3. **Returned band** — single hero card with the returned summary; raw executor output behind a `> Details` disclosure; persistent action row (Continue · Copy · Send to iPhone · Open thread).

### Concrete moves
- `AgentHomeExecutorTraceView.swift:181-204` — drop `ChannelChip` from `headerRow`; move channel into a `.help()` tooltip on the trunk node or into the inspector.
- `:202` — only render `StatusPill` when `status != .done`. The trunk node already encodes done via color/fill; an extra pill is duplication. For `.running` / `.failed` / `.waiting`, keep the pill — that's where it earns its space.
- `:153-160` — `TurnBody(eyebrow: "you said", …)` → drop eyebrow; transcript is the body text with no decoration. The author mark + chat layout already supplies the "who said it" affordance.
- `:162-170` — `TurnBody(eyebrow: "talkie · ack", …)` → swap eyebrow for a leading quote glyph or italic-only treatment; Studio canon uses `"…"` with italic display font, no eyebrow at all (`MacAgentHome.tsx:1027-1036`).
- `AgentHomeActivityStore.swift:336-374` — when `status == .done` AND `response.nonEmpty`, suppress the synthesized "Agent branch returned" thread row entirely. It's a tautology with the response card right below it. Keep the thread row only for `.running` / `.waiting` / `.failed`.
- `AgentHomeView.swift:209` — `headerSubtitle` "Conversation surface · …" reads as designer copy. Replace with hard data: `"4 turns · 2 branches live · last reply 4m ago"`.

After these moves the visible label count per completed turn drops from ~9 to ~4 (topic chip, time, transcript, returned summary).

## 2. Timeline / results — hero placement

### What's wrong
`AgentHomeExecutorTraceView.swift:208-229` renders the `ResponseCard` (raw executor output) **above** the `ReturnSummaryCard` (the spoken/written summary). The summary is the hero of the turn — it's
the thing Talkie would speak, the thing the user should scan in two seconds — and it's currently buried.

### Fix
Flip the order, and demote `ResponseCard` to a disclosure:

```swift
@ViewBuilder
private var responseSlot: some View {
    if let summary = trimmed(turn.spokenSummary) {
        ReturnSummaryCard(           // ← hero, top
            text: summary,
            onCopy: { onCopy(summary) },
            onContinue: { onContinue(turn) }
        )
        if let response = trimmed(turn.response), response != summary {
            ExecutorDetailsDisclosure(text: response, onCopy: { onCopy(response) })
        }
    } else if let response = trimmed(turn.response) {
        ResponseCard(text: response, onCopy: { onCopy(response) })
    } else if turn.status == .running || turn.status == .waiting {
        RunningHint(status: turn.status)
    } else if let error = trimmed(turn.error) {
        ErrorCard(text: error)
    }
}
```

`ExecutorDetailsDisclosure` should be a `DisclosureGroup`-style chevron labeled `executor output · N lines` that expands to the existing `ResponseCard` body. Default collapsed.

When `spokenSummary` is absent (e.g. older runs), `response` becomes the hero by promotion, no
disclosure needed. The summary→response duplication check (`response != summary`) prevents
double-render when the runtime sets both to the same string.

### Why
- Voice product → text should be readable in the same shape as Talkie speaks it.
- Raw executor output is for debugging/inspector use; available, not in your face.
- Aligns with Studio canon `FoldbackResponse` (`MacAgentHome.tsx:972-994`) which renders one
  authoritative card under the parent turn.

## 3. Action affordances — persistent, not hover

### What's wrong
- `TurnBody`'s Copy button is `.opacity(hovered ? 1 : 0.0)` (`:518-520`).
- `ResponseCard`'s Copy button same (`:560-563`).
- `ReturnSummaryCard`'s Copy button same (`:614-621`); Continue is persistent (`:629`) but only on the summary card.
- No "Send to iPhone" anywhere.
- No "Open in inspector" anywhere (inspector doesn't exist yet, per claude review).

Hover-revealed icon buttons are a desktop-only convention and they cost trackpad users a discovery
moment. On a surface that will also be reflected on iPhone (where hover doesn't exist), they're
worse: the iPhone version will have to render different controls.

### Fix
Add a small persistent **TurnActionBar** beneath the response/summary card, always visible:

```
Continue ↩    Copy ⌘C    Send to iPhone ↗    Open thread →
```

- Hide individual buttons whose underlying op isn't possible (e.g. `Continue` requires `spokenSummary != nil` OR `response != nil`).
- 11pt mono labels, no icons-only — labels disambiguate in screenshots / on-call.
- Use `TalkieTheme.textSecondary` for default tint; on hover bump to `textPrimary`.
- `Send to iPhone` is a future op stub (see §7); behind a `if FeatureFlag.iphoneRelay` until wired.

Drop the hover-only Copy icons from `TurnBody`, `ResponseCard`, `ReturnSummaryCard`. The action bar handles all copy operations for the turn.

### Files
- New: `apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeTurnActionBar.swift`
- Modify: `AgentHomeExecutorTraceView.swift:208-229` (insert action bar inside `responseSlot`)
- Modify: `TurnBody`, `ResponseCard`, `ReturnSummaryCard` — strip hover-Copy buttons (`:511-521, :556-564, :613-621`)

## 4. Empty state — starter actions

### What's wrong
`AgentHomeExecutorTraceView.swift:78-111` renders a calm card with:
- waveform icon
- `No conversation yet`
- one-line description

That's a marketing card, not an invitation. There's no way for the user to *start* without
already knowing the prompt bar exists and the keyboard chord works.

### Fix
Replace the empty card with a **starter shelf** showing three real entry points the user can click *or* trigger by voice:

```
┌────────────────────────────────────────────────────────┐
│  Start a turn                                          │
├────────────────────────────────────────────────────────┤
│  [✎  Ask a quick question        ]   ⌘K               │
│  [🎙  Hold ⇧⌃⌥⌘T to dictate     ]   walkie            │
│  [📎  Drop a tray item in and ask]   tray              │
└────────────────────────────────────────────────────────┘
```

- The chord pill (`⇧⌃⌥⌘T`) is the same one Studio shows on the new-turn card (`MacAgentHome.tsx:599-602`). Mirror it.
- "Drop a tray item" is the right cross-promotion to the Capture Tray work already in flight — sets the mental model that captures funnel into turns.
- Each chip is clickable: question → focus the prompt bar; walkie → no-op (it's a chord hint); tray → open `TrayViewer`.
- One-line subtitle below the shelf: `4 conversations · last activity 12m ago` (real data from `store.activeJobs.count` + `store.lastRefreshed`).

### Files
- Rewrite: `AgentHomeExecutorTraceView.swift:78-111` (`emptyTraceCard`)
- Make `AgentHomePromptBar` focusable from outside via a `@FocusState` binding hoisted to `AgentHomeView` (already present at `:17` — just route the starter chip action to flip it).

## 5. Sidebar / topic naming

### What's wrong
`AgentHomeActivityStore.swift:555-561` produces topic titles like `CH 01` by uppercasing the
post-`channel-` slug. That's runtime taxonomy bleeding into UI.

### Fix
Three changes in `topicTitle(for:jobs:)`:

1. **Stop uppercasing.** Title Case, not SHOUT.
2. **Prefer the first user transcript as the title**, even for `channel-` prefixed ids, when one exists. The current code does this fallback for *non*-channel ids (`:563-571`), but a channel-prefixed id never gets the transcript treatment — it always reads the slug. Reorder so transcript wins when present.
3. **Allow a user-supplied rename.** Persist `agentHome.topicNames` in `TalkieSharedSettings` keyed by `conversationId`. Right-click on a sidebar row → `Rename topic…` (NSAlert with text field). Title lookup reads the rename map first.

Channel codes (`CH-01`, `CH-02`) are still useful as routing metadata but belong in `.help()` or
inspector, not as the visible title.

### Sidebar header copy
`AgentHomeView.swift:37` — `CONVERSATIONS` eyebrow + `summaryLine` ("4 topics") is fine. Add an
inline `New` button next to the eyebrow so creating a topic doesn't require scrolling to the bottom
of the sidebar where it currently lives (`:67`). The bottom buttons (Refresh, Settings) read as
gear/utility — New belongs near the topic list.

### Sidebar icon meaning
`topicIcon(for:jobs:)` (`AgentHomeActivityStore.swift:591-599`) returns three icons based on
heuristic state (voice/active/default). Reads inconsistently in the list. Recommend: one icon per
topic, derived from `source` of the most recent turn (`waveform` for voice, `keyboard` for typed,
`iphone` for phone-originated), AND a separate live/done dot on the right edge — don't fold both
signals into the leading icon.

## 6. Header subtitle, status pill, "last refreshed"

### What's wrong
`AgentHomeView.swift:102-137` — `header` packs title + subtitle + runtime pill + "Updated 4m ago" +
close button into one row. Cognitive load:

- "Talkie online" pill — useful, keep
- "Updated 4m ago" — measures the refresh cadence, not anything the user cares about. The trunk
  pulses already indicate live work. Drop.
- "Conversation surface · …" — see §1.

### Fix
- Drop `:119-123` `"Updated …"` text.
- Replace `headerSubtitle` with real metrics (turns / branches / last reply).
- Move runtime pill to the bottom-right corner of the window in a thin status bar (Studio canon does this — `MacAgentHome.tsx:1226-1251`). Keeps the header pure title + close.

## 7. iPhone mapping

The phone is **not** a separate assistant. It's three things, all returning into the same Mac Agent
Home conversations:

| Phone surface | Source tag | Mac Agent Home behavior |
|---|---|---|
| **Capture** — voice dictation from `KeyboardActivationView` or widget | `iphone-dictation` | Posts a user-side turn into the selected conversation (defaults to General). If headphones in use, audio replays the spoken summary. |
| **Command** — same Hyper+T-style ask, with conversation picker | `iphone-command` | Posts a user-side turn; carries `conversationId` chosen on phone. Foldback summary speaks via TTS, full result lands in Mac home. |
| **Report-back** — inbox view of returned summaries | `iphone-pickup` | Read-only feed of returned summaries from Mac-originated turns, with replay + "open on Mac" deep link. |

### What this implies for Agent Home

1. **Source pip per turn.** Add a small glyph next to the author mark indicating origin: `waveform.circle` voice, `keyboard` typed, `iphone` phone. Tooltip shows the source label. Code path: `AgentHomeExecutorJob.source` already carries this (`AgentHomeActivityStore.swift:84`). Render in `headerRow` after the author mark.

2. **One conversation set, two clients.** Topics are not phone-vs-mac. Both clients render the same `conversationId` list. Phone shows a subset (the user's pinned topics) in a leaner UI; Mac shows everything.

3. **"Send to iPhone" action.** §3's TurnActionBar entry. Posts the returned summary to the phone's inbox via the same broker/IPC path as a regular agent message, tagged `to-iphone`. Does **not** require push infrastructure (Codex's lane). MVP: push goes through whatever transport Codex lands; for the UX, the button just needs to enqueue an outbound record. Behind a feature flag until wired.

4. **iPhone capture deep link.** `talkie://home?conversation={id}` opens the Mac Agent Home pre-selected to that conversation. Already partially specced in TLK-021 §"Entry Points". Map the phone's "Open on Mac" affordance to it.

5. **Naming continuity.** Don't introduce a separate "Phone" topic group on Mac. iPhone turns appear inline in the same topic timelines, distinguished only by the source pip. This is the **most important** UX choice — it's what makes the phone feel like a remote, not a second app.

### Phone UI shape (not in scope for this branch, but anchor the model)
- Top: conversation selector (segment / pill row, last 4 topics + "All").
- Body: a vertical feed of *returned summaries* only. Phone is for the foldback layer, not the executor trace. Tap → expand to see the parent ask + summary + replay button + "Open on Mac".
- Bottom: big Hyper+T-equivalent (already exists as `KeyboardActivationView`); destination conversation defaults to currently-viewed topic.

## 8. Responsive polish notes

- `AgentHomeController.swift:46-66` — window min size is 780×520 but `AgentHomeView` body is structured around a fixed 190px sidebar (`:85`). At 780px the conversation column is ~589px which is fine for one turn, but the prompt bar's two-line continuation chip + conversation-id mono text wrap awkwardly. Either bump min width to 880, or hide the conversation-id mono text below 880.
- Sidebar topic rows are 42pt tall (`:455`); at 5+ topics the bottom utility buttons get crowded. Use a `ScrollView` for the topic list and pin Refresh/Settings outside it.
- `RunningHalo` animation (`AgentHomeExecutorTraceView.swift:329-344`) re-applies on every store refresh because view identity churns. Add `.id(turn.id)` on the row or move the halo state into a parent that's stable across refreshes.
- Live dot pulse in `TraceSectionHeader` (`:867-874`) only animates when accessory == `.liveDot`, which depends on `topic.activeCount > 0`. Good. But the section header's `subtitle` says `"No turns yet"` when turns empty — never reached when `activeCount > 0` and turns are non-empty. Tighten the subtitle logic to reflect actual state: turns-count + branches-live, not a fallback string.

## 9. Suggested patch order (quick wins → bigger moves)

These are scoped to this branch's UX surface; none touch notification/push (Codex's lane).

1. **Topic title casing + transcript-wins fallback.** `AgentHomeActivityStore.swift:550-571`. ~10 lines.
2. **Drop redundant labels.** Strip eyebrow from user transcript body; drop StatusPill when done; drop channel chip from header row; drop "Updated 4m ago" from header. `AgentHomeExecutorTraceView.swift:181-204, :153-170`, `AgentHomeView.swift:119-123`. ~30 lines deleted.
3. **Suppress synthesized branch row when response present.** `AgentHomeActivityStore.swift:336-374`. ~5 lines guard.
4. **Hero flip + executor disclosure.** `AgentHomeExecutorTraceView.swift:208-229`. ~40 lines.
5. **Persistent TurnActionBar.** New file + integration. ~80 lines.
6. **Starter shelf empty state.** Replace `emptyTraceCard`. ~50 lines.
7. **Source pip on header row.** Read `turn.source`, render glyph + tooltip. ~15 lines.
8. **Topic rename.** Defaults-backed rename map + right-click. ~40 lines.
9. **Header metrics over copy.** Replace `headerSubtitle` with real numbers. ~10 lines.

Items 1–4 alone resolve the "competing labels" and "hero of the turn" complaints. 5–7 close the
action affordance + iPhone tagging story. 8–9 are polish.

## 10. Out of scope, but flag

- The Studio canon (`MacAgentHome.tsx`) carries an **Agent Tool Rail** (left, narrow, dark) with Comms/Work/Runs/Memory/Prefs. Swift today has no tool rail; the sidebar jumps straight to topics. The rail is the right home for "Settings" and future surfaces (Memos, Runs) — recommend extracting it when the second non-conversation surface arrives, not now.
- The **Branch Inspector** (Studio right pane) is absent from Swift. Per claude review (`tlk-021-review-claude.md` §"Missing boundaries"), this depends on a stable join key between dictation and job. Don't build the inspector until that exists.
- **Composer** in Studio is a sticky pinned bar with a topic chip and a voice pill (`MacAgentHome.tsx:1038-1052`). Swift's prompt bar is similar but lacks the chip + voice affordance. Adding them is a small win once §1's chip cleanup lands.

## References

- Studio canon: `design/studio/components/studies/MacAgentHome.tsx`
- Architecture/IPC review: `docs/specs/tlk-021-review-claude.md`
- Spec: `docs/specs/tlk-021-agent-home-architecture.md`
- Swift surface: `apps/macos/TalkieAgent/TalkieAgent/Views/Home/`

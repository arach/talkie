# Round 3: Claude Opus synthesis — interaction architecture, safety, data truth

**Round:** 3, Converge · **Role:** interaction, safety, data-truth editor
**Inputs:** three briefs, six Round 1 / Round 2 results · **No application code edited.**

---

## 0. The finding that reorders the field

Kimi's rejection of `[ Stop ]` was correct, and is the smaller half of a larger truth. Verified this round:

| Fact | Evidence |
|---|---|
| No turn stop or cancel endpoint exists | route list, `src/bridge/index.ts:489–520` |
| Approval sets job status `blocked`, which is **terminal**; iOS treats it as a lane end-state | `routes/codex.ts:831`; `isTerminal()`, `:916`; `CodexLaneStore.swift:1287, :1297` |
| The bridge **refuses** to approve | `codex-desktop-bridge.cjs:1083–1095`; hint `routes/codex.ts:134` |
| `Needs you` is known only for turns **this device dispatched** | snapshots are dispatch-scoped; `CodexTaskSummary` has no state field (`CodexLane.swift:58`) |

**Consequence:** `Needs you` is not a state Talkie can resolve — no answer path, no approve/deny, no stop. Every portfolio here, mine included, drew a question with buttons under it. One amendment follows; it is the owner's call:

> **Amendment to `IPAD-DESIGN-BRIEF.md` helper vocabulary:** delete `Hold to answer`. Replace the Needs-you Talk state with the disabled string **`Answer this in Codex Desktop on Arachs-Mac-Mini.Local`**.

---

## 1. Five lenses

### 1.1 One selected task, one voice destination

| Requirement | Rule |
|---|---|
| Selection control | Exactly one: the rail task row |
| Result / event / history taps | Open content. Never rebind Talk |
| Retarget from content | One explicit `Talk to this task` control that moves rail selection first |
| Destination display | Task name **inside** the Talk capsule, not only above it |
| Capture lock | Selection frozen from capture start until dispatch or cancel (`CodexLane.swift:301–312`) |
| Prohibited | Empty-canvas selection; selection as a side effect of scroll or inspection |

### 1.2 Steer, Queue, answer, unavailable

| Mode | Helper line | Status |
|---|---|---|
| Continue / Steer / Queue | `Hold to continue this task` · `Hold to steer this turn` · `Hold to queue a follow-up` | verified — `CodexMessageMode`, `CodexTurnDelivery` (`CodexLane.swift:43–55, 193–213`) |
| Answer | ~~`Hold to answer`~~ → `Answer this in Codex Desktop on <Mac>`, Talk disabled | **unsupported — must change** |
| Unavailable | `Talk unavailable while the Mac is offline` | verified path, inferred trigger (1.4) |
| Stop | — | **no such capability. Remove from all four designs** |

### 1.3 `Needs you` priority and consequential actions

| Item | Ruling |
|---|---|
| Rank | Still outranks `Working`. Sticky, non-displacing, survives task switching |
| Presentation | Pinned strip above the work surface: task name, "Waiting for you in Codex Desktop", last instruction. **No answerable question text, no approve/deny** |
| Scope honesty | Only for turns this device dispatched. Never label an undispatched task `Needs you` |
| Resolution | Clears on a later successful dispatch, or explicit dismiss. Not resolvable in-app |
| Complete list of consequential actions in Talkie | select task · choose Steer/Queue · dispatch · cancel capture |
| Floor | Strip + newest result may not push history below 200 pt; collapse to `Show detail` first |

### 1.4 Current bridge data vs proposed data

| Data | Status | If absent |
|---|---|---|
| Title, project, cwd, branch, `updatedAt` (`CodexLane.swift:58`); Mac identity | verified | — |
| Latest instruction + result, per-task history (`GET /codex/tasks/:id/history`) | verified | — |
| Turn timestamps, `durationMs` (`CodexChannelHistory.swift:16, :40`) | verified | Tape loses its axis |
| Working prose — `commentary`/`tool` (`routes/codex.ts:98–103`) | verified, dispatched turns only | degrade to plain `Working`; never design empty space around it |
| Steer / Queue delivery outcome | verified | — |
| `blocked` → attention | verified, **dispatch-scoped, terminal** | — |
| Per-task state for **undispatched** tasks | **absent** | identity + `Updated 14m ago` only |
| `Mac unavailable` as observed; live elapsed ticker | **inferred** — `lastSuccessfulContactAt` is local bookkeeping (`BridgeManager.swift:155`) | copy reads `Last successful contact · 14m ago`, never "last heard from"; drop the `· 4m` chip |
| Ordered events for **all** tasks at once | **absent** | Chronicle cannot be primary |
| Approval payload shape / labels | **unverified** | no approve/deny UI may be drawn |
| Changed files, checkpoints, tokens, traces | absent / forbidden | probe filler must not justify geometry |

**Truthfulness rule, settled:** where state is unknown, the row shows identity and recency — no badge, no dash, no grey `Idle`. Absence of knowledge renders as absence of a chip.

### 1.5 State continuity

| Transition | Required behavior |
|---|---|
| Select B while A is mid-capture | Blocked. Rail inert; capsule keeps A's name |
| Select B while A is Working | Allowed. Surface swaps; A's Working continues, still visible in the rail |
| Scroll into history | Destination unchanged. `Return to now` is one control in a fixed place |
| Open another task's attention strip | Read-only. Talk stays bound and says so |
| Connection fails mid-capture | Capture completes locally; dispatch fails with retry. Selection preserved; audio never silently dropped |
| Connection fails while Working | Activity freezes at the last known event under a terminal hairline. No new events render for that Mac |
| Reconnect | Selection, scroll position, unresolved strips restore. Stale marks clear only on a successful request |

---

## 2. Ranking

| Rank | Structure | Verdict |
|---:|---|---|
| 1 | **Fixed Command Desk** (revised) | The only structure whose entire data diet is verified; degrades without inventing state. All three models rank it first after Round 2 |
| 2 | **Selected-Task Tape** | Best instrument idea, conditional on an event census. At two event types it is a conversation view wearing chronology |
| 3 | **Operational Folio** | Best reading thesis. Default geometry too near 50/50; portrait orphans Talk. Alternative, not first ship |
| 4 | **Cross-Task Chronicle** | Not a primary. Its one durable idea transplants cleanly — which is what a wildcard is for |

---

## 3. Production composition — Fixed Command Desk, revised

Landscape 1180 × 820 pt; 744 pt content height.

| Region | Spec |
|---|---|
| Chrome band | 52 pt. Mac name, connection truth, `Last successful contact` when degraded |
| Rail | 280 pt. Name, project · branch, `Updated <rel>`. State chip **only when known**. Sole selection control |
| Work surface | Remaining width, deep navy. Instruction → activity → result, newest anchored to the bottom |
| Attention strip | Above the work surface, inside the navy pane, when an unresolved dispatched `blocked` exists |
| Talk shelf | 96 pt, fixed bottom-right corner, fixed height, invariant in every state. Destination inside the capsule |
| Evidence column | **Width-conditional:** appears only when ≥2 modules have real content; ≤300 pt and ≥120 pt narrower than the work surface. Column count changes on evidence presence only — never per state tick |
| Portrait | Rail becomes a switcher, evidence a drawer; Talk shelf full-width at the same 96 pt class on every page |

## 4. Compatible features it may adopt

| From | Feature | Condition |
|---|---|---|
| Tape | Sticky non-displacing attention with a chronological placeholder | Content de-fanged per 1.3 |
| Tape | Terminal rule at the failure timestamp | — |
| Tape | Quiet per-turn timestamps inside the selected turn | Verified `startedAt`/`completedAt` only |
| Folio | Single-open module rule; no remembered widths, no drag edges | Absolute |
| Folio | Failure as a readable recovery surface, not a toast | — |
| Chronicle | `Needs you` promotion group at the top of the rail | Dispatch-scoped rows only |
| Chronicle | Multi-Mac freeze semantics | Only if a second Mac exists |

## 5. Features that must not be combined

| Do not combine | Why |
|---|---|
| Folio focus mode **+** Chronicle lane canvas | Two geometry-changing mechanisms on one surface produce window management; both briefs reject it |
| Conditional evidence column **+** Folio focus mode | Two reasons for width to change. Keep presence-driven, drop user-driven |
| Attention strip **+** any approve / deny / answer control | Promises a capability the bridge refuses |
| Talk shelf **+** variable geometry (focus resize, portrait 64 pt collapse) | The one control that must never move |
| Swimlane axis **+** rail selection | Two selection surfaces with different voice consequences |
| Rail state chips **+** undispatched tasks | Renders a state Talkie does not know |

---

## 6. Five interaction acceptance checks

1. **Destination invariance.** Open a result, scroll to the oldest turn, open an evidence module, open another task's attention strip: the capsule name and helper line never change. Retargeting works only via a rail row, or an explicit `Talk to this task` control that moves rail selection first.
2. **Capture lock.** Begin a hold on A, then tap B's rail row and newest result — neither registers. Release dispatches to A; slide-to-cancel discards and restores interactivity.
3. **Attention persistence.** With an unresolved dispatched `blocked` on A, select B and let three new events arrive. A's strip stays visible and cannot be scrolled away; B keeps ≥200 pt of scrollable history; nothing offers to answer, approve, or stop.
4. **Truthful unknown.** Add a task dispatched from another device. Its row shows name, project · branch, recency — and **no** chip, badge, dash, or `Idle`, in every state including cold launch and reconnect.
5. **Failure freeze and restore.** Sever the bridge mid-turn: activity stops under a terminal rule, chrome reads `Last successful contact · <time>`, Talk reads `Talk unavailable while the Mac is offline` in unchanged geometry. On restore, selection, scroll position, and pinned strips return; stale marks clear only after a successful request.

---

## 7. Highest-value data verification before implementation

Run a one-task event census on `Improve iOS connection manager`, dispatched from this iPad:

1. **How many distinguishable event types actually arrive in one turn** — instruction, `agent_message`, `patch_apply_end`, `mcp_tool_call_end`, response (`codex-desktop-bridge.cjs:630–650`). Fewer than four collapses Tape into a conversation view and voids its claim on second place.
2. **Whether `commentary`/`tool` prose is continuous or bursty** — decides whether the navy surface is designed around prose or a plain `Working` line.
3. **Whether a `blocked` job is observable at all in normal deck use**, or only via the approval path the bridge refuses.

Item 3 is the highest-value check. If `blocked` is rare in practice, the attention strip must not hold permanent geometry, and the attention model every portfolio treated as load-bearing becomes peripheral.

---

*End of Round 3 synthesis — Claude Opus.*

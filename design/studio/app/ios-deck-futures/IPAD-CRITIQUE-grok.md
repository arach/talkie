# Grok — Independent iPad critique

**Reviewer:** Grok  
**Mode:** Words only. No Swift or Studio implementation changes.  
**Evidence:** Physical iPad Air (5th gen) landscape capture  
`/Users/arach/.codex/visualizations/2026/08/01/019fbddf-37c3-7fd2-b108-961e0559c6bf/ipad-current-view.png`  
**Source thesis (code):** `CodexCommandDeckSurface.swift` — “exact-task instrument, not a generic remote-control grid”; first viewport = live console, lane spine, stable keybed; console owns activity, keybed owns talk.

---

## Verdict in one paragraph

The capture is a handsome instrument that has not yet become a conversation surface. A near-technical user can see that Talkie is aimed at a Mac-side Codex task, but the screen answers almost none of the four product questions at a glance: who I’m talking to is partly visible; what Codex is doing is a quiet footer; what it last produced is absent; what I can safely do next is a 16-key puzzle with half the keys disabled and no relationship drawn to the empty console. Landscape iPad is treated as a taller phone: one full-width void console stacked on a dense phone keybed. The next study should recompose around **destination → live work / last result → voice**, and demote the keybed from co-equal hero to stable accessory.

---

## 1. First five seconds — belief and break

### What they believe

1. This is Talkie’s Codex remote for a selected Mac (`ARACHS-MAC-MINI.LOCAL`).
2. There are six numbered “channels” or slots across the top.
3. The big dark panel is the live feed for the selected work.
4. The bottom grid is the control surface; the wide gold **Talk** is the main action.

That first impression is mostly correct and worth protecting. The chrome reads as a calm technical instrument, not a chat app and not a systems admin console.

### Where the belief breaks

| Break | Why it hurts the four questions |
|-------|----------------------------------|
| **Console is empty** while the task title and path are only a thin lid | Question 3 fails immediately. The largest surface promises “live work / output” and delivers silence. |
| **`NO LANE` badge** beside a fully titled task | Question 1 fractures. Is this a mapped lane destination or a free-floating task? The product thesis says a lane *is* the destination; the UI says the task has no lane. |
| **Lane ribbon shows only `01`…`06`** with no occupancy, title, or activity | Question 2 fails across the fleet. User cannot tell which slots are live, empty, or need them. |
| **`CODEX> READY`** as the only status language | Reads like a terminal prompt, not “Codex is waiting for you.” Expert-coded, easy to miss, weak on “does it need me?” |
| **Keybed denser than the console content** | Question 4 fails. Primary action (Talk) is correct, but surrounded by Mapper / Spaces / Details / History / lane step / Task / Readout with many disabled peers. User must decode capability vs state. |
| **Hold 14–15** copy on a touch device | Voice is the front door, but the instruction is keycap-numbered like a hardware deck. Fine for power users who already learned the map; cold for near-technical. |

**Net:** In five seconds the user trusts the instrument, then realizes the instrument is mostly status chrome around an empty stage. Belief: “I’m flying this task.” Reality: “I’m looking at a parking lot for controls.”

---

## 2. Primary / secondary / progressive disclosure (iPad)

### Primary (always visible without a tap)

Answer the four questions in the main plane:

| Priority | Content | Form on landscape iPad |
|----------|---------|-------------------------|
| P0 | **Destination** — which exact task, on which Mac, mapped to which lane | Title + project/branch in one calm identity block; bridge as a single chip, not competing header chrome |
| P0 | **Live state** — idle / working / needs you / bridge down | One human phrase + one signal (not only monospaced READY/RUN) |
| P0 | **Last result or live progress** | The large surface must show *something*: latest Codex turn summary, partial stream, or an explicit empty with a next step (“Hold Talk to continue this task”) |
| P0 | **Talk** | One unmistakable hold-to-talk control, always reachable by thumb in landscape |

### Secondary (one tap or persistent but quieter)

- Other mapped lanes as a **side rail** or compact strip with occupancy, not only numbers
- History of turns for the selected task
- Read / hear last answer (Read, Replay, Readout)
- Refresh catalog when bridge is healthy
- Output route (speaker vs device) as a small instrument, not a peer of Talk

### Progressive disclosure (sheet / long-press / overflow)

- **Mapper** — assign / rebind lanes (setup, not every session)
- **Spaces** — leave the Codex deck world
- **Details** — cwd, full branch, task metadata, bridge diagnostics
- **New Task** — consequential; should feel deliberate, not a peer key of Talk
- **Copy**, stop narration, advanced steer/queue modes
- Consequential Mac-side actions if any: always explicit confirmation language

### What must not stay primary

- A 4×4 equal-weight keybed competing with an empty console
- Lane prev/next as large permanent keys when a side rail already exists
- Disabled keys left in the grid as “ghost furniture” teaching nothing about state

---

## 3. Landscape composition (not a scaled phone)

Phone deck logic: vertical stack — console lid → keybed → talk row. That is correct for one hand and limited width.

iPad landscape has **horizontal authority**. Use it.

### Recommended composition

```
┌──────────── header: Talkie · Codex · bridge ────────────┐
│  LANE RAIL (vertical or slim column)  │  STAGE (wide)   │
│  01 · title · signal                  │  identity        │
│  02 · …                               │  live / result   │
│  03                                   │  status sentence │
│  …                                    │                  │
│                                       │  [ Talk  ]       │
│                                       │  secondary tools │
└───────────────────────────────────────┴──────────────────┘
```

### Spatial rules

1. **Stage ≥ 55% of width** for the selected conversation: last result, live stream, or honest idle.
2. **Lane rail on the leading edge** (or a denser top strip with *titles*, not only digits) so switching destinations does not require Mapper or prev/next keys.
3. **Talk docks to the lower stage**, not stranded under a museum of utilities.
4. **Utility keys collapse** into a single “Tools” cluster or a trailing icon rail: Mapper, Spaces, Details, History, Refresh.
5. **Do not stretch the phone 4×4** across the width. Stretching multiplies empty key faces and makes the deck look like an app launcher.

### What landscape buys that phone does not

- Simultaneous **fleet awareness** (other lanes) and **deep focus** (this task’s last answer)
- Room for a **short result paragraph** without opening Read
- Room for **voice guidance** in plain language without covering the stage

If the study only enlarges the current stack, iPad will always feel like “phone deck with more void.”

---

## 4. Clearest mental model

Give the user one sentence they can keep:

> **I pick a lane. A lane is one exact Codex task on a Mac. I talk into that lane. Codex works. I read or hear what came back. I talk again.**

### Objects

| Object | Meaning | User-facing words |
|--------|---------|-------------------|
| **Mac bridge** | The computer running Codex Desktop | “On *this Mac*” |
| **Lane** | A numbered, stable *destination slot* bound to one task | “Lane 3 — Improve iOS connection manager” |
| **Task** | The exact Codex conversation / work item | Title the user already named |
| **Live work** | What Codex is doing *now* on that task | “Working…”, “Needs you on the Mac”, “Ready” |
| **Result** | Last completed turn or latest partial | Readable summary + optional full Read / hear |
| **Voice follow-up** | Next human turn into the *same* lane | Hold Talk |

### Rules the UI must enforce

1. **Lane = destination**, never a vague channel. Empty lanes look empty and invite mapping; mapped lanes show title + signal.
2. **Talk always addresses the active lane’s task.** No ambiguity about “which conversation hears this.”
3. **Results attach to the lane/task**, not to a global readout pile as the primary story (Readout history can remain secondary).
4. **Bridge is ambient trust**, not the product. Promote it only when it fails.
5. Avoid teaching **steer / queue / submit** in the idle chrome. Expose delivery mode only when Codex is already working and a second message arrives.

### Anti-models to reject

- Terminal session (`CODEX>` prompt as primary status)
- Generic multi-agent ops board
- “Remote desktop for the Mac”
- Equal key matrix where Talk is just another function

---

## 5. Four states

Each state should change the **stage** first, chrome second. Same composition skeleton; different content and signal.

### Idle (capture state: task selected, nothing in flight)

**Show**
- Task title, project, branch (identity, not decoration)
- Lane number if mapped; if not mapped, a clear “Unmapped — assign a lane” affordance (not a contradictory badge only)
- Stage: last result if any; else a calm empty with one line: “Ready. Hold Talk to continue.”
- Talk enabled and dominant

**Hide / quiet**
- Terminal READY footer as the only status
- Disabled Read/Copy/Replay as large peers (collapse or dim into tools)

### Codex working

**Show**
- Stage becomes activity: short live status (“Exploring connection manager…”) or streaming text if available
- Lane rail marks this lane **RUN** (or human “Working”)
- Optional: “You can still talk — message will steer/queue” only when they start a second capture
- Stop / interrupt only if product truly supports safe human interrupt; otherwise do not fake it

**Talk** remains available; do not lock the human out of the conversation.

### Needs attention

**Show**
- Stage elevates a clear human sentence: “Codex needs you on the Mac” / “Waiting for approval” / blocked reason if known
- Distinct attention color (single cold signal family already in the thesis — keep it)
- Primary actions: **Open guidance** (what to do), Talk (if voice can unblock), Details
- Lane rail marks attention on that number even when another lane is selected (fleet awareness)

**Do not** bury this in a footer equal to READY.

### Bridge failure

**Show**
- Stage replaces task theater with bridge truth: “Can’t reach ARACHS-MAC-MINI.LOCAL”
- Talk disabled with reason, not mysteriously grey
- One recovery action: Retry / Reconnect / pick another Mac
- Lane content frozen or marked stale so the user does not believe stale “READY”

**Do not** leave a full keybed that implies control while the pipe is dead.

---

## 6. Element disposition (current capture)

### Remain (with refinement)

| Element | Role |
|---------|------|
| Talk (hold) | Front door. Keep largest, most reachable. |
| Task identity (title, repo, branch) | Core answer to “who am I talking to?” |
| Lane concept (1–6 destinations) | Keep; improve occupancy and labeling. |
| Mac bridge chip | Keep ambient; promote only on failure. |
| History / Read / Replay / Readout | Keep as **result tools**, secondary. |
| Mapper | Keep as setup, not permanent co-hero. |
| Status instrument / output route dial | Keep as small instruments if they answer “where does speech go?” |

### Move

| Element | From → To |
|---------|-----------|
| Lane strip | Top monospaced digits → **labeled rail** (side or richer top) with title stubs + signals |
| Last result | Hidden behind Read → **on stage** by default |
| Live status | Footer `CODEX> READY` → **stage status sentence + lane signal** |
| Talk | Bottom of equal keybed → **docked to stage** in landscape |
| Mapper / Spaces / Details / Refresh | Peer keys → **Tools cluster** or overflow |

### Merge

| Merge | Why |
|-------|-----|
| Details + task identity overflow | One “About this task” surface |
| History + Read + Readout family | All are “what came back”; one Results entry with modes |
| Lane prev/next keys + lane ribbon | Redundant transport; one navigation model |
| Status LED window + console footer status | One status language |

### Disappear or demote hard

| Element | Why |
|---------|-----|
| Equal-weight empty/disabled key faces as permanent grid cells | Teaches a hardware deck, not the conversation |
| `NO LANE` as a quiet badge without remedy | Confuses destination model |
| `CODEX>` terminal prompt styling as default calm idle | Violates “not a literal terminal” |
| Key-number instructions (“Hold 14–15”) as primary copy | Expert deck literacy tax |
| Phone-scaled 4×4 as landscape layout | Wrong use of space |

---

## 7. Five design principles for the next iPad study

1. **Destination before controls.**  
   The first readable region answers “which exact task on which Mac.” Lanes are labeled destinations, not anonymous digits.

2. **The stage earns its size.**  
   The largest surface always shows live work, last result, attention, or an honest idle with one next step. Empty black is a failure mode, not a look.

3. **Voice is the front door; tools are the side door.**  
   Talk is compositionally primary. Mapper, Spaces, Details, Refresh never share equal visual weight with Talk on landscape.

4. **One calm status language for humans.**  
   Prefer “Ready”, “Working”, “Needs you”, “Can’t reach Mac” over terminal prompts and expert-only job jargon. Keep the instrument aesthetic without making the user parse a shell.

5. **Landscape is dual-awareness, not upscale phone.**  
   Show the selected conversation in depth and the lane fleet in periphery in one view. Consequential actions stay explicit and human-owned; ambient chrome never pretends authority when the bridge is dead.

---

## Cross-check against the four user questions

| Question | Current capture | Target |
|----------|-----------------|--------|
| 1. What am I talking to? | Partial: title + path + Mac; broken by `NO LANE` and unlabeled other lanes | Active lane title + Mac always; fleet of named lanes at a glance |
| 2. What is Codex doing / does it need me? | Weak footer READY | Stage sentence + lane signal; attention is unmissable |
| 3. What did it most recently produce? | Missing (void console) | Last result on stage; Read/Replay deepen |
| 4. What can I safely say or do next? | Talk yes; rest is a key maze | Talk + one status-appropriate secondary; tools tucked |

---

## Suggested study priority (for Studio / synthesis, not implementation)

1. Landscape **split composition** (lane rail + stage + docked Talk).  
2. **Stage content model** for idle / working / attention / bridge failure.  
3. **Lane occupancy labeling** (title stub + signal).  
4. Collapse the **keybed into tools** without losing power-user speed.  
5. Replace terminal footer status with **human status language** while keeping Talkie’s mineral/instrument chrome.

---

## Closing

The code thesis is right: exact-task instrument, console owns activity, keybed owns talk. The physical capture currently inverts the emphasis — the keybed is busy and the console is empty. The near-technical operator does not need more keys; they need the conversation to occupy the glass.

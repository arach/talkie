# Round 2: Grok critiques Claude Opus

**Round:** 2, Cross-examine  
**Reviewer:** Grok  
**Portfolio under review:** `model-flight/round-1-opus.md`  
**Shared contract:** `IPAD-DESIGN-BRIEF.md`  
**Tracks:** `IPAD-BRIEF-WORKBENCH.md`, `IPAD-BRIEF-FLIGHT-RECORDER.md`  
**Mode:** Adversarial but constructive. Composition and product judgment only. No application code edits.

---

## 0. Evidence classes used in this review

| Class | Meaning |
|---|---|
| **Verified** | Confirmed by physical capture claims in the portfolio, the confirmed briefs, or current iOS Codex models/surfaces inspected for this review |
| **Inferred** | Reasonable from verified structure, not directly proven on device for this flight |
| **Proposed** | Design wish or illustrative content that is not a confirmed bridge capability |

**Verified (capture / briefs):**

- Landscape iPad console is large and, in the captured idle state, does not show the latest exchange.
- Lane ribbon, permanent keybed, `CODEX> READY`, and `NO LANE` are real product defects relative to the task-first decision.
- History and Details exist as destinations; Readout exists as a destination.
- Talk remains hold / slide-to-cancel, bound to one selected task; voice must not approve consequential actions.
- Four first-glance questions and state contract (Idle, Working, Needs you, Mac unavailable) are binding product requirements.

**Verified (current bridge / client models, inspected for data boundary):**

- `CodexTaskSummary` carries identity and recency (`title`, `preview`, `cwd`, `project`, `gitBranch`, `updatedAt`). It does **not** carry a first-class `Idle` / `Working` / `Needs you` enum.
- Live activity on a lane is local/ephemeral (`CodexLaneActivity`: sending, working, queued, receiving, failed). That is not a durable multi-task attention model.
- Channel history for a selected task can load ordered turns (`CodexChannelHistory.Turn`: `status`, timestamps, instructions, updates, `response`). History is a secondary surface today, not a primary canvas feed.
- Changed-file lists and checkpoint timestamps used in the Command Desk probe remain unconfirmed bridge fields. Opus correctly excludes them from design dependency.

**Inferred:**

- A selected-task history sheet can be reshaped into a readable tape **if** turn statuses map cleanly to human events and timestamps are dense enough.
- Per-task plain-language state for unselected tasks may be synthesizable from local activity + latest history, but that synthesis is not verified as product-truthful for every catalog row.
- Last-heard Mac timing can likely be derived from bridge connection state, but the exact “last heard 14 minutes ago” presentation is not proven here.

**Proposed (must not score as if shipped):**

- Truthful continuous activity prose such as “Reviewing bridge discovery and saved ports.”
- A durable `Needs you` state with blocking question text for every design’s attention model.
- Ordered multi-type event streams for **all** tasks at once (Chronicle requirement).
- Elapsed “· 4m” turn timers as a guaranteed field.

This review scores Opus on composition quality **and** on honesty relative to that boundary. Novelty without data is not rewarded.

---

## 1. Portfolio-level judgment

Opus’s Round 1 is the most disciplined of the three portfolios on paper. It does four things right that many concept decks fail:

1. Measures the capture before inventing geometry.
2. Separates confirmed data from proposed data in one inventory.
3. Prints the Talk destination inside the control, not only above it.
4. Names its own failure modes instead of only its strengths.

That discipline makes the weak spots more important, not less. A careful portfolio can still over-score the design that depends on the least verified data, and can still leave a third column that is a dashboard waiting to happen.

### What the self-scores overclaim

Opus’s board:

| Rank | Design | Self-score |
|---:|---|---:|
| 1 | Selected-Task Tape | 88.7 |
| 2 | Fixed Command Desk | 86.9 |
| 3 | Operational Folio | 85.3 |
| 4 | Cross-Task Chronicle | 73.5 |

The claim that the top three are “inside the noise” is **rejected as a decision rule**. Self-awarded spreads of 3–4 points are not noise when criterion 2 and 3 mean different things across tracks, and when Tape’s temporal score assumes event variety the brief still lists as open decision 5.

Revised ranking after this review appears in §8. The short version:

- **Command Desk becomes strongest after revision** because it can be built on verified objects first.
- **Tape remains the best instrument idea**, not the safest primary until event types are counted on a real task.
- **Folio remains the best reading thesis**, with a focus-mode rule that is load-bearing and a portrait Talk collapse that is not acceptable as written.
- **Chronicle remains weakest** as a primary landscape. Its attention promotion idea still survives as a transplant.

---

## 2. One idea that must survive

**Survive: sticky, non-displacing attention for `Needs you`, with voice still bound only to the selected task.**

Across Designs 3 and 4, Opus specifies two complementary forms of this idea:

- Tape: unresolved `Needs you` pins under the header, leaves a chronological placeholder, and never steals Talk from another selected task.
- Chronicle: `Needs you` lanes promote above ordinary chronology without changing voice destination as a side effect.

Why this must survive even if temporal layouts die:

- The shared brief ranks `Needs you` above `Working`.
- The capture’s failure mode is empty area and no result, not missing telemetry. Attention is the other half of that product promise.
- The safety half of the idea is as important as the visual half: **another task’s question must not sit above a Talk control aimed elsewhere without an explicit reselection.**

Secondary survivals that are components, not full compositions:

- Terminal rule at the failure timestamp (honest “time stopped”).
- Destination task name printed inside Talk.
- Omission of `NO LANE` as an error chip.
- Refusal of changed-files / checkpoint filler as design dependencies.

Do not treat “weight decays with age” as the must-survive idea. It is elegant, but it is conditional on event variety. Sticky attention is conditional only on a true `Needs you` signal, which the product already requires as a state contract even if the bridge still needs verification.

---

## 3. One assumption that must be rejected

**Reject: that an ordered multi-type event stream is already rich enough for temporal designs to outrank a conversation workbench by default.**

Opus almost states this correctly in Design 3 §5.9 and Round 2 carry item 2, then still crowns Tape and recommends it as the image study because of “highest marginal information.” That is a process preference, not a product ranking.

**Why the assumption fails the data boundary:**

| Claim in Opus portfolio | Status |
|---|---|
| History exists as a destination | **Verified** (capture + `CodexChannelHistorySheet`) |
| Selected-task turns have status, times, instructions, response | **Verified** as model shape |
| Continuous tape of `Asked` / `Working` / `Result` / `Needs you` for the selected task is the primary surface | **Proposed** as composition; **not verified** as dense, live, distinguishable events |
| Same stream for all tasks simultaneously | **Proposed**; Chronicle cannot exist without it |
| Durable plain-language `Needs you` + question text for every rail row | **Proposed / unverified** (open decision 5; no first-class field on `CodexTaskSummary`) |

Consequence: Tape and Chronicle may not be scored as if their thesis is free. Until someone counts distinguishable event types on one real task:

- At **two** event types (instruction + result), Tape is a conversation view with ceremonial chronology.
- At **four** true event types with times, Tape becomes the stronger instrument.
- Chronicle stays optional fleet machinery either way.

Reject also the soft corollary that “top three are a cluster.” They are three viable structures with **different data taxes**. Cluster language hides the tax.

---

## 4. One interaction / voice-targeting risk

**Risk: visible question without voice ownership.**

Opus is careful, and still leaves a dangerous pattern in the portfolio:

1. **Chronicle inspector** can show another task’s `Needs you` with `Update connection` / `Keep current` / `Not now` while Talk remains bound to the selected task.
2. **Rail attention** across all designs can surface a second task as `Needs you` while the user is reading and speaking into the selected task.
3. **Folio portrait page 2** collapses Talk to a 64-point bar on the Record page. That keeps Talk “not a page away,” but it reduces the one control that must stay unmistakable under stress.

The explicit mismatch line in Chronicle (“Talk goes to …”) is good product writing. It is not enough if the inspector’s primary content is a question the user can answer by voice only after an extra selection step. Near-technical users will speak to the text they are reading.

**Hard rule that should bind all four designs:**

- If a blocking question is readable as primary content, either:
  - the selected task **is** that question’s task and Talk says `Hold to answer`, or
  - the question is secondary chrome (rail chip / compact marker) and cannot present answer-by-voice as if it were live.

Design 3’s refusal to pin another task’s question onto the selected tape is the correct safety instinct. Design 4 reintroduces the hazard in the inspector. That is the portfolio’s real voice risk, not hold/slide mechanics.

---

## 5. One iPad composition / adaptation risk

**Risk: equal-weight multi-pane layouts that become dashboards the moment content is thin.**

Two concrete forms in Opus:

1. **Fixed Command Desk** spends 300 points (25% width) on an Evidence column that Opus admits may only have History and Details. That is the Workbench brief’s stated failure mode: three zones of equal seriousness becoming an admin dashboard.
2. **Operational Folio** runs Task page 460 against Record page 456. Focus depends on navy-versus-chassis value contrast. On a physical iPad in daylight, that is an unproven bet. Opus says so; the scores still treat the Folio as nearly tied for first.

Adaptation amplifies the problem:

- Chronicle **does not survive portrait**; it becomes Tape. That is honest, and it means Chronicle is a landscape-only thesis for a product that must rotate.
- Folio portrait collapses Talk on page 2.
- Command Desk portrait turns the inspector into a drawer, which is fine only if the inspector earned its existence in landscape first.

The iPad-specific win is not “more columns because there is width.” It is a dominant work surface with one predictable Talk edge and progressive disclosure that never pretends thin data is dense instrumentation.

---

## 6. Rubric stress test by structure

Scores below are **reviewer scores after adversarial adjustment**, not a rubber stamp of Opus’s self-scores. Scale 0–100 per criterion, same weights as the track briefs.

### 6.1 Fixed Command Desk (Workbench)

| Criterion | Weight | Opus | Grok | Why adjusted |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 92 | 90 | Strongest single-viewport answer model among the four; still spends area on evidence that may not help Q3 |
| Task and voice clarity | 20% | 90 | 92 | Best fixed Talk geometry; destination-in-capsule is correct |
| iPad-specific composition | 20% | 84 | 78 | Stable, but conventional three-column form; third column is the risk |
| State and failure behavior | 15% | 86 | 84 | Complete contract; chrome band is adequate, not exceptional |
| Talkie instrument identity | 10% | 82 | 80 | Restrained; closest to generic productivity if evidence is thin |
| Adaptation and accessibility | 10% | 80 | 82 | Portrait switcher + drawer is workable; better than Folio page-2 Talk |
| **Total** | | **86.9** | **84.7** | |

**Verdict:** Best default **if** the third column is justified or removed. Do not ship a permanent empty inspector.

### 6.2 Operational Folio (Workbench)

| Criterion | Weight | Opus | Grok | Why adjusted |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 84 | 78 | Q3 depends on value contrast and a 4-point width margin |
| Task and voice clarity | 20% | 82 | 76 | Focus mode resizes Talk; portrait collapsed Talk is a real defect |
| iPad-specific composition | 20% | 90 | 88 | Spread/gutter is the most native Workbench idea; still not free of dashboard risk in focus mode |
| State and failure behavior | 15% | 90 | 90 | Failure-as-page is the best recovery reading surface |
| Talkie instrument identity | 10% | 88 | 86 | Strong technical-folio character without toy hardware |
| Adaptation and accessibility | 10% | 76 | 68 | Pager is fine; Talk on Record page is not |
| **Total** | | **85.3** | **80.6** | |

**Verdict:** Keep the reading thesis and single-open focus rule. Do not keep variable Talk geometry as a personality trait.

### 6.3 Selected-Task Tape (Flight Recorder)

| Criterion | Weight | Opus | Grok | Why adjusted |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 88 | 86 | Best structural answer for latest truth **when events exist** |
| Temporal comprehension | 20% | 86 | 72 | Mechanism is real; score must carry the data tax |
| Voice destination safety | 20% | 92 | 94 | Fixed rail + refuse other-task pin is best-in-portfolio |
| Attention and failure behavior | 15% | 94 | 92 | Sticky question + terminal rule remain outstanding |
| Talkie instrument identity | 10% | 86 | 80 | Risk of log/chat-with-gutter if collapse rules are weak |
| Adaptation and accessibility | 10% | 84 | 86 | Portrait improvement claim is plausible and brief-aligned |
| **Total** | | **88.7** | **84.0** | |

**Verdict:** Strongest **conditional** design. Image-study worthy as a composition experiment, not yet crowned as product default.

### 6.4 Cross-Task Chronicle (Flight Recorder)

| Criterion | Weight | Opus | Grok | Why adjusted |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 74 | 68 | Q3 split across short selected lane and inspector |
| Temporal comprehension | 20% | 78 | 70 | Ordinal axis helps comparison; still expert-shaped |
| Voice destination safety | 20% | 70 | 62 | Explicit rules fight a layout that constantly separates eye from Talk target |
| Attention and failure behavior | 15% | 84 | 86 | Lane promotion and multi-Mac freeze are excellent ideas |
| Talkie instrument identity | 10% | 66 | 58 | Closest to ops dashboard / trace viewer rejection line |
| Adaptation and accessibility | 10% | 62 | 50 | Landscape-only thesis is a product failure for iPad |
| **Total** | | **73.5** | **65.7** | |

**Verdict:** Do not advance as primary. Harvest attention promotion and multi-Mac freeze semantics.

---

## 7. Concrete revision for each structure

### 7.1 Fixed Command Desk — revise the third column contract

**Revision:** Make the inspector **width-conditional**, not faith-based.

1. Default landscape: **two columns** — rail ~280 pt, navy work surface the rest, History attached to task header / result foot.
2. Promote a third column only when at least two evidence modules have real content for the selected task (History list + Details, or History + Readouts). Empty modules do not reserve 300 points.
3. If a third column appears, it must still lose to the navy surface by at least ~120 points of width (Opus’s own Command Desk vs Folio comparison).
4. Keep fixed geometry **within a mode** (two-column mode or three-column mode). Do not animate column count on every state change; change only when evidence presence changes, with no custom layout work for the user.

This prevents the admin-dashboard failure without throwing away the Bridge-inspired stable desk.

### 7.2 Operational Folio — fix focus asymmetry and Talk invariance

**Revision:** Enforce a permanent focal inequality and an invariant Talk shelf.

1. Landscape split must not be ~50/50. Target **≥520 pt Task / ≤396 pt Record** in the default spread (Opus’s own rescue number), not 460/456.
2. Focus mode may expand Record, but Talk stays **fixed height, fixed bottom corner, fixed helper vocabulary**. Width may change slightly; corner and hit target may not.
3. Portrait: Talk is full-width on **both** pages at the same 96 pt class used in landscape. Delete the 64 pt collapsed Record Talk.
4. Keep single-open module rule absolute. No remembered widths. No drag edges.

### 7.3 Selected-Task Tape — gate the thesis on an event census

**Revision:** Split the design into **Conversation mode** and **Tape mode**, same chrome.

1. Before implementation or north-star lock, count distinguishable event types on one real selected task with timestamps.
2. If fewer than four meaningful types, render a conversation work surface with optional quiet timestamps — **not** weight-decay ceremony, spine, and collapse rules that buy nothing.
3. If four or more, enable full tape rules: decay, sticky `Needs you` with placeholder, terminal failure rule, `Return to now`.
4. Add a hard floor: sticky question + newest result together may not reduce scrollable history below ~200 pt; collapse the question to a one-line `Show question` control rather than eating the record.
5. Keep the peripheral rail’s latest-event word only when that word is truthful for unselected tasks; otherwise show state only when verified.

### 7.4 Cross-Task Chronicle — demote from primary to overview strip

**Revision:** Stop treating Chronicle as a full-canvas primary.

1. Primary landscape becomes selected-task surface (Desk/Folio/Tape after their revisions).
2. Chronicle reduces to a **compact multi-task overview**: full names, state chips, one latest-event word, optional `Needs you` promotion group. No swimlane time axis as the main canvas.
3. Preserve only:
   - `Needs you` group above ordinary tasks;
   - explicit `Select this task` before voice can answer a non-selected question;
   - multi-Mac freeze semantics if multiple Macs exist.
4. Portrait already becomes Tape in Opus’s draft; make that the honest product story instead of a degraded special case.

This keeps the opposing thesis’s useful attention mechanics without violating the “not an operations dashboard” rejection line.

---

## 8. Strongest and weakest after revision

### Strongest after revision: Fixed Command Desk (two-column default, evidence on demand)

**Why:**

- Answers all four first-glance questions on verified objects: named tasks, selected Mac, plain state when known, latest exchange region, fixed Talk consequence.
- Lowest data tax of the four. Degrades when `Needs you` or activity prose is missing without losing the composition.
- Best muscle-memory story for a near-technical daily driver.
- After the third-column revision, it stops being the dashboard risk Opus correctly feared.

**What it should steal from the others:**

- From Tape: sticky `Needs you` block that does not scroll away; terminal honesty in failure copy (`Last known · time`).
- From Folio: optional evidence focus as a sheet or temporary expansion, not a second equal page by default.
- From Chronicle: rail-level `Needs you` promotion group.

### Weakest after revision: Cross-Task Chronicle as primary landscape

Even after demotion of its worst habits, the full swimlane canvas remains the wrong primary for the stated user (one person, one to three Macs, two to six tasks). A 260 pt rail already carries fleet awareness. Horizontal ordinal time for five lanes solves a problem the brief does not assign as primary and fails portrait.

Chronicle’s ideas are stronger as **components** than as a structure.

### Conditional second place: Selected-Task Tape

If the event census returns four true types, Tape can overtake Command Desk as the instrument with the best latest-result behavior and the best failure legibility. Until that census, ranking Tape first is novelty-adjacent confidence dressed as measurement.

### Operational Folio after revision

Viable alternative default for users who read long evidence often. Not the safest first ship. Its focus-mode discipline is excellent; its default geometry and portrait Talk need the revisions in §7.2 before it competes with the Desk.

---

## 9. Bridge data boundary scorecard against Opus §7

| Proposed / required data | Opus claim | Reviewer call | Effect on designs |
|---|---|---|---|
| Task name, project, path, branch, Mac | Confirmed by capture | **Verified** | All four OK |
| Lane optional / unmapped valid | Corrected by omitting `NO LANE` | **Verified** product decision | All four OK |
| History / Details destinations | Confirmed | **Verified** | Desk/Folio evidence must start here |
| Working activity prose | Proposed; degrade to plain Working | Agree | Do not design empty navy around missing prose |
| Durable `Needs you` + question text | Proposed; highest-value verification | **Still unverified**; agree it is the flight’s top check | All attention models are provisional until proven |
| Selected-task ordered events | Required by Tape | **Partially verified** as history turns; not verified as live primary feed | Tape conditional |
| All-task ordered events | Required by Chronicle | **Proposed / absent** | Chronicle cannot be primary |
| Changed files / checkpoints | Excluded by Opus | Correct exclusion | Probe content must not leak into product specs |
| Token counts / traces | Forbidden | Correct | No score credit for avoiding them — it is table stakes |

Opus’s data inventory is one of the best parts of the portfolio. The critique is that **Tape still wins the self-rank despite that inventory**. Honesty in §7 should have forced a conditional ranking in §8–§9. This Round 2 review applies that force.

---

## 10. Direct answers required by the Round 2 assignment

| # | Required item | Answer |
|---|---|---|
| 1 | Idea that must survive | Sticky `Needs you` attention that cannot be scrolled away, cannot rebind Talk by side effect, and leaves an honest chronological placeholder when pinned |
| 2 | Assumption to reject | That multi-type timestamped event streams are rich enough to make temporal primaries (especially Tape) outrank a conversation workbench by default |
| 3 | Interaction / voice risk | Primary-readable question on a non-selected task (Chronicle inspector / dual attention) while Talk still targets another task |
| 4 | iPad composition risk | Equal-weight multi-pane layouts (300 pt thin inspector; 460/456 folio) becoming dashboards or losing focus under real light and thin data |
| 5 | Revision per structure | Desk: width-conditional evidence, two-column default. Folio: ≥520/≤396 default, invariant Talk, no portrait collapse. Tape: event-census gate + 200 pt history floor. Chronicle: demote to overview strip, harvest promotion rules only |
| 6 | Strongest / weakest after revision | **Strongest:** Fixed Command Desk (revised). **Weakest:** Cross-Task Chronicle as primary. **Conditional challenger:** Selected-Task Tape after event census |

---

## 11. What Opus should keep hearing in Round 3

1. Do not combine Folio focus mode with Chronicle lane canvas. Opus already said this; keep it absolute.
2. Do not use probe filler (changed files, checkpoints) to justify geometry.
3. Do not let self-score clusters substitute for data taxes.
4. The three portable state ideas (sticky question, terminal failure rule, `Needs you` promotion) are more valuable than any one full composition winning on paper.
5. The product promise remains: **See the work. Hear what came back. Speak the next move.** Geometry that cannot keep that promise on verified bridge objects is concept art, not a ship target.

---

## 12. Bottom line

Claude Opus produced a serious, self-critical portfolio with the correct porcelain language, the correct voice contract, and the best portable attention ideas in the flight so far. The adversarial correction is simple:

- **Keep** sticky attention and voice-destination honesty.
- **Reject** temporal primacy before the event census.
- **Ship-shaped default** after revision is the Fixed Command Desk with a dominant navy conversation surface and evidence that appears only when it has something true to say.
- **Do not** advance the Cross-Task Chronicle as the iPad primary.
- **Image-study Tape** is still worth drawing, but as a conditional instrument test, not as a silent coronation.

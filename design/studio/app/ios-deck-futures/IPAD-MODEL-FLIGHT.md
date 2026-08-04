# iPad model flight

**Status:** Complete  
**Date:** 2026-08-01  
**Workspace:** `/Users/arach/dev/talkie`  
**Surface:** `/ios-deck-futures`  
**Models:** Kimi, Grok, Claude Opus  
**Budget:** Three rounds, three model contributions per round, nine contributions total

## Outcome

Use Kimi, Grok, and Claude Opus as an equal design panel. The panel must expand,
challenge, and then reduce the iPad design field. The panel must not decide by
majority vote or produce nine isolated opinions.

The flight uses the confirmed design briefs:

- `IPAD-DESIGN-BRIEF.md`
- `IPAD-BRIEF-WORKBENCH.md`
- `IPAD-BRIEF-FLIGHT-RECORDER.md`

## Dispatch algorithm

The flight has three rounds. Every model receives one assignment in each round.

### Round 1: Diverge

Each model independently proposes a complete four-design portfolio:

1. Fixed Command Desk
2. Operational Folio
3. Selected-Task Tape
4. Cross-Task Chronicle

Each proposal must use the shared content, Porcelain treatment, state contract,
and review rubric. Independence in this round prevents early consensus from
reducing the design field.

### Round 2: Cross-examine

Each model reviews one peer portfolio. The review chain is a closed rotation:

| Reviewer | Portfolio under review |
|---|---|
| Kimi | Grok |
| Grok | Claude Opus |
| Claude Opus | Kimi |

Each reviewer must identify one idea to preserve, one assumption to reject, one
interaction risk, one iPad composition risk, and one concrete revision.

### Round 3: Converge

Each model reads all Round 1 and Round 2 results. Each model then synthesizes the
field through one assigned lens:

| Model | Synthesis lens |
|---|---|
| Kimi | iPad composition, adaptation, and accessibility |
| Grok | conceptual distinction, Talkie identity, and useful boldness |
| Claude Opus | interaction architecture, safety, and data truth |

Each synthesis must rank the four design structures. Each synthesis may combine
compatible features. Each synthesis must name features that must not be
combined.

## Selection rule

The final comparison uses the weighted rubrics in the two track briefs. Model
agreement is evidence, not the score. A design advances when the design:

1. answers the four first-glance questions;
2. keeps voice bound to one exact selected task;
3. preserves the latest useful result;
4. treats `Needs you` as more important than `Working`;
5. gives the iPad a composition that is not an enlarged iPhone;
6. uses only current bridge data or labels proposed data;
7. retains Talkie's restrained instrument identity.

## Image probes

Three internal Codex sub-agents generate parallel north-star probes:

1. Fixed Command Desk
2. Operational Folio
3. Flight Recorder

The probes test composition only. Porcelain, realistic content, exact task
selection, and voice safety remain fixed. The probes are not implementation
specifications and must not be traced into Swift.

### Probe 1: Fixed Command Desk

![Fixed Command Desk](/studies/ios-deck-futures/ipad-probe-command-desk.png)

The probe makes the selected task, current activity, evidence, and voice
consequence visible in one scan. The stable geometry is the clearest path to
muscle memory. The image also exposes two risks: the evidence panel can become
a dashboard, and secondary status colors can compete with cobalt.

### Probe 2: Operational Folio

![Operational Folio](/studies/ios-deck-futures/ipad-probe-operational-folio.png)

The probe gives the latest exchange and evidence enough room for serious
reading. The image proves that a persistent voice shelf can coexist with a large
evidence page. The image does not yet prove the folio thesis because the result
still reads as a polished three-column application. The Talk control is also too
large for an idle state.

### Probe 3: Flight Recorder

![Flight Recorder](/studies/ios-deck-futures/ipad-probe-flight-recorder.png)

The probe gives `Needs you` the strongest treatment of the three images. The
fixed voice rail also makes the destination unusually explicit. The temporal
tape consumes substantial width for one task, and a production design would
need a clear strategy for long results, deep history, and unavailable Macs.

### Initial visual judgment

The Fixed Command Desk is the strongest default structure. The Flight Recorder
contains the strongest attention pattern. The Operational Folio contains the
strongest reading model. A later synthesis should test whether the command desk
can adopt the recorder's pinned `Needs you` event and the folio's evidence focus
mode without becoming a hybrid dashboard.

## Receipts

### Round 1

| Model | Scout flight | Conversation | Ref | Result path |
|---|---|---|---|---|
| Kimi | `flt-msamn77o-msrtbs` | `chn-79b289a70d994023b292b7fcda95a3b6` | `o-msrtbs` | `model-flight/round-1-kimi.md` |
| Grok | `flt-msamnay3-ef3a5y` | `chn-8779dc1cc9f44678a8bfe64fbdd34230` | `3-ef3a5y` | `model-flight/round-1-grok.md` |
| Claude Opus | `flt-msamngwf-x2lfhy` | `chn-f542a305ab6e4fd3a3c602f4347cc4a2` | `f-x2lfhy` | `model-flight/round-1-opus.md` |

All three Round 1 requests completed through the requested profiles. Grok used
the `grok-acp` runtime. Kimi used the `kimi` runtime. Claude Opus used the
`opus` profile with high effort.

Round 1 produced an intentional disagreement:

- Kimi ranked Fixed Command Desk first and nominated Operational Folio for an
  image study.
- Grok ranked Fixed Command Desk first and nominated Fixed Command Desk for an
  image study.
- Claude Opus ranked Selected-Task Tape first and nominated Selected-Task Tape
  for an image study.

The normalized Round 1 scores show a close three-design field:

| Design | Kimi | Grok | Claude Opus | Mean |
|---|---:|---:|---:|---:|
| Fixed Command Desk | 8.60 | 8.75 | 8.69 | **8.68** |
| Selected-Task Tape | 8.20 | 8.48 | 8.87 | **8.52** |
| Operational Folio | 8.10 | 8.66 | 8.53 | **8.43** |
| Cross-Task Chronicle | 7.10 | 7.55 | 7.35 | **7.33** |

The mean is a diagnostic summary. The final selection rule remains the product
rubric and verified data boundary, not model consensus.

### Round 2

| Reviewer | Portfolio | Scout flight | Conversation | Ref | Result path |
|---|---|---|---|---|---|
| Kimi | Grok | `flt-msamv9uh-6bxixx` | `chn-ef0821bf321343c9aa0ff23c912d76cb` | `h-6bxixx` | `model-flight/round-2-kimi-critiques-grok.md` |
| Grok | Claude Opus | `flt-msamweh2-kmt3qh` | `chn-a5baece4874d423cabc3d8cc742f54e0` | `2-kmt3qh` | `model-flight/round-2-grok-critiques-opus.md` |
| Claude Opus | Kimi | `flt-msamydrd-hcmfyp` | `chn-87b22855a23a41d883e91968ddfb20a4` | `d-hcmfyp` | `model-flight/round-2-opus-critiques-kimi.md` |

Round 2 completed. All three reviewers independently converged on the same
structural correction:

- Keep the Fixed Command Desk as the base composition.
- Move the Recorder's pinned `Needs you` treatment into the desk.
- Treat the evidence area as a turn inspector, not a general-purpose dashboard.
- Do not promote the Cross-Task Chronicle. Its useful attention pattern is
  portable, while its shared time axis and voice-targeting risks are not.
- Do not claim a live state for every task. The bridge can describe activity
  truthfully only for tasks and turns it can observe.

The remaining disagreement is narrow and useful: whether the verified update
stream belongs in the selected task's primary reading surface or inside the
turn inspector.

### Round 3

| Model | Synthesis lens | Scout flight | Conversation | Ref | Result path |
|---|---|---|---|---|---|
| Kimi | Composition, adaptation, accessibility | `flt-msan9hag-nejzs9` | `chn-19cdc78707ba479eb2a23f42b9764eaf` | `g-nejzs9` | `model-flight/round-3-kimi-composition.md` |
| Grok | Distinction, Talkie identity, useful boldness | `flt-msan9h64-qwi0uo` | `chn-2f4413b0568f41d3a75e0098b4e81520` | `4-qwi0uo` | `model-flight/round-3-grok-identity.md` |
| Claude Opus | Interaction, safety, data truth | `flt-msan9h4e-i7f0uh` | `chn-d320099d20d24f8c962f3fde84c604fd` | `e-i7f0uh` | `model-flight/round-3-opus-interaction.md` |

Round 3 completed through all three requested profiles. The final rankings were:

| Model | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Kimi | Fixed Command Desk | Selected-Task Tape | Operational Folio | Cross-Task Chronicle |
| Grok | Fixed Command Desk | Operational Folio | Selected-Task Tape | Cross-Task Chronicle |
| Claude Opus | Fixed Command Desk | Selected-Task Tape | Operational Folio | Cross-Task Chronicle |

## Findings

### Decision

Advance a revised **Fixed Command Desk**, named the **Talkie Task Desk** for the
next study. This is not a majority-vote result. It is the only structure whose
composition, voice targeting, accessibility behavior, and data diet survive the
adversarial reviews together.

The production shape is:

1. A 260–280 pt task rail with one selection model and truthful state or
   recency. Unknown state renders as no state chip, never false `Idle`.
2. One dominant navy live-work surface holding task identity, the latest
   instruction, truthful activity, and the latest useful result.
3. A width-conditional **Turn inspector**, bound to one turn. It appears only
   when at least two real evidence modules earn the space. It never reserves an
   empty third column.
4. An invariant 96 pt Talk shelf with the destination task name inside the
   control. Selection locks from capture start through dispatch or cancel.
5. A pinned attention strip only for a `blocked` turn that this device actually
   dispatched. The strip survives task switching without retargeting Talk.

### Adopt without adopting the donor structure

- From Selected-Task Tape: sticky attention, terminal failure honesty, and
  quiet in-turn timestamps or updates when the event census supports them.
- From Operational Folio: strong long-result reading and failure as a readable
  recovery surface.
- From Cross-Task Chronicle: promote known attention tasks above recency in the
  task rail. Do not adopt the shared time axis.

### Do not combine

- Do not ship Stop, Approve, Deny, or answer-by-voice controls. The bridge has
  no turn-cancel endpoint and deliberately refuses approvals.
- Do not show state chips for tasks whose state Talkie cannot observe.
- Do not combine a focus-resizing folio with a timeline or conditional evidence
  column. Talk must not move because the user reads evidence.
- Do not let event, result, history, or empty-canvas taps rebind the voice
  destination.
- Do not make the Chronicle or a generic dashboard the primary iPad surface.

### Required brief correction

The final safety pass found that `Needs you` is observable but not resolvable in
Talkie. Replace `Hold to answer` with a disabled message such as
`Answer this in Codex Desktop on Arachs-Mac-Mini.Local`. The attention state
still outranks `Working`, but the interface must not promise an action that the
bridge cannot complete.

### Next visual pass

After approval, create two production-oriented Task Desk variants:

1. **Default and Working:** two-column desk, evidence on demand, latest result
   as the reading anchor.
2. **Needs you and Mac unavailable:** the same geometry, with the pinned
   attention and honest recovery treatments. No new action vocabulary.

Before implementation, run one physical-device event census for a task
dispatched from this iPad. Confirm the real event density, the continuity of
activity prose, and whether `blocked` is observable in normal deck use. Those
facts decide how much permanent geometry the update stream and attention strip
deserve.

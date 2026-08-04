---
target: current iPad More Console study
total_score: 32
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
timestamp: 2026-08-02T02-23-57Z
slug: app-ios-deck-futures-round-3-incremental-deck-tsx
---
# Impeccable critique — iPad command deck, Round 3 Take 04

## Design health score

| Heuristic | Score | Rationale |
| --- | ---: | --- |
| Visibility of system status | 3/4 | Host, active task, task state, and now every lane state are visible without fake telemetry. |
| Match between system and real world | 4/4 | The deck uses the established agentic vocabulary: STEER, TASK, MAPPER, and QUEUE retain their canonical meanings. |
| User control and freedom | 3/4 | Voice, lane selection, delivery mode, direct commands, refresh, stop, and recovery are all visible. |
| Consistency and standards | 4/4 | The same instrument language, geometry, command vocabulary, and state model carry across all task scenes. |
| Error prevention | 3/4 | STEER and QUEUE are explicit modes, destructive-looking actions are isolated, and offline state redirects to connection recovery. |
| Recognition rather than recall | 3/4 | Controls are labeled and per-lane codes are exposed; terse operational codes still assume near-technical fluency. |
| Flexibility and efficiency | 3/4 | Voice is the fastest path, while direct keys and delivery modes support experienced use. |
| Aesthetic and minimalist design | 4/4 | The black-glass console, cream keybed, restrained amber signal, and disciplined stack remain calm and product-specific. |
| Error recognition and recovery | 3/4 | ERR is visually distinct, the active task remains readable offline, and Review connection is a direct recovery action. |
| Help and documentation | 2/4 | The surface relies on familiar agentic terms and labels; deeper explanations belong outside the primary deck. |
| **Total** | **32/40 — Good** | Strong, distinctive, and operationally coherent, with remaining questions best answered through device use rather than more speculative chrome. |

## Specificity verdict

This is unmistakably Talkie rather than a generic dashboard. It combines voice-first control, exact Codex task state, a physical command-instrument metaphor, and the established agentic vocabulary without drifting toward an IDE.

## Overall impression

Take 03 already had the right composition. Take 04 succeeds by leaving that composition alone and repairing two practical weaknesses: hidden lane status and undersized small controls. The deck is now more useful without looking busier.

## What is working

- The active task is the visual center of gravity.
- Six lanes are legible as operational lanes, not app navigation.
- STEER and QUEUE communicate delivery semantics directly and keep their canonical meanings.
- The 4 by 4 command field remains glanceable and tactile.
- Offline state preserves task context and points directly to connection recovery.
- No fake percentages, timing, queue depth, token counts, or invented telemetry appear.

## Priority issues and fixes

### P0

None.

### P1

None.

### P2 resolved in Take 04

1. Nonactive lane states existed in the DOM but were visually hidden. Take 04 exposes RDY, QUE, RUN, RX, and ERR in the lane rail while preserving the selected-lane emphasis.
2. STEER and QUEUE were approximately 38.5 by 27 points, and Review connection was 34 points high. Take 04 brings delivery controls to 44 by 44 points and the recovery action to 44 points high.

### P3 follow-up

- Validate the dim RDY state and six-point lane-code typography on a physical iPad under normal room brightness.
- Treat the horizontally preserved deck at narrow browser widths as a study constraint, not a phone layout recommendation.
- Keep deeper status explanation outside the instrument unless device testing proves the codes are genuinely unclear.

## Persona walkthroughs

### Alex — near-technical Codex operator

Alex can see which task is running, which one is queued, and whether the Mac bridge is available without reading a log. They can speak a direction, choose STEER or QUEUE, and use TASK or MAPPER without the product redefining those terms.

### Sam — voice-first user

Sam sees TALK as the largest, warmest action and can stay in the voice path. The command field remains available without competing with the active task.

### Jordan — troubleshooting a bridge

Jordan keeps the current task context when the Mac Mini drops offline, sees ERR at both task and lane level, and gets a reachable Review connection action instead of a dead-end error.

## Minor observations

- Six lanes and fourteen command actions exceed a simple four-choice surface, but the cognitive load is intrinsic to the command deck and is strongly chunked into lane, console, and keybed regions.
- The studio-only state switcher is 36 points high; it is not part of the iPad product surface.
- Take 03 remains available and unchanged as the clean incumbent baseline.

## Evidence

- Deterministic Impeccable detector: zero findings.
- Verified Ready, Working, Result, and Offline scenes with truthful lane codes.
- Verified Take 04 STEER and QUEUE at 44 by 44 points and Review connection at 44 points high.
- Verified Take 03 still hides the supplemental lane codes and retains the original 27-point delivery controls.
- Verified 1720 by 1263 and 1180 by 820 browser presentations without document-level horizontal overflow; the narrow 700-point study intentionally preserves the 760-point deck minimum width inside a horizontal scroller.

## Recommended next move

Put Take 04 on the physical iPad and judge only three things: dim-state legibility, thumb reach to STEER and QUEUE, and whether ERR to Review connection feels immediate. Do not add more interface until that use produces a concrete failure.

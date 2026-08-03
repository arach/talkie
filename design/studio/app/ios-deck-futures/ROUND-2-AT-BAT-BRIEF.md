# Round 2: full-size iPad design at-bat

## Outcome

Build one runnable Talkie Studio proposal for a near-technical person who uses Talkie on iPad to direct and supervise Codex work on a Mac.

The proposal must look and feel as authored as the existing Camera, Agent Bay, Mac Recording State, and Mac Compose studies. The deliverable is a polished, full-size design artifact. A written explanation is secondary.

## User and task

The user understands tasks, Macs, projects, and recoverable connection problems. The user does not want an IDE on iPad.

The surface must help the user:

1. See which Codex task currently matters.
2. Understand the latest useful state in plain language.
3. Read a useful result without opening Codex Desktop.
4. Speak a follow-up to one exact task.
5. Recognize when the selected Mac is unavailable and enter a clear recovery path.

Talkie is the voice and context front door. Codex remains the execution environment.

## Visual authority

Inspect these live studies and their source before choosing a direction:

- `/camera` and `design/studio/components/studies/CameraStudy.tsx`
- `/agent-bay` and its material treatments
- `/mac-recording-state` and its recorder composition
- `/mac-compose` and `design/studio/components/studies/MacCompose.tsx`

Use the studies as evidence of Talkie's craft level, material language, typography, restraint, and compositional confidence. Do not copy their layouts.

The proposal must have one product-specific spatial premise. A reviewer must be able to recognize the premise with all text blurred.

## Required states

Make at least three meaningful states selectable in the study:

- active work;
- useful result;
- Mac unavailable or connection recovery.

The selected task and the destination of voice input must remain explicit in every state.

Use truthful labels. Do not invent progress percentages, token counts, queue depth, continuous telemetry, reasoning traces, or capabilities that the bridge does not provide.

## Form and interaction

- Design for a 12.9-inch iPad in landscape at a 4:3 ratio.
- Let the work artifact dominate the screen.
- Use iPad-native reach, touch targets, sheets, focus, and direct manipulation.
- Include one memorable voice object or transition that belongs specifically to Talkie.
- Use sparse, meaningful chrome.
- Keep technical evidence subordinate and reveal it only when requested.
- Preserve calm, premium, technical-instrument character without fake hardware.

## Reject before implementation

Do not build any of these structures:

- sidebar plus cards plus toolbar;
- generic admin dashboard;
- chat app with a task list attached;
- split-pane IDE, terminal, file tree, diff viewer, or inspector;
- decorative telemetry or sci-fi control room;
- a light and dark restyle of an existing proposal;
- a research board, comparison deck, or long written rationale in place of the artifact.

If the proposal can be summarized as one of those structures, choose another premise before writing code.

## Implementation boundary

Create only the assigned route directory under:

`design/studio/app/ios-deck-futures/round-2/<model>/`

The route must be runnable inside the existing Studio application. Keep the implementation self-contained in that directory. Do not edit the existing `ios-deck-futures` page, shared Studio navigation, native iOS code, package manifests, or another model's directory. Do not add dependencies.

The current checkout contains user work. Preserve every existing modification.

## Acceptance checks

1. Open the assigned route at a 4:3 landscape viewport. The complete iPad proposal is visible without explanatory content preceding it.
2. Switch among active, result, and unavailable states. The composition changes meaningfully without losing the selected task or voice destination.
3. Blur or ignore the copy. The proposal still has a distinctive silhouette and one obvious focal object.
4. Compare the render with Camera, Agent Bay, Mac Recording State, and Mac Compose. The proposal has comparable finish and commitment.
5. Confirm that the surface does not resemble an IDE or a generic dashboard.
6. Run the narrowest available Studio type or build check that does not modify shared files.

## Completion report

Report:

- the one-sentence spatial premise;
- the route;
- files created;
- states implemented;
- checks run;
- one honest design risk.

Do not return a design essay without the runnable artifact.

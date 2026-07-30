---
version: 1
slug: "apps-ios-talkie-ios-codex-codexnewtaskview-swift"
primary_target: "apps/ios/Talkie iOS/Codex/CodexNewTaskView.swift"
related_targets: ["apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift"]
---

# Codex new task creation

- Scope: the dedicated iPhone sheet opened by the Command Deck NEW key.
- Mode: Operate.
- Audience and job: a developer starts a fresh Codex task in a known project, then immediately speaks into it.
- Primary action: select one project and create one task with the Mac's default model.
- Constraints: creation never changes lane assignments; model selection is not exposed; the mapper remains a separate existing-task workflow; native sheet navigation, Dynamic Type, VoiceOver, Reduce Motion, and 44-point targets remain intact.
- Direction: Signal Path. A compact PROJECT to TASK to TALK rail explains the entire transition. Projects remain flat grouped rows; selection is one amber trace plus a checkmark. The bottom action names the destination and never duplicates the selected project as a second card.
- Memorable moment: after creation, the rail advances from PROJECT to TASK and then TALK before the sheet dismisses onto the already-selected task in the Command Deck.
- Unresolved: validate density and success timing on the physical iPhone before final polish.

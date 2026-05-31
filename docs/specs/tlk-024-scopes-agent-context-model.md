# TLK-024 - Agent Context Model

**Status**: Product exploration
**Owner**: Talkie product + agent runtime
**Date**: 2026-05-30
**Studio**: /eng/tlk-024
**Related**: [TLK-004](tlk-004-file-based-context-system.md) (file-based context roots), [TLK-011](tlk-011-skill-presentation.md) (skills), [TLK-021](tlk-021-agent-home-architecture.md) (agent home), [TLK-022](tlk-022-media-augmentation-pipeline.md) (sidecars), [TLK-023](tlk-023-action-workbench.md) (action runs)

## Summary

This spec sketches the context primitive Talkie needs when capture is built for
agents, assistants, skills, and durable context from the start.

Talkie should remain the fast human input layer: voice, dictation, notes,
screenshots, and ambient context captured without breaking flow. The missing
object is a bounded working context those captures can enter when an assistant
needs to understand, route, transform, or act on them.

Working language:

```text
Talkie captures.
Bounded contexts organize the work.
Agents work inside those contexts.
```

For now, treat "Scope" as a working term for this bounded context model, not as
committed product naming or a public rebrand. The concept is the important part.
It sits above captures, skills, actions, and agent sessions.

## Origin

Talkie started from the limitations of voice dictation flows that end at text
insertion. That class of tool is useful, but the interaction usually terminates
too early:

- speech becomes text, then loses its surrounding context
- the active text field becomes the only destination
- corrections and routing are ad hoc
- follow-up work has to be manually copied into other apps or agents
- repeated personal workflows do not become first-class capabilities
- the user's local environment is outside the assistant's working model

The Talkie answer is not just "better dictation." It is a capture system where
the spoken moment can become structured context, routed work, memory,
automation, and agent collaboration.

Bounded agent context is the missing container for that answer.

## Product Definition

A **Scope** is the working term for a bounded, user-owned context where Talkie
can collect relevant captures, expose selected resources, run skills, and let
agents operate with explicit limits.

Examples:

| Scope | What belongs there |
| --- | --- |
| `talkie-ios` | iOS app captures, screenshots, feature notes, test results, related Codex sessions |
| `personal-admin` | errands, reminders, email drafts, receipts, calendar follow-ups |
| `client-acme` | meeting notes, links, project docs, follow-up tasks, allowed integrations |
| `daily-standup` | yesterday's commits, open PRs, dictated notes, generated summary action |
| `writing-book` | voice fragments, source notes, outlines, reading context, draft exports |

The important property is not the category name. The important property is that
the assistant knows what it is allowed to see, what tools it can use, and what
"done" usually means inside that bounded context.

## Relationship To Existing Terms

Scopes sit above the existing Talkie primitives:

| Primitive | Meaning |
| --- | --- |
| Capture | A raw or lightly processed thing the user made: audio, dictation, note, screenshot, URL, selection |
| Memo | A durable capture object, usually voice-first |
| Skill | A packaged capability the user teaches Talkie |
| Action | A concrete invocation or manifestation of a skill/workflow/agent command |
| ActionRun | The durable runtime record for one execution |
| Agent Session | A conversational or delegated runtime thread |
| Scope | The bounded context that ties captures, skills, actions, agents, memory, and permissions together |

This avoids making "Scope" compete with "Skill" or "Action." A skill can be
available in one or more scopes. An action run happens inside a scope. An agent
session gets its working set from a scope.

## What A Scope Contains

A scope should eventually be able to declare:

| Field | Purpose |
| --- | --- |
| `id` | Stable local identity |
| `slug` | Human-readable route and file name |
| `name` | Display name |
| `description` | What this context is for |
| `captureRules` | How new captures are suggested or assigned |
| `resources` | Files, folders, URLs, apps, calendars, contacts, repositories, or databases made visible |
| `skills` | Skills available by default inside the scope |
| `agents` | Assistants or runtimes allowed to work inside the scope |
| `permissions` | What may be read, written, sent, posted, or executed |
| `memoryPolicy` | What should be remembered, summarized, embedded, or forgotten |
| `retentionPolicy` | How long local context should remain |
| `views` | Preferred user surfaces: timeline, workbench, agent trace, library filter |
| `automations` | Scheduled or event-bound scope work |

The first implementation does not need all of these. The shape matters because
it prevents Scopes from becoming just tags or folders.

## Agent Model

Agents need scoped context for three reasons:

1. **Grounding** - The agent sees the captures, files, sidecars, and prior runs
   that matter for the job instead of an unbounded personal history.
2. **Permission** - The agent knows what it may read or change before it starts
   work.
3. **Continuity** - Repeated work in the same area gets better because prior
   decisions, outputs, and corrections live in the same place.

An agent invocation should carry a `scopeId` when possible:

```json
{
  "source": "voice",
  "transcript": "turn this into a GitHub issue and attach the screenshot",
  "scopeId": "talkie-ios",
  "subjects": [
    { "kind": "capture", "id": "..." },
    { "kind": "screenshot", "assetURL": "..." }
  ],
  "requestedSkill": "log-bug"
}
```

If the source surface cannot provide a scope directly, Talkie can infer a
candidate from app context, window title, active repository, capture history, or
the user's recent manual choices. Inference should be visible and correctable.

## UX Principles

- Capture should stay fast. Scope resolution must not slow the recording or
  dictation moment.
- Scope assignment can be suggested after capture, enriched in the background,
  or corrected later.
- The user should be able to say "send this to the Talkie iOS scope" as a
  natural routing command.
- A Scope should feel like a working room, not a settings folder.
- Agents should explain which scope they are using before doing meaningful
  side-effectful work.
- Scope membership should be inspectable: why is this capture here, what did it
  trigger, and what can see it?
- The default scope should be "Inbox" or "Unscoped" so capture never blocks on
  organization.

## Portability

Portability is the future ecosystem layer for this model.

Internally, Talkie can use whatever persistence is fastest. Externally, an
exported context package should make a bounded context understandable to other
agents and tools:

```text
my-context/
  scope.json
  README.md
  skills/
  resources/
  rules/
  memory/
  runs/
```

An exported package is not just notes. It is a portable bounded context:
description, allowed resources, skills, memories, and enough provenance for
another assistant to work responsibly.

This aligns with [TLK-004](tlk-004-file-based-context-system.md), but raises the
container from a generic `.talkie/` context root to a user-facing product object.
The file-based system can be one implementation strategy for this portable
context layer.

## Data Model Sketch

Phase 1 can be intentionally lightweight:

```swift
struct ScopeDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var slug: String
    var name: String
    var description: String
    var color: String?
    var icon: String?
    var captureRules: [ScopeCaptureRule]
    var skillIds: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct ScopeAssignment: Identifiable, Codable, Hashable {
    var id: UUID
    var scopeId: UUID
    var subjectKind: ScopeSubjectKind
    var subjectId: String
    var confidence: Double?
    var reason: String?
    var assignedAt: Date
    var assignedBy: ScopeAssignmentSource
}
```

This keeps scopes additive. Existing captures and memos do not need to be
migrated into a required relationship on day one. A separate assignment table or
file can map objects into scopes and allow multiple scope memberships later.

## V1 Vertical Slice

The smallest valuable slice:

1. Add an `Inbox` scope and at least one user-created scope.
2. Allow a capture, memo, note, screenshot, or action run to be assigned to a
   scope.
3. Show a scope-filtered library/timeline.
4. Let Action Workbench runs carry `scopeId`.
5. Let Agent Home show which scope an agent session belongs to.
6. Add one routing path: "send this to <scope>" from voice or command input.
7. Persist scope definitions in a file-backed format that can later become an
   portable context package.

This gives the user the feeling immediately: voice is no longer just text. It
lands in a context where agents can help.

## Non-Goals

- Do not rename Talkie or integrate new public naming in this slice.
- Do not make users organize every capture before it is useful.
- Do not build a marketplace or public protocol before the local object works.
- Do not require cloud sync or server storage for scope context.
- Do not give agents broad access just because a capture belongs to a scope.
- Do not collapse skills, actions, and scopes into one overloaded term.

## Open Questions

- Should scope definitions live under `~/Library/Application Support/Talkie/Scopes/`
  first, or in user-visible exported packages?
- Does iOS need scope creation in V1, or only assignment and routing?
- Should the first scope surface live inside Agent Home, Action Workbench, or the
  Library?
- What is the right default vocabulary: Inbox, Unscoped, or Today?
- How explicit should permissions be in the first slice?

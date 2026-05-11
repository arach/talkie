# Ambient Context: Engineering & Product Vision

**Date**: 2026-02-26
**Status**: Early exploration, proven in prototype interaction

## The Insight

Talkie already captures rich metadata with every dictation: the source app, window title, browser URL, transcription model, performance timing, and the transcript itself. When this stream is combined with external signals — git commits, branch state, PR status — an AI agent can reconstruct a detailed picture of a user's work session without any explicit logging.

This was demonstrated in a live session where an agent:
1. Pulled 39 dictations from a single day via the Talkie CLI
2. Extracted metadata (app, window title, URLs) to identify which Claude Code sessions and Chrome tabs each dictation targeted
3. Cross-referenced git history across 4 repos to match dictations to commits
4. Identified completed-but-unshipped work (unpushed commits, branches without PRs, stale stashes)

The result was a full reconstruction of the workday: what was worked on, in what order, across which tools, what shipped, and what's still in flight.

## What We Have Today

Each dictation already captures:

| Signal | Source | Cost |
|--------|--------|------|
| Transcript | Whisper/parakeet on-device | Free (already captured) |
| Source app + bundle ID | Accessibility / NSWorkspace | Free |
| Window title | Accessibility | Free |
| Browser URL | Accessibility (Chrome, Safari) | Free |
| Start/end app (context switches) | NSWorkspace observation | Free |
| Transcription latency | Engine timing | Free |
| Duration + word count | Audio pipeline | Free |

External signals (queryable, not captured by Talkie):

| Signal | Source | Cost |
|--------|--------|------|
| Git commits + diffs | `git log` | CLI query |
| Branch state + PRs | `gh` CLI | CLI query |
| Claude Code session names | Window title (already captured) | Free |
| DevMux session IDs | Window title embedding | Free |

## The Vision: Passive Context Accumulation

### Principle: Don't interrupt the dictation moment

The dictation hotkey is a sacred interaction — sub-second latency, zero friction. Context gathering must never compete with it. Instead, context accumulates **between** dictations, asynchronously.

### Layered scanning

**Layer 1 — Cheap, always-on (current)**
- App focus tracking (which app, which window)
- Window title capture on every dictation
- Browser URL from accessibility

**Layer 2 — Triggered, lightweight (next)**
- When the same window appears in N consecutive dictations, trigger a deeper scan
- Read accessibility tree for that window: visible text, UI state, form contents
- Capture tab groups, open file paths (from editor title bars)
- Build a "session context" object that persists across dictations

**Layer 3 — On-demand, heavier (future)**
- Screenshot of the active window (already possible via Talkie's screenshot infra)
- OCR / vision model pass on the screenshot for structured extraction
- Cross-reference with git state: what branch, what files modified, uncommitted changes
- Build a "workspace snapshot" that ties dictation context to code state

### The feedback loop

When users know their context is being captured and can be reconstructed later, they naturally:
- Narrate intent more explicitly ("switching to the click reliability issue")
- Drop breadcrumbs that are cheap to say but expensive to reconstruct ("this is done, moving on")
- Trust that they can ask "what did I work on?" and get a real answer

This creates a virtuous cycle: better narration leads to better context, which leads to better reconstruction, which encourages better narration.

## Concrete Use Cases

### "What's ready to ship?"
Cross-reference branches, commits, and PR state across all repos. Surface work that's committed but not pushed, pushed but not PRed, or PRed but not merged. Rank by staleness and completeness.

### "What was I working on?"
Reconstruct a session timeline from dictation metadata + git activity. Group by project, identify context switches, surface the narrative arc of a work session.

### "What's blocked?"
Identify branches with recent activity but no forward progress. Cross-reference with dictation transcripts that mention frustration, bugs, or blockers ("clicks not registering", "can't get the tool to load").

### "Give me a standup summary"
Aggregate yesterday's commits, PRs, and dictation topics into a structured update. Separate shipped work from in-progress from parked.

### "What did I decide?"
Search dictation transcripts for decision language. Cross-reference with the code changes that followed. Surface the intent behind architectural choices.

## Implementation Notes

### DevMux session IDs as correlation keys
DevMux already embeds session identifiers in window titles (e.g., `[devmux:shaper-8b0bc4]`). These appear in Talkie's metadata automatically, creating a free correlation between dictations and specific development contexts.

### Claude Code session names as intent markers
Claude Code window titles describe the task (e.g., "Screen Map Action Bar", "Dictionary Settings V2 Redesign"). These are captured by Talkie and serve as natural grouping keys for dictation clusters.

### The CLI as the query layer
The `talkie` CLI already supports structured JSON output, date ranges, app filtering, and full-text search. The analytical workflows demonstrated in the prototype session all ran through the CLI, making them composable with other tools and scriptable by AI agents.

## Privacy Model: By the User, For the User

This is personal infrastructure, not telemetry. The distinction is fundamental to Talkie's design.

- **No server in the loop.** All context — dictations, metadata, accessibility signals — stays on-device in SQLite. There is no backend receiving this data. Even when Talkie eventually has server infrastructure, ambient context is not the kind of thing that leaves the machine.
- **No exfiltration path.** The query layer (CLI, agents) runs locally. The AI agents reconstructing your workday are running on your machine, reading your local database and your local git repos.
- **The user is the only audience.** This data exists to serve the person who generated it. It's not aggregated, not anonymized-and-shipped, not used to train anything. It's yours.
- **Capture is user-controlled.** Dictation is an intentional act (press hotkey, speak, release). Passive context (accessibility, window titles) follows the dictation — it doesn't run independently or continuously.

The mental model: Talkie is a personal memory layer, not an analytics platform. The difference matters architecturally (local-first, no sync requirement) and philosophically (the user's context is not a product).

## What This Is Not

- Not surveillance — capture follows user intent, not the other way around
- Not telemetry — no server receives ambient context, ever
- Not real-time analytics — this is retrospective reconstruction and planning
- Not a replacement for explicit note-taking — it's a safety net for when you forget to write things down
- Not dependent on cloud — all signals are local-first (SQLite, git, accessibility)

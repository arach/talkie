# TLK-034 — Codex Task Status Document

**Status**: Exploration recommendation  
**Owner**: Talkie iOS + TalkieServer  
**Date**: 2026-07-29  
**Studio**: /eng/tlk-034  
**Surface**: /ios-codex-status-document

## Summary

Replace the conventional status list opened from the Codex deck status key with
a constrained, server-rendered technical document. The native iOS sheet remains
responsible for trust, loading, navigation, accessibility, and dismissal.
TalkieServer owns repository inspection and the assembly of a task-scoped HTML
document.

The Studio study recommends the **Keyfile** treatment. It merges task identity,
runtime, and repository truth into one high-contrast masthead before moving
directly into changed files. Small diff hunks can expand without turning the
sheet into an IDE.

## Current system audit

### Already available on iOS

`CodexTaskSummary` already carries the exact task identifier, title, preview,
working directory, project name, git branch, git origin, and update timestamp.

The turn model already exposes:

- queue or steer mode
- queued, running, blocked, completed, and failed states
- created and updated timestamps
- useful progress updates
- the latest response, delivery state, and actionable error details

`BridgeManager` already knows the paired Mac identity, active route, connection
state, and last successful contact. `BridgeClient` already uses the configured
bridge address, signed requests, and negotiated encrypted transport.

### Already available on TalkieServer

The Codex bridge can list and validate exact task identifiers, submit a turn,
and report turn progress. The desktop adapter resolves task state from the
Codex task catalog and its matching rollout file. It filters private reasoning
and emits user-visible progress only.

Production bridge routes already require pairing authentication. Signed
requests cover the method, path and query, timestamp, nonce, and body digest.
Authenticated response bodies use the bridge encryption envelope.

### Missing narrow capability

Neither the current task summary nor turn status includes:

- upstream and base branch identity
- clean or dirty repository state
- ahead and behind counts
- exact HEAD
- aggregate and per-file diff statistics
- bounded unified diff hunks
- a single task-scoped document assembled from repository, turn, and bridge
  state

These values should not be reconstructed on the phone. They require repository
access and belong on the paired Mac.

## Recommended interaction

Use the Keyfile treatment from the Studio study:

1. A native header establishes the trusted task title, loading state, reload,
   and dismissal.
2. The document opens with one compact masthead containing lifecycle, title,
   repository, host, task identity, harness, adapter, route, branch, upstream,
   base, HEAD, tree state, divergence, and diff totals.
3. The complete masthead fits within 280 points at a 390-point phone width, so
   changed files begin within the first viewport.
4. Changed files remain a concise ledger. Only useful hunks expand through
   native HTML `details` elements.
5. Recent agent updates and the previous delivery complete the explanation of
   what the task is doing.
6. Bridge health and render time sit in a quiet footer rather than competing
   with task status.

The Ribbon and Index treatments remain useful comparison points but are not
recommended. Ribbon is extremely fast to scan but weakens grouping between
task and repository facts. Index is the most literal field-to-value structure,
but its narrow title column feels more administrative than instrumental.

## Ownership boundary

### Native iOS

- select and validate the exact Codex task
- issue the authenticated bridge request
- decrypt the response through `BridgeClient`
- own loading, retry, offline, and failure presentation
- own the trusted title bar, dismissal, reload, and outer VoiceOver focus
- pass the preferred content-size scale with the document request
- host a read-only, constrained `WKWebView`
- reject navigation outside the loaded document and local fragment links
- retain at most the last successful document in memory for the sheet lifetime

### TalkieServer and desktop adapter

- resolve the task from the existing Codex task catalog
- derive the repository from the catalogued task working directory
- inspect git through a fixed, read-only command allowlist
- combine repository, turn, route, and bridge timestamps
- escape all task, repository, diff, and response content
- render a deterministic, self-contained HTML document
- own semantic document structure, scalable `rem` typography, and the viewport
  metadata needed for Dynamic Type
- enforce file, hunk, line, byte, and execution-time limits
- mark truncation in the document rather than silently omitting data

### Web document

- present semantic headings, tables, lists, code, and `details` disclosures
- contain inline CSS only
- perform no network requests and execute no script
- offer no terminal, arbitrary file browsing, or editable code surface

## Endpoint and data contract

Add one authenticated route:

```http
GET /codex/tasks/:taskId/status-document?jobId=:jobId
Accept: text/html
```

The response is `text/html; charset=utf-8` inside the existing authenticated and
encrypted bridge response path. The phone should fetch it with `BridgeClient`
and load the decrypted bytes with `WKWebView.load(_:mimeType:...)` or
`loadHTMLString`. The web view must not navigate directly to the bridge URL:
direct navigation would bypass the request signer and its replay protections.

`jobId` is optional. When present, the server must validate that the job belongs
to the exact task or reject the request. When absent, the server selects the
most recently updated queued, running, or blocked job for that task; if none is
active, it selects the most recently updated terminal job. Equal timestamps are
resolved by job identifier so fixtures and tests remain deterministic.

The server renderer should use an internal value model equivalent to:

```swift
struct CodexStatusDocument {
    var renderedAt: Date
    var task: TaskIdentity
    var turn: TurnSnapshot?
    var repository: RepositorySnapshot
    var bridge: BridgeSnapshot
    var recentDelivery: DeliverySnapshot?
}

struct RepositorySnapshot {
    var rootLabel: String
    var branch: String?
    var upstream: String?
    var head: String
    var upstreamDivergence: Divergence?
    var comparison: ComparisonSnapshot?
    var worktree: WorktreeSnapshot
}

struct Divergence {
    var ahead: Int
    var behind: Int
}

struct ComparisonSnapshot {
    var reference: String
    var mergeBase: String
    var divergence: Divergence
    var changedFiles: Int
    var additions: Int
    var deletions: Int
    var files: [ChangedFile]
    var hunks: [DiffHunk]
    var truncation: Truncation?
}

struct WorktreeSnapshot {
    var staged: [ChangedFile]
    var unstaged: [ChangedFile]
    var untracked: [String]
}
```

This is a renderer input, not a second public JSON API. Keeping HTML generation
beside repository inspection avoids duplicating formatting and diff semantics on
iOS. A comparison reference is included only when it is explicit in the task or
bridge configuration and can be resolved in the repository. The server must not
guess a base branch from a name. Upstream divergence, comparison-ref divergence,
and staged, unstaged, and untracked worktree changes remain separate facts.

## Security constraints

- Resolve repository roots only from validated task catalog entries. Never
  accept a filesystem path from the phone.
- Require a UUID task identifier and confirm it maps to the exact requested
  task before inspection.
- Require a user-owned git repository and keep all reads inside its resolved
  root. Reject unsafe symlink escapes.
- Execute fixed git argument arrays without a shell. Set
  `GIT_OPTIONAL_LOCKS=0` and `GIT_TERMINAL_PROMPT=0`, use a fixed locale, and
  enforce short timeouts and output caps.
- Never expose arbitrary filesystem reads, command execution, or URL browsing.
- Escape all rendered values, including branch names, commit subjects, diff
  content, and agent updates.
- Do not persist or log diff bodies.
- Use a content security policy equivalent to:
  `default-src 'none'; img-src 'none'; connect-src 'none'; form-action 'none';
  base-uri 'none'; frame-ancestors 'none'; style-src 'unsafe-inline'`.
- Use a nonpersistent `WKWebsiteDataStore` and block external schemes and
  navigation.
- Include a viewport meta tag and scalable CSS. The server applies the bounded
  preferred content-size scale supplied by the authenticated native client;
  fixed microtype must not be the only way to read technical values.

## Loading and offline behavior

The native sheet shows a stable skeleton while the first document loads. A
failed request becomes a native error with the bridge route, last successful
contact, and retry action; raw HTML errors never replace the sheet.

After a successful load, a refresh failure may leave that document visible with
a native “Last updated” and offline label. The cache should be memory-only and
limited to the sheet lifetime because diffs can contain sensitive source text.
Completed tasks refresh on demand. Running tasks may refresh conservatively,
with the native layer controlling cadence and stopping when the sheet is not
visible.

## Smallest production slice

1. Add deterministic repository inspection and HTML renderer tests to
   TalkieServer.
2. Add `GET /codex/tasks/:taskId/status-document` behind the existing bridge
   authentication and encrypted response path.
3. Add `BridgeClient.codexStatusDocument(taskID:jobID:)` returning decrypted
   HTML bytes and response metadata, including the preferred content-size scale
   in the signed request.
4. Replace only `CodexDeckStatusSheet` internals with a native state container
   and constrained read-only web view.
5. Verify VoiceOver order, Dynamic Type behavior, light and dark appearance,
   hostile diff escaping, repository limit handling, offline refresh, and
   blocked/completed turn states.

This slice does not change the main Codex deck, status key, lane console,
playback rail, command plate, submission paths, or task selection.

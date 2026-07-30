# TLK-034 — Codex Task Creation and Watch Dispatch

**Status**: In progress
**Owner**: arach
**Studio**: /eng/tlk-034
**Related**: TLK-020, Command Deck Codex lanes

## Summary

Talkie can create a new Codex task from the iPhone Command Deck and can dispatch
to an exact Codex task from Apple Watch. Both clients use the Mac bridge as the
owner of Codex process state, project working directories, and turn receipts.

The feature keeps two concepts separate:

- A **lane** is one of six persistent, numbered shortcuts. Creating a task never
  replaces a lane binding.
- A **channel** is an exact Codex task. The channel catalogue is unbounded and
  paginated. A channel may be assigned to one lane.

The exact Codex task ID, not the lane number or project name, is the routing
identity on every device.

## Product behavior

### Create a task

1. The user presses the visible **NEW** key beside **HOLD TO TALK** on the
   Command Deck. Task creation is not nested inside the channel mapper.
2. Talkie shows projects already represented by lanes first, followed by recent
   projects. Projects are deduplicated by Mac host and canonical working
   directory.
3. The model row reads **Default**. Talkie does not send a model override.
4. The Mac bridge creates the task in the selected working directory and
   returns the exact task summary.
5. Talkie inserts and selects the new channel. Existing lane bindings remain
   byte-for-byte unchanged. The user may explicitly assign the channel later.
6. The creation sheet briefly confirms **Ready to talk**, then reveals the
   Command Deck with the exact new task already selected.
7. The next spoken dispatch uses the existing durable Codex turn path.

Creation accepts a client-generated UUID. Repeating the same creation UUID and
working directory returns the original task. Reusing the UUID for another
working directory fails rather than creating a second task.

Talkie coalesces concurrent requests and persists successful creation receipts
atomically. Codex app-server does not accept an idempotency key for
`thread/start`, so a hard TalkieServer crash after Codex creates the task but
before the receipt is persisted cannot be correlated safely. Talkie does not
guess by working directory or creation time in that case.

### Browse channels

The first catalogue page loads on entry. Reaching the last visible row requests
the next cursor. Refresh replaces the first page; loading another page appends
and deduplicates by task ID. The six-lane control never scrolls or grows.

The mapper keeps selection and assignment visibly separate. Selecting a row
routes the deck directly to that exact channel. Its integrated assignment
footer says **Assign**, **Move**, **Replace**, or **Assigned · Clear**. The UI
does not use pin vocabulary or a trailing pin-icon column.

### Watch Codex mode

The Watch app has two horizontal primary pages: Capture and Codex. Horizontal
swipes change the primary page. The Digital Crown and explicit buttons change
the selected Codex channel so those gestures do not compete.

Codex mode shows:

- top: exact task title, project, channel position, and live state;
- bottom: press-and-hold recording and the dispatch receipt;
- explicit unavailable or queued state when the phone is not reachable.

The Watch records audio locally and transfers it after release. Channel
selection and status updates use immediate messages when reachable. This slice
does not claim live audio streaming or partial transcription.

The Watch app and its embedded widget both target watchOS 10.6 so the bundle is
installable on the paired Apple Watch SE running watchOS 10.6.1.

## Ownership

| Component | Owns |
| --- | --- |
| Mac TalkieServer | Codex app-server session, task creation, catalogue cursor, turn receipts |
| iPhone | Selected channel, lane bindings, project picker, transcription, Watch relay |
| Watch | Compact channel snapshot, local recording, visible delivery state |

The Watch never contacts Codex or the Mac directly.

## Bridge contract

### List tasks

```http
GET /codex/tasks?limit=25&cursor=<opaque>
```

```json
{
  "tasks": [],
  "nextCursor": "opaque-or-null"
}
```

Clients must treat the cursor as opaque.

### Create task

```http
POST /codex/tasks
```

```json
{
  "creationId": "UUID",
  "cwd": "/canonical/project/path"
}
```

```json
{
  "task": {
    "id": "codex-thread-id",
    "title": "New task",
    "preview": "",
    "cwd": "/canonical/project/path",
    "project": "project-name",
    "updatedAt": 0
  }
}
```

Talkie omits `model`, approval, and sandbox overrides. Codex resolves those from
the user's current configuration. The bridge rejects an empty, relative, or
nonexistent working directory.

## Watch contract

The iPhone publishes a compact property-list-compatible snapshot:

```text
revision, hostID, selectedTaskID, channels[]
channel: taskID, title, project, status, updatedAt
```

Watch audio metadata for Codex includes:

```text
type=audio, intent=codex, requestID, hostID, taskID, taskTitle
```

The iPhone validates that the received host and task still match an available
channel before transcribing and submitting. A mismatch fails visibly; it never
falls back to the active lane.

## Failure rules

- Concurrent create retries and retries after receipt persistence return the
  same task.
- Failed first dispatch leaves the created channel available for retry.
- Creating or directly selecting a channel does not mutate lane persistence.
- Assigning a channel to another lane moves it; one channel cannot occupy two
  numbered lanes at once.
- A stale Watch snapshot never dispatches by lane number or guessed title.
- When the phone is unavailable, the Watch labels the recording queued. The
  iPhone validates its exact host and task IDs before later delivery.
- Approval requests remain visible Codex failures and are not auto-approved.

## Delivery slices

1. Mac bridge creation, creation idempotency, and paginated catalogue.
2. iPhone Command Deck NEW key, project picker, unbounded channel selection,
   explicit lane assignment, and unchanged bindings after creation.
3. Watch horizontal Codex page, compact snapshot relay, post-release dispatch,
   and status receipts.
4. Cross-device integration tests and on-device latency measurement.

## Acceptance criteria

- Creating a task in a selected project returns an exact Codex task ID and uses
  the configured default model.
- Repeating a creation request returns the same task.
- All six lane bindings are unchanged after creation.
- The new task appears and is selected in the channel catalogue.
- Additional catalogue pages load without duplicate tasks.
- Watch dispatch lands in the task ID shown on Watch.
- Watch reports phone-unavailable, queued, running, completed, and failed states
  without silently redirecting a request.

## Studio follow-up

Add a Studio study for the iPhone project picker and the two-page Watch shell
before the final Swift polish pass. The implementation may establish the
functional hierarchy first, but Studio remains the review surface for the
finished interaction.

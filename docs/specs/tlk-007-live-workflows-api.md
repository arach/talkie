# TLK-007 — Talkie-Owned Live Workflows API

**Status**: Implemented (pending production deploy)
**Owner**: TBD

## Summary

V1 API contract for live iPhone-to-Mac workflow execution using Talkie's own backend queue.

The intended product model is:

- iPhone and Mac both authenticate with the user's Talkie account
- iPhone creates a workflow run
- any healthy signed-in Mac for that same user may claim the run
- if no Mac is online, the run stays queued until one appears
- Bridge/HMAC and SSH are not part of workflow dispatch

## Status

The API contract and client wiring have already been implemented locally in:

- `services/talkie-api/src/app.ts`
- `services/talkie-api/src/workflowQueue.ts`
- `apps/macos/Talkie/Services/WorkflowControlPlaneClient.swift`
- `apps/macos/Talkie/Services/WorkflowControlPlaneService.swift`
- `apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift`

At the time of writing, production deployment still needs to be updated so these routes exist at `api.usetalkie.com`.

## Core requirements

- No Convex in the shipped path
- No CloudKit workflow queueing
- No workflow pairing UI
- No target picker in V1
- Account-based auth only
- Queue-for-later behavior is supported
- Execution is Mac-only in V1

## Authentication

All workflow endpoints are authenticated with:

- `Authorization: Bearer <Talkie account token>`

The backend verifies the Talkie account token through Clerk and scopes all workflow runs and executor registrations by `userId`.

That means:

- a phone can only create and view its user's runs
- a Mac can only register and claim work for its user's runs

No workflow-specific HMAC handshake is required.

## Run model

Each run includes:

- `id`
- `workflowId`
- `workflowName`
- `workflowIcon?`
- `memoId`
- `status`
- `executionClass`
- `routingMode`
- `requestedByDeviceId?`
- `claimedByDeviceId?`
- `leaseToken?`
- `leaseExpiresAt?`
- `backendId?`
- `output?`
- `finalOutputs?`
- `stepOutputsJSON?`
- `errorMessage?`
- `createdAt`
- `updatedAt`
- `runDate`

V1 defaults:

- `executionClass = "macOnly"`
- `routingMode = "any"`

## Run states

- `queued`
- `claimed`
- `running`
- `completed`
- `failed`
- `cancelled`

## Executor model

Each executor registration includes:

- `deviceId`
- `name`
- `platform`
- `status`
- `priority`
- `capabilities`
- `installId?`
- `appVersion?`
- `tailscaleHostname?`
- `metadata?`
- `claimedRunId?`
- `lastHeartbeatAt`
- `heartbeatExpiresAt`

## Lease and queue behavior

- Runs start in `queued`
- Macs list claimable runs and attempt to claim one
- Claiming is single-winner via a per-run lock
- Lease duration is currently `30s`
- Executor heartbeat TTL is currently `120s`
- A claimed or running run whose lease expires is reconciled back to `queued`
- Completion and failure clear the lock

This gives:

- one Mac executes each run
- crashed or sleeping Macs do not permanently wedge runs
- queued runs remain available until a Mac claims them

## Phone-facing endpoints

### `POST /api/workflow-runs`

Creates a new queued run.

Request body:

```json
{
  "workflowId": "uuid-string",
  "workflowName": "Quick Summary",
  "workflowIcon": "text.alignleft",
  "memoId": "uuid-string",
  "requestedByDeviceId": "optional-device-id"
}
```

Response:

```json
{
  "run": {
    "id": "uuid",
    "workflowId": "uuid-string",
    "workflowName": "Quick Summary",
    "workflowIcon": "text.alignleft",
    "memoId": "uuid-string",
    "status": "queued",
    "executionClass": "macOnly",
    "routingMode": "any",
    "requestedByDeviceId": "optional-device-id",
    "createdAt": "2026-03-28T15:00:00.000Z",
    "updatedAt": "2026-03-28T15:00:00.000Z",
    "runDate": "2026-03-28T15:00:00.000Z"
  }
}
```

### `GET /api/workflow-runs?memoId=<memo-id>`

Lists runs for the authenticated user, optionally filtered by memo.

Response:

```json
{
  "runs": [
    {
      "id": "uuid",
      "workflowId": "uuid-string",
      "workflowName": "Quick Summary",
      "memoId": "uuid-string",
      "status": "running",
      "createdAt": "2026-03-28T15:00:00.000Z",
      "updatedAt": "2026-03-28T15:01:00.000Z",
      "runDate": "2026-03-28T15:00:00.000Z"
    }
  ]
}
```

### `GET /api/workflow-runs/:id`

Fetches one run plus its event history.

Response:

```json
{
  "run": {
    "id": "uuid",
    "workflowId": "uuid-string",
    "workflowName": "Quick Summary",
    "memoId": "uuid-string",
    "status": "completed",
    "output": "Final summary text",
    "finalOutputs": {
      "summary": "Final summary text"
    },
    "stepOutputsJSON": "{\"summary\":\"Final summary text\"}",
    "createdAt": "2026-03-28T15:00:00.000Z",
    "updatedAt": "2026-03-28T15:02:00.000Z",
    "runDate": "2026-03-28T15:02:00.000Z"
  },
  "events": [
    {
      "id": "uuid",
      "runId": "uuid",
      "type": "created",
      "status": "queued",
      "createdAt": "2026-03-28T15:00:00.000Z",
      "message": "Run queued for the next available Mac."
    }
  ]
}
```

## Executor-facing endpoints

### `POST /api/executors/register`

Registers or updates a Mac executor for the current user.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "name": "Arach MacBook Pro",
  "platform": "macos",
  "status": "online",
  "priority": 100,
  "capabilities": ["workflow"],
  "installId": "optional-install-id",
  "appVersion": "optional-version",
  "tailscaleHostname": "optional-hostname",
  "metadata": {
    "appMode": "lite"
  }
}
```

Response:

```json
{
  "deviceId": "stable-device-id",
  "heartbeatExpiresAt": "2026-03-28T15:02:00.000Z"
}
```

### `POST /api/executors/heartbeat`

Refreshes executor liveness.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "status": "online",
  "claimedRunId": "optional-run-id",
  "metadata": {
    "trigger": "idle",
    "phase": "idle"
  }
}
```

Response:

```json
{
  "ok": true,
  "heartbeatExpiresAt": "2026-03-28T15:02:00.000Z"
}
```

### `GET /api/workflow-runs/claimable?limit=20`

Lists queued runs claimable by the current user.

Response:

```json
{
  "runs": [
    {
      "id": "uuid",
      "workflowId": "uuid-string",
      "workflowName": "Quick Summary",
      "memoId": "uuid-string",
      "status": "queued"
    }
  ]
}
```

### `POST /api/workflow-runs/:id/claim`

Attempts to claim a queued run.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "backendId": "talkie-mac-swift"
}
```

Response on success:

```json
{
  "granted": true,
  "leaseToken": "uuid",
  "leaseExpiresAt": "2026-03-28T15:00:30.000Z"
}
```

Response when another Mac won:

```json
{
  "granted": false,
  "reason": "Workflow run is already claimed."
}
```

### `POST /api/workflow-runs/:id/start`

Marks a claimed run as running.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "leaseToken": "uuid",
  "backendId": "talkie-mac-swift"
}
```

Response:

```json
{
  "ok": true
}
```

### `POST /api/workflow-runs/:id/renew`

Renews lease ownership during execution.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "leaseToken": "uuid"
}
```

Response:

```json
{
  "ok": true,
  "leaseExpiresAt": "2026-03-28T15:01:00.000Z"
}
```

### `POST /api/workflow-runs/:id/release`

Returns a claimed or running run to the queue.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "leaseToken": "uuid",
  "reason": "optional message"
}
```

Response:

```json
{
  "ok": true
}
```

### `POST /api/workflow-runs/:id/complete`

Marks a run complete and stores the output payload.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "leaseToken": "uuid",
  "backendId": "talkie-mac-swift",
  "finalOutputs": {
    "summary": "Final summary text"
  },
  "output": "Final summary text",
  "stepOutputsJSON": "{\"summary\":\"Final summary text\"}"
}
```

Response:

```json
{
  "ok": true,
  "run": {
    "id": "uuid",
    "status": "completed",
    "output": "Final summary text"
  }
}
```

### `POST /api/workflow-runs/:id/fail`

Marks a run failed.

Request body:

```json
{
  "deviceId": "stable-device-id",
  "leaseToken": "uuid",
  "backendId": "talkie-mac-swift",
  "error": {
    "message": "Execution failed."
  }
}
```

Response:

```json
{
  "ok": true,
  "run": {
    "id": "uuid",
    "status": "failed",
    "errorMessage": "Execution failed."
  }
}
```

## Error behavior

Expected status codes:

- `401` when auth is missing or invalid
- `404` when a run does not exist
- `409` for lease/claim conflicts
- `400` for malformed request bodies
- `500` for unexpected server failures

Important invariant:

- once deployed correctly, these routes should return `401` when signed out and not `404`

## Storage requirements

The current implementation supports:

- Vercel Blob when `BLOB_READ_WRITE_TOKEN` is configured
- local filesystem fallback for development when Blob is unavailable

Stored objects are encrypted before persistence.

Current environment variables used by the workflow queue layer:

- `CLERK_SECRET_KEY`
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
- `BLOB_READ_WRITE_TOKEN`
- `WORKFLOW_QUEUE_SECRET` optional but recommended
- `WORKFLOW_QUEUE_SCOPE_SALT` optional

## Current implementation details

- user scoping is hashed into storage paths
- events are append-only
- run locks are stored separately from run payloads
- a run with a missing or expired lock is reconciled back to `queued`
- current Mac executor backend id is `talkie-mac-swift`

## Suggested acceptance tests

### Single Mac

- phone creates a run
- Mac lists it as claimable
- Mac claims it
- Mac starts it
- Mac completes it
- phone sees `queued -> running -> completed`

### No Mac online

- phone creates a run
- run remains `queued`
- Mac comes online later
- Mac claims and completes it

### Two Macs online

- both Macs see the queued run
- only one receives `granted: true` from claim
- the other gets `granted: false`

### Signed-out behavior

- signed-out phone cannot create runs
- signed-out Mac cannot register or claim runs

## Notes for the Talkie Server team

If the Talkie Server team wants to own this path, the easiest route is not to change the client contract. Keep the above endpoints and auth model stable, and move the implementation behind them.

That lets:

- iPhone keep its current live workflow client
- macOS keep its current executor client
- the backend implementation evolve without app changes

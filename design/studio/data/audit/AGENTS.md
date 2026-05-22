# Scope design audit protocol

The Scope Audit at `design/studio/app/mac-audit/page.tsx` reviews six mac-* surfaces across five axes (typography, spacing, hierarchy, semantics, copy) plus a11y. This doc is the coordination protocol for agents working items in the audit.

The audit page reads `scope-2026-05-21.json` (this directory) fresh per request via `/mac-audit/api/status`. Anything you write to that file shows up in the audit UI on next focus (browser auto-refetches) or on click of the Refresh button.

## Items

Every actionable thing in the audit has a stable `id`. There are three kinds:

| kind | count | id prefix |
|------|-------|-----------|
| Cross-cutting theme | 7 | `t-` |
| Top of stack | 5 | `tos-` |
| Per-surface finding | 48 | `h-` (Home) · `lib-` · `dict-` · `note-` · `cap-` · `sk-` |

The full id list is rendered on the audit page under "Agent contract → Item ID reference" (collapsible). The authoritative source is the `AUDITS` / `THEMES` / `TOP_OF_STACK` constants in `page.tsx` — grep for an id to find a finding's `detail`, `fix`, `severity`, `axis`, and parent surface.

## Lifecycle

Statuses: `queued` → `inflight` → `shipped` (or `skipped`).

1. **Claim** — pick an item with `status: "queued"` (or no entry at all — absence implies queued). Set `status: "inflight"`, update `updatedAt` to current ISO, set `updatedBy` to your handle. Optionally append a `progress` note.
2. **Look back** — before acting, scan the item's `notes` array for any `info` / `proposal` / `question` notes from the user (handle `user-art`). Treat those as steering.
3. **Work** — apply the fix. The finding's `fix` field in `page.tsx` is your spec. Edit the relevant studio (.tsx) or Swift file. Verify with curl or build.
4. **Land** — set `status: "shipped"`, append a `landed` note with a short message and `ref` (commit sha or file:line).
5. **Skip** — if the fix isn't worth it or has been superseded, set `status: "skipped"` with an `info` note explaining why.

## Item schema

```ts
interface ItemRecord {
  status: "queued" | "inflight" | "shipped" | "skipped";
  updatedAt: string;       // ISO
  updatedBy: string;       // your handle
  note?: string;           // short one-liner (status-level summary)
  notes?: Note[];          // append-only log
}

interface Note {
  ts: string;              // ISO
  agent: string;           // your handle
  level: "info" | "progress" | "landed" | "blocked" | "proposal" | "question";
  message: string;         // 1–3 sentences. File:line refs welcome.
  ref?: string;            // optional commit sha or file:line
}
```

Levels:

- **info** — observation, context, summary.
- **progress** — work started or partially landed (still open).
- **landed** — change is on the branch (include `ref` with commit sha).
- **blocked** — can't proceed. Explain in `message`.
- **proposal** — concrete plan awaiting user signoff. Stop and wait.
- **question** — needs the user. Stop and wait.

(Mirrors `data/parity/AGENTS.md` vocab minus `decision` — design audits don't have PORT/DROP/DEFER. Skipping an item replaces that channel.)

## Write protocol

`scope-2026-05-21.json` is shared mutable state.

1. Read the file fresh right before you write.
2. Patch only the item you own.
3. Append to `notes`, never rewrite or reorder existing entries.
4. Bump the top-level `updatedAt`.
5. Write back.

You may write directly with Edit, or use the API:

```bash
# Set status
curl -X POST http://localhost:3001/mac-audit/api/status \
  -H "Content-Type: application/json" \
  -d '{"id":"h-scheme-picker","status":"inflight","updatedBy":"investigator-home","note":"starting investigation"}'

# Reset all
curl -X DELETE http://localhost:3001/mac-audit/api/status

# Read current state
curl http://localhost:3001/mac-audit/api/status
```

The API does a read-modify-write under the hood; multiple agents racing fall under last-write-wins. If a write you expected to land disappeared, refetch and replay.

## Boundaries

- **One item at a time per agent.** Don't claim more than you can actively work.
- **Stay in scope.** A finding for `mac-skills` lives in `MacSkills.tsx`. Cross-surface fixes (themes) are explicit — those carry a `hits` array of surfaces.
- **Studio first, Swift after.** Per project memory: design lives in `design/studio/`. Swift ports happen after the studio version lands. The audit findings are studio-focused; Swift parity is tracked separately.
- **Marketing copy stays out.** When proposing copy fixes, default to neutral instrument labels. Let affordances speak.
- **Don't invent new ids.** If you spot a problem the audit missed, post a `level: "info"` note on the closest related finding flagging it. Don't add new ids to `page.tsx` without user signoff.

## Related

- Parity audit (iOS donor → Next): `design/studio/data/parity/AGENTS.md` — same convention, richer pair protocol.
- Scope canon decisions: in `DECISIONS` array on `page.tsx`. Latest: 2026-05-21 palette pivot to cool gray.

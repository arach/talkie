#!/usr/bin/env bun
/**
 * Append a note to a parity audit stream, or change its status.
 *
 * Usage:
 *   bun scripts/parity-stream.ts note --cluster C1 --agent <handle> \
 *       --level info|progress|landed|blocked|proposal|question|decision \
 *       [--finding "C1::HomeView::Full-screen search"] \
 *       [--ref <sha or file:line>] \
 *       [--propose port|drop|defer] \
 *       --message "what happened"
 *
 *   bun scripts/parity-stream.ts claim --cluster C1 --agent <handle>
 *
 *   bun scripts/parity-stream.ts status --cluster C1 \
 *       --to queued|in-flight|blocked|done [--agent <handle>]
 *
 *   bun scripts/parity-stream.ts inbox --cluster C1 [--agent <handle>] \
 *       [--since 2026-05-21T18:00:00Z]
 *
 * The script reads streams.json fresh, applies the change, and writes back.
 * It does NOT push or commit; do that yourself once you have a meaningful
 * checkpoint.
 *
 * Concurrency: if two agents race, the later writer's `git push` will fail
 * non-fast-forward. Pull, replay, push again. Don't blindly --force.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

type Level =
  | "info"
  | "progress"
  | "landed"
  | "blocked"
  | "proposal"
  | "question"
  | "decision";

type Status = "queued" | "in-flight" | "blocked" | "done";

const LEVELS: Level[] = [
  "info",
  "progress",
  "landed",
  "blocked",
  "proposal",
  "question",
  "decision",
];
const STATUSES: Status[] = ["queued", "in-flight", "blocked", "done"];

type ProposedDecision = "PORT" | "DROP" | "DEFER";
const PROPOSED_DECISIONS: ProposedDecision[] = ["PORT", "DROP", "DEFER"];

interface Note {
  ts: string;
  agent: string;
  level: Level;
  findingKey?: string;
  message: string;
  ref?: string;
  proposedDecision?: ProposedDecision;
}

interface Stream {
  key: string;
  title: string;
  scope: string;
  owner: string | null;
  status: Status;
  lockedAt: string | null;
  notes: Note[];
}

interface StreamsFile {
  version: number;
  updatedAt: string;
  streams: Stream[];
}

const STREAMS_PATH = resolve(import.meta.dir, "..", "data", "parity", "streams.json");

function parseArgs(argv: string[]): { command: string; flags: Record<string, string> } {
  const [command, ...rest] = argv;
  const flags: Record<string, string> = {};
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (!arg.startsWith("--")) {
      die(`unexpected positional argument: ${arg}`);
    }
    const key = arg.slice(2);
    const value = rest[i + 1];
    if (!value || value.startsWith("--")) {
      die(`flag --${key} requires a value`);
    }
    flags[key] = value;
    i++;
  }
  return { command, flags };
}

function die(msg: string): never {
  console.error(`parity-stream: ${msg}`);
  process.exit(1);
}

function load(): StreamsFile {
  const raw = readFileSync(STREAMS_PATH, "utf8");
  return JSON.parse(raw);
}

function save(data: StreamsFile): void {
  data.updatedAt = new Date().toISOString();
  writeFileSync(STREAMS_PATH, JSON.stringify(data, null, 2) + "\n");
}

function findStream(data: StreamsFile, key: string): Stream {
  const stream = data.streams.find((s) => s.key === key);
  if (!stream) die(`unknown cluster key: ${key}`);
  return stream!;
}

function cmdNote(flags: Record<string, string>): void {
  const cluster = flags.cluster ?? die("--cluster required");
  const agent = flags.agent ?? die("--agent required");
  const level = (flags.level ?? die("--level required")) as Level;
  const message = flags.message ?? die("--message required");
  if (!LEVELS.includes(level)) {
    die(`invalid --level: ${level} (valid: ${LEVELS.join(", ")})`);
  }
  const data = load();
  const stream = findStream(data, cluster);
  const note: Note = {
    ts: new Date().toISOString(),
    agent,
    level,
    message,
  };
  if (flags.finding) note.findingKey = flags.finding;
  if (flags.ref) note.ref = flags.ref;
  if (flags.propose) {
    const upper = flags.propose.toUpperCase() as ProposedDecision;
    if (!PROPOSED_DECISIONS.includes(upper)) {
      die(`invalid --propose: ${flags.propose} (valid: port, drop, defer)`);
    }
    if (!note.findingKey) {
      die("--propose requires --finding (recommendations attach to a specific finding)");
    }
    note.proposedDecision = upper;
  }
  stream.notes.push(note);
  save(data);
  console.log(`appended note to ${cluster} (level=${level}, agent=${agent})`);
}

function cmdClaim(flags: Record<string, string>): void {
  const cluster = flags.cluster ?? die("--cluster required");
  const agent = flags.agent ?? die("--agent required");
  const data = load();
  const stream = findStream(data, cluster);
  if (stream.owner && stream.owner !== agent) {
    die(`stream ${cluster} already claimed by ${stream.owner} (locked ${stream.lockedAt}). Use a different cluster or coordinate the handoff.`);
  }
  stream.owner = agent;
  stream.status = "in-flight";
  stream.lockedAt = new Date().toISOString();
  save(data);
  console.log(`claimed ${cluster} for ${agent}`);
}

function cmdStatus(flags: Record<string, string>): void {
  const cluster = flags.cluster ?? die("--cluster required");
  const to = (flags.to ?? die("--to required")) as Status;
  if (!STATUSES.includes(to)) {
    die(`invalid --to: ${to} (valid: ${STATUSES.join(", ")})`);
  }
  const data = load();
  const stream = findStream(data, cluster);
  if (flags.agent && stream.owner && stream.owner !== flags.agent) {
    die(`stream ${cluster} owned by ${stream.owner}, not ${flags.agent}`);
  }
  stream.status = to;
  if (to === "done") {
    stream.owner = null;
  }
  save(data);
  console.log(`set ${cluster} status to ${to}`);
}

function cmdInbox(flags: Record<string, string>): void {
  const cluster = flags.cluster ?? die("--cluster required");
  const data = load();
  const stream = findStream(data, cluster);

  // Default `since` to this agent's most recent note in the cluster, so
  // each check-in surfaces only what the user posted since you last touched it.
  let sinceTs: string | null = flags.since ?? null;
  if (!sinceTs && flags.agent) {
    const mine = stream.notes
      .filter((n) => n.agent === flags.agent)
      .map((n) => n.ts)
      .sort();
    sinceTs = mine.length > 0 ? mine[mine.length - 1] : null;
  }

  const userNotes = stream.notes.filter((n) => {
    if (!n.agent.startsWith("user-")) return false;
    if (sinceTs && n.ts <= sinceTs) return false;
    return true;
  });

  const header = sinceTs
    ? `${cluster} · ${userNotes.length} user note(s) since ${sinceTs}`
    : `${cluster} · ${userNotes.length} user note(s) (all time)`;
  console.log(header);
  if (userNotes.length === 0) {
    console.log("  (nothing new — proceed)");
    return;
  }

  for (const n of userNotes) {
    const pin = n.findingKey ? ` · ${n.findingKey}` : " · (stream-wide)";
    const ref = n.ref ? ` [ref: ${n.ref}]` : "";
    console.log(`  [${n.ts}] ${n.agent} ${n.level.toUpperCase()}${pin}`);
    console.log(`    ${n.message}${ref}`);
  }

  // Roll up effective decisions touched in this window, so the agent sees
  // the operative PORT/DROP/DEFER for each finding without re-deriving it.
  const decisionsInWindow = userNotes.filter((n) => n.level === "decision");
  if (decisionsInWindow.length > 0) {
    console.log("");
    console.log("Decisions in this window:");
    for (const n of decisionsInWindow) {
      console.log(`  ${n.findingKey ?? "(no key?)"} → ${n.message}`);
    }
  }
}

const { command, flags } = parseArgs(process.argv.slice(2));
switch (command) {
  case "note":
    cmdNote(flags);
    break;
  case "claim":
    cmdClaim(flags);
    break;
  case "status":
    cmdStatus(flags);
    break;
  case "inbox":
    cmdInbox(flags);
    break;
  case undefined:
    die("missing command (note | claim | status | inbox)");
    break;
  default:
    die(`unknown command: ${command}`);
}

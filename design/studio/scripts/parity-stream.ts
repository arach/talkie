#!/usr/bin/env bun
/**
 * Append a note to a parity audit stream, or change its status.
 *
 * Usage:
 *   bun scripts/parity-stream.ts note --cluster C1 --agent <handle> \
 *       --level info|progress|landed|blocked|proposal|question \
 *       [--finding "C1::HomeView::Full-screen search"] \
 *       [--ref <sha or file:line>] \
 *       --message "what happened"
 *
 *   bun scripts/parity-stream.ts claim --cluster C1 --agent <handle>
 *
 *   bun scripts/parity-stream.ts status --cluster C1 \
 *       --to queued|in-flight|blocked|done [--agent <handle>]
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
  | "question";

type Status = "queued" | "in-flight" | "blocked" | "done";

const LEVELS: Level[] = [
  "info",
  "progress",
  "landed",
  "blocked",
  "proposal",
  "question",
];
const STATUSES: Status[] = ["queued", "in-flight", "blocked", "done"];

interface Note {
  ts: string;
  agent: string;
  level: Level;
  findingKey?: string;
  message: string;
  ref?: string;
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
  case undefined:
    die("missing command (note | claim | status)");
    break;
  default:
    die(`unknown command: ${command}`);
}

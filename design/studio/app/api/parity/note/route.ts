import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Level =
  | "info"
  | "progress"
  | "landed"
  | "blocked"
  | "proposal"
  | "question"
  | "decision";

const LEVELS: Level[] = [
  "info",
  "progress",
  "landed",
  "blocked",
  "proposal",
  "question",
  "decision",
];

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
  status: "queued" | "in-flight" | "blocked" | "done";
  lockedAt: string | null;
  notes: Note[];
}

interface StreamsFile {
  version: number;
  updatedAt: string;
  streams: Stream[];
}

const STREAMS_PATH = path.resolve(
  process.cwd(),
  "data",
  "parity",
  "streams.json",
);

export async function POST(req: Request): Promise<Response> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const { clusterKey, level, message, findingKey, ref, agent, proposedDecision } =
    body as {
      clusterKey?: string;
      level?: string;
      message?: string;
      findingKey?: string;
      ref?: string;
      agent?: string;
      proposedDecision?: string;
    };

  if (!clusterKey || typeof clusterKey !== "string") {
    return NextResponse.json({ error: "clusterKey required" }, { status: 400 });
  }
  if (!level || !LEVELS.includes(level as Level)) {
    return NextResponse.json(
      { error: `level must be one of ${LEVELS.join(", ")}` },
      { status: 400 },
    );
  }
  if (!message || typeof message !== "string" || !message.trim()) {
    return NextResponse.json({ error: "message required" }, { status: 400 });
  }

  const note: Note = {
    ts: new Date().toISOString(),
    agent: typeof agent === "string" && agent.trim() ? agent : "user-art",
    level: level as Level,
    message: message.trim(),
  };
  if (findingKey && typeof findingKey === "string") note.findingKey = findingKey;
  if (ref && typeof ref === "string") note.ref = ref;
  if (proposedDecision) {
    if (!PROPOSED_DECISIONS.includes(proposedDecision as ProposedDecision)) {
      return NextResponse.json(
        { error: `proposedDecision must be one of ${PROPOSED_DECISIONS.join(", ")}` },
        { status: 400 },
      );
    }
    if (!note.findingKey) {
      return NextResponse.json(
        { error: "proposedDecision requires findingKey" },
        { status: 400 },
      );
    }
    note.proposedDecision = proposedDecision as ProposedDecision;
  }

  // Read fresh, append, write back. Matches the protocol's write protocol.
  // Concurrent writes from CLI helper + this route race on the file; last
  // writer wins. That's acceptable for an append-only log.
  const raw = await fs.readFile(STREAMS_PATH, "utf8");
  const data = JSON.parse(raw) as StreamsFile;
  const stream = data.streams.find((s) => s.key === clusterKey);
  if (!stream) {
    return NextResponse.json(
      { error: `unknown cluster: ${clusterKey}` },
      { status: 404 },
    );
  }
  stream.notes.push(note);
  data.updatedAt = note.ts;
  await fs.writeFile(STREAMS_PATH, JSON.stringify(data, null, 2) + "\n", "utf8");

  return NextResponse.json({ ok: true, note });
}

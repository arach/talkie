import { promises as fs } from "fs";
import path from "path";
import { NextResponse } from "next/server";

/**
 * Audit status API. Reads/writes design/studio/data/audit/scope-2026-05-21.json
 * so both the browser (via fetch) and agents (via Read/Edit on the file)
 * work against the same source of truth.
 *
 * Convention mirrors design/studio/data/parity/ — see data/audit/AGENTS.md
 * for the protocol doc.
 *
 * Concurrency: last-write-wins. Browser polls on focus. If an agent and a
 * human edit at the exact same instant, one click is lost — acceptable for
 * a worksheet.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Status = "queued" | "inflight" | "shipped" | "skipped";
type Level = "info" | "progress" | "landed" | "blocked" | "proposal" | "question";

const LEVELS: Level[] = ["info", "progress", "landed", "blocked", "proposal", "question"];

interface Note {
  ts: string;
  agent: string;
  level: Level;
  message: string;
  ref?: string;
}

interface ItemRecord {
  status: Status;
  updatedAt: string;
  updatedBy: string;
  note?: string;
  notes?: Note[];
}

interface StatusFile {
  version: number;
  audit: string;
  updatedAt: string;
  items: Record<string, ItemRecord>;
}

const STATUS_PATH = path.join(process.cwd(), "data", "audit", "scope-2026-05-21.json");

async function readStatus(): Promise<StatusFile> {
  const raw = await fs.readFile(STATUS_PATH, "utf-8");
  return JSON.parse(raw);
}

async function writeStatus(data: StatusFile): Promise<void> {
  data.updatedAt = new Date().toISOString();
  await fs.writeFile(STATUS_PATH, JSON.stringify(data, null, 2) + "\n", "utf-8");
}

export async function GET() {
  try {
    const data = await readStatus();
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const { id, status, updatedBy, note, appendNote } = body as {
      id: string;
      status?: Status;
      updatedBy?: string;
      note?: string;
      appendNote?: { level: Level; message: string; ref?: string };
    };

    if (!id) {
      return NextResponse.json({ error: "id required" }, { status: 400 });
    }

    const data = await readStatus();
    const existing = data.items[id];
    const nowIso = new Date().toISOString();
    const agent = updatedBy || "ui";

    const next: ItemRecord = {
      status: status ?? existing?.status ?? "queued",
      updatedAt: nowIso,
      updatedBy: agent,
      ...(note !== undefined ? { note } : existing?.note ? { note: existing.note } : {}),
      ...(existing?.notes ? { notes: existing.notes } : {}),
    };

    if (appendNote && appendNote.level && appendNote.message) {
      if (!LEVELS.includes(appendNote.level)) {
        return NextResponse.json({ error: `invalid level: ${appendNote.level}` }, { status: 400 });
      }
      const noteEntry: Note = {
        ts: nowIso,
        agent,
        level: appendNote.level,
        message: appendNote.message,
        ...(appendNote.ref ? { ref: appendNote.ref } : {}),
      };
      next.notes = [...(next.notes ?? []), noteEntry];
    }

    data.items[id] = next;
    await writeStatus(data);
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}

/**
 * Bulk reset — DELETE clears all items.
 */
export async function DELETE() {
  try {
    const data = await readStatus();
    data.items = {};
    await writeStatus(data);
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}

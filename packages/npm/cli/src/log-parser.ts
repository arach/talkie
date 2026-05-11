import { readdirSync, readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// ── Types ──────────────────────────────────────────────────

export interface LogEntry {
  timestamp: Date;
  process: string;
  category: string;
  message: string;
  detail: string;
  source?: string; // file:line from log suffix
}

// ── Log directories ────────────────────────────────────────

const LOG_DIRS: Record<string, string> = {
  TalkieAgent: join(homedir(), "Library", "Application Support", "TalkieAgent", "logs"),
  Talkie: join(homedir(), "Library", "Application Support", "Talkie", "logs"),
  TalkieSync: join(homedir(), "Library", "Application Support", "TalkieSync", "logs"),
};

export function getLogDir(service: string): string {
  return LOG_DIRS[service] ?? join(homedir(), "Library", "Application Support", service, "logs");
}

// ── Duration parsing ───────────────────────────────────────

/** Parse duration strings like "1h", "2d", "30m", "1d12h" into milliseconds */
export function parseDuration(input: string): number {
  let total = 0;
  const re = /(\d+)\s*(d|h|m|s)/gi;
  let match: RegExpExecArray | null;
  while ((match = re.exec(input)) !== null) {
    const n = parseInt(match[1], 10);
    switch (match[2].toLowerCase()) {
      case "d": total += n * 86400000; break;
      case "h": total += n * 3600000; break;
      case "m": total += n * 60000; break;
      case "s": total += n * 1000; break;
    }
  }
  // Bare number → treat as days for backwards compat
  if (total === 0 && /^\d+$/.test(input.trim())) {
    total = parseInt(input.trim(), 10) * 86400000;
  }
  return total || 86400000; // default 1 day
}

// ── Line parser ────────────────────────────────────────────

const LOG_LINE_RE = /^(.+?)\|([^|]*)\|([^|]*)\|([^|]*)\|(.*)$/;

export function parseLogLine(line: string): LogEntry | null {
  const m = line.match(LOG_LINE_RE);
  if (!m) return null;

  const [, tsRaw, process, category, message, detailRaw] = m;
  const timestamp = new Date(tsRaw);
  if (isNaN(timestamp.getTime())) return null;

  // Extract [File:line] suffix from detail
  let detail = detailRaw;
  let source: string | undefined;
  const srcMatch = detail.match(/\s*\[(\w+:\d+)\]\s*$/);
  if (srcMatch) {
    source = srcMatch[1];
    detail = detail.slice(0, -srcMatch[0].length);
  }

  return { timestamp, process, category, message, detail, source };
}

// ── File reader ────────────────────────────────────────────

interface ReadOptions {
  since?: string;   // duration like "1d", "2h"
  maxFiles?: number;
}

/** List log files for a service sorted by date descending */
function listLogFiles(service: string): string[] {
  const dir = getLogDir(service);
  if (!existsSync(dir)) return [];

  return readdirSync(dir)
    .filter((f) => f.startsWith("talkie-") && f.endsWith(".log"))
    .sort()
    .reverse()
    .map((f) => join(dir, f));
}

/** Read and parse log entries from a service's log files */
export function readLogEntries(service: string, opts: ReadOptions = {}): LogEntry[] {
  const files = listLogFiles(service);
  if (files.length === 0) return [];

  const maxFiles = opts.maxFiles ?? 7;
  const cutoff = opts.since
    ? new Date(Date.now() - parseDuration(opts.since))
    : new Date(Date.now() - 86400000); // default: last 24h

  const entries: LogEntry[] = [];

  for (const file of files.slice(0, maxFiles)) {
    // Quick date check from filename: talkie-2026-02-26.log
    const dateMatch = file.match(/talkie-(\d{4}-\d{2}-\d{2})\.log$/);
    if (dateMatch) {
      const fileDate = new Date(dateMatch[1] + "T23:59:59Z");
      if (fileDate < cutoff) break; // older files won't have relevant entries
    }

    let content: string;
    try {
      content = readFileSync(file, "utf-8");
    } catch {
      continue;
    }

    for (const line of content.split("\n")) {
      if (!line.trim()) continue;
      const entry = parseLogLine(line);
      if (!entry) continue;
      if (entry.timestamp >= cutoff) {
        entries.push(entry);
      }
    }
  }

  // Sort newest first
  entries.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
  return entries;
}

import type { Command } from "commander";
import { getDb, queryAll, findByIdPrefix } from "../db";
import {
  getFormatOptions,
  output,
  outputTable,
  formatDuration,
  formatDate,
  truncate,
  wordCount,
} from "../format";
import { parseSince } from "./shared";

export function registerMemosCommand(program: Command): void {
  program
    .command("memos [id]")
    .description("List voice memos, or get a specific memo by ID (prefix match)")
    .option("--limit <n>", "max results", "50")
    .option("--since <date>", "filter by date (e.g. 2025-02-01 or 7d)")
    .option("--segments", "show word-level timestamps in detail view")
    .action((id: string | undefined, opts) => {
      const globalOpts = program.opts();
      getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);

      if (id) {
        return getMemo(id, fmt, opts.segments);
      }

      const limit = parseInt(opts.limit, 10);
      const since = opts.since ? parseSince(opts.since) : null;

      let query = `
        SELECT id, title, text, duration, source, createdAt, lastModified, summary, tasks
        FROM recordings
        WHERE type = 'memo' AND deletedAt IS NULL
      `;
      const params: unknown[] = [];

      if (since) {
        query += ` AND createdAt >= ?`;
        params.push(since);
      }

      query += ` ORDER BY createdAt DESC LIMIT ?`;
      params.push(limit);

      const rows = queryAll(query, ...params);

      if (fmt.pretty) {
        outputTable(rows, [
          { key: "id", label: "ID", width: 8, format: (v) => String(v ?? "").slice(0, 8) },
          { key: "title", label: "Title", width: 30, format: (v) => truncate(String(v ?? "Untitled"), 30) },
          { key: "duration", label: "Duration", width: 10, format: (v) => formatDuration(v as number) },
          { key: "createdAt", label: "Created", width: 20, format: (v) => formatDate(v as string) },
          { key: "text", label: "Words", width: 6, format: (v) => String(wordCount(v as string)) },
        ], fmt);
      } else {
        const result = rows.map((r) => ({
          ...r,
          wordCount: wordCount(r.text as string),
        }));
        output(result, fmt);
      }
    });
}

function getMemo(
  id: string,
  fmt: { pretty: boolean; json: boolean },
  showSegments?: boolean
): void {
  const row = findByIdPrefix("recordings", id, "type = 'memo' AND deletedAt IS NULL");

  if (!row) {
    console.error(`Memo not found: ${id}`);
    process.exit(1);
  }

  // Parse segments if available
  const segmentsJSON = row.segmentsJSON as string | null;
  let segments: { text: string; words: Array<{ word: string; start: number; end: number; confidence?: number }> } | null = null;
  if (segmentsJSON) {
    try {
      segments = JSON.parse(segmentsJSON);
    } catch {
      // ignore parse errors
    }
  }

  if (fmt.pretty) {
    console.log(`# ${row.title || "Untitled"}\n`);
    console.log(`ID:       ${row.id}`);
    console.log(`Duration: ${formatDuration(row.duration as number)}`);
    console.log(`Source:   ${row.source}`);
    console.log(`Created:  ${formatDate(row.createdAt as string)}`);
    console.log(`Words:    ${wordCount(row.text as string)}`);
    if (segments) {
      console.log(`Segments: ${segments.words.length} word timings`);
    }
    if (row.summary) {
      console.log(`\n## Summary\n${row.summary}`);
    }
    if (row.tasks) {
      console.log(`\n## Tasks\n${row.tasks}`);
    }
    console.log(`\n## Transcript\n${row.text || "(no transcript)"}`);

    // Show word-level timeline if --segments flag is set
    if (showSegments && segments && segments.words.length > 0) {
      console.log(`\n## Timeline`);
      // Group words into ~5-second phrases for readable output
      let phraseStart = segments.words[0].start;
      let phraseWords: string[] = [];
      for (const w of segments.words) {
        if (w.start - phraseStart > 5 && phraseWords.length > 0) {
          const ts = formatTimestamp(phraseStart);
          console.log(`  [${ts}] ${phraseWords.join(" ")}`);
          phraseWords = [];
          phraseStart = w.start;
        }
        phraseWords.push(w.word);
      }
      if (phraseWords.length > 0) {
        const ts = formatTimestamp(phraseStart);
        console.log(`  [${ts}] ${phraseWords.join(" ")}`);
      }
    }
  } else {
    const result: Record<string, unknown> = {
      ...row,
      wordCount: wordCount(row.text as string),
    };
    if (segments) {
      result.segments = segments;
    }
    output(result, { pretty: false, json: true });
  }
}

function formatTimestamp(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = (seconds % 60).toFixed(1);
  return m > 0 ? `${m}:${s.padStart(4, "0")}` : `${s}s`;
}

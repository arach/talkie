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

export function registerDictationsCommand(program: Command): void {
  program
    .command("dictations [id]")
    .description("List recent dictations, or get a specific dictation by ID")
    .option("--limit <n>", "max results", "50")
    .option("--since <date>", "filter by date (e.g. 2025-02-01 or 7d)")
    .action((id: string | undefined, opts) => {
      const globalOpts = program.opts();
      getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);

      if (id) {
        return getDictation(id, fmt);
      }

      const limit = parseInt(opts.limit, 10);
      const since = opts.since ? parseSince(opts.since) : null;

      let query = `
        SELECT id, text, duration, source, createdAt, metadataJSON
        FROM recordings
        WHERE type = 'dictation'
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
          { key: "text", label: "Text", width: 40, format: (v) => truncate(v as string, 40) },
          { key: "duration", label: "Duration", width: 10, format: (v) => formatDuration(v as number) },
          { key: "createdAt", label: "Created", width: 20, format: (v) => formatDate(v as string) },
          { key: "text", label: "Words", width: 6, format: (v) => String(wordCount(v as string)) },
        ], fmt);
      } else {
        const result = rows.map((r) => {
          const out: Record<string, unknown> = { ...r };
          if (out.metadataJSON) {
            try { out.metadata = JSON.parse(out.metadataJSON as string); } catch { out.metadata = null; }
            delete out.metadataJSON;
          }
          out.wordCount = wordCount(r.text as string);
          return out;
        });
        output(result, fmt);
      }
    });
}

function getDictation(
  id: string,
  fmt: { pretty: boolean; json: boolean }
): void {
  const row = findByIdPrefix("recordings", id, "type = 'dictation'");

  if (!row) {
    console.error(`Dictation not found: ${id}`);
    process.exit(1);
  }

  if (fmt.pretty) {
    console.log(`# Dictation\n`);
    console.log(`ID:       ${row.id}`);
    console.log(`Duration: ${formatDuration(row.duration as number)}`);
    console.log(`Source:   ${row.source}`);
    console.log(`Created:  ${formatDate(row.createdAt as string)}`);
    console.log(`Words:    ${wordCount(row.text as string)}`);
    if (row.metadataJSON) {
      try {
        const meta = JSON.parse(row.metadataJSON as string);
        console.log(`App:      ${meta.bundleName || meta.bundleID || "—"}`);
      } catch {}
    }
    console.log(`\n## Text\n${row.text || "(no transcript)"}`);
  } else {
    const result: Record<string, unknown> = { ...row };
    if (result.metadataJSON) {
      try { result.metadata = JSON.parse(result.metadataJSON as string); } catch { result.metadata = null; }
      delete result.metadataJSON;
    }
    result.wordCount = wordCount(row.text as string);
    output(result, { pretty: false, json: true });
  }
}

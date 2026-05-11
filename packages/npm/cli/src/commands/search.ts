import type { Command } from "commander";
import { getDb, queryAll } from "../db";
import {
  getFormatOptions,
  output,
  formatDate,
  formatDuration,
  truncate,
} from "../format";
import { parseSince, parseUntil } from "./shared";

const HAS_FIELDS: Record<string, string> = {
  screenshots: "screenshotsJSON IS NOT NULL",
  summary: "summary IS NOT NULL AND summary != ''",
  tasks: "tasks IS NOT NULL AND tasks != ''",
  audio: "audioFileBookmark IS NOT NULL",
  segments: "segmentsJSON IS NOT NULL",
};

const SORT_OPTIONS: Record<string, string> = {
  newest: "r.createdAt DESC",
  oldest: "r.createdAt ASC",
  longest: "r.duration DESC",
  shortest: "r.duration ASC",
};

interface FilterResult {
  clauses: string[];
  params: unknown[];
}

function buildFilters(opts: Record<string, unknown>): FilterResult {
  const clauses: string[] = [];
  const params: unknown[] = [];

  if (opts.type) {
    clauses.push("r.type = ?");
    params.push(opts.type);
  }

  if (opts.since) {
    clauses.push("r.createdAt >= ?");
    params.push(parseSince(opts.since as string));
  }

  if (opts.until) {
    clauses.push("r.createdAt <= ?");
    params.push(parseUntil(opts.until as string));
  }

  if (opts.app) {
    const app = opts.app as string;
    clauses.push(
      "(json_extract(r.metadataJSON, '$.app.name') LIKE ? OR json_extract(r.metadataJSON, '$.app.bundleId') LIKE ?)"
    );
    params.push(`%${app}%`, `%${app}%`);
  }

  if (opts.source) {
    clauses.push("r.source = ?");
    params.push(opts.source);
  }

  if (opts.has) {
    const field = opts.has as string;
    const condition = HAS_FIELDS[field];
    if (!condition) {
      console.error(
        `Unknown --has value: ${field}. Options: ${Object.keys(HAS_FIELDS).join(", ")}`
      );
      process.exit(1);
    }
    clauses.push(condition.replace(/\b(screenshotsJSON|summary|tasks|audioFileBookmark|segmentsJSON)\b/g, "r.$1"));
  }

  if (opts.longerThan) {
    clauses.push("r.duration >= ?");
    params.push(parseFloat(opts.longerThan as string));
  }

  if (opts.shorterThan) {
    clauses.push("r.duration <= ?");
    params.push(parseFloat(opts.shorterThan as string));
  }

  return { clauses, params };
}

function getOrderBy(sort: string | undefined, hasTextQuery: boolean): string {
  if (!sort) {
    return hasTextQuery ? "rank" : "r.createdAt DESC";
  }
  if (sort === "relevance") {
    return hasTextQuery ? "rank" : "r.createdAt DESC";
  }
  const order = SORT_OPTIONS[sort];
  if (!order) {
    console.error(
      `Unknown --sort value: ${sort}. Options: ${["newest", "oldest", "longest", "shortest", "relevance"].join(", ")}`
    );
    process.exit(1);
  }
  return order;
}

function prettyPrint(rows: Record<string, unknown>[], query?: string): void {
  if (rows.length === 0) {
    const msg = query ? `No results for "${query}".` : "No results.";
    console.log(msg);
    return;
  }

  const countLabel = `${rows.length} result${rows.length === 1 ? "" : "s"}`;
  console.log(query ? `${countLabel} for "${query}"\n` : `${countLabel}\n`);

  for (const row of rows) {
    const type = row.type as string;
    const typeTag = type === "memo" ? "\x1b[34m[memo]\x1b[0m" : "\x1b[33m[dict]\x1b[0m";
    const idShort = String(row.id).slice(0, 8);
    const title = row.title ? ` — ${row.title}` : "";
    const date = formatDate(row.createdAt as string);
    const dur = formatDuration(row.duration as number);
    const source = row.source ? ` · ${row.source}` : "";

    // App name from metadataJSON
    let appName = "";
    if (row.metadataJSON) {
      try {
        const meta = JSON.parse(row.metadataJSON as string);
        const name = meta?.app?.name;
        if (name) appName = ` · ${name}`;
      } catch {}
    }

    // Feature indicators
    const features: string[] = [];
    if (row.screenshotsJSON) features.push("📷");
    if (row.summary) features.push("📝");
    if (row.tasks) features.push("✅");
    if (row.segmentsJSON) features.push("⏱");
    const featureStr = features.length > 0 ? ` ${features.join("")}` : "";

    console.log(
      `${typeTag} ${idShort}${title} (${date} · ${dur}${source}${appName})${featureStr}`
    );

    // Show text snippet or FTS highlight
    const highlight = (row.textHighlight as string) || truncate(row.text as string, 120);
    if (highlight) {
      const lines = highlight.split("\n").filter(Boolean);
      const matchLine =
        lines.find((l) => l.includes(">>>")) || lines[0] || "";
      console.log(`  ${truncate(matchLine.trim(), 100)}\n`);
    }
  }
}

export function registerSearchCommand(program: Command): void {
  program
    .command("search [query]")
    .description("Search and filter recordings")
    .option("--limit <n>", "max results", "20")
    .option("--type <type>", "filter by type (memo, dictation)")
    .option("--since <date>", "created after date (7d, 24h, 2026-02-01)")
    .option("--until <date>", "created before date")
    .option("--app <name>", "filter by app name or bundle ID")
    .option("--source <src>", "filter by source (mac, iphone, watch, live)")
    .option("--has <field>", "has data: screenshots, summary, tasks, audio, segments")
    .option("--longer-than <seconds>", "minimum duration in seconds")
    .option("--shorter-than <seconds>", "maximum duration in seconds")
    .option("--sort <order>", "sort: newest, oldest, longest, shortest, relevance")
    .action((query: string | undefined, opts) => {
      const globalOpts = program.opts();
      const db = getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);
      const limit = parseInt(opts.limit, 10);

      if (!query && !opts.type && !opts.since && !opts.until && !opts.app &&
          !opts.source && !opts.has && !opts.longerThan && !opts.shorterThan) {
        console.error("Provide a search query or at least one filter (--since, --type, --app, etc.)");
        process.exit(1);
      }

      const { clauses, params } = buildFilters(opts);
      let rows: Record<string, unknown>[];

      const selectCols = `r.id, r.type, r.title, r.text, r.createdAt, r.duration,
                 r.source, r.metadataJSON, r.screenshotsJSON, r.summary, r.tasks, r.segmentsJSON`;

      if (query) {
        // FTS path
        const ftsCount = db
          .prepare("SELECT count(*) as c FROM recordings_fts")
          .get() as { c: number } | null;
        const useFts = ftsCount && ftsCount.c > 0;

        if (useFts) {
          const orderBy = getOrderBy(opts.sort, true);
          const whereParts = ["recordings_fts MATCH ?", ...clauses.map(c => c), "r.deletedAt IS NULL"];
          const sql = `
            SELECT ${selectCols},
                   highlight(recordings_fts, 0, '>>>', '<<<') AS titleHighlight,
                   highlight(recordings_fts, 1, '>>>', '<<<') AS textHighlight
            FROM recordings_fts
            JOIN recordings r ON r.rowid = recordings_fts.rowid
            WHERE ${whereParts.join(" AND ")}
            ORDER BY ${orderBy} LIMIT ?
          `;
          rows = queryAll(sql, query, ...params, limit);
        } else {
          // LIKE fallback — no rank column available
          const orderBy = getOrderBy(opts.sort, false);
          const whereParts = [
            "(r.text LIKE '%' || ? || '%' OR r.title LIKE '%' || ? || '%')",
            ...clauses,
            "r.deletedAt IS NULL",
          ];
          const sql = `
            SELECT ${selectCols}
            FROM recordings r
            WHERE ${whereParts.join(" AND ")}
            ORDER BY ${orderBy} LIMIT ?
          `;
          rows = queryAll(sql, query, query, ...params, limit);
        }
      } else {
        // Filter-only path (no text query)
        const orderBy = getOrderBy(opts.sort, false);
        const whereParts = [...clauses, "r.deletedAt IS NULL"];
        const sql = `
          SELECT ${selectCols}
          FROM recordings r
          WHERE ${whereParts.join(" AND ")}
          ORDER BY ${orderBy} LIMIT ?
        `;
        rows = queryAll(sql, ...params, limit);
      }

      if (fmt.pretty) {
        prettyPrint(rows, query);
      } else {
        output(rows, fmt);
      }
    });
}

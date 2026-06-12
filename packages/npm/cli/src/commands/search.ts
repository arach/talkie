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

const HAS_FIELDS = [
  "screenshots",
  "clips",
  "videos",
  "captures",
  "summary",
  "tasks",
  "audio",
  "segments",
];

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

function buildFilters(opts: Record<string, unknown>, columns: Set<string>): FilterResult {
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
    const condition = hasFieldCondition(field, columns);
    if (!condition) {
      console.error(
        `Unknown --has value: ${field}. Options: ${HAS_FIELDS.join(", ")}`
      );
      process.exit(1);
    }
    clauses.push(condition);
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

function hasFieldCondition(field: string, columns: Set<string>): string | null {
  switch (field) {
    case "screenshots":
      return mediaCondition(columns, "screenshots");
    case "clips":
    case "videos":
      return mediaCondition(columns, "clips");
    case "captures": {
      const screenshots = mediaCondition(columns, "screenshots");
      const clips = mediaCondition(columns, "clips");
      return `(${[screenshots, clips].filter(Boolean).join(" OR ")})`;
    }
    case "summary":
      return columns.has("summary") ? "r.summary IS NOT NULL AND r.summary != ''" : "0";
    case "tasks":
      return columns.has("tasks") ? "r.tasks IS NOT NULL AND r.tasks != ''" : "0";
    case "audio": {
      const clauses: string[] = [];
      if (columns.has("hasAudio")) clauses.push("r.hasAudio = 1");
      if (columns.has("audioFilename")) clauses.push("r.audioFilename IS NOT NULL AND r.audioFilename != ''");
      if (columns.has("audioFileBookmark")) clauses.push("r.audioFileBookmark IS NOT NULL AND r.audioFileBookmark != ''");
      return clauses.length > 0 ? `(${clauses.join(" OR ")})` : "0";
    }
    case "segments": {
      const clauses: string[] = [];
      if (columns.has("assetsJSON")) {
        clauses.push("json_valid(r.assetsJSON) AND json_type(r.assetsJSON, '$.segments') IS NOT NULL");
      }
      if (columns.has("segmentsJSON")) clauses.push("r.segmentsJSON IS NOT NULL");
      return clauses.length > 0 ? `(${clauses.join(" OR ")})` : "0";
    }
    default:
      return null;
  }
}

function mediaCondition(columns: Set<string>, key: "screenshots" | "clips"): string {
  const clauses: string[] = [];
  if (columns.has("assetsJSON")) {
    clauses.push(`json_valid(r.assetsJSON) AND json_array_length(json_extract(r.assetsJSON, '$.${key}')) > 0`);
  }
  const legacyColumn = key === "screenshots" ? "screenshotsJSON" : "clipsJSON";
  if (columns.has(legacyColumn)) clauses.push(`r.${legacyColumn} IS NOT NULL`);
  return clauses.length > 0 ? `(${clauses.join(" OR ")})` : "0";
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
    if (rowHasAsset(row, "screenshots")) features.push("📷");
    if (rowHasAsset(row, "clips")) features.push("🎞");
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

function rowHasAsset(row: Record<string, unknown>, key: "screenshots" | "clips"): boolean {
  const legacyColumn = key === "screenshots" ? "screenshotsJSON" : "clipsJSON";
  if (row[legacyColumn]) return true;
  if (typeof row.assetsJSON !== "string") return false;
  try {
    const assets = JSON.parse(row.assetsJSON);
    return Array.isArray(assets?.[key]) && assets[key].length > 0;
  } catch {
    return false;
  }
}

function prefixedColumns(columns: Set<string>, names: string[]): string[] {
  return names.filter((name) => columns.has(name)).map((name) => `r.${name}`);
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
    .option("--has <field>", "has data: screenshots, clips, videos, captures, summary, tasks, audio, segments")
    .option("--longer-than <seconds>", "minimum duration in seconds")
    .option("--shorter-than <seconds>", "maximum duration in seconds")
    .option("--sort <order>", "sort: newest, oldest, longest, shortest, relevance")
    .action((query: string | undefined, opts) => {
      const globalOpts = program.opts();
      const db = getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);
      const limit = parseInt(opts.limit, 10);
      const columns = new Set(
        (db.prepare("PRAGMA table_info(recordings)").all() as Array<{ name: string }>)
          .map((row) => row.name)
      );

      if (!query && !opts.type && !opts.since && !opts.until && !opts.app &&
          !opts.source && !opts.has && !opts.longerThan && !opts.shorterThan) {
        console.error("Provide a search query or at least one filter (--since, --type, --app, etc.)");
        process.exit(1);
      }

      const { clauses, params } = buildFilters(opts, columns);
      let rows: Record<string, unknown>[];

      const selectCols = prefixedColumns(columns, [
        "id",
        "type",
        "title",
        "text",
        "createdAt",
        "duration",
        "source",
        "metadataJSON",
        "assetsJSON",
        "screenshotsJSON",
        "clipsJSON",
        "summary",
        "tasks",
        "segmentsJSON",
      ]).join(", ");

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

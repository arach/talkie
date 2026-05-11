import type { Command } from "commander";
import { existsSync, statSync } from "fs";
import { Database } from "bun:sqlite";
import { getFormatOptions, output, outputTable } from "../../format";
import { resolveDbPath } from "../../db";

function openDb(override?: string): Database {
  const dbPath = resolveDbPath(override);
  if (!existsSync(dbPath)) {
    console.error(`Database not found: ${dbPath}`);
    process.exit(1);
  }
  const db = new Database(dbPath, { readonly: true });
  db.exec("PRAGMA journal_mode = WAL");
  db.exec("PRAGMA busy_timeout = 5000");
  return db;
}

function showDbInfo(db: Database, dbPath: string, fmt: { pretty: boolean; json: boolean }): void {
  const stats = statSync(dbPath);
  const sizeMb = (stats.size / 1024 / 1024).toFixed(1);

  const tables = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    .all() as { name: string }[];

  const tableInfo = tables.map((t) => {
    const count = (db.prepare(`SELECT count(*) as count FROM "${t.name}"`).get() as { count: number }).count;
    return { name: t.name, rows: count };
  });

  if (fmt.pretty) {
    console.log(`\n\x1b[1mDatabase\x1b[0m: ${dbPath.replace(process.env.HOME || "", "~")}`);
    console.log(`\x1b[1mSize\x1b[0m: ${sizeMb} MB`);
    console.log(`\x1b[1mTables\x1b[0m: ${tables.length}\n`);

    for (const t of tableInfo) {
      console.log(`  ${t.name.padEnd(30)} ${String(t.rows).padStart(8)} rows`);
    }
    console.log("");
  } else {
    output({ path: dbPath, sizeBytes: stats.size, sizeMb: `${sizeMb} MB`, tables: tableInfo }, fmt);
  }
}

function showTables(db: Database, fmt: { pretty: boolean; json: boolean }): void {
  const tables = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    .all() as { name: string }[];

  const tableInfo = tables.map((t) => {
    const count = (db.prepare(`SELECT count(*) as count FROM "${t.name}"`).get() as { count: number }).count;
    return { name: t.name, rows: count };
  });

  if (fmt.pretty) {
    outputTable(
      tableInfo as unknown as Record<string, unknown>[],
      [
        { key: "name", label: "Table", width: 35 },
        { key: "rows", label: "Rows", width: 10, format: (v) => String(v) },
      ],
      fmt
    );
  } else {
    output(tableInfo, fmt);
  }
}

function runQuery(db: Database, sql: string, fmt: { pretty: boolean; json: boolean }): void {
  try {
    const rows = db.prepare(sql).all() as Record<string, unknown>[];

    if (fmt.pretty) {
      if (rows.length === 0) {
        console.log("No results.");
        return;
      }

      // Auto-detect columns from first row
      const keys = Object.keys(rows[0]);
      const columns = keys.map((key) => ({
        key,
        label: key,
        format: (v: unknown) => {
          if (v === null || v === undefined) return "NULL";
          if (v instanceof Uint8Array) return `<blob ${v.length}b>`;
          const s = String(v);
          return s.length > 60 ? s.slice(0, 59) + "…" : s;
        },
      }));

      outputTable(rows, columns, fmt);
    } else {
      output(rows, fmt);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`SQL error: ${msg}`);
    process.exit(1);
  }
}

export function registerDbCommand(devCmd: Command): void {
  devCmd
    .command("db [query]")
    .description(
      "Inspect the Talkie GRDB database (read-only).\n\n" +
      "Use when: checking database state, counting recordings, or running diagnostic queries.\n" +
      "No args shows overview, 'tables' lists all tables, or pass raw SQL.\n\n" +
      "Example: talkie-dev db                                  (overview)\n" +
      "         talkie-dev db tables                            (list tables)\n" +
      "         talkie-dev db \"SELECT count(*) FROM recordings\"  (raw SQL)"
    )
    .action((query: string | undefined, _, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const dbPath = resolveDbPath(globalOpts.db);
      const db = openDb(globalOpts.db);

      try {
        if (!query) {
          showDbInfo(db, dbPath, fmt);
        } else if (query.toLowerCase() === "tables") {
          showTables(db, fmt);
        } else {
          runQuery(db, query, fmt);
        }
      } finally {
        db.close();
      }
    });
}

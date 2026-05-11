import { Database, type SQLQueryBindings } from "bun:sqlite";
import { homedir } from "os";
import { join } from "path";
import { existsSync } from "fs";

const DEFAULT_PATH = join(
  homedir(),
  "Library",
  "Application Support",
  "Talkie",
  "talkie.sqlite"
);

let _db: Database | null = null;

export function resolveDbPath(override?: string): string {
  if (override) return override;
  if (process.env.TALKIE_DB) return process.env.TALKIE_DB;
  return DEFAULT_PATH;
}

export function getDb(override?: string): Database {
  if (_db) return _db;

  const dbPath = resolveDbPath(override);

  if (!existsSync(dbPath)) {
    console.error(`Database not found: ${dbPath}`);
    console.error(
      "Is Talkie installed? Try specifying --db <path> or set TALKIE_DB env var."
    );
    process.exit(1);
  }

  _db = new Database(dbPath, { readonly: true });
  _db.exec("PRAGMA journal_mode = WAL");
  _db.exec("PRAGMA busy_timeout = 5000");

  return _db;
}

export function closeDb(): void {
  if (_db) {
    _db.close();
    _db = null;
  }
}

/**
 * Convert a 16-byte UUID blob to a UUID string.
 * GRDB stores Swift UUID values as 16-byte blobs, while some rows
 * have text UUIDs. This normalizes both to uppercase UUID strings.
 */
function uuidFromBytes(bytes: Uint8Array): string {
  const hex = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
  return (
    hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-" + hex.slice(12, 16) + "-" +
    hex.slice(16, 20) + "-" + hex.slice(20)
  );
}

/**
 * Decode a row from bun:sqlite, converting any Uint8Array UUID blobs to strings.
 * Handles the mixed blob/text UUID storage from GRDB.
 */
export function decodeRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    if (v instanceof Uint8Array) {
      // 16-byte = UUID blob, otherwise try text decode
      out[k] = v.length === 16 ? uuidFromBytes(v) : new TextDecoder().decode(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

/**
 * Run a query and decode all rows (handling UUID blobs).
 */
export function queryAll(sql: string, ...params: unknown[]): Record<string, unknown>[] {
  const db = _db!;
  return db.prepare(sql).all(...(params as SQLQueryBindings[])).map((r) => decodeRow(r as Record<string, unknown>));
}

/**
 * Run a query and decode a single row.
 */
export function queryOne(sql: string, ...params: unknown[]): Record<string, unknown> | null {
  const db = _db!;
  const row = db.prepare(sql).get(...(params as SQLQueryBindings[])) as Record<string, unknown> | null;
  return row ? decodeRow(row) : null;
}

/**
 * Find a row by ID prefix. Handles mixed blob/text UUID storage by searching
 * both text UUIDs (LIKE) and blob UUIDs (hex comparison).
 */
export function findByIdPrefix(
  table: string,
  prefix: string,
  extraWhere?: string
): Record<string, unknown> | null {
  const db = _db!;
  const upper = prefix.toUpperCase();
  const noDashes = upper.replace(/-/g, "");
  const where = extraWhere ? ` AND ${extraWhere}` : "";

  // Search text UUIDs with LIKE, and blob UUIDs via hex()
  const sql = `
    SELECT * FROM ${table}
    WHERE (
      (typeof(id) = 'text' AND upper(id) LIKE ? || '%')
      OR (typeof(id) = 'blob' AND upper(hex(id)) LIKE ? || '%')
    )${where}
    LIMIT 1
  `;
  const row = db.prepare(sql).get(upper, noDashes) as Record<string, unknown> | null;
  return row ? decodeRow(row) : null;
}

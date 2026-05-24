/**
 * iOS Settings extraction — schema types + pure helpers.
 *
 * Client-safe. Loading the snapshot from disk lives in the
 * server-only sibling `lib/ios-settings.server.ts` so this file can
 * be imported from both the server page and the client table.
 *
 * The actual snapshot rows live in `data/ios-settings/snapshot.json`.
 */

export type SettingsPanel =
  | "voice"
  | "look"
  | "connect"
  | "keys"
  | "lab"
  | "about";

export type SettingsRowType =
  | "field"
  | "cycle"
  | "toggle"
  | "text"
  | "metric"
  | "install"
  | "action"
  | "nav"
  | "swatch";

export type SettingsStatus =
  | "wired"
  | "todo"
  | "computed"
  | "debug"
  | "conditional";

export interface SettingsRow {
  panel: SettingsPanel;
  /** Section header above this row (TRANSCRIPTION / RECORDING / etc). */
  section?: string;
  type: SettingsRowType;
  label: string;
  /**
   * Alternate labels this row claims. When the regex scanner finds
   * any of these strings, the row is treated as still-present.
   * Necessary when one snapshot entry collapses several conditional
   * Swift call sites (Sign in / Sign out).
   */
  aliases?: string[];
  value: string | null;
  hint?: string;
  /** Backing TalkieAppSettings key when wired. */
  setting?: string;
  status: SettingsStatus;
  /** Source line in SettingsNext.swift. */
  line: number;
  /** Free-form note. */
  note?: string;
}

export interface SettingsSnapshot {
  schemaVersion: number;
  source: string;
  extractedAt: string;
  rows: SettingsRow[];
}

/** All literal Swift labels this snapshot row claims. */
export function rowLabels(row: SettingsRow): string[] {
  return row.aliases?.length ? [row.label, ...row.aliases] : [row.label];
}

/** Counts by status — handy for the page header summary. */
export function statusSummary(rows: SettingsRow[]) {
  const out: Record<SettingsStatus, number> = {
    wired: 0,
    todo: 0,
    computed: 0,
    debug: 0,
    conditional: 0,
  };
  for (const r of rows) out[r.status]++;
  return out;
}

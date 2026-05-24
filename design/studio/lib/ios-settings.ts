/**
 * iOS Settings extraction — types, JSON loader, alias-aware matching.
 *
 * The actual snapshot rows live in
 * `data/ios-settings/snapshot.json`. This file holds the schema +
 * helpers around it (status summary, alias-aware label matching).
 *
 * `aliases` lets one snapshot row claim multiple literal labels — the
 * `Sign in with Apple` / `Sign out` pair in `SettingsNext.swift` is
 * conditionally rendered, but reads as one row in the audit. The
 * regex scanner sees two literal `actionRow("…")` calls; the
 * snapshot row's `aliases` field collects them so drift detection
 * doesn't false-flag.
 */

import { promises as fs } from "node:fs";
import path from "node:path";

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

/**
 * Read the snapshot JSON at request time. Studio runs from
 * `design/studio`, so the data path is local to that root.
 */
export async function loadSnapshot(): Promise<SettingsSnapshot> {
  const filePath = path.resolve(
    process.cwd(),
    "data",
    "ios-settings",
    "snapshot.json",
  );
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as SettingsSnapshot;
}

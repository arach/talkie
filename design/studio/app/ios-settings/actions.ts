"use server";

/**
 * Live re-walk of SettingsNext.swift.
 *
 * Reads the source file, regex-scans for the standard panel-row
 * helpers (`field` / `cycleRow` / `toggleRow` / `textEntryRow` /
 * `actionRow` / `navRow`) and returns each match with its label
 * and source line. The page diff's this against the manual snapshot
 * in `lib/ios-settings.ts` so the user can see drift since the last
 * extraction without losing the human-classified `status` / `note`
 * fields on the existing rows.
 *
 * Deliberately narrow — we don't try to capture `metricStrip` metric
 * names, `parakeetInstallRow`, theme swatches, etc. Those are listed
 * separately in the snapshot and don't change often.
 */

import { promises as fs } from "node:fs";
import path from "node:path";

/**
 * Whole-file scan. `\s*` includes newlines, so a helper call whose
 * label sits on the next line (the common shape for cycleRow /
 * toggleRow / textEntryRow with binding args) is matched the same as
 * a single-line `field("X", "Y")`. The `g` flag walks every match;
 * line numbers are recovered from the match index by counting `\n`
 * up to that offset.
 */
const HELPER_RE =
  /(field|cycleRow|toggleRow|textEntryRow|actionRow|navRow)\s*\(\s*"([^"]+)"/g;

export interface ScannedRow {
  type: string;
  label: string;
  line: number;
}

export interface ScanResult {
  ok: true;
  scannedAt: string;
  source: string;
  rows: ScannedRow[];
}

export interface ScanError {
  ok: false;
  message: string;
}

const SETTINGS_PATH = "apps/ios/Talkie iOS/Views/Next/SettingsNext.swift";

function lineNumberAt(content: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index; i++) {
    if (content.charCodeAt(i) === 10 /* \n */) line++;
  }
  return line;
}

export async function scanIOSSettings(): Promise<ScanResult | ScanError> {
  try {
    // Studio lives at `design/studio`; repo root is two levels up.
    const filePath = path.resolve(process.cwd(), "..", "..", SETTINGS_PATH);
    const content = await fs.readFile(filePath, "utf8");

    const rows: ScannedRow[] = [];
    HELPER_RE.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = HELPER_RE.exec(content)) !== null) {
      rows.push({
        type: m[1],
        label: m[2],
        line: lineNumberAt(content, m.index),
      });
    }

    return {
      ok: true,
      scannedAt: new Date().toISOString(),
      source: SETTINGS_PATH,
      rows,
    };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : String(err),
    };
  }
}

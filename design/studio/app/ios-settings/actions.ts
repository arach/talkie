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

const HELPER_RE =
  /(field|cycleRow|toggleRow|textEntryRow|actionRow|navRow)\(\s*"([^"]+)"/g;

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

export async function scanIOSSettings(): Promise<ScanResult | ScanError> {
  try {
    // Studio lives at `design/studio`; repo root is two levels up.
    const filePath = path.resolve(process.cwd(), "..", "..", SETTINGS_PATH);
    const content = await fs.readFile(filePath, "utf8");
    const lines = content.split("\n");

    const rows: ScannedRow[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      HELPER_RE.lastIndex = 0;
      let m: RegExpExecArray | null;
      while ((m = HELPER_RE.exec(line)) !== null) {
        rows.push({ type: m[1], label: m[2], line: i + 1 });
      }
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

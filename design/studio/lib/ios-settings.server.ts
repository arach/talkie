import { promises as fs } from "node:fs";
import path from "node:path";

import type { SettingsSnapshot } from "./ios-settings";

/**
 * Read the snapshot JSON at request time. Studio runs from
 * `design/studio`, so the data path is local to that root.
 *
 * Kept in a `.server.ts` sibling so the `node:fs` import never leaks
 * into the client bundle — the regular `lib/ios-settings` module is
 * imported by both server and client surfaces. Only ever import this
 * file from server components / server actions.
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

import type { Command } from "commander";
import { existsSync, rmSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import { getFormatOptions, output } from "../format";

const HOME = homedir();
const APP_SUPPORT = join(HOME, "Library/Application Support/Talkie");
const AUDIO_DIR = join(APP_SUPPORT, "Audio");
const DB_PATH = join(APP_SUPPORT, "talkie.sqlite");

// All user data locations (production only — this is a user-facing command)
const DATA_LOCATIONS = [
  { path: APP_SUPPORT, label: "Database & audio", desc: "Recordings, transcripts, and audio files" },
  { path: join(HOME, "Library/Preferences/jdi.talkie.core.plist"), label: "Preferences", desc: "App settings and configuration" },
  { path: join(HOME, "Library/Preferences/com.jdi.talkie.shared.plist"), label: "Shared settings", desc: "Settings shared with helper apps" },
  { path: join(HOME, "Library/LaunchAgents/jdi.talkie.agent.plist"), label: "Agent launch agent", desc: "Auto-start for dictation helper" },
  { path: join(HOME, "Library/LaunchAgents/jdi.talkie.engine.plist"), label: "Engine launch agent", desc: "Auto-start for transcription engine" },
  { path: join(HOME, "Library/LaunchAgents/jdi.talkie.sync.plist"), label: "Sync launch agent", desc: "Auto-start for sync service" },
  { path: join(HOME, "Library/Caches/jdi.talkie.core"), label: "App cache", desc: "Cached data" },
  { path: join(HOME, "Library/Caches/jdi.talkie.agent"), label: "Agent cache", desc: "Agent cached data" },
  { path: join(HOME, "Library/Caches/jdi.talkie.engine"), label: "Engine cache", desc: "Transcription model cache" },
];

const DEFAULTS_DOMAINS = [
  "jdi.talkie.core",
  "jdi.talkie.agent",
  "jdi.talkie.engine",
  "com.jdi.talkie.shared",
];

function getUid(): string {
  return Bun.spawnSync(["id", "-u"]).stdout.toString().trim();
}

function getSizeMB(path: string): number | null {
  if (!existsSync(path)) return null;
  const du = Bun.spawnSync(["du", "-sm", path], { stdout: "pipe", stderr: "pipe" });
  if (du.exitCode !== 0) return null;
  return parseInt(du.stdout.toString().split("\t")[0], 10);
}

function formatSize(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${mb} MB`;
}

function getRecordingCount(): number | null {
  if (!existsSync(DB_PATH)) return null;
  try {
    const result = Bun.spawnSync(
      ["sqlite3", DB_PATH, "SELECT COUNT(*) FROM recordings;"],
      { stdout: "pipe", stderr: "pipe" }
    );
    if (result.exitCode !== 0) return null;
    return parseInt(result.stdout.toString().trim(), 10);
  } catch {
    return null;
  }
}

function stopTalkieServices(): number {
  let stopped = 0;
  const uid = getUid();

  // Quit the main app gracefully
  Bun.spawnSync(["osascript", "-e", 'tell application "Talkie" to quit'], { stderr: "pipe" });

  // Kill helper processes
  for (const name of ["TalkieAgent", "TalkieEngine", "TalkieSync"]) {
    const result = Bun.spawnSync(["pkill", "-x", name]);
    if (result.exitCode === 0) stopped++;
  }

  // Bootout launchd registrations
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  for (const line of listResult.stdout.toString().split("\n")) {
    if (!line.includes("jdi.talkie")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");
    // Only bootout production labels (not .dev or .staging)
    if (!label.includes(".dev") && !label.includes(".staging")) {
      Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
    }
  }

  return stopped;
}

// ---------------------------------------------------------------------------
// `talkie data` — show data locations and usage
// ---------------------------------------------------------------------------

function dataInfoAction(pretty: boolean) {
  const locations: { label: string; path: string; exists: boolean; sizeMB: number | null }[] = [];
  let totalMB = 0;

  for (const loc of DATA_LOCATIONS) {
    const exists = existsSync(loc.path);
    const sizeMB = exists ? getSizeMB(loc.path) : null;
    locations.push({ label: loc.label, path: loc.path, exists, sizeMB });
    if (sizeMB) totalMB += sizeMB;
  }

  const recordingCount = getRecordingCount();

  if (pretty) {
    console.log("\n  \x1b[1mTalkie Data\x1b[0m\n");

    if (recordingCount !== null) {
      console.log(`  Recordings: ${recordingCount}`);
    }
    console.log(`  Total size: ${formatSize(totalMB)}\n`);

    for (const loc of locations) {
      if (!loc.exists) continue;
      const size = loc.sizeMB ? `\x1b[90m${formatSize(loc.sizeMB)}\x1b[0m` : "";
      console.log(`  \x1b[32m●\x1b[0m ${loc.label.padEnd(25)} ${size}`);
      console.log(`    \x1b[90m${loc.path}\x1b[0m`);
    }

    console.log(`\n  \x1b[90mtalkie data archive    Back up to a zip file\x1b[0m`);
    console.log(`  \x1b[90mtalkie data clean      Remove all data and start fresh\x1b[0m`);
    console.log(`  \x1b[90mtalkie data path       Show the data folder\x1b[0m\n`);
  } else {
    output({ locations: locations.filter(l => l.exists), totalMB, recordingCount }, { pretty: false, json: true });
  }
}

// ---------------------------------------------------------------------------
// `talkie data path` — print or open the data folder
// ---------------------------------------------------------------------------

function dataPathAction(opts: { open?: boolean }, pretty: boolean) {
  if (opts.open) {
    if (existsSync(APP_SUPPORT)) {
      Bun.spawnSync(["open", APP_SUPPORT]);
      if (pretty) console.log(`  Opened ${APP_SUPPORT}`);
    } else {
      if (pretty) console.log(`  \x1b[90mData folder not found: ${APP_SUPPORT}\x1b[0m`);
    }
  } else {
    console.log(APP_SUPPORT);
  }
}

// ---------------------------------------------------------------------------
// `talkie data clean` — wipe all user data
// ---------------------------------------------------------------------------

async function dataCleanAction(opts: { yes?: boolean; keepKeys?: boolean }, pretty: boolean) {
  // Collect what exists
  const existing = DATA_LOCATIONS.filter(loc => existsSync(loc.path));
  let totalMB = 0;
  for (const loc of existing) {
    totalMB += getSizeMB(loc.path) ?? 0;
  }

  const recordingCount = getRecordingCount();
  const apiKeysPath = join(APP_SUPPORT, ".apikeys");
  const hasApiKeys = existsSync(apiKeysPath);

  if (existing.length === 0) {
    if (pretty) {
      console.log("  \x1b[32mNo Talkie data found.\x1b[0m");
    } else {
      output({ status: "empty" }, { pretty: false, json: true });
    }
    return;
  }

  if (pretty) {
    console.log("\n  \x1b[1mThis will remove:\x1b[0m\n");
    if (recordingCount !== null && recordingCount > 0) {
      console.log(`    • ${recordingCount} recording${recordingCount !== 1 ? "s" : ""}`);
    }
    console.log(`    • All transcripts, settings, and cached data`);
    console.log(`    • ~${formatSize(totalMB)} of data`);
    if (hasApiKeys && !opts.keepKeys) {
      console.log(`    • API keys (use --keep-keys to preserve)`);
    }
    console.log("");
  }

  // Confirmation
  if (!opts.yes) {
    process.stdout.write("  \x1b[1mThis cannot be undone. Continue? [y/N] \x1b[0m");
    const response = await new Promise<string>((resolve) => {
      process.stdin.setEncoding("utf8");
      process.stdin.once("data", (data) => resolve(data.toString().trim().toLowerCase()));
      process.stdin.resume();
    });
    process.stdin.pause();

    if (response !== "y" && response !== "yes") {
      console.log("  Cancelled.");
      return;
    }
    console.log("");
  }

  // Stop services
  if (pretty) process.stdout.write("  Stopping Talkie...");
  const stopped = stopTalkieServices();
  if (pretty) console.log(` \x1b[32mdone\x1b[0m`);

  // Brief pause
  await Bun.sleep(500);

  // Delete files
  let deletedCount = 0;
  for (const loc of existing) {
    try {
      rmSync(loc.path, { recursive: true, force: true });
      deletedCount++;
      if (pretty) console.log(`  \x1b[32m✓\x1b[0m ${loc.label}`);
    } catch (e) {
      if (pretty) console.log(`  \x1b[31m✗\x1b[0m ${loc.label}: ${e instanceof Error ? e.message : e}`);
    }
  }

  // Reset UserDefaults
  let defaultsCleared = 0;
  for (const domain of DEFAULTS_DOMAINS) {
    const result = Bun.spawnSync(["defaults", "delete", domain]);
    if (result.exitCode === 0) defaultsCleared++;
  }
  if (pretty && defaultsCleared > 0) {
    console.log(`  \x1b[32m✓\x1b[0m Settings reset`);
  }

  // API keys
  if (!opts.keepKeys && hasApiKeys) {
    try {
      rmSync(apiKeysPath, { force: true });
      if (pretty) console.log(`  \x1b[32m✓\x1b[0m API keys removed`);
    } catch {}
  }

  if (pretty) {
    console.log(`\n  \x1b[32mDone.\x1b[0m ~${formatSize(totalMB)} freed.`);
    console.log("  Launch Talkie to start fresh.\n");
  } else {
    output({ status: "cleaned", deleted: deletedCount, freedMB: totalMB }, { pretty: false, json: true });
  }
}

// ---------------------------------------------------------------------------
// `talkie data archive` — zip up data for backup or sharing
// ---------------------------------------------------------------------------

async function dataArchiveAction(opts: { output?: string; open?: boolean }, pretty: boolean) {
  if (!existsSync(APP_SUPPORT)) {
    if (pretty) console.log("  \x1b[90mNo Talkie data found.\x1b[0m");
    else output({ status: "empty" }, { pretty: false, json: true });
    return;
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const defaultDest = join(HOME, "Desktop", `talkie-data-${timestamp}.zip`);
  const dest = opts.output ?? defaultDest;

  const sizeMB = getSizeMB(APP_SUPPORT);
  const recordingCount = getRecordingCount();

  if (pretty) {
    console.log(`\n  \x1b[1mArchiving Talkie data\x1b[0m\n`);
    if (recordingCount !== null) console.log(`  Recordings: ${recordingCount}`);
    if (sizeMB !== null) console.log(`  Source size: ${formatSize(sizeMB)}`);
    console.log("");
    process.stdout.write("  Compressing...");
  }

  const zip = Bun.spawnSync(
    ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP_SUPPORT, dest],
    { stdout: "pipe", stderr: "pipe" }
  );

  if (zip.exitCode !== 0) {
    const err = zip.stderr.toString().trim();
    if (pretty) console.log(` \x1b[31mfailed\x1b[0m\n  ${err}`);
    else output({ error: err }, { pretty: false, json: true });
    process.exit(1);
  }

  const archiveSizeMB = getSizeMB(dest);

  if (pretty) {
    console.log(` \x1b[32mdone\x1b[0m`);
    console.log(`\n  \x1b[32m✓\x1b[0m Saved to ${dest}`);
    if (archiveSizeMB !== null) console.log(`    Archive size: ${formatSize(archiveSizeMB)}`);
    console.log("");
  } else {
    output({ status: "archived", path: dest, sizeMB: archiveSizeMB, recordingCount }, { pretty: false, json: true });
  }

  if (opts.open) {
    Bun.spawnSync(["open", "-R", dest]);
  }
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

export function registerDataCommand(program: Command): void {
  const data = program
    .command("data")
    .description("Show where Talkie stores your data and how much space it uses")
    .action((_opts, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      dataInfoAction(fmt.pretty);
    });

  data
    .command("path")
    .description("Print the data folder path")
    .option("--open", "open the folder in Finder")
    .action((opts, cmd) => {
      const fmt = getFormatOptions(cmd.parent!.parent!.optsWithGlobals());
      dataPathAction(opts, fmt.pretty);
    });

  data
    .command("archive")
    .description("Back up all Talkie data to a zip file")
    .option("-o, --output <path>", "output path (default: ~/Desktop/talkie-data-<timestamp>.zip)")
    .option("--open", "reveal the archive in Finder after creating")
    .action(async (opts, cmd) => {
      const fmt = getFormatOptions(cmd.parent!.parent!.optsWithGlobals());
      try {
        await dataArchiveAction(opts, fmt.pretty);
      } catch (err: any) {
        if (fmt.pretty) {
          console.error(`  \x1b[31m✗ ${err.message}\x1b[0m`);
        } else {
          output({ error: err.message }, { pretty: false, json: true });
        }
        process.exit(1);
      }
    });

  data
    .command("clean")
    .description("Remove all Talkie data and start fresh")
    .option("-y, --yes", "skip confirmation")
    .option("--keep-keys", "preserve API keys")
    .action(async (opts, cmd) => {
      const fmt = getFormatOptions(cmd.parent!.parent!.optsWithGlobals());
      try {
        await dataCleanAction(opts, fmt.pretty);
      } catch (err: any) {
        if (fmt.pretty) {
          console.error(`  \x1b[31m✗ ${err.message}\x1b[0m`);
        } else {
          output({ error: err.message }, { pretty: false, json: true });
        }
        process.exit(1);
      }
    });
}

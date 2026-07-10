import type { Command } from "../../gunshi-command";
import { existsSync, rmSync, readdirSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import { getFormatOptions, output } from "../../format";
import { SERVICES, getUid } from "./services";

const HOME = homedir();

// All Talkie data locations, organized by category
const DATA_LOCATIONS = {
  database: {
    label: "Database",
    paths: [
      { path: join(HOME, "Library/Application Support/Talkie"), desc: "Production database & audio" },
      { path: join(HOME, "Library/Application Support/Talkie.dev"), desc: "Dev database & audio" },
      { path: join(HOME, "Library/Application Support/Talkie.staging"), desc: "Staging database & audio" },
    ],
  },
  preferences: {
    label: "Preferences & Settings",
    paths: [
      { path: join(HOME, "Library/Preferences/to.talkie.app.mac.plist"), desc: "Talkie preferences" },
      { path: join(HOME, "Library/Preferences/to.talkie.app.mac.dev.plist"), desc: "Talkie dev preferences" },
      { path: join(HOME, "Library/Preferences/to.talkie.app.mac.staging.plist"), desc: "Talkie staging preferences" },
      { path: join(HOME, "Library/Preferences/to.talkie.agent.plist"), desc: "Agent preferences" },
      { path: join(HOME, "Library/Preferences/to.talkie.agent.dev.plist"), desc: "Agent dev preferences" },
    ],
  },
  sharedDefaults: {
    label: "Shared Settings (UserDefaults suite)",
    paths: [
      { path: join(HOME, "Library/Preferences/to.talkie.app.shared.plist"), desc: "Shared settings (prod)" },
      { path: join(HOME, "Library/Preferences/to.talkie.app.shared.dev.plist"), desc: "Shared settings (dev)" },
      { path: join(HOME, "Library/Preferences/to.talkie.app.shared.staging.plist"), desc: "Shared settings (staging)" },
    ],
  },
  launchAgents: {
    label: "Launch Agents",
    paths: [
      { path: join(HOME, "Library/LaunchAgents/to.talkie.agent.plist"), desc: "Agent launch agent" },
      { path: join(HOME, "Library/LaunchAgents/to.talkie.app.sync.plist"), desc: "Sync launch agent" },
      { path: join(HOME, "Library/LaunchAgents/to.talkie.agent.dev.plist"), desc: "Agent dev launch agent" },
      { path: join(HOME, "Library/LaunchAgents/to.talkie.app.sync.dev.plist"), desc: "Sync dev launch agent" },
    ],
  },
  caches: {
    label: "Caches",
    paths: [
      { path: join(HOME, "Library/Caches/to.talkie.app.mac"), desc: "Talkie cache" },
      { path: join(HOME, "Library/Caches/to.talkie.app.mac.dev"), desc: "Talkie dev cache" },
      { path: join(HOME, "Library/Caches/to.talkie.agent"), desc: "Agent cache" },
      { path: join(HOME, "Library/Caches/to.talkie.agent.dev"), desc: "Agent dev cache" },
    ],
  },
};

type CategoryKey = keyof typeof DATA_LOCATIONS;

function stopAllServices(): string[] {
  const stopped: string[] = [];
  const uid = getUid();

  // Kill all Talkie processes
  for (const bundleId of [
    "to.talkie.app.mac", "to.talkie.app.mac.dev",
    "to.talkie.agent", "to.talkie.agent.dev",
    "to.talkie.app.sync", "to.talkie.app.sync.dev",
  ]) {
    const result = Bun.spawnSync(["pkill", "-f", bundleId]);
    if (result.exitCode === 0) stopped.push(bundleId);
  }

  // Bootout all launchd registrations
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  const lines = listResult.stdout.toString().split("\n");
  for (const line of lines) {
    if (!line.toLowerCase().includes("talkie")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");
    Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
  }

  return stopped;
}

function deletePath(path: string): { deleted: boolean; sizeMB?: number; error?: string } {
  if (!existsSync(path)) return { deleted: false };

  try {
    // Get size before deleting
    const du = Bun.spawnSync(["du", "-sm", path], { stdout: "pipe", stderr: "pipe" });
    const sizeMB = du.exitCode === 0 ? parseInt(du.stdout.toString().split("\t")[0], 10) : undefined;

    rmSync(path, { recursive: true, force: true });
    return { deleted: true, sizeMB };
  } catch (e) {
    return { deleted: false, error: e instanceof Error ? e.message : String(e) };
  }
}

function resetUserDefaults(domains: string[]): number {
  let count = 0;
  for (const domain of domains) {
    const result = Bun.spawnSync(["defaults", "delete", domain]);
    if (result.exitCode === 0) count++;
  }
  return count;
}

export function registerWipeCommand(devCmd: Command): void {
  devCmd
    .command("wipe")
    .description(
      "Wipe all Talkie user data and reset to fresh state.\n\n" +
      "Stops all services, removes databases, audio, preferences, caches,\n" +
      "and launch agents. After wiping, launch Talkie to re-run onboarding.\n\n" +
      "Options:\n" +
      "  --dry-run       Preview what would be deleted\n" +
      "  --keep-keys     Keep API keys (.apikeys file)\n" +
      "  --prod-only     Only wipe production data (keep dev/staging)\n" +
      "  --data-only     Only wipe database and audio (keep preferences)\n\n" +
      "Example: talkie-dev wipe --dry-run    (preview)\n" +
      "         talkie-dev wipe              (full wipe)\n" +
      "         talkie-dev wipe --data-only  (just database + audio)"
    )
    .option("--dry-run", "preview what would be deleted without deleting")
    .option("--keep-keys", "preserve API keys")
    .option("--prod-only", "only wipe production environment data")
    .option("--data-only", "only wipe database and audio files")
    .option("-y, --yes", "skip confirmation prompt")
    .action(async (opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const dryRun = opts.dryRun ?? false;
      const keepKeys = opts.keepKeys ?? false;
      const prodOnly = opts.prodOnly ?? false;
      const dataOnly = opts.dataOnly ?? false;
      const skipConfirm = opts.yes ?? false;

      // Determine which categories to wipe
      const categories: CategoryKey[] = dataOnly
        ? ["database"]
        : ["database", "preferences", "sharedDefaults", "launchAgents", "caches"];

      // Filter paths based on --prod-only
      const filterPath = (p: { path: string; desc: string }) => {
        if (!prodOnly) return true;
        // Keep only paths without .dev or .staging
        return !p.path.includes(".dev") && !p.path.includes(".staging") &&
               !p.path.includes("dev.plist") && !p.path.includes("staging.plist");
      };

      // Collect what exists
      const toDelete: { path: string; desc: string; category: string; sizeMB?: number }[] = [];

      for (const catKey of categories) {
        const cat = DATA_LOCATIONS[catKey];
        for (const entry of cat.paths.filter(filterPath)) {
          if (existsSync(entry.path)) {
            const du = Bun.spawnSync(["du", "-sm", entry.path], { stdout: "pipe", stderr: "pipe" });
            const sizeMB = du.exitCode === 0 ? parseInt(du.stdout.toString().split("\t")[0], 10) : undefined;
            toDelete.push({ ...entry, category: cat.label, sizeMB });
          }
        }
      }

      // Check API keys separately
      const apiKeysPath = join(HOME, "Library/Application Support/Talkie/.apikeys");
      const hasApiKeys = existsSync(apiKeysPath);

      if (fmt.pretty) {
        if (toDelete.length === 0) {
          console.log("\x1b[32mNothing to wipe — Talkie data not found.\x1b[0m");
          return;
        }

        console.log(`\n\x1b[1m${dryRun ? "Would wipe" : "Will wipe"}:\x1b[0m\n`);

        let currentCategory = "";
        let totalSizeMB = 0;
        for (const item of toDelete) {
          if (item.category !== currentCategory) {
            currentCategory = item.category;
            console.log(`  \x1b[90m${currentCategory}\x1b[0m`);
          }
          const size = item.sizeMB ? `\x1b[33m${item.sizeMB}MB\x1b[0m` : "";
          console.log(`    \x1b[31m✗\x1b[0m ${item.desc.padEnd(35)} ${size}`);
          totalSizeMB += item.sizeMB ?? 0;
        }

        if (keepKeys && hasApiKeys) {
          console.log(`\n  \x1b[32m✓\x1b[0m API keys will be preserved`);
        } else if (hasApiKeys && !dataOnly) {
          console.log(`\n  \x1b[31m✗\x1b[0m API keys will be deleted (use --keep-keys to preserve)`);
        }

        console.log(`\n  Total: ~${totalSizeMB}MB across ${toDelete.length} locations\n`);
      }

      if (dryRun) {
        if (!fmt.pretty) {
          output({ wouldDelete: toDelete, keepApiKeys: keepKeys, totalItems: toDelete.length }, fmt);
        }
        return;
      }

      // Confirmation
      if (!skipConfirm) {
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
      }

      console.log("");

      // Step 1: Stop all services
      if (fmt.pretty) process.stdout.write("  Stopping services... ");
      const stopped = stopAllServices();
      if (fmt.pretty) console.log(`\x1b[32mdone\x1b[0m (${stopped.length} stopped)`);

      // Brief pause for processes to exit
      await Bun.sleep(500);

      // Step 2: Delete everything
      let deletedCount = 0;
      let freedMB = 0;

      for (const item of toDelete) {
        const result = deletePath(item.path);
        if (result.deleted) {
          deletedCount++;
          freedMB += result.sizeMB ?? 0;
          if (fmt.pretty) console.log(`  \x1b[32m✓\x1b[0m Deleted ${item.desc}`);
        } else if (result.error) {
          if (fmt.pretty) console.log(`  \x1b[31m✗\x1b[0m Failed: ${item.desc} (${result.error})`);
        }
      }

      // Step 3: Reset UserDefaults via `defaults delete`
      if (!dataOnly) {
        const defaultsDomains = [
          "to.talkie.app.mac", "to.talkie.app.mac.dev", "to.talkie.app.mac.staging",
          "to.talkie.agent", "to.talkie.agent.dev",
          "to.talkie.app.shared", "to.talkie.app.shared.dev", "to.talkie.app.shared.staging",
        ].filter(d => !prodOnly || (!d.includes(".dev") && !d.includes(".staging")));

        const defaultsCleared = resetUserDefaults(defaultsDomains);
        if (fmt.pretty && defaultsCleared > 0) {
          console.log(`  \x1b[32m✓\x1b[0m Cleared ${defaultsCleared} UserDefaults domains`);
        }
      }

      // Step 4: Handle API keys
      if (!keepKeys && !dataOnly && hasApiKeys) {
        const result = deletePath(apiKeysPath);
        if (result.deleted && fmt.pretty) {
          console.log(`  \x1b[32m✓\x1b[0m Deleted API keys`);
        }
      }

      // Summary
      if (fmt.pretty) {
        console.log(`\n\x1b[32m  Wiped ${deletedCount} locations (~${freedMB}MB freed)\x1b[0m`);
        console.log("  Launch Talkie to re-run onboarding.\n");
      } else {
        output({ deleted: deletedCount, freedMB, stopped: stopped.length }, fmt);
      }
    });
}

import type { Command } from "commander";
import { readdirSync, statSync, rmSync, existsSync } from "fs";
import { join } from "path";
import { getFormatOptions, output } from "../../format";
import { getUid, getDerivedDataRoot, SERVICES, type TalkieService } from "./services";

interface StaleEntry {
  label: string;
  status: number;
  reason: string;
}

function findStaleRegistrations(): StaleEntry[] {
  const result = Bun.spawnSync(["launchctl", "list"]);
  const stdout = result.stdout.toString();
  const stale: StaleEntry[] = [];

  // Track entries per service bundle ID to detect duplicates
  const entriesByBundleId = new Map<string, { pid: number | null; status: number; label: string }[]>();

  for (const line of stdout.split("\n")) {
    if (!line.toLowerCase().includes("talkie")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;

    const [pidStr, statusStr, ...labelParts] = parts;
    const pid = pidStr === "-" ? null : parseInt(pidStr, 10);
    const status = parseInt(statusStr, 10);
    const label = labelParts.join(" ");

    // Crashed or exited entries are always stale
    if (pid === null && status === 78) {
      stale.push({ label, status, reason: "not running (status 78)" });
    } else if (status < 0) {
      stale.push({ label, status, reason: `crashed (signal ${-status})` });
    } else if (pid === null && status !== 0) {
      stale.push({ label, status, reason: `exited (status ${status})` });
    }

    // Track running entries by service for duplicate detection
    for (const service of SERVICES) {
      if (label.includes(service.devBundleId)) {
        const entries = entriesByBundleId.get(service.devBundleId) ?? [];
        entries.push({ pid, status, label });
        entriesByBundleId.set(service.devBundleId, entries);
      }
    }
  }

  // Detect duplicates: if a service has multiple running entries, older ones are stale
  for (const [bundleId, entries] of entriesByBundleId) {
    const running = entries.filter((e) => e.pid !== null && e.status === 0);
    if (running.length <= 1) continue;

    // Keep the newest (highest pid), mark others as stale — unless Xcode-attached
    running.sort((a, b) => (b.pid ?? 0) - (a.pid ?? 0));
    for (const entry of running.slice(1)) {
      // Skip Xcode-attached processes (parent is debugserver)
      if (entry.pid) {
        const ppid = Bun.spawnSync(["ps", "-o", "ppid=", "-p", String(entry.pid)]);
        if (ppid.exitCode === 0) {
          const parentPid = ppid.stdout.toString().trim();
          const parentCmd = Bun.spawnSync(["ps", "-o", "comm=", "-p", parentPid]);
          if (parentCmd.exitCode === 0 && parentCmd.stdout.toString().includes("debugserver")) {
            continue; // Don't mark Xcode debug sessions as stale
          }
        }
      }

      // Only add if not already in stale list
      if (!stale.some((s) => s.label === entry.label)) {
        stale.push({
          label: entry.label,
          status: entry.status,
          reason: `duplicate (newer instance running)`,
        });
      }
    }
  }

  return stale;
}

interface StaleDerivedData {
  path: string;
  service: string;
  binaryMtime: Date;
}

/**
 * Find old DerivedData build directories. For each service, keep only the
 * newest build (by binary mtime) and mark the rest as stale.
 */
export function findStaleDerivedData(): { stale: StaleDerivedData[]; kept: StaleDerivedData[] } {
  const root = getDerivedDataRoot();
  if (!existsSync(root)) return { stale: [], kept: [] };

  const stale: StaleDerivedData[] = [];
  const kept: StaleDerivedData[] = [];

  // Collect all prefixes across all services
  const prefixToService = new Map<string, TalkieService>();
  for (const service of SERVICES) {
    const prefixes = Array.isArray(service.derivedDataPrefix)
      ? service.derivedDataPrefix
      : [service.derivedDataPrefix];
    for (const p of prefixes) {
      prefixToService.set(p, service);
    }
  }

  // Group DerivedData dirs by service
  const byService = new Map<string, { dir: string; appPath: string; binaryMtime: Date }[]>();

  let allDirs: string[];
  try {
    allDirs = readdirSync(root);
  } catch {
    return { stale: [], kept: [] };
  }

  for (const dir of allDirs) {
    for (const [prefix, service] of prefixToService) {
      if (!dir.startsWith(prefix)) continue;

      const appPath = join(root, dir, "Build", "Products", "Debug", service.appName);
      if (!existsSync(appPath)) continue;

      // Check binary mtime for accurate comparison
      const execName = service.appName.replace(".app", "");
      const binaryPath = join(appPath, "Contents", "MacOS", execName);
      const target = existsSync(binaryPath) ? binaryPath : appPath;

      try {
        const stat = statSync(target);
        const entries = byService.get(service.name) ?? [];
        entries.push({ dir, appPath, binaryMtime: stat.mtime });
        byService.set(service.name, entries);
      } catch {
        // Skip if we can't stat
      }
      break; // Don't match same dir against multiple prefixes for same service
    }
  }

  // For each service, keep the newest, mark the rest as stale
  for (const [serviceName, entries] of byService) {
    if (entries.length <= 1) {
      if (entries.length === 1) {
        kept.push({ path: join(root, entries[0].dir), service: serviceName, binaryMtime: entries[0].binaryMtime });
      }
      continue;
    }

    entries.sort((a, b) => b.binaryMtime.getTime() - a.binaryMtime.getTime());

    // Keep the newest
    kept.push({ path: join(root, entries[0].dir), service: serviceName, binaryMtime: entries[0].binaryMtime });

    // Mark the rest as stale
    for (const entry of entries.slice(1)) {
      stale.push({ path: join(root, entry.dir), service: serviceName, binaryMtime: entry.binaryMtime });
    }
  }

  return { stale, kept };
}

export function registerCleanCommand(devCmd: Command): void {
  devCmd
    .command("clean")
    .description("Remove stale launch registrations and old DerivedData builds")
    .option("--dry-run", "show what would be cleaned without deleting")
    .action((opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const dryRun = opts.dryRun ?? false;

      // --- Phase 1: Stale launchd registrations ---
      const stale = findStaleRegistrations();

      if (fmt.pretty && stale.length > 0) {
        console.log("Stale launchd registrations:");
      }

      const uid = getUid();
      const launchdResults: { label: string; success: boolean; error?: string }[] = [];

      for (const entry of stale) {
        if (dryRun) {
          if (fmt.pretty) console.log(`  \x1b[33m~\x1b[0m ${entry.label} (${entry.reason})`);
          launchdResults.push({ label: entry.label, success: true });
          continue;
        }

        if (fmt.pretty) process.stdout.write(`  Bootout ${entry.label} ... `);

        const bootout = Bun.spawnSync([
          "launchctl",
          "bootout",
          `gui/${uid}/${entry.label}`,
        ]);

        const success = bootout.exitCode === 0;
        const error = success ? undefined : bootout.stderr.toString().trim();
        launchdResults.push({ label: entry.label, success, error });

        if (fmt.pretty) {
          console.log(success ? "\x1b[32mdone\x1b[0m" : `\x1b[31mfailed\x1b[0m${error ? ` (${error})` : ""}`);
        }
      }

      // --- Phase 2: Old DerivedData builds ---
      const { stale: staleDirs, kept: keptDirs } = findStaleDerivedData();

      if (fmt.pretty && staleDirs.length > 0) {
        if (stale.length > 0) console.log("");
        console.log("Old DerivedData builds:");
      }

      const ddResults: { path: string; service: string; success: boolean; sizeMB?: number; error?: string }[] = [];

      for (const entry of staleDirs) {
        // Estimate size
        const du = Bun.spawnSync(["du", "-sm", entry.path], { stdout: "pipe", stderr: "pipe" });
        const sizeMB = du.exitCode === 0 ? parseInt(du.stdout.toString().split("\t")[0], 10) : undefined;
        const dirName = entry.path.split("/").pop() ?? entry.path;

        if (dryRun) {
          if (fmt.pretty) {
            console.log(`  \x1b[33m~\x1b[0m ${entry.service.padEnd(16)} ${dirName} ${sizeMB ? `(${sizeMB}MB)` : ""}`);
          }
          ddResults.push({ path: entry.path, service: entry.service, success: true, sizeMB });
          continue;
        }

        if (fmt.pretty) {
          process.stdout.write(`  \x1b[31m✗\x1b[0m ${entry.service.padEnd(16)} ${dirName} ${sizeMB ? `(${sizeMB}MB)` : ""}... `);
        }

        try {
          rmSync(entry.path, { recursive: true, force: true });
          ddResults.push({ path: entry.path, service: entry.service, success: true, sizeMB });
          if (fmt.pretty) console.log("\x1b[32mdeleted\x1b[0m");
        } catch (e) {
          const error = e instanceof Error ? e.message : String(e);
          ddResults.push({ path: entry.path, service: entry.service, success: false, error });
          if (fmt.pretty) console.log(`\x1b[31mfailed\x1b[0m (${error})`);
        }
      }

      // Show kept builds for context
      if (fmt.pretty && keptDirs.length > 0 && staleDirs.length > 0) {
        console.log("\nKept (latest per service):");
        for (const entry of keptDirs) {
          const dirName = entry.path.split("/").pop() ?? entry.path;
          const age = Math.round((Date.now() - entry.binaryMtime.getTime()) / 86400000);
          console.log(`  \x1b[32m●\x1b[0m ${entry.service.padEnd(16)} ${dirName} \x1b[90m(${age}d ago)\x1b[0m`);
        }
      }

      // --- Summary ---
      const launchdCleaned = launchdResults.filter((r) => r.success).length;
      const ddCleaned = ddResults.filter((r) => r.success).length;
      const totalSizeMB = ddResults.reduce((sum, r) => sum + (r.sizeMB ?? 0), 0);

      if (fmt.pretty) {
        if (stale.length === 0 && staleDirs.length === 0) {
          console.log("\x1b[32mNothing to clean.\x1b[0m");
        } else {
          const parts: string[] = [];
          if (launchdCleaned > 0) parts.push(`${launchdCleaned} stale registration${launchdCleaned !== 1 ? "s" : ""}`);
          if (ddCleaned > 0) parts.push(`${ddCleaned} old build${ddCleaned !== 1 ? "s" : ""} (${totalSizeMB}MB)`);
          const verb = dryRun ? "would clean" : "cleaned";
          console.log(`\n${parts.join(", ")} ${verb}`);
        }
      } else {
        output({
          launchd: { cleaned: launchdResults, count: launchdCleaned },
          derivedData: { cleaned: ddResults, count: ddCleaned, freedMB: totalSizeMB },
          dryRun,
        }, fmt);
      }
    });
}

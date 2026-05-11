import type { Command } from "commander";
import { getFormatOptions, output } from "../format";
import { callBridge, callBridgeStreaming, ensureServiceRunning } from "../bridge";
import { BRIDGE_PORTS } from "../ports";

/** Run a bridge call with auto-start. */
async function syncCall(
  method: string,
  params?: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const { ok, error } = ensureServiceRunning("sync");
  if (!ok) throw new Error(error);
  return callBridge(BRIDGE_PORTS.sync, method, params);
}

/** Parse a sync date from the bridge — handles ISO 8601 strings and legacy CF absolute timestamps. */
function parseSyncDate(value: unknown): Date | null {
  if (!value) return null;
  if (typeof value === "string") {
    const d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof value === "number") {
    // Core Foundation absolute time: seconds since 2001-01-01
    const CF_EPOCH_OFFSET = 978307200; // seconds between 1970-01-01 and 2001-01-01
    return new Date((value + CF_EPOCH_OFFSET) * 1000);
  }
  return null;
}

export function registerSyncCommand(program: Command): void {
  const syncCmd = program
    .command("sync")
    .description("TalkieSync — iCloud sync management");

  // Default action (no subcommand) — show status
  syncCmd.action(async (_, cmd) => {
    const globalOpts = cmd.optsWithGlobals();
    const fmt = getFormatOptions(globalOpts);

    try {
      const status = await syncCall("status");

      if (fmt.pretty) {
        const s = status as Record<string, unknown>;
        const icon = s.status === "syncing" ? "⟳" : s.status === "idle" ? "●" : "✗";
        const color = s.status === "idle" ? "\x1b[32m" : s.status === "syncing" ? "\x1b[33m" : "\x1b[31m";
        console.log(`${color}${icon}\x1b[0m Sync: ${s.status}`);
        const lastSync = parseSyncDate(s.lastSyncDate);
        if (lastSync) {
          console.log(`  Last sync: ${lastSync.toLocaleString()}`);
        }
        console.log(`  iCloud: ${s.iCloudAvailable ? "available" : "unavailable"}`);
        console.log(`  Provider: ${s.activeProvider ?? "none"}`);
        if (s.errorMessage) {
          console.log(`  \x1b[31mError: ${s.errorMessage}\x1b[0m`);
        }
      } else {
        output(status, fmt);
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      if (fmt.pretty && (msg.includes("Cannot connect") || msg.includes("WebSocket") || msg.includes("not running"))) {
        console.log(`\x1b[33m●\x1b[0m Sync: offline`);
        console.log(`  TalkieSync is not running. Run \`talkie sync now\` to start it and sync.`);
      } else {
        console.error(`Error: ${msg}`);
      }
      process.exit(1);
    }
  });

  // talkie sync now
  syncCmd
    .command("now")
    .description("Trigger an immediate sync (incremental by default, syncs since last sync)")
    .option("--limit <n>", "Fetch at most N records", parseInt)
    .option("--since <date>", "Only records created after this date (ISO 8601 or yyyy-MM-dd)")
    .option("--full", "Full reconciliation of all memos (slow — use sparingly)")
    .action(async (opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);

      try {
        const { ok, error, started } = ensureServiceRunning("sync");
        if (!ok) {
          if (fmt.pretty) {
            console.log(`\x1b[31m✗\x1b[0m TalkieSync is not running`);
            console.log(`  ${error}`);
            console.log(`\n  To start it manually:`);
            console.log(`    talkie-dev start sync`);
          }
          throw new Error(error);
        }
        if (started && fmt.pretty) {
          console.log(`\x1b[32m✓\x1b[0m Started TalkieSync`);
        }

        const params: Record<string, unknown> = {};
        if (opts.limit) params.limit = opts.limit;
        if (opts.since) params.since = opts.since;
        if (opts.full) {
          params.full = true;
        } else if (!opts.limit && !opts.since) {
          // Default: incremental sync from last sync date, with a 1-day safety margin.
          // Falls back to last 7 days if no prior sync, or full if no date is usable.
          try {
            const status = await callBridge(BRIDGE_PORTS.sync, "status");
            const lastSync = parseSyncDate((status as Record<string, unknown>).lastSyncDate);
            if (lastSync) {
              // Back up 1 day for safety margin (propagation delays, timezone edge cases)
              const since = new Date(lastSync.getTime() - 24 * 60 * 60 * 1000);
              params.since = since.toISOString().split("T")[0];
            } else {
              // No prior sync — default to last 7 days instead of full
              const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
              params.since = weekAgo.toISOString().split("T")[0];
            }
          } catch {
            // Can't reach status — fall back to last 7 days
            const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
            params.since = weekAgo.toISOString().split("T")[0];
          }
        }

        const constraints: string[] = [];
        if (opts.full) constraints.push("full");
        if (params.limit) constraints.push(`limit=${params.limit}`);
        if (params.since) constraints.push(`since=${params.since}`);
        const suffix = constraints.length > 0 ? ` (${constraints.join(", ")})` : "";
        const bridgeParams = Object.keys(params).length > 0 ? params : undefined;

        let result: Record<string, unknown>;

        if (fmt.pretty) {
          process.stdout.write(`Syncing${suffix}...`);
          result = await callBridgeStreaming(
            BRIDGE_PORTS.sync,
            "syncNow",
            bridgeParams,
            (_event, data) => {
              const pct = Math.round((data.progress as number) * 100);
              const msg = data.message as string;
              // Clear line and overwrite with progress
              process.stdout.write(`\r\x1b[KSyncing${suffix}...  \x1b[2m[${pct}%]\x1b[0m ${msg}`);
            },
            120000
          );
          // Clear the progress line before printing final output
          process.stdout.write(`\r\x1b[K`);
        } else {
          result = await callBridge(
            BRIDGE_PORTS.sync,
            "syncNow",
            bridgeParams,
            120000
          );
        }

        if (fmt.pretty) {
          const r = result as Record<string, unknown>;
          const success = r.success as boolean;
          if (!success) {
            console.log(`\x1b[31m✗\x1b[0m Sync failed`);
          } else {
            const ins = r.inserted as number;
            const upd = r.updated as number;
            const del = r.deleted as number;
            const skip = r.skipped as number;
            const remote = r.remoteCount as number;
            const local = r.localCount as number;
            const fetchMs = r.fetchTimeMs as number;
            const totalMs = r.totalTimeMs as number;
            console.log(`\x1b[32m✓\x1b[0m Synced${suffix}`);
            console.log(`  +${ins} new, ~${upd} updated, -${del} deleted, =${skip} unchanged`);
            console.log(`  Remote: ${remote}, Local: ${local} [fetch ${fetchMs}ms, total ${totalMs}ms]`);
          }
        } else {
          output(result, fmt);
        }
      } catch (e: unknown) {
        if (fmt.pretty) {
          process.stdout.write(`\r\x1b[K`);
          const msg = e instanceof Error ? e.message : String(e);
          if (msg.includes("Cannot connect") || msg.includes("WebSocket")) {
            console.log(`\x1b[31m✗\x1b[0m Could not reach TalkieSync`);
            console.log(`  The sync service may not be running or is still starting up.\n`);
            console.log(`  Try:`);
            console.log(`    1. Wait a few seconds and retry: talkie sync now`);
            console.log(`    2. Check status: talkie-dev status | grep Sync`);
            console.log(`    3. Restart: talkie-dev stop sync && talkie-dev start sync`);
          } else {
            console.error(`\x1b[31m✗\x1b[0m ${msg}`);
          }
        } else {
          console.error(`Error: ${e instanceof Error ? e.message : e}`);
        }
        process.exit(1);
      }
    });

  // talkie sync status
  syncCmd
    .command("status")
    .description("Detailed sync status")
    .action(async (_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);

      try {
        const status = await syncCall("status");
        const memoCount = await syncCall("remoteMemoCount");

        if (fmt.pretty) {
          const s = status as Record<string, unknown>;
          console.log("# TalkieSync Status\n");
          console.log(`Status:         ${s.status}`);
          console.log(`Provider:       ${s.activeProvider ?? "none"}`);
          console.log(`iCloud:         ${s.iCloudAvailable ? "available" : "unavailable"}`);
          console.log(`Remote memos:   ${(memoCount as Record<string, unknown>).count}`);
          const lastSync = parseSyncDate(s.lastSyncDate);
          if (lastSync) {
            console.log(`Last sync:      ${lastSync.toLocaleString()}`);
          }
          if (s.pendingChanges) {
            console.log(`Pending:        ${s.pendingChanges}`);
          }
          if (s.errorMessage) {
            console.log(`Error:          ${s.errorMessage}`);
          }
        } else {
          output({ ...status, remoteMemoCount: (memoCount as Record<string, unknown>).count }, fmt);
        }
      } catch (e: unknown) {
        console.error(`Error: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
    });

  // talkie sync ping
  syncCmd
    .command("ping")
    .description("Check if TalkieSync is reachable")
    .action(async (_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);

      try {
        const result = await syncCall("ping");

        if (fmt.pretty) {
          console.log(`\x1b[32m✓\x1b[0m TalkieSync is running (pong: ${result.pong})`);
        } else {
          output(result, fmt);
        }
      } catch (e: unknown) {
        if (fmt.pretty) {
          console.log(`\x1b[31m✗\x1b[0m TalkieSync unreachable: ${e instanceof Error ? e.message : e}`);
        } else {
          output({ reachable: false, error: e instanceof Error ? e.message : String(e) }, fmt);
        }
        process.exit(1);
      }
    });

  // talkie sync providers
  syncCmd
    .command("providers")
    .description("List sync providers")
    .action(async (_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);

      try {
        const result = await syncCall("providers");
        const providers = (result.providers ?? []) as Record<string, unknown>[];

        if (fmt.pretty) {
          if (providers.length === 0) {
            console.log("No providers configured.");
            return;
          }
          for (const p of providers) {
            const icon = p.isConnected ? "\x1b[32m●\x1b[0m" : "\x1b[31m●\x1b[0m";
            console.log(`${icon} ${p.displayName} (${p.id})`);
            console.log(`    Enabled: ${p.isEnabled}, Connected: ${p.isConnected}`);
            const providerLastSync = parseSyncDate(p.lastSyncDate);
            if (providerLastSync) {
              console.log(`    Last sync: ${providerLastSync.toLocaleString()}`);
            }
            if (p.errorMessage) {
              console.log(`    \x1b[31mError: ${p.errorMessage}\x1b[0m`);
            }
          }
        } else {
          output(providers, fmt);
        }
      } catch (e: unknown) {
        console.error(`Error: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
    });

  // talkie sync run-pass
  syncCmd
    .command("run-pass")
    .description("Force a sync pass")
    .action(async (_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);

      try {
        const { ok, error: startErr } = ensureServiceRunning("sync");
        if (!ok) throw new Error(startErr);
        if (fmt.pretty) process.stdout.write("Running sync pass...");
        const result = await callBridge(BRIDGE_PORTS.sync, "runSyncPass", undefined, 120000);

        if (fmt.pretty) {
          console.log(` \x1b[32m✓\x1b[0m ${result.syncedCount} record(s) synced`);
        } else {
          output(result, fmt);
        }
      } catch (e: unknown) {
        if (fmt.pretty) console.log("");
        console.error(`Error: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
    });
}

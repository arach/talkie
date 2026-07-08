import type { Command } from "commander";
import { getFormatOptions, output } from "../../format";
import { SERVICES, resolveService, getUid, type TalkieService } from "./services";

interface StopResult {
  name: string;
  success: boolean;
  method: string;
  error?: string;
}

function stopDevService(service: TalkieService): StopResult {
  const uid = getUid();

  // Try launchd bootout first if this service has a launchd label
  if (service.launchdLabel) {
    const check = Bun.spawnSync(["launchctl", "list", service.launchdLabel]);
    if (check.exitCode === 0) {
      const bootout = Bun.spawnSync([
        "launchctl",
        "bootout",
        `gui/${uid}/${service.launchdLabel}`,
      ]);
      if (bootout.exitCode === 0) {
        return { name: service.name, success: true, method: "launchctl bootout (dev)" };
      }
    }
  }

  // Try killing by dev bundle ID (app-launched processes)
  // Use pkill -f matching DerivedData path to avoid killing production builds
  const pgrep = Bun.spawnSync(["pgrep", "-f", `DerivedData.*${service.appName}/Contents/MacOS`]);
  if (pgrep.exitCode === 0) {
    const pids = pgrep.stdout.toString().trim().split("\n").filter(Boolean);
    let killed = false;
    for (const pid of pids) {
      const kill = Bun.spawnSync(["kill", pid]);
      if (kill.exitCode === 0) killed = true;
    }
    if (killed) {
      return { name: service.name, success: true, method: "kill (DerivedData)" };
    }
  }

  // Also try matching by dev bundle ID via launchctl list
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  const lines = listResult.stdout.toString().split("\n");
  for (const line of lines) {
    if (!line.includes(service.devBundleId)) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");
    const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
    if (bootout.exitCode === 0) {
      return { name: service.name, success: true, method: "launchctl bootout (app)" };
    }
  }

  return { name: service.name, success: false, method: "none", error: "Not running (dev)" };
}

function stopProdService(service: TalkieService): StopResult {
  if (!service.prodBundleId) {
    return { name: service.name, success: false, method: "none", error: "No prod bundle ID" };
  }

  const uid = getUid();

  // Derive the prod launchd label from the prod bundle ID
  // Production agents/engines register as e.g. "to.talkie.agent", "to.talkie.app.engine"
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  const lines = listResult.stdout.toString().split("\n");

  for (const line of lines) {
    if (!line.includes(service.prodBundleId)) continue;
    // Skip dev entries
    if (line.includes(".dev")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");
    const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
    if (bootout.exitCode === 0) {
      return { name: service.name, success: true, method: "launchctl bootout (prod)" };
    }
  }

  // Try killing by /Applications/ path
  const pgrep = Bun.spawnSync(["pgrep", "-f", `/Applications/.*${service.appName}/Contents/MacOS`]);
  if (pgrep.exitCode === 0) {
    const pids = pgrep.stdout.toString().trim().split("\n").filter(Boolean);
    let killed = false;
    for (const pid of pids) {
      const kill = Bun.spawnSync(["kill", pid]);
      if (kill.exitCode === 0) killed = true;
    }
    if (killed) {
      return { name: service.name, success: true, method: "kill (prod)" };
    }
  }

  return { name: service.name, success: false, method: "none", error: "Not running (prod)" };
}

function printResult(result: StopResult): void {
  const icon = result.success ? "\x1b[32m✓\x1b[0m" : "\x1b[90m·\x1b[0m";
  const detail = result.success
    ? `\x1b[90m(${result.method})\x1b[0m`
    : `\x1b[90m${result.error}\x1b[0m`;
  console.log(`  ${icon} ${result.name.padEnd(20)} ${detail}`);
}

export function registerStopCommand(devCmd: Command): void {
  devCmd
    .command("stop [service]")
    .description(
      "Stop running Talkie services.\n\n" +
      "By default, stops dev (DerivedData) builds only.\n" +
      "Use --prod to stop production (/Applications/) instances instead.\n" +
      "Use --all to stop both dev and prod instances.\n\n" +
      "Example: talkie-dev stop agent          (stop dev agent)\n" +
      "         talkie-dev stop --prod          (stop all prod services)\n" +
      "         talkie-dev stop agent --prod    (stop prod agent only)\n" +
      "         talkie-dev stop --all           (stop everything)"
    )
    .option("--prod", "stop production (/Applications/) instances instead of dev")
    .option("--all", "stop both dev and production instances")
    .action((serviceName: string | undefined, opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const stopProd = opts.prod || opts.all;
      const stopDev = !opts.prod || opts.all;

      const services = serviceName
        ? (() => {
            const s = resolveService(serviceName);
            if (!s) {
              console.error(`Unknown service: ${serviceName}`);
              console.error(`Available: ${SERVICES.map((s) => s.aliases[0]).join(", ")}`);
              process.exit(1);
            }
            return [s];
          })()
        : SERVICES;

      const results: StopResult[] = [];

      if (stopDev) {
        if (fmt.pretty && (stopProd || opts.all)) {
          console.log("\x1b[1mDev:\x1b[0m");
        }
        for (const service of services) {
          const result = stopDevService(service);
          results.push(result);
          if (fmt.pretty) printResult(result);
        }
      }

      if (stopProd) {
        if (fmt.pretty && stopDev) {
          console.log("\x1b[1mProd:\x1b[0m");
        }
        for (const service of services) {
          const result = stopProdService(service);
          results.push(result);
          if (fmt.pretty) printResult(result);
        }
      }

      if (!fmt.pretty) {
        output({ results }, fmt);
      }
    });
}

import type { Command } from "../../gunshi-command";
import { getFormatOptions, output } from "../../format";
import { SERVICES, resolveService, getUid, type TalkieService } from "./services";
import { findLatestBuild, launchViaLaunchd } from "./start";

interface RestartResult {
  name: string;
  stopped: boolean;
  started: boolean;
  path?: string;
  error?: string;
}

function stopServiceQuiet(service: TalkieService): boolean {
  const uid = getUid();
  let stopped = false;

  // Try launchd bootout for known label
  if (service.launchdLabel) {
    const check = Bun.spawnSync(["launchctl", "list", service.launchdLabel]);
    if (check.exitCode === 0) {
      const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${service.launchdLabel}`]);
      if (bootout.exitCode === 0) stopped = true;
    }
  }

  // Bootout ALL matching application.{bundleId}.* entries (catches every instance)
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  for (const line of listResult.stdout.toString().split("\n")) {
    if (!line.includes(service.devBundleId)) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");
    if (label === service.launchdLabel) continue; // Already handled above
    Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
    stopped = true;
  }

  // Kill DerivedData processes (SIGTERM first)
  const pgrep = Bun.spawnSync(["pgrep", "-f", `DerivedData.*${service.appName}/Contents/MacOS`]);
  if (pgrep.exitCode === 0) {
    const pids = pgrep.stdout.toString().trim().split("\n").filter(Boolean);
    for (const pid of pids) {
      Bun.spawnSync(["kill", pid]);
    }
    stopped = true;

    // Wait up to 2s for processes to die, then SIGKILL stragglers
    for (let i = 0; i < 10; i++) {
      Bun.sleepSync(200);
      const check = Bun.spawnSync(["pgrep", "-f", `DerivedData.*${service.appName}/Contents/MacOS`]);
      if (check.exitCode !== 0) break; // All dead
      if (i === 9) {
        // Force kill remaining
        const remaining = check.stdout.toString().trim().split("\n").filter(Boolean);
        for (const pid of remaining) {
          Bun.spawnSync(["kill", "-9", pid]);
        }
      }
    }
  }

  return stopped;
}

function startServiceQuiet(service: TalkieService): { success: boolean; path?: string; error?: string } {
  const build = findLatestBuild(service);
  if (!build) {
    return { success: false, error: "No DerivedData build found" };
  }

  // XPC services need launchctl bootstrap for Mach service ports
  if (service.machServices) {
    const result = launchViaLaunchd(service, build.path);
    return { success: result.success, path: build.path, error: result.error };
  }

  // Regular apps — launch via `open`
  const result = Bun.spawnSync(["open", build.path]);
  if (result.exitCode !== 0) {
    return { success: false, path: build.path, error: "open command failed" };
  }
  return { success: true, path: build.path };
}

function restartAction(serviceName: string | undefined, _: unknown, cmd: Command): void {
  const globalOpts = cmd.optsWithGlobals();
  const fmt = getFormatOptions(globalOpts);

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

  const results: RestartResult[] = [];

  for (const service of services) {
    const stopped = stopServiceQuiet(service);

    // Brief pause for cleanup
    Bun.sleepSync(300);

    const start = startServiceQuiet(service);
    results.push({
      name: service.name,
      stopped,
      started: start.success,
      path: start.path,
      error: start.error,
    });

    if (fmt.pretty) {
      const stopIcon = stopped ? "\x1b[32m↓\x1b[0m" : "\x1b[90m·\x1b[0m";
      const startIcon = start.success ? "\x1b[32m↑\x1b[0m" : "\x1b[31m✗\x1b[0m";
      const detail = start.success
        ? "\x1b[90mrestarted\x1b[0m"
        : `\x1b[31m${start.error}\x1b[0m`;
      console.log(`  ${stopIcon}${startIcon} ${service.name.padEnd(20)} ${detail}`);
    }
  }

  if (!fmt.pretty) {
    output({ results }, fmt);
  }
}

const restartDesc =
  "Stop all instances of a service, then launch the newest DerivedData build.\n\n" +
  "Use when: a service is misbehaving and you want a fresh start without rebuilding.\n" +
  "Thorough: boots out launchd entries, kills DerivedData processes, waits for clean state.\n\n" +
  "Example: talkie-dev relaunch talkie   (relaunch Talkie)\n" +
  "         talkie-dev relaunch           (relaunch all services)";

/** Register `relaunch` command (+ hidden `restart` alias). */
export function registerRestartCommand(devCmd: Command): void {
  devCmd
    .command("relaunch [service]")
    .description(restartDesc)
    .action(restartAction);

  devCmd
    .command("restart [service]", { hidden: true })
    .action(restartAction);
}

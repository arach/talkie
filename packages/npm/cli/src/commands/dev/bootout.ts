import type { Command } from "commander";
import { getFormatOptions, output } from "../../format";
import { SERVICES, resolveService, getUid, type TalkieService } from "./services";

interface BootoutResult {
  name: string;
  pid: number | null;
  success: boolean;
  method: string;
  error?: string;
}

function bootoutProdService(service: TalkieService): BootoutResult {
  if (!service.prodBundleId) {
    return { name: service.name, pid: null, success: false, method: "none", error: "No production bundle ID" };
  }

  const uid = getUid();

  // Find production processes (running from /Applications/, not DerivedData)
  const pgrep = Bun.spawnSync(["pgrep", "-f", `/Applications/Talkie.app.*${service.appName.replace(".app", "")}`]);
  const pids = pgrep.exitCode === 0
    ? pgrep.stdout.toString().trim().split("\n").filter(Boolean).map(Number)
    : [];

  // Try launchctl bootout for any matching production launch agents
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  const lines = listResult.stdout.toString().split("\n");
  let bootedOut = false;

  for (const line of lines) {
    if (!line.includes(service.prodBundleId)) continue;
    // Skip dev bundle IDs
    if (line.includes(".dev")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const label = parts.slice(2).join(" ");

    const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
    if (bootout.exitCode === 0) bootedOut = true;
  }

  if (bootedOut && pids.length === 0) {
    return { name: service.name, pid: null, success: true, method: "launchctl bootout" };
  }

  // Kill any remaining production processes
  let killed = false;
  for (const pid of pids) {
    const kill = Bun.spawnSync(["kill", String(pid)]);
    if (kill.exitCode === 0) killed = true;
  }

  if (killed || bootedOut) {
    return {
      name: service.name,
      pid: pids[0] ?? null,
      success: true,
      method: bootedOut && killed ? "bootout + kill" : bootedOut ? "launchctl bootout" : "kill",
    };
  }

  if (pids.length === 0) {
    return { name: service.name, pid: null, success: false, method: "none", error: "Not running" };
  }

  return { name: service.name, pid: pids[0], success: false, method: "none", error: "Failed to stop" };
}

export function registerBootoutCommand(devCmd: Command): void {
  devCmd
    .command("bootout [service]")
    .description(
      "Stop production Talkie services running from /Applications.\n\n" +
      "Use when: production Talkie is interfering with dev builds, or you need to\n" +
      "fully clear production launch agents before testing.\n" +
      "Only affects /Applications/ installs, never DerivedData dev builds.\n\n" +
      "Example: talkie-dev bootout           (stop all production services)\n" +
      "         talkie-dev bootout agent      (stop just TalkieAgent)"
    )
    .action((serviceName: string | undefined, _, cmd) => {
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
        : SERVICES.filter((s) => s.prodBundleId !== null);

      if (fmt.pretty) {
        console.log("Booting out production Talkie services:");
      }

      const results: BootoutResult[] = [];
      for (const service of services) {
        const result = bootoutProdService(service);
        results.push(result);

        if (fmt.pretty) {
          const icon = result.success
            ? "\x1b[32m✓\x1b[0m"
            : result.error === "Not running"
              ? "\x1b[90m·\x1b[0m"
              : "\x1b[31m✗\x1b[0m";
          const detail = result.success
            ? `\x1b[90m(${result.method}${result.pid ? `, pid ${result.pid}` : ""})\x1b[0m`
            : `\x1b[90m${result.error}\x1b[0m`;
          console.log(`  ${icon} ${service.name.padEnd(20)} ${detail}`);
        }
      }

      const stopped = results.filter((r) => r.success).length;
      if (fmt.pretty && stopped > 0) {
        console.log(`\n${stopped} production service${stopped !== 1 ? "s" : ""} stopped`);
      }

      if (!fmt.pretty) {
        output({ results }, fmt);
      }
    });
}

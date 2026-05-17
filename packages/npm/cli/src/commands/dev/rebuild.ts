import type { Command } from "commander";
import { rmSync } from "fs";
import { getFormatOptions, output } from "../../format";
import { SERVICES, resolveService, getProjectRoot, getUid, type TalkieService } from "./services";
import { findLatestBuild, launchViaLaunchd } from "./start";
import { findStaleDerivedData } from "./clean";

interface RebuildStep {
  phase: "build" | "kill" | "verify" | "launch";
  name: string;
  success: boolean;
  detail?: string;
}

interface RebuildResult {
  name: string;
  success: boolean;
  buildDuration: number;
  steps: RebuildStep[];
}

/**
 * Thoroughly kill every trace of a service — launchd registrations, app processes, duplicates.
 * Returns a list of what was cleaned up.
 */
export function killEverything(service: TalkieService, uid: number): RebuildStep[] {
  const steps: RebuildStep[] = [];

  // 1. Bootout the dev launchd label
  if (service.launchdLabel) {
    const check = Bun.spawnSync(["launchctl", "list", service.launchdLabel]);
    if (check.exitCode === 0) {
      const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${service.launchdLabel}`]);
      steps.push({
        phase: "kill",
        name: service.name,
        success: bootout.exitCode === 0,
        detail: `bootout ${service.launchdLabel}`,
      });
    }
  }

  // 2. Bootout the prod launchd label (e.g. to.talkie.app.engine registered by prod)
  if (service.prodBundleId) {
    const prodLabels = [service.prodBundleId];
    for (const label of prodLabels) {
      const check = Bun.spawnSync(["launchctl", "list", label]);
      if (check.exitCode === 0) {
        const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
        steps.push({
          phase: "kill",
          name: service.name,
          success: bootout.exitCode === 0,
          detail: `bootout ${label} (prod)`,
        });
      }
    }
  }

  // 3. Bootout any application.{bundleId}.* launchctl entries (app-launched)
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  const lines = listResult.stdout.toString().split("\n");
  for (const line of lines) {
    // Match both dev and prod bundle IDs
    const matchIds = [service.devBundleId, service.prodBundleId].filter(Boolean) as string[];
    for (const bundleId of matchIds) {
      if (!line.includes(bundleId)) continue;
      const parts = line.trim().split(/\s+/);
      if (parts.length < 3) continue;
      const label = parts.slice(2).join(" ");
      // Skip if we already handled this label
      if (label === service.launchdLabel) continue;
      const bootout = Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`]);
      steps.push({
        phase: "kill",
        name: service.name,
        success: bootout.exitCode === 0,
        detail: `bootout ${label}`,
      });
    }
  }

  // 4. Kill any remaining processes by DerivedData path
  const pgrepDerived = Bun.spawnSync(["pgrep", "-f", `DerivedData.*${service.appName}/Contents/MacOS`]);
  if (pgrepDerived.exitCode === 0) {
    const pids = pgrepDerived.stdout.toString().trim().split("\n").filter(Boolean);
    for (const pid of pids) {
      Bun.spawnSync(["kill", pid]);
    }
    steps.push({
      phase: "kill",
      name: service.name,
      success: true,
      detail: `killed ${pids.length} DerivedData process${pids.length > 1 ? "es" : ""}`,
    });
  }

  // 5. Kill any remaining processes by app name (catches stragglers)
  // Extract the executable name from appName (e.g. "TalkieAgent.app" -> "TalkieAgent")
  const execName = service.appName.replace(".app", "");
  const pgrepName = Bun.spawnSync(["pgrep", "-x", execName]);
  if (pgrepName.exitCode === 0) {
    const pids = pgrepName.stdout.toString().trim().split("\n").filter(Boolean);
    // Filter out production PIDs — only kill if the process path contains DerivedData
    for (const pid of pids) {
      const psResult = Bun.spawnSync(["ps", "-o", "args=", "-p", pid]);
      const args = psResult.stdout.toString().trim();
      // Only kill if it's a DerivedData build, NOT a production /Applications/ build
      if (args.includes("DerivedData") || args.includes("Build/Products")) {
        Bun.spawnSync(["kill", pid]);
        steps.push({
          phase: "kill",
          name: service.name,
          success: true,
          detail: `killed straggler pid ${pid}`,
        });
      }
    }
  }

  return steps;
}

/**
 * Wait for a service to fully die, polling up to maxWaitMs.
 * Returns true if clean, false if something is still lingering.
 */
export function waitForClean(service: TalkieService, maxWaitMs: number = 3000): { clean: boolean; remaining: string[] } {
  const interval = 200;
  const maxAttempts = Math.ceil(maxWaitMs / interval);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const remaining = checkRemaining(service);
    if (remaining.length === 0) return { clean: true, remaining: [] };
    Bun.sleepSync(interval);
  }

  return { clean: false, remaining: checkRemaining(service) };
}

function checkRemaining(service: TalkieService): string[] {
  const remaining: string[] = [];
  const execName = service.appName.replace(".app", "");

  // Check for live dev processes
  const pgrep = Bun.spawnSync(["pgrep", "-x", execName]);
  if (pgrep.exitCode === 0) {
    const pids = pgrep.stdout.toString().trim().split("\n").filter(Boolean);
    for (const pid of pids) {
      const psResult = Bun.spawnSync(["ps", "-o", "args=", "-p", pid]);
      const args = psResult.stdout.toString().trim();
      if (args.includes("DerivedData") || args.includes("Build/Products")) {
        remaining.push(`process: pid ${pid}`);
      }
    }
  }

  // Check launchctl for running dev entries
  const listResult = Bun.spawnSync(["launchctl", "list"]);
  for (const line of listResult.stdout.toString().split("\n")) {
    if (!line.includes(service.devBundleId)) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 3 && parts[0] !== "-") {
      remaining.push(`launchctl: pid ${parts[0]}`);
    }
  }

  return remaining;
}

function buildService(service: TalkieService, projectRoot: string): { success: boolean; duration: number; error?: string } {
  if ((!service.xcodeWorkspace && !service.xcodeProject) || !service.xcodeScheme) {
    return { success: false, duration: 0, error: "No Xcode container configured" };
  }

  const containerArgs = service.xcodeWorkspace
    ? ["-workspace", `${projectRoot}/${service.xcodeWorkspace}`]
    : ["-project", `${projectRoot}/${service.xcodeProject}`];
  const start = Date.now();

  // `-destination 'platform=macOS'` ensures xcodebuild filters to a macOS-
  // capable scheme. Without it, an ambiguous workspace scheme (or one whose
  // first-matching target happens to be iOS) can build the wrong product
  // — reporting success while leaving the macOS .app stale.
  const result = Bun.spawnSync(
    ["xcodebuild", ...containerArgs, "-scheme", service.xcodeScheme, "-configuration", "Debug", "-destination", "platform=macOS", "build"],
    { stdout: "pipe", stderr: "pipe", timeout: 900_000 }
  );

  const duration = Date.now() - start;

  if (result.exitCode !== 0) {
    const stderr = result.stderr.toString();
    const lines = stderr.trim().split("\n");
    return { success: false, duration, error: lines.slice(-5).join("\n") };
  }

  return { success: true, duration };
}

export function registerRebuildCommand(parent: Command): void {
  parent
    .command("rebuild [service]")
    .description(
      "Full rebuild cycle: xcodebuild → kill all traces → verify clean → launch fresh.\n\n" +
      "Use when: you want a guaranteed clean slate — build, stop everything, and relaunch.\n" +
      "More thorough than `build --restart`: kills launchd entries, app processes, and stragglers.\n" +
      "Use --skip-build to just clean+relaunch the existing build.\n" +
      "Use --clean to also remove stale DerivedData after launch.\n\n" +
      "Example: talkie-dev rebuild agent              (full rebuild)\n" +
      "         talkie-dev rebuild agent --skip-build  (clean + relaunch only)\n" +
      "         talkie-dev rebuild --clean             (rebuild all + clean stale builds)\n" +
      "         talkie-dev rebuild                     (rebuild all services)"
    )
    .option("--skip-build", "skip the build step (just clean + relaunch existing build)")
    .option("--clean", "also remove stale DerivedData builds after launch")
    .action((serviceName: string | undefined, opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const projectRoot = getProjectRoot();
      const uid = getUid();

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
        : SERVICES.filter((s) => s.xcodeProject || s.xcodeWorkspace);

      const results: RebuildResult[] = [];

      for (const service of services) {
        const allSteps: RebuildStep[] = [];

        // Phase 1: Build
        let buildDuration = 0;
        if (!opts.skipBuild) {
          if (fmt.pretty) process.stdout.write(`  \x1b[1m${service.name}\x1b[0m  building...`);

          const build = buildService(service, projectRoot);
          buildDuration = build.duration;
          allSteps.push({
            phase: "build",
            name: service.name,
            success: build.success,
            detail: build.success
              ? `${(build.duration / 1000).toFixed(1)}s`
              : build.error,
          });

          if (fmt.pretty) {
            const durationStr = `${(build.duration / 1000).toFixed(1)}s`;
            if (build.success) {
              process.stdout.write(`\r  \x1b[1m${service.name}\x1b[0m  \x1b[32m✓ built\x1b[0m \x1b[90m(${durationStr})\x1b[0m\n`);
            } else {
              process.stdout.write(`\r  \x1b[1m${service.name}\x1b[0m  \x1b[31m✗ build failed\x1b[0m \x1b[90m(${durationStr})\x1b[0m\n`);
              if (build.error) console.log(`    \x1b[31m${build.error}\x1b[0m`);
              results.push({ name: service.name, success: false, buildDuration, steps: allSteps });
              continue;
            }
          } else if (!build.success) {
            results.push({ name: service.name, success: false, buildDuration, steps: allSteps });
            continue;
          }
        } else if (fmt.pretty) {
          console.log(`  \x1b[1m${service.name}\x1b[0m  \x1b[90mskipping build\x1b[0m`);
        }

        // Phase 2: Kill everything
        if (fmt.pretty) process.stdout.write(`    cleaning...`);
        const killSteps = killEverything(service, uid);
        allSteps.push(...killSteps);

        if (fmt.pretty) {
          const killCount = killSteps.filter((s) => s.success).length;
          if (killCount > 0) {
            process.stdout.write(`\r    \x1b[32m✓ cleaned\x1b[0m \x1b[90m(${killCount} action${killCount > 1 ? "s" : ""})\x1b[0m\n`);
          } else {
            process.stdout.write(`\r    \x1b[90m· nothing to clean\x1b[0m\n`);
          }
        }

        // Phase 3: Wait for clean state (poll up to 3s)
        if (fmt.pretty) process.stdout.write(`    verifying...`);
        const verify = waitForClean(service);
        allSteps.push({
          phase: "verify",
          name: service.name,
          success: verify.clean,
          detail: verify.clean ? "clean" : verify.remaining.join(", "),
        });

        if (!verify.clean) {
          // One more aggressive kill round
          killEverything(service, uid);
          const retry = waitForClean(service, 2000);
          if (fmt.pretty) {
            if (retry.clean) {
              process.stdout.write(`\r    \x1b[32m✓ verified clean\x1b[0m\n`);
            } else {
              process.stdout.write(`\r    \x1b[33m⚠ ${retry.remaining.join(", ")}\x1b[0m\n`);
            }
          }
        } else if (fmt.pretty) {
          process.stdout.write(`\r    \x1b[32m✓ verified clean\x1b[0m\n`);
        }

        // Phase 4: Launch
        const build = findLatestBuild(service);
        if (!build) {
          allSteps.push({
            phase: "launch",
            name: service.name,
            success: false,
            detail: "No DerivedData build found",
          });
          if (fmt.pretty) console.log(`    \x1b[31m✗ no build found\x1b[0m`);
          results.push({ name: service.name, success: false, buildDuration, steps: allSteps });
          continue;
        }

        let launched: boolean;
        let launchError: string | undefined;

        if (service.machServices) {
          // XPC services need launchctl bootstrap for Mach service ports
          const result = launchViaLaunchd(service, build.path);
          launched = result.success;
          launchError = result.error;
        } else {
          // Regular apps — launch via `open`
          const result = Bun.spawnSync(["open", "-n", build.path]);
          launched = result.exitCode === 0;
          launchError = launched ? undefined : "open command failed";
        }

        allSteps.push({
          phase: "launch",
          name: service.name,
          success: launched,
          detail: launched ? build.path : (launchError ?? "launch failed"),
        });

        if (fmt.pretty) {
          if (launched) {
            console.log(`    \x1b[32m✓ launched\x1b[0m`);
          } else {
            console.log(`    \x1b[31m✗ launch failed\x1b[0m`);
          }
        }

        results.push({ name: service.name, success: launched, buildDuration, steps: allSteps });
      }

      // Clean stale DerivedData if --clean
      if (opts.clean) {
        const { stale } = findStaleDerivedData();
        if (stale.length > 0) {
          let freedMB = 0;
          for (const entry of stale) {
            const du = Bun.spawnSync(["du", "-sm", entry.path], { stdout: "pipe", stderr: "pipe" });
            const sizeMB = du.exitCode === 0 ? parseInt(du.stdout.toString().split("\t")[0], 10) : 0;
            try {
              rmSync(entry.path, { recursive: true, force: true });
              freedMB += sizeMB;
            } catch {
              // Best-effort
            }
          }
          if (fmt.pretty) {
            console.log(`\n  \x1b[90m↳ cleaned ${stale.length} stale build${stale.length !== 1 ? "s" : ""} (${freedMB}MB)\x1b[0m`);
          }
        }
      }

      // Summary
      if (fmt.pretty && results.length > 1) {
        console.log("");
        const ok = results.filter((r) => r.success).length;
        const fail = results.length - ok;
        if (fail === 0) {
          console.log(`\x1b[32m${ok}/${results.length} services rebuilt\x1b[0m`);
        } else {
          console.log(`\x1b[33m${ok}/${results.length} rebuilt, ${fail} failed\x1b[0m`);
        }
      }

      if (!fmt.pretty) {
        output({ results }, fmt);
      }
    });
}

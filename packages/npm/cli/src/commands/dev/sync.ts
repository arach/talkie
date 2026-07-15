import type { Command } from "../../gunshi-command";
import { getFormatOptions, output } from "../../format";
import { SERVICES, getProjectRoot, getUid, type TalkieService } from "./services";
import { findLatestBuild, launchViaLaunchd } from "./start";
import { getNewestSourceMtime } from "./status";
import { killEverything, waitForClean } from "./rebuild";

interface SyncCheck {
  service: TalkieService;
  sourceMtime: Date | null;
  buildMtime: Date | null;
  stale: boolean;
  reason: string;
}

function checkStaleness(projectRoot: string): SyncCheck[] {
  const checks: SyncCheck[] = [];

  for (const service of SERVICES) {
    if ((!service.xcodeProject && !service.xcodeWorkspace) || !service.sourceDir) continue;

    const sourceMtime = getNewestSourceMtime(service, projectRoot);
    const build = findLatestBuild(service);

    if (!build) {
      checks.push({ service, sourceMtime, buildMtime: null, stale: true, reason: "no build" });
    } else if (!sourceMtime) {
      checks.push({ service, sourceMtime: null, buildMtime: build.buildDate, stale: false, reason: "no sources" });
    } else if (sourceMtime.getTime() > build.buildDate.getTime()) {
      const diffSec = Math.floor((sourceMtime.getTime() - build.buildDate.getTime()) / 1000);
      const diffMin = Math.floor(diffSec / 60);
      const diffStr = diffSec < 60 ? `${diffSec}s`
        : diffMin < 60 ? `${diffMin}m`
        : diffMin < 1440 ? `${Math.floor(diffMin / 60)}h`
        : `${Math.floor(diffMin / 1440)}d`;
      checks.push({ service, sourceMtime, buildMtime: build.buildDate, stale: true, reason: `source ahead by ${diffStr}` });
    } else {
      checks.push({ service, sourceMtime, buildMtime: build.buildDate, stale: false, reason: "up to date" });
    }
  }

  return checks;
}

function buildService(service: TalkieService, projectRoot: string): { success: boolean; duration: number; error?: string } {
  if ((!service.xcodeWorkspace && !service.xcodeProject) || !service.xcodeScheme) {
    return { success: false, duration: 0, error: "No Xcode container configured" };
  }

  const containerArgs = service.xcodeWorkspace
    ? ["-workspace", `${projectRoot}/${service.xcodeWorkspace}`]
    : ["-project", `${projectRoot}/${service.xcodeProject}`];
  const start = Date.now();

  const result = Bun.spawnSync(
    ["xcodebuild", ...containerArgs, "-scheme", service.xcodeScheme, "-configuration", "Debug", "build"],
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

export function registerSyncCommand(parent: Command): void {
  parent
    .command("incremental")
    .description(
      "Build and restart only services with source changes since the last build.\n\n" +
      "Compares source file timestamps against build binary timestamps.\n" +
      "Shared packages (TalkieKit, packages/swift/) trigger rebuilds for all dependent services.\n\n" +
      "Example: talkie-dev incremental           (build + restart stale services)\n" +
      "         talkie-dev incremental --dry-run  (show what's stale without building)"
    )
    .option("--dry-run", "show what would be built without building")
    .action((opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const projectRoot = getProjectRoot();
      const uid = getUid();

      const checks = checkStaleness(projectRoot);
      const stale = checks.filter((c) => c.stale);

      if (fmt.pretty) {
        console.log("");
        for (const c of checks) {
          const name = c.service.name.padEnd(20);
          if (c.stale) {
            console.log(`  \x1b[33m▲\x1b[0m ${name} \x1b[33m${c.reason}\x1b[0m`);
          } else {
            console.log(`  \x1b[32m✓\x1b[0m ${name} \x1b[90m${c.reason}\x1b[0m`);
          }
        }

        if (stale.length === 0) {
          console.log("\n\x1b[32mEverything up to date.\x1b[0m\n");
          return;
        }

        if (opts.dryRun) {
          console.log(
            `\n\x1b[33mWould rebuild: ${stale.map((c) => c.service.name).join(", ")}\x1b[0m\n`
          );
          return;
        }

        console.log(
          `\nRebuilding ${stale.length} service${stale.length > 1 ? "s" : ""}...\n`
        );
      } else {
        if (opts.dryRun || stale.length === 0) {
          output(
            {
              checks: checks.map((c) => ({
                service: c.service.name,
                stale: c.stale,
                reason: c.reason,
              })),
            },
            fmt
          );
          return;
        }
      }

      // Build + restart stale services
      let successCount = 0;

      for (const c of stale) {
        const service = c.service;

        // Build
        if (fmt.pretty)
          process.stdout.write(`  \x1b[1m${service.name}\x1b[0m  building...`);

        const build = buildService(service, projectRoot);

        if (!build.success) {
          if (fmt.pretty) {
            const dur = `${(build.duration / 1000).toFixed(1)}s`;
            process.stdout.write(
              `\r  \x1b[1m${service.name}\x1b[0m  \x1b[31m✗ build failed\x1b[0m \x1b[90m(${dur})\x1b[0m\n`
            );
            if (build.error) console.log(`    \x1b[31m${build.error}\x1b[0m`);
          }
          continue;
        }

        if (fmt.pretty) {
          const dur = `${(build.duration / 1000).toFixed(1)}s`;
          process.stdout.write(
            `\r  \x1b[1m${service.name}\x1b[0m  \x1b[32m✓ built\x1b[0m \x1b[90m(${dur})\x1b[0m\n`
          );
        }

        // Kill + verify clean
        killEverything(service, uid);
        waitForClean(service);

        // Launch
        const latest = findLatestBuild(service);
        if (!latest) {
          if (fmt.pretty)
            console.log(`    \x1b[31m✗ no build found after compile\x1b[0m`);
          continue;
        }

        let launched = false;
        if (service.machServices) {
          const result = launchViaLaunchd(service, latest.path);
          launched = result.success;
        } else {
          const result = Bun.spawnSync(["open", latest.path]);
          launched = result.exitCode === 0;
        }

        if (fmt.pretty) {
          if (launched) {
            console.log(`    \x1b[32m↑ restarted\x1b[0m`);
          } else {
            console.log(`    \x1b[31m✗ restart failed\x1b[0m`);
          }
        }

        if (launched) successCount++;
      }

      if (fmt.pretty && stale.length > 0) {
        console.log("");
        if (successCount === stale.length) {
          console.log(`\x1b[32m${successCount}/${stale.length} synced\x1b[0m\n`);
        } else {
          console.log(
            `\x1b[33m${successCount}/${stale.length} synced\x1b[0m\n`
          );
        }
      }

      if (!fmt.pretty) {
        output({ synced: successCount, total: stale.length }, fmt);
      }
    });
}

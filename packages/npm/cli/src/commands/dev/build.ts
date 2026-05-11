import type { Command } from "commander";
import { getFormatOptions, output } from "../../format";
import { SERVICES, resolveService, getProjectRoot, getUid, type TalkieService } from "./services";
import { findLatestBuild, launchViaLaunchd } from "./start";

interface BuildResult {
  name: string;
  success: boolean;
  duration: number;
  error?: string;
}

function buildService(service: TalkieService, projectRoot: string): BuildResult {
  if ((!service.xcodeWorkspace && !service.xcodeProject) || !service.xcodeScheme) {
    return { name: service.name, success: false, duration: 0, error: "No Xcode container configured" };
  }

  const containerArgs = service.xcodeWorkspace
    ? ["-workspace", `${projectRoot}/${service.xcodeWorkspace}`]
    : ["-project", `${projectRoot}/${service.xcodeProject}`];
  const start = Date.now();

  const result = Bun.spawnSync(
    [
      "xcodebuild",
      ...containerArgs,
      "-scheme", service.xcodeScheme,
      "-configuration", "Debug",
      "build",
    ],
    {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 900_000,
    }
  );

  const duration = Date.now() - start;

  if (result.exitCode !== 0) {
    // Extract the last few lines of stderr for error context
    const stderr = result.stderr.toString();
    const lines = stderr.trim().split("\n");
    const errorSummary = lines.slice(-5).join("\n");
    return { name: service.name, success: false, duration, error: errorSummary };
  }

  return { name: service.name, success: true, duration };
}

export function registerBuildCommand(devCmd: Command): void {
  devCmd
    .command("build [service]")
    .description(
      "Build a Talkie service via xcodebuild (Debug configuration).\n\n" +
      "Use when: you've changed Swift code and want to compile without opening Xcode.\n" +
      "Outputs to DerivedData. Use --restart to stop+relaunch after a successful build.\n\n" +
      "Example: talkie-dev build agent            (build TalkieAgent)\n" +
      "         talkie-dev build agent --restart   (build + restart)\n" +
      "         talkie-dev build                   (build all services)"
    )
    .option("--restart", "restart the service after a successful build")
    .action((serviceName: string | undefined, opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const projectRoot = getProjectRoot();

      const services = serviceName
        ? (() => {
            const s = resolveService(serviceName);
            if (!s) {
              console.error(`Unknown service: ${serviceName}`);
              console.error(`Available: ${SERVICES.filter((s) => s.xcodeProject || s.xcodeWorkspace).map((s) => s.aliases[0]).join(", ")}`);
              process.exit(1);
            }
            if (!s.xcodeProject && !s.xcodeWorkspace) {
              console.error(`${s.name} has no Xcode container`);
              process.exit(1);
            }
            return [s];
          })()
        : SERVICES.filter((s) => s.xcodeProject || s.xcodeWorkspace);

      const results: BuildResult[] = [];

      for (const service of services) {
        if (fmt.pretty) {
          process.stdout.write(`  Building ${service.name}...`);
        }

        const result = buildService(service, projectRoot);
        results.push(result);

        if (fmt.pretty) {
          const durationStr = `${(result.duration / 1000).toFixed(1)}s`;
          if (result.success) {
            console.log(` \x1b[32m✓\x1b[0m \x1b[90m(${durationStr})\x1b[0m`);
          } else {
            console.log(` \x1b[31m✗\x1b[0m \x1b[90m(${durationStr})\x1b[0m`);
            if (result.error) {
              console.log(`\x1b[31m${result.error}\x1b[0m`);
            }
          }
        }
      }

      // Restart services that built successfully if --restart
      if (opts.restart) {
        const uid = getUid();

        if (fmt.pretty) console.log("\nRestarting...");

        for (const result of results) {
          if (!result.success) continue;
          const service = SERVICES.find((s) => s.name === result.name)!;

          // Stop
          if (service.launchdLabel) {
            Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${service.launchdLabel}`]);
          } else {
            const pgrep = Bun.spawnSync(["pgrep", "-f", `DerivedData.*${service.appName}/Contents/MacOS`]);
            if (pgrep.exitCode === 0) {
              for (const pid of pgrep.stdout.toString().trim().split("\n").filter(Boolean)) {
                Bun.spawnSync(["kill", pid]);
              }
            }
          }

          Bun.sleepSync(300);

          // Start — XPC services need launchctl for Mach service ports
          const build = findLatestBuild(service);
          if (build) {
            let startOk = false;
            if (service.machServices) {
              const result = launchViaLaunchd(service, build.path);
              startOk = result.success;
            } else {
              const open = Bun.spawnSync(["open", "-n", build.path]);
              startOk = open.exitCode === 0;
            }
            if (fmt.pretty) {
              const icon = startOk ? "\x1b[32m↑\x1b[0m" : "\x1b[31m✗\x1b[0m";
              console.log(`  ${icon} ${service.name} restarted`);
            }
          }
        }
      }

      if (!fmt.pretty) {
        output({ results }, fmt);
      }
    });
}

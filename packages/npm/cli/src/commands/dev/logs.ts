import type { Command } from "commander";
import { SERVICES, resolveService } from "./services";

const COLORS: Record<string, string> = {
  "to.talkie.app.mac": "\x1b[36m",   // cyan
  "to.talkie.app.agent": "\x1b[35m",  // magenta
};
const RESET = "\x1b[0m";

function buildPredicate(serviceName?: string): string {
  if (serviceName) {
    const service = resolveService(serviceName);
    if (!service) {
      console.error(`Unknown service: ${serviceName}`);
      console.error(`Available: ${SERVICES.map((s) => s.aliases[0]).join(", ")}`);
      process.exit(1);
    }
    return `subsystem == "${service.logSubsystem}"`;
  }
  // All talkie subsystems
  return `subsystem BEGINSWITH "to.talkie.app"`;
}

export function registerLogsCommand(devCmd: Command): void {
  devCmd
    .command("logs [service]")
    .description(
      "Tail or query unified logs from Talkie services.\n\n" +
      "Default: live tail (streams until Ctrl+C). Add --since for historical.\n\n" +
      "Example: talkie-dev logs agent             (live tail — stays open)\n" +
      "         talkie-dev logs agent --since 5m   (last 5 min, then exits)\n" +
      "         talkie-dev logs agent --level error (live stream errors only)"
    )
    .option("--since <duration>", "show logs from last N duration (e.g. 5m, 1h, 30s)")
    .option("--level <level>", "minimum log level (default, info, debug, error, fault)", "default")
    .action((serviceName: string | undefined, opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const predicate = buildPredicate(serviceName);
      const pretty = globalOpts.pretty;

      if (opts.since) {
        // Historical: use `log show`
        const args = [
          "log", "show",
          "--predicate", predicate,
          "--last", opts.since,
          "--style", "compact",
          "--info", "--debug",
        ];

        if (pretty) {
          // Stream through and colorize
          const proc = Bun.spawn(args, { stdout: "pipe", stderr: "inherit" });
          const reader = proc.stdout.getReader();
          const decoder = new TextDecoder();

          (async () => {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              const text = decoder.decode(value);
              for (const line of text.split("\n")) {
                if (!line.trim()) continue;
                let colored = line;
                for (const [subsystem, color] of Object.entries(COLORS)) {
                  if (line.includes(subsystem)) {
                    colored = `${color}${line}${RESET}`;
                    break;
                  }
                }
                console.log(colored);
              }
            }
          })();
        } else {
          // JSON mode: collect and output as structured data
          const result = Bun.spawnSync(["log", "show", "--predicate", predicate, "--last", opts.since, "--style", "ndjson", "--info", "--debug"]);
          const lines = result.stdout.toString().trim().split("\n").filter(Boolean);
          const entries = lines
            .map((line) => {
              try { return JSON.parse(line); } catch { return null; }
            })
            .filter(Boolean);
          console.log(JSON.stringify(entries, null, 2));
        }
      } else {
        // Live: use `log stream`
        const args = [
          "log", "stream",
          "--predicate", predicate,
          "--style", pretty ? "compact" : "ndjson",
          "--level", opts.level,
        ];

        const target = serviceName || "all services";
        console.error(`\x1b[90m🔴 Live tailing ${target}... Ctrl+C to stop\x1b[0m`);

        const proc = Bun.spawn(args, {
          stdout: "pipe",
          stderr: "inherit",
        });

        const reader = proc.stdout.getReader();
        const decoder = new TextDecoder();

        (async () => {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            const text = decoder.decode(value);

            if (pretty) {
              for (const line of text.split("\n")) {
                if (!line.trim()) continue;
                let colored = line;
                for (const [subsystem, color] of Object.entries(COLORS)) {
                  if (line.includes(subsystem)) {
                    colored = `${color}${line}${RESET}`;
                    break;
                  }
                }
                process.stdout.write(colored + "\n");
              }
            } else {
              process.stdout.write(text);
            }
          }
        })();

        // Keep alive until killed
        process.on("SIGINT", () => {
          proc.kill();
          process.exit(0);
        });
      }
    });
}

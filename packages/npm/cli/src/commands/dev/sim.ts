import type { Command } from "commander";

const RESET = "\x1b[0m";
const DIM = "\x1b[90m";
const CYAN = "\x1b[36m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";

interface SimDevice {
  udid: string;
  name: string;
  state: string;
  runtime: string;
}

/** Parse `xcrun simctl list devices available -j` into flat device list */
function listDevices(): SimDevice[] {
  const result = Bun.spawnSync(["xcrun", "simctl", "list", "devices", "available", "-j"]);
  const data = JSON.parse(result.stdout.toString());
  const devices: SimDevice[] = [];
  for (const [runtime, devs] of Object.entries(data.devices) as [string, any[]][]) {
    for (const d of devs) {
      devices.push({
        udid: d.udid,
        name: d.name,
        state: d.state,
        runtime: runtime.replace("com.apple.CoreSimulator.SimRuntime.", ""),
      });
    }
  }
  return devices;
}

/** Get booted devices only */
function getBootedDevices(): SimDevice[] {
  return listDevices().filter((d) => d.state === "Booted");
}

/** Resolve a device by partial name match, preferring booted devices */
function resolveDevice(hint?: string): SimDevice | null {
  const devices = listDevices();
  const booted = devices.filter((d) => d.state === "Booted");

  if (!hint) {
    // Default: first booted device, prefer Pro Max, then Pro, then any
    if (booted.length === 0) return null;
    return (
      booted.find((d) => d.name.includes("Pro Max")) ||
      booted.find((d) => d.name.includes("Pro")) ||
      booted[0]
    );
  }

  const lower = hint.toLowerCase();
  // Try booted first
  const bootedMatch = booted.find(
    (d) => d.name.toLowerCase().includes(lower) || d.udid === hint
  );
  if (bootedMatch) return bootedMatch;

  // Then all devices
  return (
    devices.find(
      (d) => d.name.toLowerCase().includes(lower) || d.udid === hint
    ) || null
  );
}

export function registerSimCommand(devCmd: Command): void {
  const simCmd = devCmd
    .command("sim")
    .description(
      "iOS Simulator tools for testing keyboard extensions and the iOS app.\n\n" +
        "Quick start:\n" +
        "  talkie-dev sim list                List booted simulators\n" +
        "  talkie-dev sim logs                Stream TalkieKeys logs from default sim\n" +
        '  talkie-dev sim logs --grep "PUNC"  Filter logs by keyword\n' +
        "  talkie-dev sim logs --app          Stream main app logs instead\n" +
        "  talkie-dev sim install             Install latest build on default sim\n" +
        "  talkie-dev sim kill-ext            Kill TalkieKeys extension to force reload"
    );

  // --- sim list ---
  simCmd
    .command("list")
    .description("List available and booted simulators")
    .action(() => {
      const devices = listDevices();
      const booted = devices.filter((d) => d.state === "Booted");
      const available = devices.filter(
        (d) => d.state !== "Booted" && (d.name.includes("iPhone") || d.name.includes("iPad"))
      );

      if (booted.length > 0) {
        console.log(`${GREEN}Booted:${RESET}`);
        for (const d of booted) {
          console.log(`  ${d.name} (${d.runtime}) ${DIM}${d.udid}${RESET}`);
        }
      } else {
        console.log(`${YELLOW}No booted simulators${RESET}`);
      }

      if (available.length > 0) {
        console.log(`\n${DIM}Available:${RESET}`);
        for (const d of available.slice(0, 8)) {
          console.log(`  ${DIM}${d.name} (${d.runtime})${RESET}`);
        }
      }
    });

  // --- sim logs ---
  simCmd
    .command("logs [device]")
    .description(
      "Stream logs from iOS keyboard extension (TalkieKeys) on a simulator.\n" +
        "Defaults to the first booted simulator (prefers Pro Max)."
    )
    .option("--app", "stream main Talkie app logs instead of TalkieKeys")
    .option("--grep <pattern>", "filter log messages by keyword")
    .option("--since <duration>", "show historical logs (e.g. 2m, 5m, 1h)")
    .option("--all", "show all logs (not just TalkieKeys/Talkie)")
    .action((deviceHint: string | undefined, opts) => {
      const device = resolveDevice(deviceHint);
      if (!device) {
        console.error(
          `${YELLOW}No booted simulator found.${RESET} Boot one first or specify a device.`
        );
        process.exit(1);
      }

      const processFilter = opts.all
        ? 'process CONTAINS "Talkie"'
        : opts.app
          ? 'process == "Talkie"'
          : 'process CONTAINS "TalkieKeys"';

      let predicate = processFilter;
      if (opts.grep) {
        predicate += ` AND eventMessage CONTAINS "${opts.grep}"`;
      }

      console.log(
        `${CYAN}${opts.app ? "Talkie" : "TalkieKeys"}${RESET} logs on ${GREEN}${device.name}${RESET} ${DIM}(${device.udid.slice(0, 8)}...)${RESET}`
      );

      if (opts.since) {
        // Historical
        console.log(`${DIM}Showing last ${opts.since}...${RESET}\n`);
        const args = [
          "xcrun", "simctl", "spawn", device.udid,
          "log", "show",
          "--last", opts.since,
          "--debug",
          "--predicate", predicate,
          "--style", "compact",
        ];
        const proc = Bun.spawn(args, { stdout: "pipe", stderr: "inherit" });
        pipeAndColorize(proc);
      } else {
        // Live stream
        console.log(`${DIM}Streaming... Ctrl+C to stop${RESET}\n`);
        const args = [
          "xcrun", "simctl", "spawn", device.udid,
          "log", "stream",
          "--debug",
          "--predicate", predicate,
          "--style", "compact",
        ];
        const proc = Bun.spawn(args, { stdout: "pipe", stderr: "inherit" });
        pipeAndColorize(proc);

        process.on("SIGINT", () => {
          proc.kill();
          process.exit(0);
        });
      }
    });

  // --- sim install ---
  simCmd
    .command("install [device]")
    .description("Install latest Talkie iOS build onto a simulator")
    .action((deviceHint: string | undefined) => {
      const device = resolveDevice(deviceHint);
      if (!device) {
        console.error(`${YELLOW}No booted simulator found.${RESET}`);
        process.exit(1);
      }

      // Find the latest iOS build in DerivedData (Talkie-iOS-* prefix)
      const derivedData = `${Bun.env.HOME}/Library/Developer/Xcode/DerivedData`;
      const findResult = Bun.spawnSync([
        "find", derivedData,
        "-maxdepth", "5",
        "-path", "*/Talkie-iOS-*/Build/Products/Debug-iphonesimulator/Talkie.app",
        "-type", "d",
      ]);
      const appPaths = findResult.stdout
        .toString()
        .trim()
        .split("\n")
        .filter(Boolean);

      if (appPaths.length === 0) {
        console.error(`${YELLOW}No Talkie.app found in DerivedData.${RESET} Build first.`);
        process.exit(1);
      }

      // Use the most recent
      const appPath = appPaths[0];
      console.log(
        `Installing on ${GREEN}${device.name}${RESET}...`
      );
      console.log(`${DIM}${appPath}${RESET}`);

      const install = Bun.spawnSync([
        "xcrun", "simctl", "install", device.udid, appPath,
      ]);
      if (install.exitCode !== 0) {
        console.error(`${YELLOW}Install failed${RESET}`);
        console.error(install.stderr.toString());
        process.exit(1);
      }

      console.log(`${GREEN}Installed.${RESET} Switch keyboards or reopen text field to reload TalkieKeys.`);
    });

  // --- sim kill-ext ---
  simCmd
    .command("kill-ext [device]")
    .description(
      "Kill the TalkieKeys extension process to force it to reload the new binary.\n" +
        "After killing, switch keyboards or tap a text field to relaunch."
    )
    .action((deviceHint: string | undefined) => {
      const device = resolveDevice(deviceHint);
      if (!device) {
        console.error(`${YELLOW}No booted simulator found.${RESET}`);
        process.exit(1);
      }

      console.log(`Killing TalkieKeys on ${GREEN}${device.name}${RESET}...`);
      const result = Bun.spawnSync([
        "xcrun", "simctl", "spawn", device.udid, "killall", "TalkieKeys",
      ]);

      if (result.exitCode === 0) {
        console.log(
          `${GREEN}Killed.${RESET} Tap a text field to relaunch with the new build.`
        );
      } else {
        // killall returns 1 if no matching process
        console.log(
          `${DIM}TalkieKeys wasn't running (already dead or not yet launched).${RESET}`
        );
      }
    });

  // --- sim prep ---
  simCmd
    .command("prep")
    .description(
      "Prepare all booted simulators for App Store screenshots.\n" +
        "Sets status bar to Apple standard: 9:41, full battery, full signal.\n" +
        "Run once before capturing screenshots across all devices."
    )
    .action(() => {
      const booted = getBootedDevices();
      if (booted.length === 0) {
        console.error(`${YELLOW}No booted simulators.${RESET}`);
        process.exit(1);
      }

      for (const device of booted) {
        console.log(`Prepping ${GREEN}${device.name}${RESET}...`);
        const result = Bun.spawnSync([
          "xcrun", "simctl", "status_bar", device.udid, "override",
          "--time", "11:11",
          "--batteryState", "discharging",
          "--batteryLevel", "100",
          "--cellularBars", "4",
          "--wifiBars", "3",
          "--operatorName", "",
        ]);
        if (result.exitCode === 0) {
          console.log(`  ${GREEN}✓${RESET} Status bar set (full battery, full signal)`);
        } else {
          console.error(`  ${YELLOW}✗${RESET} Failed: ${result.stderr.toString().trim()}`);
        }
      }

      console.log(`\n${GREEN}Done.${RESET} ${booted.length} simulator(s) ready for screenshots.`);
    });

  // --- sim boot ---
  simCmd
    .command("boot <device>")
    .description(
      "Boot a simulator by name (partial match).\n" +
        "Opens the Simulator app if not already running.\n" +
        '  Example: talkie-dev sim boot "iPad Air"'
    )
    .action((deviceHint: string) => {
      const devices = listDevices();
      const lower = deviceHint.toLowerCase();
      const match = devices.find(
        (d) => d.name.toLowerCase().includes(lower) || d.udid === deviceHint
      );

      if (!match) {
        console.error(`${YELLOW}No simulator matching "${deviceHint}".${RESET}`);
        process.exit(1);
      }

      if (match.state === "Booted") {
        console.log(`${GREEN}${match.name}${RESET} is already booted.`);
        return;
      }

      console.log(`Booting ${GREEN}${match.name}${RESET} (${match.runtime})...`);
      const result = Bun.spawnSync(["xcrun", "simctl", "boot", match.udid]);
      if (result.exitCode !== 0) {
        console.error(`${YELLOW}Boot failed:${RESET} ${result.stderr.toString().trim()}`);
        process.exit(1);
      }

      // Open Simulator.app so the device window appears
      Bun.spawnSync(["open", "-a", "Simulator"]);
      console.log(`${GREEN}Booted.${RESET}`);
    });

  // --- sim launch ---
  simCmd
    .command("launch [device]")
    .description("Launch the Talkie app on a simulator")
    .action((deviceHint: string | undefined) => {
      const device = resolveDevice(deviceHint);
      if (!device) {
        console.error(`${YELLOW}No booted simulator found.${RESET}`);
        process.exit(1);
      }

      console.log(`Launching Talkie on ${GREEN}${device.name}${RESET}...`);
      const result = Bun.spawnSync([
        "xcrun", "simctl", "launch", device.udid, "to.talkie.app.ios",
      ]);

      if (result.exitCode === 0) {
        console.log(`${GREEN}Launched.${RESET}`);
      } else {
        console.error(result.stderr.toString());
      }
    });
}

/** Pipe a process stdout through line-by-line colorization */
function pipeAndColorize(proc: ReturnType<typeof Bun.spawn>): void {
  const reader = (proc.stdout as ReadableStream).getReader();
  const decoder = new TextDecoder();

  (async () => {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = decoder.decode(value);
      for (const line of text.split("\n")) {
        if (!line.trim()) continue;
        // Skip the "Filtering..." preamble and header
        if (line.includes("Filtering the log data") || line.startsWith("Timestamp")) continue;
        if (line.includes("getpwuid")) continue;
        // Highlight [TAGS] in cyan
        const colored = line.replace(/\[([^\]]+)\]/g, `${CYAN}[$1]${RESET}`);
        process.stdout.write(colored + "\n");
      }
    }
  })();
}

import type { Command } from "commander";
import { readdirSync, statSync, existsSync, writeFileSync } from "fs";
import { join } from "path";
import { getFormatOptions, output } from "../../format";
import {
  SERVICES,
  resolveService,
  getDerivedDataRoot,
  getUid,
  type TalkieService,
} from "./services";

interface StartResult {
  name: string;
  success: boolean;
  path?: string;
  buildDate?: string;
  error?: string;
}

export interface BuildCandidate {
  path: string;
  mtime: Date;
  derivedDataDir: string;
}

/**
 * Find all DerivedData builds for a service, sorted newest-first.
 * Scans ~/Library/Developer/Xcode/DerivedData/{prefix}* for
 * Build/Products/Debug/{appName}.
 */
export function findAllBuilds(service: TalkieService): BuildCandidate[] {
  const root = getDerivedDataRoot();
  if (!existsSync(root)) return [];

  const candidates: BuildCandidate[] = [];

  try {
    const prefixes = Array.isArray(service.derivedDataPrefix)
      ? service.derivedDataPrefix
      : [service.derivedDataPrefix];
    const dirs = readdirSync(root).filter((d) =>
      prefixes.some((p) => d.startsWith(p))
    );

    for (const dir of dirs) {
      const appPath = join(root, dir, "Build", "Products", "Debug", service.appName);
      if (existsSync(appPath)) {
        // Stat the binary inside the .app, not the .app directory itself.
        // xcodebuild updates the binary mtime but not always the .app dir mtime.
        const execName = service.appName.replace(".app", "");
        const binaryPath = join(appPath, "Contents", "MacOS", execName);
        const target = existsSync(binaryPath) ? binaryPath : appPath;
        const stat = statSync(target);
        candidates.push({ path: appPath, mtime: stat.mtime, derivedDataDir: dir });
      }
    }
  } catch {
    return [];
  }

  candidates.sort((a, b) => b.mtime.getTime() - a.mtime.getTime());
  return candidates;
}

/**
 * Find the latest DerivedData build for a service.
 * Returns the newest build from findAllBuilds.
 */
export function findLatestBuild(service: TalkieService): { path: string; buildDate: Date } | null {
  const builds = findAllBuilds(service);
  if (builds.length === 0) return null;

  if (service.preferredDerivedDataPrefix) {
    const preferred = builds.find((build) =>
      build.derivedDataDir.startsWith(service.preferredDerivedDataPrefix!)
    );
    if (preferred) {
      return { path: preferred.path, buildDate: preferred.mtime };
    }
  }

  return { path: builds[0].path, buildDate: builds[0].mtime };
}

/**
 * Launch an XPC service via launchctl bootstrap so Mach service ports are registered.
 * Services launched with `open` don't get Mach ports — clients can't connect.
 */
export function launchViaLaunchd(
  service: TalkieService,
  appPath: string
): { success: boolean; error?: string } {
  if (!service.launchdLabel || !service.machServices) {
    return { success: false, error: "Service has no launchd/machServices config" };
  }

  const uid = getUid();
  const execName = service.appName.replace(".app", "");
  const executablePath = join(appPath, "Contents", "MacOS", execName);

  if (!existsSync(executablePath)) {
    return { success: false, error: `Executable not found: ${executablePath}` };
  }

  // Build MachServices dict
  const machServicesDict: Record<string, boolean> = {};
  for (const name of service.machServices) {
    machServicesDict[name] = true;
  }

  const label = service.launchdLabel;
  const plist: Record<string, unknown> = {
    Label: label,
    ProgramArguments: [executablePath, "--daemon"],
    MachServices: machServicesDict,
    KeepAlive: service.defaultLaunch,
    RunAtLoad: false,
    StandardOutPath: `/tmp/${label}.stdout.log`,
    StandardErrorPath: `/tmp/${label}.stderr.log`,
  };

  // Write plist as XML
  const plistPath = `/tmp/${label}.plist`;
  const plistXml = buildPlistXml(plist);
  writeFileSync(plistPath, plistXml);

  // Bootout any existing dev registration (ignore errors — may not exist)
  Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${label}`], {
    stdout: "pipe",
    stderr: "pipe",
  });

  // Bootout production instances to prevent doubling.
  // Production app registers its own launchd agents (e.g. jdi.talkie.agent)
  // and macOS may also register application.{bundleId}.* entries for LoginItems.
  if (service.prodBundleId) {
    // Direct prod label (e.g. jdi.talkie.agent)
    Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${service.prodBundleId}`], {
      stdout: "pipe",
      stderr: "pipe",
    });

    // application.{bundleId}.* entries (LoginItems registered by macOS)
    const listResult = Bun.spawnSync(["launchctl", "list"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const lines = listResult.stdout.toString().split("\n");
    for (const line of lines) {
      if (!line.includes(`application.${service.prodBundleId}`)) continue;
      const parts = line.trim().split(/\s+/);
      if (parts.length < 3) continue;
      const appLabel = parts.slice(2).join(" ");
      Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${appLabel}`], {
        stdout: "pipe",
        stderr: "pipe",
      });
    }
  }

  // Brief pause to let bootout complete
  Bun.sleepSync(200);

  // Bootstrap
  const bootstrap = Bun.spawnSync(
    ["launchctl", "bootstrap", `gui/${uid}`, plistPath],
    { stdout: "pipe", stderr: "pipe" }
  );

  if (bootstrap.exitCode !== 0) {
    const stderr = bootstrap.stderr.toString().trim();
    return { success: false, error: `launchctl bootstrap failed: ${stderr}` };
  }

  return { success: true };
}

/** Build a minimal Apple plist XML string. */
function buildPlistXml(obj: Record<string, unknown>): string {
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    "<dict>",
  ];

  for (const [key, value] of Object.entries(obj)) {
    lines.push(`\t<key>${key}</key>`);
    lines.push(plistValue(value, 1));
  }

  lines.push("</dict>");
  lines.push("</plist>");
  return lines.join("\n") + "\n";
}

function plistValue(value: unknown, indent: number): string {
  const tabs = "\t".repeat(indent);
  if (typeof value === "string") {
    return `${tabs}<string>${value}</string>`;
  }
  if (typeof value === "boolean") {
    return `${tabs}<${value}/>`;
  }
  if (Array.isArray(value)) {
    const items = value.map((v) => plistValue(v, indent + 1)).join("\n");
    return `${tabs}<array>\n${items}\n${tabs}</array>`;
  }
  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value as Record<string, unknown>);
    const items = entries
      .map(([k, v]) => `${tabs}\t<key>${k}</key>\n${plistValue(v, indent + 1)}`)
      .join("\n");
    return `${tabs}<dict>\n${items}\n${tabs}</dict>`;
  }
  return `${tabs}<string>${String(value)}</string>`;
}

function startService(service: TalkieService): StartResult {
  const build = findLatestBuild(service);

  if (!build) {
    return {
      name: service.name,
      success: false,
      error: `No DerivedData build found (looking for ${service.derivedDataPrefix}*)`,
    };
  }

  // XPC services need launchctl bootstrap for Mach service ports
  if (service.machServices) {
    const result = launchViaLaunchd(service, build.path);
    return {
      name: service.name,
      success: result.success,
      path: build.path,
      buildDate: build.buildDate.toISOString(),
      error: result.error,
    };
  }

  // Regular apps — launch via `open`
  const result = Bun.spawnSync(["open", "-n", build.path]);

  if (result.exitCode !== 0) {
    return {
      name: service.name,
      success: false,
      path: build.path,
      error: result.stderr.toString().trim() || "open command failed",
    };
  }

  return {
    name: service.name,
    success: true,
    path: build.path,
    buildDate: build.buildDate.toISOString(),
  };
}

function launchAction(serviceName: string | undefined, _: unknown, cmd: Command): void {
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
    : SERVICES.filter((s) => s.defaultLaunch);

  const results: StartResult[] = [];
  for (const service of services) {
    const result = startService(service);
    results.push(result);

    if (fmt.pretty) {
      const icon = result.success ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m";
      const detail = result.success
        ? `\x1b[90m${result.path?.replace(getDerivedDataRoot(), "…")}\x1b[0m`
        : `\x1b[31m${result.error}\x1b[0m`;
      console.log(`  ${icon} ${service.name.padEnd(20)} ${detail}`);
    }
  }

  if (!fmt.pretty) {
    output({ results }, fmt);
  }
}

const launchDesc =
  "Launch a Talkie dev service from the newest DerivedData build (no build step).\n\n" +
  "Use when: you have a built .app in DerivedData and want to launch it without Xcode.\n" +
  "Scans all matching DerivedData dirs and picks the newest .app by modification time.\n\n" +
  "Example: talkie-dev launch agent    (launch TalkieAgent)\n" +
  "         talkie-dev launch           (launch Talkie, Agent)";

/** Register `launch` command (+ hidden `start` alias). */
export function registerStartCommand(parent: Command): void {
  parent
    .command("launch [service]")
    .description(launchDesc)
    .action(launchAction);

  parent
    .command("start [service]", { hidden: true })
    .action(launchAction);
}

import type { Command } from "../../gunshi-command";
import { existsSync, readFileSync, statSync, readdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { getFormatOptions, output } from "../../format";
import { resolveDbPath } from "../../db";
import { SERVICES, SHARED_SOURCE_DIRS, getUid, getProjectRoot, type TalkieService } from "./services";
import { findAllBuilds, type BuildCandidate } from "./start";

interface ServiceStatus {
  name: string;
  status: "running" | "crashed" | "stopped" | "not_registered";
  pid: number | null;
  exitStatus: number | null;
  label: string | null;
  type: "app" | "launchd" | null;
  isStale: boolean;
}

interface BuildInfo {
  service: string;
  active: {
    path: string;
    derivedDataDir: string;
    buildDate: string;
    age: string;
    stale: boolean;
  } | null;
  altCount: number;
}

interface LaunchctlEntry {
  pid: number | null;
  status: number;
  label: string;
}

function parseLaunchctlList(): LaunchctlEntry[] {
  const result = Bun.spawnSync(["launchctl", "list"]);
  const stdout = result.stdout.toString();
  const entries: LaunchctlEntry[] = [];

  for (const line of stdout.split("\n")) {
    if (!line.toLowerCase().includes("talkie")) continue;
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;

    const [pidStr, statusStr, ...labelParts] = parts;
    entries.push({
      pid: pidStr === "-" ? null : parseInt(pidStr, 10),
      status: parseInt(statusStr, 10),
      label: labelParts.join(" "),
    });
  }

  return entries;
}

function classifyEntry(entry: LaunchctlEntry): { status: ServiceStatus["status"]; isStale: boolean } {
  if (entry.pid !== null && entry.status === 0) {
    return { status: "running", isStale: false };
  }
  if (entry.pid === null && entry.status === 78) {
    return { status: "stopped", isStale: true };
  }
  if (entry.status < 0) {
    // Negative = killed by signal (e.g., -15 = SIGTERM, -9 = SIGKILL)
    return { status: "crashed", isStale: true };
  }
  if (entry.pid === null && entry.status !== 0) {
    return { status: "stopped", isStale: true };
  }
  return { status: "stopped", isStale: false };
}

function matchServiceToEntry(
  service: TalkieService,
  entries: LaunchctlEntry[]
): LaunchctlEntry | null {
  // Match by launchd label
  if (service.launchdLabel) {
    const match = entries.find((e) => e.label === service.launchdLabel);
    if (match) return match;
  }

  // Match by dev bundle ID (app-launched processes show as application.{bundleId}.*)
  const appPrefix = `application.${service.devBundleId}`;
  const appMatch = entries.find((e) => e.label.startsWith(appPrefix));
  if (appMatch) return appMatch;

  return null;
}

function getServiceStatuses(): ServiceStatus[] {
  const entries = parseLaunchctlList();
  const statuses: ServiceStatus[] = [];
  const matchedLabels = new Set<string>();

  // Match known services
  for (const service of SERVICES) {
    const entry = matchServiceToEntry(service, entries);
    if (entry) {
      matchedLabels.add(entry.label);
      const { status, isStale } = classifyEntry(entry);
      statuses.push({
        name: service.name,
        status,
        pid: entry.pid,
        exitStatus: entry.status !== 0 ? entry.status : null,
        label: entry.label,
        type: entry.label.startsWith("application.") ? "app" : "launchd",
        isStale,
      });
    } else {
      statuses.push({
        name: service.name,
        status: "not_registered",
        pid: null,
        exitStatus: null,
        label: null,
        type: null,
        isStale: false,
      });
    }
  }

  // Show unmatched talkie entries (other registrations like TalkieSync, TalkieLive)
  for (const entry of entries) {
    if (matchedLabels.has(entry.label)) continue;
    const { status, isStale } = classifyEntry(entry);

    // If this entry matches a known service's bundle ID, label it as a duplicate
    const ownerService = SERVICES.find((s) => entry.label.includes(s.devBundleId));
    let displayName = ownerService ? `${ownerService.name} (duplicate)` : entry.label;

    // Check if this process is attached to Xcode debugger
    let isXcodeAttached = false;
    if (entry.pid) {
      const ppid = Bun.spawnSync(["ps", "-o", "ppid=", "-p", String(entry.pid)]);
      if (ppid.exitCode === 0) {
        const parentPid = ppid.stdout.toString().trim();
        const parentCmd = Bun.spawnSync(["ps", "-o", "comm=", "-p", parentPid]);
        if (parentCmd.exitCode === 0 && parentCmd.stdout.toString().includes("debugserver")) {
          displayName = ownerService ? `${ownerService.name} (Xcode)` : entry.label;
          isXcodeAttached = true;
        }
      }
    }

    statuses.push({
      name: displayName,
      status,
      pid: entry.pid,
      exitStatus: entry.status !== 0 ? entry.status : null,
      label: entry.label,
      type: entry.label.startsWith("application.") ? "app" : "launchd",
      isStale: isXcodeAttached ? false : (ownerService ? true : isStale),
    });
  }

  return statuses;
}

function statusIcon(status: ServiceStatus["status"]): string {
  switch (status) {
    case "running": return "\x1b[32m●\x1b[0m";
    case "crashed": return "\x1b[31m✗\x1b[0m";
    case "stopped": return "\x1b[33m—\x1b[0m";
    case "not_registered": return "\x1b[90m·\x1b[0m";
  }
}

function formatRelativeTime(date: Date): string {
  const now = Date.now();
  const diffMs = now - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);

  if (diffDay > 0) return `${diffDay}d ago`;
  if (diffHr > 0) return `${diffHr}h ago`;
  if (diffMin > 0) return `${diffMin}m ago`;
  return `${diffSec}s ago`;
}

/** Find the newest .swift mtime across sourceDir + shared dirs (packages/swift/, TalkieKit, etc.) */
export function getNewestSourceMtime(service: TalkieService, projectRoot: string): Date | null {
  if (!service.sourceDir) return null;

  let newest = 0;
  const dirs = [
    join(projectRoot, service.sourceDir),
    ...SHARED_SOURCE_DIRS.map(d => join(projectRoot, d)),
  ];

  for (const dir of dirs) {
    if (!existsSync(dir)) continue;
    try {
      scanSwiftFiles(dir, (mtime) => {
        if (mtime > newest) newest = mtime;
      });
    } catch {
      // ignore permission errors etc.
    }
  }

  return newest > 0 ? new Date(newest) : null;
}

function scanSwiftFiles(dir: string, onMtime: (mtime: number) => void): void {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === ".build" || entry.name === "DerivedData") continue;
      scanSwiftFiles(fullPath, onMtime);
    } else if (entry.name.endsWith(".swift")) {
      try {
        const stat = statSync(fullPath);
        onMtime(stat.mtime.getTime());
      } catch {
        // skip
      }
    }
  }
}

function getBuildInfos(projectRoot: string): BuildInfo[] {
  const infos: BuildInfo[] = [];

  for (const service of SERVICES) {
    const builds = findAllBuilds(service);

    if (builds.length === 0) {
      infos.push({ service: service.name, active: null, altCount: 0 });
      continue;
    }

    const newest = builds[0];
    const sourceMtime = getNewestSourceMtime(service, projectRoot);
    const stale = sourceMtime ? sourceMtime.getTime() > newest.mtime.getTime() : false;

    infos.push({
      service: service.name,
      active: {
        path: newest.path,
        derivedDataDir: newest.derivedDataDir,
        buildDate: newest.mtime.toISOString(),
        age: formatRelativeTime(newest.mtime),
        stale,
      },
      altCount: builds.length - 1,
    });
  }

  return infos;
}

function getDbInfo(): { path: string; size: string } | null {
  try {
    const dbPath = resolveDbPath();
    if (!existsSync(dbPath)) return null;
    const stats = statSync(dbPath);
    const mb = (stats.size / 1024 / 1024).toFixed(1);
    return { path: dbPath.replace(homedir(), "~"), size: `${mb} MB` };
  } catch {
    return null;
  }
}

// ── Diagnostics ─────────────────────────────────────────────

type DiagnosticLevel = "pass" | "warn" | "fail";

interface DiagnosticCheck {
  check: string;
  service: string;
  level: DiagnosticLevel;
  message: string;
  detail?: Record<string, unknown>;
}

function diagIcon(level: DiagnosticLevel): string {
  switch (level) {
    case "pass": return "\x1b[32m✓\x1b[0m";
    case "warn": return "\x1b[33m⚠\x1b[0m";
    case "fail": return "\x1b[31m✗\x1b[0m";
  }
}

function checkMachPorts(
  service: TalkieService,
  status: ServiceStatus
): DiagnosticCheck[] {
  if (!service.machServices) return [];
  const uid = getUid();
  const checks: DiagnosticCheck[] = [];

  for (const machName of service.machServices) {
    const label = service.launchdLabel ?? machName;
    const result = Bun.spawnSync(
      ["launchctl", "print", `gui/${uid}/${label}`],
      { stdout: "pipe", stderr: "pipe" }
    );
    const stdout = result.stdout.toString();

    if (result.exitCode !== 0) {
      checks.push({
        check: "mach_ports",
        service: service.name,
        level: status.status === "running" ? "warn" : "fail",
        message: `Mach port ${machName} not registered`,
        detail: { machService: machName, label },
      });
      continue;
    }

    // Look for "active port" in the mach-port section
    const portMatch = stdout.match(
      new RegExp(`"${machName.replace(/\./g, "\\.")}"\\s*=\\s*\\(active,\\s*port:\\s*(0x[0-9a-f]+)\\)`, "i")
    );
    if (portMatch) {
      checks.push({
        check: "mach_ports",
        service: service.name,
        level: "pass",
        message: `Mach port ${machName} active (port ${portMatch[1]})`,
        detail: { machService: machName, port: portMatch[1] },
      });
    } else {
      // Check if the port exists at all (might be inactive)
      const hasPort = stdout.includes(machName);
      checks.push({
        check: "mach_ports",
        service: service.name,
        level: hasPort ? "warn" : "fail",
        message: hasPort
          ? `Mach port ${machName} registered but inactive`
          : `Mach port ${machName} not found in service`,
        detail: { machService: machName },
      });
    }
  }

  return checks;
}

function checkProcessPath(
  service: TalkieService,
  status: ServiceStatus
): DiagnosticCheck | null {
  if (!status.pid) return null;

  const result = Bun.spawnSync(["ps", "-o", "args=", "-p", String(status.pid)]);
  if (result.exitCode !== 0) return null;

  const processPath = result.stdout.toString().trim();
  const builds = findAllBuilds(service);

  if (builds.length === 0) {
    return {
      check: "process_path",
      service: service.name,
      level: "warn",
      message: "No DerivedData build found to compare",
    };
  }

  const newestBuildDir = builds[0].path;
  // The process path should be inside the same DerivedData dir as the newest build
  const newestParent = newestBuildDir.substring(
    0,
    newestBuildDir.indexOf("/Build/Products/")
  );
  if (processPath.includes(newestParent)) {
    return {
      check: "process_path",
      service: service.name,
      level: "pass",
      message: "Process binary matches newest build",
    };
  }

  return {
    check: "process_path",
    service: service.name,
    level: "warn",
    message: "Process binary does NOT match newest build",
    detail: { processPath, newestBuild: newestBuildDir },
  };
}

function checkPlistValid(service: TalkieService): DiagnosticCheck | null {
  if (!service.launchdLabel) return null;

  const plistPath = `/tmp/${service.launchdLabel}.plist`;
  if (!existsSync(plistPath)) {
    return {
      check: "plist_valid",
      service: service.name,
      level: "warn",
      message: `Plist not found at ${plistPath}`,
    };
  }

  try {
    const contents = readFileSync(plistPath, "utf-8");

    // Verify Label key matches
    const labelMatch = contents.match(/<key>Label<\/key>\s*<string>([^<]+)<\/string>/);
    if (!labelMatch || labelMatch[1] !== service.launchdLabel) {
      return {
        check: "plist_valid",
        service: service.name,
        level: "fail",
        message: `Plist Label mismatch: expected ${service.launchdLabel}, got ${labelMatch?.[1] ?? "none"}`,
      };
    }

    // Verify MachServices key exists if service expects it
    if (service.machServices) {
      const hasMachServices = contents.includes("<key>MachServices</key>");
      if (!hasMachServices) {
        return {
          check: "plist_valid",
          service: service.name,
          level: "fail",
          message: "Plist missing MachServices key",
        };
      }
    }

    return {
      check: "plist_valid",
      service: service.name,
      level: "pass",
      message: "Plist valid",
    };
  } catch {
    return {
      check: "plist_valid",
      service: service.name,
      level: "fail",
      message: `Failed to read plist at ${plistPath}`,
    };
  }
}

function checkBridgePort(service: TalkieService): DiagnosticCheck | null {
  if (!service.bridgePort) return null;

  const result = Bun.spawnSync(
    ["nc", "-z", "-w", "1", "127.0.0.1", String(service.bridgePort)],
    { stdout: "pipe", stderr: "pipe" }
  );

  if (result.exitCode === 0) {
    return {
      check: "bridge_port",
      service: service.name,
      level: "pass",
      message: `Bridge port ${service.bridgePort} listening`,
    };
  }

  return {
    check: "bridge_port",
    service: service.name,
    level: "fail",
    message: `Bridge port ${service.bridgePort} not listening`,
    detail: { port: service.bridgePort },
  };
}

function checkBuildCurrent(
  service: TalkieService,
  buildInfo: BuildInfo
): DiagnosticCheck | null {
  if (!buildInfo.active) {
    if (service.sourceDir) {
      return {
        check: "build_current",
        service: service.name,
        level: "warn",
        message: "No build found",
      };
    }
    return null;
  }

  if (buildInfo.active.stale) {
    return {
      check: "build_current",
      service: service.name,
      level: "warn",
      message: `Build stale (${buildInfo.active.age}) — source modified since build`,
    };
  }

  return {
    check: "build_current",
    service: service.name,
    level: "pass",
    message: `Build current (${buildInfo.active.age})`,
  };
}

/** Single batched `log show` call — returns error+fault count per subsystem. */
function getRecentErrorCounts(): Map<string, number> {
  const subsystems = SERVICES.map((s) => s.logSubsystem);
  const predicate = subsystems
    .map((s) => `subsystem == "${s}"`)
    .join(" OR ");

  const result = Bun.spawnSync(
    [
      "log", "show",
      "--last", "5m",
      "--predicate", `(${predicate}) AND (messageType == error OR messageType == fault)`,
      "--style", "ndjson",
    ],
    { stdout: "pipe", stderr: "pipe" }
  );

  const counts = new Map<string, number>();
  if (result.exitCode !== 0) return counts;

  const stdout = result.stdout.toString();
  for (const line of stdout.split("\n")) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line);
      const sub = entry.subsystem as string;
      if (sub) {
        counts.set(sub, (counts.get(sub) ?? 0) + 1);
      }
    } catch {
      // not JSON — skip header/footer lines
    }
  }

  return counts;
}

function checkRecentErrors(
  service: TalkieService,
  errorCounts: Map<string, number>
): DiagnosticCheck {
  const count = errorCounts.get(service.logSubsystem) ?? 0;

  if (count === 0) {
    return {
      check: "recent_errors",
      service: service.name,
      level: "pass",
      message: "No errors in last 5m",
    };
  }

  return {
    check: "recent_errors",
    service: service.name,
    level: count >= 10 ? "fail" : "warn",
    message: `${count} error${count !== 1 ? "s" : ""} in last 5m`,
    detail: { count, subsystem: service.logSubsystem },
  };
}

function runDiagnostics(
  statuses: ServiceStatus[],
  buildInfos: BuildInfo[]
): DiagnosticCheck[] {
  const errorCounts = getRecentErrorCounts();
  const checks: DiagnosticCheck[] = [];

  for (const service of SERVICES) {
    const status = statuses.find((s) => s.name === service.name);
    const buildInfo = buildInfos.find((b) => b.service === service.name);
    if (!status) continue;

    // Only run detailed checks for services that are running or have XPC plumbing
    const isRunning = status.status === "running";

    // Mach ports — only if service uses XPC and is running
    if (isRunning && service.machServices) {
      checks.push(...checkMachPorts(service, status));
    }

    // Process path — only if running
    if (isRunning) {
      const pathCheck = checkProcessPath(service, status);
      if (pathCheck) checks.push(pathCheck);
    }

    // Plist validity — if service uses launchd
    if (service.launchdLabel) {
      const plistCheck = checkPlistValid(service);
      if (plistCheck) checks.push(plistCheck);
    }

    // Bridge port — if service has a bridge port
    if (service.bridgePort) {
      const bridgeCheck = checkBridgePort(service);
      if (bridgeCheck) checks.push(bridgeCheck);
    }

    // Build current — reuse build info
    if (buildInfo) {
      const buildCheck = checkBuildCurrent(service, buildInfo);
      if (buildCheck) checks.push(buildCheck);
    }

    // Recent errors — only if running
    if (isRunning) {
      checks.push(checkRecentErrors(service, errorCounts));
    }
  }

  return checks;
}

export function registerStatusCommand(devCmd: Command): void {
  devCmd
    .command("status")
    .description(
      "Dashboard showing service health, builds, and database.\n\n" +
      "Use when: checking what's running, diagnosing launch failures, or verifying a rebuild.\n\n" +
      "Example: talkie-dev status\n" +
      "         talkie-dev status --json"
    )
    .action((_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const statuses = getServiceStatuses();
      const staleCount = statuses.filter((s) => s.isStale).length;
      const dbInfo = getDbInfo();
      const projectRoot = getProjectRoot();
      const buildInfos = getBuildInfos(projectRoot);
      const diagnostics = runDiagnostics(statuses, buildInfos);

      if (fmt.pretty) {
        console.log("\n\x1b[1mSERVICES\x1b[0m");
        console.log("─".repeat(60));

        for (const s of statuses) {
          const icon = statusIcon(s.status);
          const name = s.name.padEnd(20);
          let detail = s.status.padEnd(12);

          if (s.pid) detail = `${s.status}`.padEnd(12) + `\x1b[90mpid ${s.pid}\x1b[0m`;
          if (s.exitStatus && s.exitStatus < 0) {
            detail = `crashed`.padEnd(12) + `\x1b[90msignal ${-s.exitStatus}\x1b[0m`;
          } else if (s.exitStatus && s.exitStatus !== 0) {
            detail = `stopped`.padEnd(12) + `\x1b[90mstatus ${s.exitStatus}\x1b[0m`;
          }

          const typeStr = s.type ? `\x1b[90m(${s.type})\x1b[0m` : "";
          const staleStr = s.isStale ? "  \x1b[33m⚠ STALE\x1b[0m" : "";

          console.log(`  ${name} ${icon} ${detail}  ${typeStr}${staleStr}`);
        }

        if (staleCount > 0) {
          console.log(`\n\x1b[33m${staleCount} stale registration${staleCount > 1 ? "s" : ""} — run \`talkie-dev clean\` to remove\x1b[0m`);
        }

        // BUILDS section
        console.log(`\n\x1b[1mBUILDS\x1b[0m`);
        console.log("─".repeat(60));

        for (const b of buildInfos) {
          const name = b.service.padEnd(20);
          if (!b.active) {
            console.log(`  ${name} \x1b[90m· no build found\x1b[0m`);
            continue;
          }

          const staleFlag = b.active.stale ? "\x1b[33m⚠ STALE\x1b[0m " : "";
          const altStr = b.altCount > 0 ? `\x1b[90m +${b.altCount} alt\x1b[0m` : "";
          // Truncate derivedDataDir to show prefix + first 8 chars of hash
          const dirParts = b.active.derivedDataDir.split("-");
          const shortDir = dirParts.length > 1
            ? `${dirParts[0]}-${dirParts.slice(1).join("-").slice(0, 8)}…`
            : b.active.derivedDataDir;

          console.log(`  ${name} ${staleFlag}\x1b[90m${b.active.age.padEnd(8)}\x1b[0m  \x1b[90m${shortDir}\x1b[0m  ${altStr}`);
        }

        // DIAGNOSTICS section
        if (diagnostics.length > 0) {
          console.log(`\n\x1b[1mDIAGNOSTICS\x1b[0m`);
          console.log("─".repeat(60));

          // Group by service
          const byService = new Map<string, DiagnosticCheck[]>();
          for (const d of diagnostics) {
            const list = byService.get(d.service) ?? [];
            list.push(d);
            byService.set(d.service, list);
          }

          for (const [serviceName, serviceChecks] of byService) {
            console.log(`  \x1b[1m${serviceName}\x1b[0m`);
            for (const c of serviceChecks) {
              console.log(`    ${diagIcon(c.level)} ${c.message}`);
            }
            console.log("");
          }

          const issueCount = diagnostics.filter(
            (d) => d.level === "fail" || d.level === "warn"
          ).length;
          if (issueCount > 0) {
            console.log(
              `\x1b[33m${issueCount} issue${issueCount !== 1 ? "s" : ""} — run \`talkie-dev logs\` for details\x1b[0m`
            );
          }
        }

        if (dbInfo) {
          console.log(`\nDatabase: ${dbInfo.path} (${dbInfo.size})`);
        }
        console.log("");
      } else {
        output({
          services: statuses,
          staleCount,
          builds: buildInfos,
          diagnostics,
          database: dbInfo,
        }, fmt);
      }
    });
}

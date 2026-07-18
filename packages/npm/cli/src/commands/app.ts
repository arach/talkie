import type { Command } from "../gunshi-command";
import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { getFormatOptions, output } from "../format";

const APP_NAME = "Talkie.app";
const APP_PATH = `/Applications/${APP_NAME}`;
const PLIST_PATH = `${APP_PATH}/Contents/Info.plist`;
const PROD_AGENT_PATH = `${APP_PATH}/Contents/Library/LoginItems/TalkieAgent.app`;
const DEV_AGENT_PATH = join(
  homedir(),
  "Applications",
  "dev",
  "Talkie",
  "TalkieAgent.app"
);
const BRIDGE_PORT = 8765;
const LOCAL_AUTH_TOKEN_FILE = join(
  homedir(),
  "Library",
  "Application Support",
  "Talkie",
  "Bridge",
  ".config",
  ".local-auth-token"
);
const COMPANION_APP_STORE_URL = "https://apps.apple.com/us/app/talkie-mobile/id6755734109";
const COMPANION_QR_IMAGE_URL = `https://api.qrserver.com/v1/create-qr-code/?size=480x480&margin=18&data=${encodeURIComponent(COMPANION_APP_STORE_URL)}`;

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";

interface PairInfo {
  publicKey: string;
  hostname: string;
  port: number;
  protocol: string;
  mode?: "pairing" | "local_dev";
  pairingReady?: boolean;
}

interface BridgeFetchResult<T> {
  host: string;
  url: string;
  data: T;
}

interface DevicesResponse {
  total: number;
  devices: { id: string; name: string; pairedAt: string; lastSeen?: string | null }[];
}

interface PendingResponse {
  pending: { deviceId: string; name: string; requestedAt: string }[];
}

interface SecurityEventRequest {
  type: string;
  severity: "info" | "notice" | "warning" | "critical";
  source: "cli";
  title: string;
  message: string;
  macName?: string;
  metadata?: Record<string, unknown>;
}

function run(args: string[]) {
  return Bun.spawnSync(args, { stdout: "pipe", stderr: "pipe" });
}

function commandOutput(args: string[]): string | null {
  const result = run(args);
  if (result.exitCode !== 0) return null;
  const value = result.stdout.toString().trim();
  return value.length > 0 ? value : null;
}

function commandExists(name: string): boolean {
  return run(["/usr/bin/env", "sh", "-lc", `command -v ${name} >/dev/null 2>&1`]).exitCode === 0;
}

function getInstalledVersion(): string | null {
  return commandOutput(["defaults", "read", PLIST_PATH, "CFBundleShortVersionString"]);
}

function getActiveCliPath(): string | null {
  return commandOutput(["/usr/bin/env", "sh", "-lc", "command -v talkie"]);
}

function getNpmGlobalBin(): string | null {
  return commandOutput(["npm", "bin", "-g"]) ?? commandOutput(["/usr/bin/env", "sh", "-lc", "npm prefix -g 2>/dev/null | sed 's#$#/bin#'"]);
}

function computerName(): string {
  return commandOutput(["scutil", "--get", "ComputerName"])
    ?? commandOutput(["hostname", "-s"])
    ?? "This Mac";
}

function openUrl(url: string): boolean {
  return run(["open", url]).exitCode === 0;
}

function renderQr(url: string): string | null {
  if (!commandExists("qrencode")) return null;
  const result = run(["qrencode", "-t", "ANSIUTF8", url]);
  if (result.exitCode !== 0) return null;
  return result.stdout.toString();
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readTailscaleCandidates(): string[] {
  const json = commandOutput(["/usr/bin/env", "sh", "-lc", "tailscale status --json 2>/dev/null || /Applications/Tailscale.app/Contents/MacOS/Tailscale status --json 2>/dev/null"]);
  const interfaceIPv4 = commandOutput(["/usr/bin/env", "sh", "-lc", "ifconfig 2>/dev/null | awk '/inet 100\\./ { print $2; exit }'"]);
  if (!json) return interfaceIPv4 ? [interfaceIPv4] : [];

  try {
    const status = JSON.parse(json) as {
      Self?: {
        DNSName?: string;
        TailscaleIPs?: string[];
      };
    };
    return [
      interfaceIPv4,
      ...(status.Self?.TailscaleIPs ?? []).filter((ip) => ip.includes(".")),
      status.Self?.DNSName?.replace(/\.$/, ""),
    ].filter((value): value is string => Boolean(value));
  } catch {
    return interfaceIPv4 ? [interfaceIPv4] : [];
  }
}

function bridgeCandidates(host?: string): string[] {
  const candidates = [
    host,
    ...readTailscaleCandidates(),
    "localhost",
  ].filter((value): value is string => Boolean(value));

  return Array.from(new Set(candidates));
}

async function bridgeFetch<T>(
  path: string,
  options: { host?: string; port?: number; method?: string; timeoutMs?: number } = {}
): Promise<BridgeFetchResult<T>> {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  const port = options.port ?? BRIDGE_PORT;
  const method = options.method ?? "GET";
  const errors: string[] = [];
  // Mac-local management routes (/devices, /pair/pending, /pair/:id/approve,
  // /pair/:id/reject) now require the local bearer token. Attach it when
  // present; the server's bootstrap/health routes ignore it, so this is safe
  // for every call. null token (file absent) => header omitted, prior behavior.
  const token = readLocalAuthToken();
  const authHeaders = token ? { Authorization: `Bearer ${token}` } : undefined;

  for (const host of bridgeCandidates(options.host)) {
    const url = `http://${host}:${port}${normalizedPath}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? 2500);

    try {
      const response = await fetch(url, { method, headers: authHeaders, signal: controller.signal });
      clearTimeout(timer);

      if (!response.ok) {
        errors.push(`${host}: HTTP ${response.status}`);
        continue;
      }

      return {
        host,
        url,
        data: (await response.json()) as T,
      };
    } catch (error) {
      clearTimeout(timer);
      errors.push(`${host}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  throw new Error(`Could not reach Talkie Bridge on port ${port}. Tried: ${errors.join("; ")}`);
}

async function bridgeFetchWithAppStart<T>(
  path: string,
  options: { host?: string; port?: number; method?: string; timeoutMs?: number } = {}
): Promise<BridgeFetchResult<T>> {
  try {
    return await bridgeFetch<T>(path, options);
  } catch (firstError) {
    if (!getInstalledVersion()) throw firstError;

    openUrl(APP_PATH);
    for (let attempt = 0; attempt < 8; attempt += 1) {
      await sleep(750);
      try {
        return await bridgeFetch<T>(path, options);
      } catch {}
    }

    throw firstError;
  }
}

function readLocalAuthToken(): string | null {
  try {
    if (!existsSync(LOCAL_AUTH_TOKEN_FILE)) return null;
    const token = readFileSync(LOCAL_AUTH_TOKEN_FILE, "utf8").trim();
    return token.length > 0 ? token : null;
  } catch {
    return null;
  }
}

async function postLocalSecurityEvent(
  event: SecurityEventRequest,
  options: { host?: string; port?: number } = {}
): Promise<void> {
  const token = readLocalAuthToken();
  if (!token) return;

  const port = options.port ?? BRIDGE_PORT;
  for (const host of bridgeCandidates(options.host)) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 1500);

    try {
      const response = await fetch(`http://${host}:${port}/security/events`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(event),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (response.ok) return;
    } catch {
      clearTimeout(timer);
    }
  }
}

function makePairPayload(info: PairInfo): string {
  return JSON.stringify({
    publicKey: info.publicKey,
    hostname: info.hostname,
    port: info.port,
    protocol: info.protocol,
    mode: info.mode,
    pairingReady: info.pairingReady,
  });
}

function pairReadinessWarning(info: PairInfo): string | null {
  if (info.mode === "local_dev" || info.pairingReady === false) {
    return "This bridge reports local dev mode, so mobile pairing will be rejected.";
  }

  if (info.hostname === "localhost") {
    return "This bridge is advertising localhost, which only works from this Mac.";
  }

  return null;
}

async function getDeviceIds(options: { host?: string; port?: number }): Promise<Set<string>> {
  const response = await bridgeFetch<DevicesResponse>("/devices", options);
  return new Set((response.data.devices ?? []).map((device) => device.id));
}

async function waitForNewDevice(
  before: Set<string>,
  options: { host?: string; port?: number; seconds: number },
  onTick?: () => void
): Promise<{ id: string; name: string } | null> {
  const deadline = Date.now() + options.seconds * 1000;

  while (Date.now() < deadline) {
    await sleep(1000);
    onTick?.();

    try {
      const response = await bridgeFetch<DevicesResponse>("/devices", options);
      const found = (response.data.devices ?? []).find((device) => !before.has(device.id));
      if (found) return { id: found.id, name: found.name };
    } catch {}
  }

  return null;
}

function checkAppRunning(): boolean {
  return run(["pgrep", "-x", "Talkie"]).exitCode === 0;
}

type AgentFlavor = "production" | "dev" | "other";

interface AgentProcess {
  pid: number;
  appPath: string | null;
  flavor: AgentFlavor;
}

interface AgentCommandOptions {
  dev?: boolean;
  production?: boolean;
  restart?: boolean;
}

interface AgentLaunchResult {
  launched: boolean;
  alreadyRunning: boolean;
  restarted: boolean;
  flavor: AgentFlavor;
  path: string;
  version: string | null;
  build: string | null;
  pids: number[];
  error?: string;
}

function agentFlavor(appPath: string | null): AgentFlavor {
  if (appPath === DEV_AGENT_PATH) return "dev";
  if (appPath === PROD_AGENT_PATH) return "production";
  return "other";
}

function agentAppPathFromCommand(command: string | null): string | null {
  if (!command) return null;
  const executableSuffix = "/Contents/MacOS/TalkieAgent";
  const suffixIndex = command.indexOf(executableSuffix);
  return suffixIndex >= 0 ? command.slice(0, suffixIndex) : null;
}

function getAgentProcesses(): AgentProcess[] {
  const result = run(["pgrep", "-x", "TalkieAgent"]);
  if (result.exitCode !== 0) return [];

  return result.stdout
    .toString()
    .trim()
    .split("\n")
    .map((value) => Number.parseInt(value, 10))
    .filter(Number.isFinite)
    .map((pid) => {
      const command = commandOutput(["ps", "-o", "command=", "-p", String(pid)]);
      const appPath = agentAppPathFromCommand(command);
      return { pid, appPath, flavor: agentFlavor(appPath) };
    });
}

function agentMetadata(appPath: string): { version: string | null; build: string | null } {
  const plistPath = `${appPath}/Contents/Info.plist`;
  return {
    version: commandOutput(["plutil", "-extract", "CFBundleShortVersionString", "raw", "-o", "-", plistPath]),
    build: commandOutput(["plutil", "-extract", "CFBundleVersion", "raw", "-o", "-", plistPath]),
  };
}

function agentBinaryModificationTime(appPath: string): number {
  try {
    return statSync(`${appPath}/Contents/MacOS/TalkieAgent`).mtimeMs;
  } catch {
    return 0;
  }
}

function compareVersionStrings(left: string | null, right: string | null): number {
  const leftParts = left?.split(".").map((part) => Number.parseInt(part, 10)) ?? [];
  const rightParts = right?.split(".").map((part) => Number.parseInt(part, 10)) ?? [];
  const count = Math.max(leftParts.length, rightParts.length);

  for (let index = 0; index < count; index += 1) {
    const difference = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

function resolveAgentPath(options: AgentCommandOptions): string | null {
  if (options.dev) return existsSync(DEV_AGENT_PATH) ? DEV_AGENT_PATH : null;
  if (options.production) return existsSync(PROD_AGENT_PATH) ? PROD_AGENT_PATH : null;

  const installed = [PROD_AGENT_PATH, DEV_AGENT_PATH].filter((path) => existsSync(path));
  installed.sort((a, b) => {
    const versionOrder = compareVersionStrings(
      agentMetadata(b).version,
      agentMetadata(a).version
    );
    return versionOrder !== 0
      ? versionOrder
      : agentBinaryModificationTime(b) - agentBinaryModificationTime(a);
  });
  return installed[0] ?? null;
}

function stopAgentProcesses(): void {
  for (const process of getAgentProcesses()) {
    run(["kill", "-TERM", String(process.pid)]);
  }

  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (getAgentProcesses().length === 0) return;
    Bun.sleepSync(100);
  }

  for (const process of getAgentProcesses()) {
    run(["kill", "-KILL", String(process.pid)]);
  }
  Bun.sleepSync(100);
}

function emitAgentLaunchResult(result: AgentLaunchResult, cmd: Command): void {
  const fmt = getFormatOptions(cmd.optsWithGlobals());

  if (fmt.pretty) {
    if (result.error) {
      console.log(`  ${YELLOW}!${RESET} ${result.error}`);
    } else if (result.alreadyRunning) {
      console.log(
        `  ${GREEN}✓${RESET} TalkieAgent is already running ${DIM}(${result.flavor}${result.version ? ` v${result.version}` : ""}, PID ${result.pids.join(", ")})${RESET}`
      );
    } else {
      const action = result.restarted ? "Restarted" : "Launched";
      console.log(
        `  ${GREEN}✓${RESET} ${action} TalkieAgent ${DIM}(${result.flavor}${result.version ? ` v${result.version}` : ""}, PID ${result.pids.join(", ")})${RESET}`
      );
    }
  } else {
    output(result, fmt);
  }

  if (result.error) process.exitCode = 1;
}

function launchAgent(options: AgentCommandOptions, cmd: Command): void {
  const running = getAgentProcesses();

  if (options.dev && options.production) {
    emitAgentLaunchResult({
      launched: false,
      alreadyRunning: false,
      restarted: false,
      flavor: "other",
      path: "",
      version: null,
      build: null,
      pids: running.map((process) => process.pid),
      error: "Choose either --dev or --production, not both.",
    }, cmd);
    return;
  }

  const appPath = resolveAgentPath(options);

  if (!appPath) {
    const error = options.dev
      ? `TalkieAgent dev build not found at ${DEV_AGENT_PATH}. Build it with apps/macos/run.sh first.`
      : options.production
        ? `Production TalkieAgent not found inside ${APP_PATH}. Run talkie install first.`
        : "TalkieAgent is not installed. Run talkie install first.";
    emitAgentLaunchResult({
      launched: false,
      alreadyRunning: false,
      restarted: false,
      flavor: options.dev ? "dev" : options.production ? "production" : "other",
      path: options.dev ? DEV_AGENT_PATH : options.production ? PROD_AGENT_PATH : "",
      version: null,
      build: null,
      pids: [],
      error,
    }, cmd);
    return;
  }

  const flavor = agentFlavor(appPath);
  const metadata = agentMetadata(appPath);
  const matching = running.filter((process) => process.appPath === appPath);
  const conflicting = running.filter((process) => process.appPath !== appPath);

  if (!options.restart && matching.length > 0 && conflicting.length === 0) {
    emitAgentLaunchResult({
      launched: false,
      alreadyRunning: true,
      restarted: false,
      flavor,
      path: appPath,
      ...metadata,
      pids: matching.map((process) => process.pid),
    }, cmd);
    return;
  }

  const replacingExistingAgent = running.length > 0;
  if (options.restart || conflicting.length > 0) stopAgentProcesses();

  const open = run(["open", "-g", appPath]);
  if (open.exitCode !== 0) {
    emitAgentLaunchResult({
      launched: false,
      alreadyRunning: false,
      restarted: options.restart === true || replacingExistingAgent,
      flavor,
      path: appPath,
      ...metadata,
      pids: [],
      error: open.stderr.toString().trim() || "macOS could not open TalkieAgent.",
    }, cmd);
    return;
  }

  let launched: AgentProcess[] = [];
  for (let attempt = 0; attempt < 30; attempt += 1) {
    launched = getAgentProcesses().filter((process) => process.appPath === appPath);
    if (launched.length > 0) break;
    Bun.sleepSync(100);
  }

  const error = launched.length === 0
    ? "macOS accepted the launch request, but TalkieAgent did not stay running."
    : undefined;
  emitAgentLaunchResult({
    launched: launched.length > 0,
    alreadyRunning: false,
    restarted: options.restart === true || replacingExistingAgent,
    flavor,
    path: appPath,
    ...metadata,
    pids: launched.map((process) => process.pid),
    error,
  }, cmd);
}

function printCheck(ok: boolean, label: string, detail?: string): void {
  const mark = ok ? `${GREEN}✓${RESET}` : `${YELLOW}!${RESET}`;
  const suffix = detail ? ` ${DIM}${detail}${RESET}` : "";
  console.log(`  ${mark} ${label}${suffix}`);
}

function registerOpenCommand(program: Command): void {
  program
    .command("open [target]")
    .description("Open Talkie.app, or use `talkie open agent` for TalkieAgent")
    .option("--dev", "open the stable local TalkieAgent development build")
    .option("--production", "open the TalkieAgent embedded in /Applications/Talkie.app")
    .option("--restart", "restart TalkieAgent before opening it")
    .action((target: string | undefined, opts: AgentCommandOptions, cmd) => {
      const normalizedTarget = target?.toLowerCase();
      if (normalizedTarget === "agent" || normalizedTarget === "talkieagent") {
        launchAgent(opts, cmd);
        return;
      }

      const fmt = getFormatOptions(cmd.optsWithGlobals());
      if (normalizedTarget && normalizedTarget !== "app" && normalizedTarget !== "talkie") {
        const error = `Unknown app target: ${target}. Available: app, agent`;
        if (fmt.pretty) console.log(`  ${YELLOW}!${RESET} ${error}`);
        else output({ opened: false, target, error }, fmt);
        process.exitCode = 1;
        return;
      }
      if (opts.dev || opts.production || opts.restart) {
        const error = "--dev, --production, and --restart are only supported with `talkie open agent`.";
        if (fmt.pretty) console.log(`  ${YELLOW}!${RESET} ${error}`);
        else output({ opened: false, target: "app", error }, fmt);
        process.exitCode = 1;
        return;
      }

      const installed = getInstalledVersion();
      const ok = installed ? openUrl(APP_PATH) : false;

      if (fmt.pretty) {
        if (ok) {
          console.log(`  ${GREEN}✓${RESET} Opened Talkie.app ${DIM}${installed}${RESET}`);
        } else {
          console.log(`  ${YELLOW}!${RESET} Talkie.app is not installed yet`);
          console.log(`    Run ${CYAN}talkie install${RESET} or ${CYAN}npx @talkie/app${RESET}`);
        }
      } else {
        output({ opened: ok, installedVersion: installed, path: APP_PATH }, fmt);
      }

      if (!ok) process.exit(1);
    });
}

function registerAgentCommand(program: Command): void {
  program
    .command("agent")
    .description("Launch TalkieAgent without opening the main Talkie window")
    .option("--dev", "launch the stable local development build")
    .option("--production", "launch the helper embedded in /Applications/Talkie.app")
    .option("--restart", "restart all running TalkieAgent instances before launch")
    .action((opts: AgentCommandOptions, cmd) => launchAgent(opts, cmd));
}

function registerProCommand(program: Command): void {
  const PRO_URL = "talkie://onboarding/pro";

  program
    .command("pro")
    .description("Launch Pro Tools onboarding in Talkie.app")
    .action((_opts, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const installed = getInstalledVersion();

      if (!installed) {
        if (fmt.pretty) {
          console.log(`  ${YELLOW}!${RESET} Talkie.app is not installed yet`);
          console.log(`    Run ${CYAN}talkie install${RESET} or ${CYAN}npx @talkie/app${RESET}`);
        } else {
          output({ opened: false, installedVersion: null, url: PRO_URL }, fmt);
        }
        process.exit(1);
      }

      const ok = openUrl(PRO_URL);

      if (fmt.pretty) {
        if (ok) {
          console.log(`  ${GREEN}✓${RESET} Launched Pro Tools onboarding ${DIM}(${installed})${RESET}`);
        } else {
          console.log(`  ${YELLOW}!${RESET} Failed to open ${PRO_URL}`);
        }
      } else {
        output({ opened: ok, installedVersion: installed, url: PRO_URL }, fmt);
      }

      if (!ok) process.exit(1);
    });
}

function registerWhereCommand(program: Command): void {
  program
    .command("where")
    .description("Show Talkie app, CLI, and data locations")
    .action((_opts, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const activeCli = getActiveCliPath();
      const npmGlobalBin = getNpmGlobalBin();
      const installedVersion = getInstalledVersion();
      const dataPath = `${process.env.HOME ?? "~"}/Library/Containers/jdi.Talkie/Data/Library/Application Support/Talkie`;

      if (fmt.pretty) {
        console.log(`${BOLD}Talkie locations${RESET}\n`);
        console.log(`  app:      ${APP_PATH}${installedVersion ? ` ${DIM}(${installedVersion})${RESET}` : ` ${DIM}(not installed)${RESET}`}`);
        console.log(`  cli:      ${activeCli ?? `${DIM}not found on PATH${RESET}`}`);
        console.log(`  npm bin:  ${npmGlobalBin ?? `${DIM}not found${RESET}`}`);
        console.log(`  data:     ${dataPath}`);
      } else {
        output({ appPath: APP_PATH, installedVersion, activeCli, npmGlobalBin, dataPath }, fmt);
      }
    });
}

const TALKIE_APP_HTTP_PORT = 8766;

interface DoctorPermissionSlot {
  microphone: string;
  accessibility: string;
  inputMonitoring: string;
  screenRecording: string;
}

interface DoctorStatus {
  version: string;
  permissions: { talkie: DoctorPermissionSlot; agent: DoctorPermissionSlot };
  services: { talkie: string; agent: string; sync: string; talkieServer: string };
  proTools: { active: boolean; prerequisites: { bun: boolean; serverSource: boolean; dependencies: boolean; tailscale: boolean } };
}

const SYSTEM_SETTINGS_URL: Record<keyof DoctorPermissionSlot, string> = {
  microphone: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
  accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
  inputMonitoring: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
  screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
};

const PERMISSION_LABEL: Record<keyof DoctorPermissionSlot, string> = {
  microphone: "Microphone",
  accessibility: "Accessibility",
  inputMonitoring: "Input Monitoring",
  screenRecording: "Screen Recording",
};

function permissionGlyph(status: string): string {
  switch (status) {
    case "granted": return `${GREEN}✓${RESET}`;
    case "denied": return `${YELLOW}✗${RESET}`;
    case "notDetermined": return `${DIM}·${RESET}`;
    default: return `${DIM}—${RESET}`;
  }
}

function serviceGlyph(state: string): string {
  switch (state) {
    case "running": return `${GREEN}●${RESET}`;
    case "starting": return `${YELLOW}◐${RESET}`;
    case "stopped": return `${DIM}○${RESET}`;
    case "degraded": return `${YELLOW}◐${RESET}`;
    case "error": return `${YELLOW}✗${RESET}`;
    default: return `${DIM}—${RESET}`;
  }
}

async function fetchDoctorStatus(): Promise<DoctorStatus | null> {
  try {
    const result = await bridgeFetch<DoctorStatus>("/doctor", { port: TALKIE_APP_HTTP_PORT, timeoutMs: 1500 });
    return result.data;
  } catch {
    return null;
  }
}

function registerDoctorCommand(program: Command): void {
  program
    .command("doctor")
    .description("Check Talkie installation, permissions, services, and Pro Tools")
    .action(async (_opts, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const installedVersion = getInstalledVersion();
      const activeCli = getActiveCliPath();
      const npmGlobalBin = getNpmGlobalBin();
      const bunVersion = commandOutput(["bun", "--version"]);
      const qrReady = commandExists("qrencode");
      const appRunning = checkAppRunning();
      const shadowedByBun = activeCli?.includes("/.bun/bin/") === true && npmGlobalBin != null;

      const doctorStatus = appRunning ? await fetchDoctorStatus() : null;

      if (fmt.pretty) {
        console.log();
        console.log(`  ${BOLD}Talkie doctor${RESET}`);
        console.log();

        // App & CLI
        console.log(`  ${BOLD}App & CLI${RESET}`);
        printCheck(installedVersion != null, "Talkie.app installed", installedVersion ?? `run ${CYAN}talkie install${RESET}`);
        printCheck(appRunning, "Talkie.app running", appRunning ? undefined : `run ${CYAN}talkie open${RESET}`);
        printCheck(activeCli != null, "talkie command on PATH", activeCli ?? "not found on PATH");
        printCheck(bunVersion != null, "Bun runtime", bunVersion ?? `install: ${CYAN}curl -fsSL https://bun.sh/install | bash${RESET}`);
        printCheck(qrReady, "QR support", qrReady ? "qrencode" : `optional: ${CYAN}brew install qrencode${RESET}`);

        if (shadowedByBun) {
          console.log();
          console.log(`  ${YELLOW}!${RESET} talkie is the Bun-linked dev build: ${DIM}${activeCli}${RESET}`);
          console.log(`    ${DIM}npm users may expect ${npmGlobalBin}/talkie.${RESET}`);
        }

        // Permissions
        console.log();
        const permKeys = Object.keys(PERMISSION_LABEL) as (keyof DoctorPermissionSlot)[];
        const permColWidth = Math.max(...permKeys.map((k) => PERMISSION_LABEL[k].length)) + 4;
        const permHeader = "Permissions".padEnd(permColWidth);
        console.log(`  ${BOLD}${permHeader}${RESET}${DIM}Talkie    Agent${RESET}`);
        if (doctorStatus) {
          permKeys.forEach((key) => {
            const label = PERMISSION_LABEL[key].padEnd(permColWidth);
            const t = permissionGlyph(doctorStatus.permissions.talkie[key]);
            const a = permissionGlyph(doctorStatus.permissions.agent[key]);
            const agentStatus = doctorStatus.permissions.agent[key];
            const fix = (agentStatus === "denied" || agentStatus === "notDetermined")
              ? `   ${DIM}→ System Settings › ${PERMISSION_LABEL[key]}${RESET}`
              : "";
            console.log(`  ${label}${t}         ${a}${fix}`);
          });
        } else {
          console.log(`  ${DIM}unavailable — Talkie.app must be running to query permissions${RESET}`);
        }

        // Services
        console.log();
        console.log(`  ${BOLD}Services${RESET}`);
        if (doctorStatus) {
          const svcs: [string, string][] = [
            ["Talkie", doctorStatus.services.talkie],
            ["TalkieAgent", doctorStatus.services.agent],
            ["TalkieSync", doctorStatus.services.sync],
            ["TalkieServer", doctorStatus.services.talkieServer],
          ];
          svcs.forEach(([name, state]) => {
            console.log(`  ${serviceGlyph(state)} ${name.padEnd(15)} ${DIM}${state}${RESET}`);
          });
        } else {
          console.log(`  ${DIM}unavailable — start Talkie.app: ${CYAN}talkie open${RESET}`);
        }

        // Pro Tools
        console.log();
        console.log(`  ${BOLD}Pro Tools${RESET}`);
        if (doctorStatus) {
          const pro = doctorStatus.proTools;
          printCheck(pro.active, "activated", pro.active ? undefined : `run ${CYAN}talkie pro${RESET}`);
          printCheck(pro.prerequisites.bun, "Bun runtime");
          printCheck(pro.prerequisites.serverSource, "local TalkieServer source");
          printCheck(pro.prerequisites.dependencies, "dependencies installed");
          if (pro.prerequisites.tailscale) {
            printCheck(true, "Tailscale");
          }
        } else {
          console.log(`  ${DIM}unavailable${RESET}`);
        }

        console.log();
      } else {
        output(
          {
            appPath: APP_PATH,
            installedVersion,
            appRunning,
            activeCli,
            npmGlobalBin,
            bunVersion,
            qrReady,
            bridgePort: BRIDGE_PORT,
            talkieAppHttpPort: TALKIE_APP_HTTP_PORT,
            doctor: doctorStatus,
            warnings: shadowedByBun ? ["active_talkie_command_is_bun_linked"] : [],
          },
          fmt
        );
      }
    });
}

function registerPairCommand(program: Command): void {
  const pairCommand = program
    .command("pair")
    .description("Pair an iPhone or iPad with this Mac Bridge")
    .option("--host <host>", "override the local bridge host to contact")
    .option("--port <port>", "override the bridge port", (value) => parseInt(value, 10), BRIDGE_PORT)
    .option("--payload", "print only the raw Talkie Bridge QR payload")
    .option("--no-qr", "skip terminal QR rendering")
    .option("--wait [seconds]", "wait for a newly paired device", (value) => typeof value === "string" ? parseInt(value, 10) : 60)
    .action(async (opts: { host?: string; port?: number; payload?: boolean; qr?: boolean; wait?: number | true }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const port = opts.port ?? BRIDGE_PORT;
      const before = opts.wait ? await getDeviceIds({ host: opts.host, port }).catch(() => new Set<string>()) : new Set<string>();
      const response = await bridgeFetchWithAppStart<PairInfo>("/pair/info", { host: opts.host, port });
      const payload = makePairPayload(response.data);
      const qr = opts.qr === false || opts.payload ? null : renderQr(payload);
      const warning = pairReadinessWarning(response.data);

      await postLocalSecurityEvent({
        type: "bridge_pair_payload_created",
        severity: "notice",
        source: "cli",
        title: "Mac Bridge pairing QR created",
        message: "A Talkie Mac Bridge pairing QR was created from the CLI.",
        macName: computerName(),
        metadata: {
          advertisedHostname: response.data.hostname,
          advertisedPort: response.data.port,
          bridgeMode: response.data.mode,
          pairingReady: response.data.pairingReady,
          sourceUrl: response.url,
        },
      }, { host: response.host, port });

      if (opts.payload) {
        console.log(payload);
        return;
      }

      if (fmt.pretty) {
        console.log(`${BOLD}Talkie Mac Bridge pairing${RESET}`);
        console.log(`${DIM}Scan this from Talkie on iPhone or iPad to pair with this Mac.${RESET}\n`);

        if (warning) {
          console.log(`  ${YELLOW}!${RESET} ${warning}`);
          console.log(`    Try restarting Mac Bridge from Talkie settings, then run ${CYAN}talkie pair${RESET} again.\n`);
        }

        if (qr) {
          console.log(qr.trimEnd());
          console.log();
        } else {
          const reason = opts.qr === false
            ? "Terminal QR rendering skipped"
            : `Terminal QR renderer not found ${DIM}(optional: brew install qrencode)${RESET}`;
          console.log(`  ${YELLOW}!${RESET} ${reason}`);
          console.log(`  Raw payload: ${CYAN}talkie pair --payload${RESET}`);
          console.log(`  Copy it:     ${CYAN}talkie pair --payload | pbcopy${RESET}\n`);
        }

        console.log(`  Bridge: ${CYAN}${response.data.hostname}:${response.data.port}${RESET}`);
        console.log(`  Mode:   ${response.data.mode ?? "unknown"}`);
        console.log(`  Source: ${DIM}${response.url}${RESET}`);
        console.log();
        console.log(`  On iPhone/iPad: Talkie → Settings → Mac Bridge → Scan QR Code`);
        console.log(`  After pairing:  ${CYAN}talkie terminal pair${RESET}`);

        if (opts.wait) {
          const seconds = opts.wait === true ? 60 : opts.wait;
          process.stdout.write(`\n  Waiting for a new paired device (${seconds}s)...`);
          const paired = await waitForNewDevice(before, { host: opts.host, port, seconds }, () => {
            process.stdout.write(".");
          });
          process.stdout.write("\n");

          if (paired) {
            console.log(`  ${GREEN}✓${RESET} Paired ${paired.name}`);
            console.log(`  Next: ${CYAN}talkie terminal pair${RESET}`);
          } else {
            console.log(`  ${YELLOW}!${RESET} No new device paired yet`);
            console.log(`    Check pending requests with ${CYAN}talkie pair pending${RESET}`);
          }
        }
      } else {
        output(
          {
            bridgeUrl: response.url,
            payload,
            qrRendered: qr != null,
            pairingReady: response.data.pairingReady,
            mode: response.data.mode,
            hostname: response.data.hostname,
            port: response.data.port,
            warning,
          },
          fmt
        );
      }
    });

  pairCommand
    .command("pending")
    .description("List pending Mac Bridge pairing requests")
    .option("--host <host>", "override the local bridge host to contact")
    .option("--port <port>", "override the bridge port", (value) => parseInt(value, 10), BRIDGE_PORT)
    .action(async (opts: { host?: string; port?: number }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const response = await bridgeFetchWithAppStart<PendingResponse>("/pair/pending", opts);

      if (fmt.pretty) {
        if (response.data.pending.length === 0) {
          console.log(`  ${DIM}No pending pairing requests${RESET}`);
          return;
        }

        console.log(`${BOLD}Pending pairings${RESET}\n`);
        for (const request of response.data.pending) {
          console.log(`  ${request.name}`);
          console.log(`    id: ${request.deviceId}`);
          console.log(`    requested: ${request.requestedAt}`);
          console.log(`    approve: ${CYAN}talkie pair approve ${request.deviceId}${RESET}`);
        }
      } else {
        output(response.data, fmt);
      }
    });

  pairCommand
    .command("approve <deviceId>")
    .description("Approve a pending Mac Bridge pairing request")
    .option("--host <host>", "override the local bridge host to contact")
    .option("--port <port>", "override the bridge port", (value) => parseInt(value, 10), BRIDGE_PORT)
    .action(async (deviceId: string, opts: { host?: string; port?: number }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const response = await bridgeFetchWithAppStart<{ status: string; device?: { id: string; name: string; pairedAt: string } }>(
        `/pair/${encodeURIComponent(deviceId)}/approve`,
        { ...opts, method: "POST" }
      );

      if (fmt.pretty) {
        console.log(`  ${GREEN}✓${RESET} Approved ${response.data.device?.name ?? deviceId}`);
      } else {
        output(response.data, fmt);
      }
    });

  pairCommand
    .command("reject <deviceId>")
    .description("Reject a pending Mac Bridge pairing request")
    .option("--host <host>", "override the local bridge host to contact")
    .option("--port <port>", "override the bridge port", (value) => parseInt(value, 10), BRIDGE_PORT)
    .action(async (deviceId: string, opts: { host?: string; port?: number }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const response = await bridgeFetchWithAppStart<{ status: string }>(
        `/pair/${encodeURIComponent(deviceId)}/reject`,
        { ...opts, method: "POST" }
      );

      if (fmt.pretty) {
        console.log(`  ${GREEN}✓${RESET} Rejected ${deviceId}`);
      } else {
        output(response.data, fmt);
      }
    });
}

function registerCompanionCommand(program: Command): void {
  program
    .command("companion")
    .alias("barcode")
    .description("Show the iPhone/iPad companion App Store QR code")
    .option("--open", "open the App Store page on this Mac")
    .option("--image", "open a QR image in the browser")
    .option("--url", "print only the App Store URL")
    .option("--qr-url", "print only the QR image URL")
    .option("--no-qr", "skip terminal QR rendering")
    .action((opts: { open?: boolean; image?: boolean; url?: boolean; qrUrl?: boolean; qr?: boolean }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const opened = opts.open === true ? openUrl(COMPANION_APP_STORE_URL) : false;
      const openedQr = opts.image === true ? openUrl(COMPANION_QR_IMAGE_URL) : false;
      const qr = opts.qr === false || opts.url || opts.qrUrl ? null : renderQr(COMPANION_APP_STORE_URL);

      if (opts.url) {
        console.log(COMPANION_APP_STORE_URL);
        return;
      }
      if (opts.qrUrl) {
        console.log(COMPANION_QR_IMAGE_URL);
        return;
      }

      if (fmt.pretty) {
        console.log(`${BOLD}Talkie companion${RESET}`);
        console.log(`${DIM}Install the iPhone/iPad app, then pair it from Talkie on your Mac.${RESET}\n`);

        if (qr) {
          console.log(qr.trimEnd());
          console.log();
        } else {
          console.log(`  ${YELLOW}!${RESET} QR renderer not found ${DIM}(optional: brew install qrencode)${RESET}`);
          console.log(`  QR image:  ${CYAN}${COMPANION_QR_IMAGE_URL}${RESET}`);
        }

        console.log(`  App Store: ${CYAN}${COMPANION_APP_STORE_URL}${RESET}`);
        console.log(`  Open now:  ${CYAN}talkie companion --open${RESET}`);
        console.log(`  Open QR:   ${CYAN}talkie companion --image${RESET}`);
        if (opened) console.log(`  ${GREEN}✓${RESET} Opened App Store page`);
        if (openedQr) console.log(`  ${GREEN}✓${RESET} Opened QR image`);
      } else {
        output(
          {
            appStoreUrl: COMPANION_APP_STORE_URL,
            qrImageUrl: COMPANION_QR_IMAGE_URL,
            qrRendered: qr != null,
            opened,
            openedQr,
          },
          fmt
        );
      }
    });
}

export function registerAppCommand(program: Command): void {
  registerOpenCommand(program);
  registerAgentCommand(program);
  registerProCommand(program);
  registerWhereCommand(program);
  registerDoctorCommand(program);
  registerPairCommand(program);
  registerCompanionCommand(program);
}

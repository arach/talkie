import type { Command } from "commander";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { getFormatOptions, output } from "../format";

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";

const HOME = homedir();
const BRIDGE_PORT = 8765;
const LOCAL_AUTH_TOKEN_FILE = join(
  HOME,
  "Library",
  "Application Support",
  "Talkie",
  "Bridge",
  ".config",
  ".local-auth-token"
);
const KEY_DIR = join(HOME, "Library", "Application Support", "Talkie", "SSH");
const KEY_PATH = join(KEY_DIR, "iphone-terminal-ed25519");
const PUBLIC_KEY_PATH = `${KEY_PATH}.pub`;
const SSH_DIR = join(HOME, ".ssh");
const AUTHORIZED_KEYS_PATH = join(SSH_DIR, "authorized_keys");
const REMOTE_HELPER_DIR = join(HOME, ".talkie-shell");
const REMOTE_HELPER_BIN_DIR = join(REMOTE_HELPER_DIR, "bin");
const REMOTE_HELPER_RUNTIME_DIR = join(REMOTE_HELPER_DIR, "runtime");
const REMOTE_HELPER_RUNTIME_BIN_DIR = join(REMOTE_HELPER_RUNTIME_DIR, "bin");
const REMOTE_HELPER_COMPANION_ENTRYPOINT = join(
  REMOTE_HELPER_RUNTIME_DIR,
  "lib",
  "node_modules",
  "@talkie",
  "companion",
  "src",
  "index.js"
);
const REMOTE_HELPER_COMPANION_EXECUTABLE = join(REMOTE_HELPER_RUNTIME_BIN_DIR, "talkie-companion");
const REMOTE_HELPER_SHELL_PATH = "$HOME/.talkie-shell/bin:$HOME/.talkie-shell/runtime/bin:$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
const TOOL_PATH = `${HOME}/bin:${HOME}/.local/bin:${HOME}/.opencode/bin:${HOME}/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin`;

interface TerminalStatus {
  label: string;
  keyPath: string;
  publicKeyPath: string;
  authorizedKeysPath: string;
  hasKeyPair: boolean;
  isAuthorized: boolean;
  fingerprint: string | null;
  remoteLogin: "enabled" | "disabled" | "unknown";
}

interface PreparedTerminalAccess {
  status: TerminalStatus;
  payload: string;
  link: string;
  connection: TerminalConnection | null;
}

interface TerminalConnection {
  host: string;
  port: number;
  username: string;
  startupProfileRawValue: string;
  launcherModeRawValue: string;
  autoConnect: boolean;
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

function run(args: string[], options: { env?: Record<string, string>; timeout?: number } = {}) {
  return Bun.spawnSync(args, {
    stdout: "pipe",
    stderr: "pipe",
    env: options.env ? { ...process.env, ...options.env } : undefined,
    timeout: options.timeout,
  });
}

function commandOutput(command: string): string | null {
  const result = run(["/usr/bin/env", "zsh", "-lc", command]);
  if (result.exitCode !== 0) return null;
  const value = result.stdout.toString().trim();
  return value.length > 0 ? value : null;
}

function commandPath(name: string): string | null {
  return commandOutput(`command -v ${name} 2>/dev/null || true`);
}

function computerName(): string {
  return commandOutput("scutil --get ComputerName 2>/dev/null")
    ?? commandOutput("hostname -s 2>/dev/null")
    ?? "This Mac";
}

function currentUsername(): string {
  return commandOutput("id -un 2>/dev/null") ?? process.env.USER ?? "user";
}

function label(): string {
  return `Talkie SSH for ${computerName()}`;
}

function hostToken(): string {
  return computerName()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    || "mac";
}

function ensureDirectory(path: string, permissions: number): void {
  mkdirSync(path, { recursive: true });
  chmodSync(path, permissions);
}

function readNonEmpty(path: string): string {
  const value = readFileSync(path, "utf8").trim();
  if (!value) throw new Error(`${path} is empty`);
  return value;
}

function ensureKeyPair(): void {
  ensureDirectory(KEY_DIR, 0o700);

  const hasPrivateKey = existsSync(KEY_PATH);
  const hasPublicKey = existsSync(PUBLIC_KEY_PATH);

  if (hasPrivateKey && hasPublicKey) {
    chmodSync(KEY_PATH, 0o600);
    chmodSync(PUBLIC_KEY_PATH, 0o644);
    return;
  }

  if (hasPrivateKey) rmSync(KEY_PATH, { force: true });
  if (hasPublicKey) rmSync(PUBLIC_KEY_PATH, { force: true });

  const result = run([
    "/usr/bin/ssh-keygen",
    "-q",
    "-t", "ed25519",
    "-N", "",
    "-C", `talkie-iphone-${hostToken()}`,
    "-f", KEY_PATH,
  ]);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr.toString().trim() || "ssh-keygen failed");
  }

  chmodSync(KEY_PATH, 0o600);
  chmodSync(PUBLIC_KEY_PATH, 0o644);
}

function ensureAuthorizedKey(publicKey: string): void {
  ensureDirectory(SSH_DIR, 0o700);
  const normalized = publicKey.trim();
  const lines = existsSync(AUTHORIZED_KEYS_PATH)
    ? readFileSync(AUTHORIZED_KEYS_PATH, "utf8")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
    : [];

  if (!lines.includes(normalized)) {
    lines.push(normalized);
    writeFileSync(AUTHORIZED_KEYS_PATH, `${lines.join("\n")}\n`, "utf8");
  }

  chmodSync(AUTHORIZED_KEYS_PATH, 0o600);
}

function isAuthorized(publicKey: string): boolean {
  if (!existsSync(AUTHORIZED_KEYS_PATH)) return false;
  const normalized = publicKey.trim();
  return readFileSync(AUTHORIZED_KEYS_PATH, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .includes(normalized);
}

function fingerprint(): string | null {
  if (!existsSync(PUBLIC_KEY_PATH)) return null;
  const result = run(["/usr/bin/ssh-keygen", "-lf", PUBLIC_KEY_PATH]);
  if (result.exitCode !== 0) return null;
  return result.stdout.toString().trim() || null;
}

function remoteLoginStatus(): "enabled" | "disabled" | "unknown" {
  const nc = run(["/usr/bin/nc", "-z", "localhost", "22"], { timeout: 2000 });
  if (nc.exitCode === 0) return "enabled";
  if (nc.exitCode === 1) return "disabled";
  return "unknown";
}

function currentStatus(): TerminalStatus {
  const hasKeyPair = existsSync(KEY_PATH) && existsSync(PUBLIC_KEY_PATH);
  const publicKey = hasKeyPair ? readNonEmpty(PUBLIC_KEY_PATH) : null;

  return {
    label: label(),
    keyPath: KEY_PATH,
    publicKeyPath: PUBLIC_KEY_PATH,
    authorizedKeysPath: AUTHORIZED_KEYS_PATH,
    hasKeyPair,
    isAuthorized: publicKey ? isAuthorized(publicKey) : false,
    fingerprint: hasKeyPair ? fingerprint() : null,
    remoteLogin: remoteLoginStatus(),
  };
}

function remoteCompanionBootstrap(command: string): string {
  return `TALKIE_COMPANION="$HOME/.talkie-shell/runtime/bin/talkie-companion"
TALKIE_COMPANION_ENTRY="$HOME/.talkie-shell/runtime/lib/node_modules/@talkie/companion/src/index.js"
if [[ -x "$TALKIE_COMPANION" ]]; then
  exec "$TALKIE_COMPANION" ${command} "$@"
fi
if [[ -f "$TALKIE_COMPANION_ENTRY" ]]; then
  if command -v bun >/dev/null 2>&1; then
    exec "$(command -v bun)" "$TALKIE_COMPANION_ENTRY" ${command} "$@"
  fi
  if command -v node >/dev/null 2>&1; then
    exec "$(command -v node)" "$TALKIE_COMPANION_ENTRY" ${command} "$@"
  fi
fi`;
}

function writeExecutable(path: string, script: string): void {
  writeFileSync(path, script, "utf8");
  chmodSync(path, 0o755);
}

function helperScript(command: "shell" | "session" | "enter" | "menu"): string {
  if (command === "menu") {
    return `#!/bin/zsh
export PATH="${REMOTE_HELPER_SHELL_PATH}"
[[ -n "\${TERM:-}" && "\${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "\${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="\${TALKIE_SURFACE:-phone}"
${remoteCompanionBootstrap("menu")}

clear
HOST_LABEL="$(scutil --get ComputerName 2>/dev/null || hostname -s || printf 'your Mac')"
printf 'Welcome to %s\\n' "$HOST_LABEL"
printf 'You are in %s\\n\\n' "$HOME"
printf '1. OpenCode\\n'
printf '2. Claude Code\\n'
printf '3. Shell\\n\\n'
printf 'Choose an option and press Return: '
IFS= read -r choice
case "$choice" in
  1)
    if command -v opencode >/dev/null 2>&1; then exec opencode; fi
    printf '\\nOpenCode is not installed. Staying in the shell.\\n\\n'
    ;;
  2)
    if command -v claude >/dev/null 2>&1; then exec claude; fi
    printf '\\nClaude Code is not installed. Staying in the shell.\\n\\n'
    ;;
  3|'') printf '\\n' ;;
  *) printf '\\nUnknown option. Staying in the shell.\\n\\n' ;;
esac
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
`;
  }

  return `#!/bin/zsh
export PATH="${REMOTE_HELPER_SHELL_PATH}"
[[ -n "\${TERM:-}" && "\${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "\${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="\${TALKIE_SURFACE:-phone}"
${remoteCompanionBootstrap(command)}
printf '\\r\\n[Talkie] Remote companion is missing on this Mac. Opening a plain shell.\\r\\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
`;
}

function installRemoteCompanionIfAvailable(): void {
  const packagePath = findCompanionPackage();
  const npmPath = commandPath("npm");
  if (!packagePath || !npmPath) return;

  const npmDir = dirname(npmPath);
  const nodePath = commandPath("node");
  const bunPath = commandPath("bun");
  const extraPath = [bunPath && dirname(bunPath), nodePath && dirname(nodePath), npmDir, TOOL_PATH]
    .filter(Boolean)
    .join(":");

  run(
    [
      npmPath,
      "install",
      "--foreground-scripts",
      "--no-audit",
      "--no-fund",
      "--force",
      "--global",
      "--prefix", REMOTE_HELPER_RUNTIME_DIR,
      packagePath,
    ],
    { env: { HOME, PATH: extraPath } }
  );

  if (!existsSync(REMOTE_HELPER_COMPANION_ENTRYPOINT)) return;

  const bunLaunch = bunPath
    ? `if [[ -x "${bunPath}" ]]; then exec "${bunPath}" "${REMOTE_HELPER_COMPANION_ENTRYPOINT}" "$@"; fi`
    : "";
  const nodeLaunch = nodePath
    ? `if [[ -x "${nodePath}" ]]; then exec "${nodePath}" "${REMOTE_HELPER_COMPANION_ENTRYPOINT}" "$@"; fi`
    : "";

  writeExecutable(REMOTE_HELPER_COMPANION_EXECUTABLE, `#!/bin/zsh
${bunLaunch}
${nodeLaunch}
printf '\\r\\n[Talkie] Remote companion runtime is missing on this Mac.\\r\\n'
exit 1
`);
}

function findCompanionPackage(): string | null {
  let current = resolve(process.cwd());

  while (true) {
    const candidate = join(current, "companion");
    if (existsSync(join(candidate, "package.json"))) {
      return candidate;
    }

    const parent = dirname(current);
    if (parent === current) return null;
    current = parent;
  }
}

function ensureRemoteHelperInstalled(): void {
  ensureDirectory(REMOTE_HELPER_DIR, 0o700);
  ensureDirectory(REMOTE_HELPER_BIN_DIR, 0o700);
  ensureDirectory(REMOTE_HELPER_RUNTIME_DIR, 0o700);
  ensureDirectory(REMOTE_HELPER_RUNTIME_BIN_DIR, 0o700);

  installRemoteCompanionIfAvailable();

  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-shell"), helperScript("shell"));
  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-session"), helperScript("session"));
  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-enter"), helperScript("enter"));
  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-home"), helperScript("menu"));
  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-clean"), `#!/bin/zsh
HELPER="$HOME/.talkie-shell/bin/talkie-shell"
if [[ -x "$HELPER" ]]; then exec "$HELPER" "$@"; fi
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
`);
  writeExecutable(join(REMOTE_HELPER_BIN_DIR, "talkie-context"), `#!/bin/zsh
HELPER="$HOME/.talkie-shell/bin/talkie-session"
if [[ -x "$HELPER" ]]; then exec "$HELPER" "$@"; fi
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
`);
}

function tailscaleHost(): string | null {
  const json = commandOutput("tailscale status --json 2>/dev/null || /Applications/Tailscale.app/Contents/MacOS/Tailscale status --json 2>/dev/null");
  if (json) {
    try {
      const status = JSON.parse(json) as { Self?: { DNSName?: string; TailscaleIPs?: string[] } };
      return status.Self?.DNSName?.replace(/\.$/, "")
        ?? status.Self?.TailscaleIPs?.find((ip) => ip.includes("."))
        ?? null;
    } catch {}
  }

  return commandOutput("ifconfig 2>/dev/null | awk '/inet 100\\./ { print $2; exit }'");
}

function bridgeCandidates(): string[] {
  return Array.from(new Set([
    tailscaleHost(),
    "localhost",
  ].filter((value): value is string => Boolean(value))));
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

async function postLocalSecurityEvent(event: SecurityEventRequest): Promise<void> {
  const token = readLocalAuthToken();
  if (!token) return;

  for (const host of bridgeCandidates()) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 1500);

    try {
      const response = await fetch(`http://${host}:${BRIDGE_PORT}/security/events`, {
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

function buildConnection(options: { host?: string; port?: number; username?: string }): TerminalConnection | null {
  const host = options.host?.trim() || tailscaleHost();
  if (!host) return null;

  return {
    host,
    port: options.port ?? 22,
    username: options.username?.trim() || currentUsername(),
    startupProfileRawValue: "cleanShell",
    launcherModeRawValue: "pairedHome",
    autoConnect: true,
  };
}

function makePayload(privateKey: string, connection: TerminalConnection | null): string {
  return JSON.stringify({
    protocol: "talkie-ssh-key-v2",
    label: label(),
    privateKey,
    connection,
  });
}

function makeImportLink(payload: string): string {
  const params = new URLSearchParams({ payload });
  return `talkie://ssh/import-key?${params.toString()}`;
}

function renderQr(value: string): string | null {
  if (!commandPath("qrencode")) return null;
  const result = run(["qrencode", "-t", "ANSIUTF8", value]);
  if (result.exitCode !== 0) return null;
  return result.stdout.toString();
}

function prepareTerminalAccess(options: {
  host?: string;
  port?: number;
  username?: string;
  installHelper?: boolean;
}): PreparedTerminalAccess {
  ensureKeyPair();
  const publicKey = readNonEmpty(PUBLIC_KEY_PATH);
  ensureAuthorizedKey(publicKey);
  if (options.installHelper !== false) {
    ensureRemoteHelperInstalled();
  }

  const privateKey = readNonEmpty(KEY_PATH);
  const connection = buildConnection(options);
  const payload = makePayload(privateKey, connection);
  return {
    status: currentStatus(),
    payload,
    link: makeImportLink(payload),
    connection,
  };
}

function openRemoteLoginSettings(): void {
  run(["open", "x-apple.systempreferences:com.apple.preferences.sharing?Services_RemoteLogin"]);
}

function printTerminalStatus(status: TerminalStatus): void {
  console.log(`${BOLD}Talkie terminal access${RESET}\n`);
  console.log(`  ${status.hasKeyPair ? `${GREEN}✓${RESET}` : `${YELLOW}!${RESET}`} SSH key pair ${DIM}${status.keyPath}${RESET}`);
  console.log(`  ${status.isAuthorized ? `${GREEN}✓${RESET}` : `${YELLOW}!${RESET}`} authorized_keys ${DIM}${status.authorizedKeysPath}${RESET}`);
  console.log(`  ${status.remoteLogin === "enabled" ? `${GREEN}✓${RESET}` : `${YELLOW}!${RESET}`} Remote Login ${status.remoteLogin}`);
  if (status.fingerprint) {
    console.log(`  fingerprint: ${DIM}${status.fingerprint}${RESET}`);
  }
}

export function registerTerminalCommand(program: Command): void {
  const terminal = program
    .command("terminal")
    .alias("ssh")
    .description("Pair the iOS Talkie app for SSH access (works without Talkie.app or TalkieAgent running)");

  terminal
    .command("pair")
    .description("Prepare SSH terminal access for the iOS Talkie app and show the import QR")
    .option("--ios-only", "explicit acknowledgement that this pair flow targets the iOS Talkie app (the QR carries a private key for the phone to import)", true)
    .option("--host <host>", "SSH host to save on iPhone/iPad (defaults to Tailscale hostname)")
    .option("--port <port>", "SSH port", (value) => parseInt(value, 10), 22)
    .option("--username <name>", "SSH username", currentUsername())
    .option("--payload", "print only the raw SSH key payload JSON")
    .option("--link", "print only the talkie:// import link")
    .option("--no-qr", "skip terminal QR rendering")
    .option("--no-helper", "skip installing local Talkie terminal helper scripts")
    .option("--open-settings", "open macOS Remote Login settings after preparing")
    .action(async (opts: {
      iosOnly?: boolean;
      host?: string;
      port?: number;
      username?: string;
      payload?: boolean;
      link?: boolean;
      qr?: boolean;
      helper?: boolean;
      openSettings?: boolean;
    }, cmd) => {
      const fmt = getFormatOptions(cmd.optsWithGlobals());
      const prepared = prepareTerminalAccess({
        host: opts.host,
        port: opts.port,
        username: opts.username,
        installHelper: opts.helper,
      });
      await postLocalSecurityEvent({
        type: "ssh_terminal_payload_created",
        severity: "warning",
        source: "cli",
        title: "Terminal access pairing QR created",
        message: `An SSH terminal import QR was created for ${prepared.connection?.username ?? opts.username ?? currentUsername()}@${prepared.connection?.host ?? "this Mac"}.`,
        macName: computerName(),
        metadata: {
          host: prepared.connection?.host,
          port: prepared.connection?.port,
          username: prepared.connection?.username,
          remoteLogin: prepared.status.remoteLogin,
          isAuthorized: prepared.status.isAuthorized,
          helperInstalled: opts.helper !== false,
        },
      });

      if (opts.openSettings) openRemoteLoginSettings();
      if (opts.payload) {
        console.log(prepared.payload);
        return;
      }
      if (opts.link) {
        console.log(prepared.link);
        return;
      }

      const qr = opts.qr === false ? null : renderQr(prepared.link);

      if (fmt.pretty) {
        console.log(`${BOLD}Talkie terminal pairing${RESET} ${DIM}(iOS-only)${RESET}`);
        console.log(`${DIM}Scan this with the Talkie iOS app to import the SSH key.${RESET}`);
        console.log(`${DIM}No Talkie.app or TalkieAgent needs to run after pairing — iOS connects to sshd directly.${RESET}\n`);

        if (qr) {
          console.log(qr.trimEnd());
          console.log();
        } else {
          const reason = opts.qr === false
            ? "Terminal QR rendering skipped"
            : `Terminal QR renderer not found ${DIM}(optional: brew install qrencode)${RESET}`;
          console.log(`  ${YELLOW}!${RESET} ${reason}`);
          console.log(`  Import link: ${CYAN}talkie terminal pair --link${RESET}`);
          console.log(`  Raw payload: ${CYAN}talkie terminal pair --payload${RESET}\n`);
        }

        printTerminalStatus(prepared.status);
        if (prepared.connection) {
          console.log(`  connection:  ${CYAN}${prepared.connection.username}@${prepared.connection.host}:${prepared.connection.port}${RESET}`);
        } else {
          console.log(`  ${YELLOW}!${RESET} No Tailscale SSH host found. Re-run with ${CYAN}--host <host>${RESET} to save an auto-connect target.`);
        }

        if (prepared.status.remoteLogin !== "enabled") {
          console.log();
          console.log(`  Next: enable Remote Login in macOS Sharing settings.`);
          console.log(`  Open it: ${CYAN}talkie terminal pair --open-settings --no-qr${RESET}`);
        }
      } else {
        output(
          {
            ...prepared.status,
            connection: prepared.connection,
            payload: prepared.payload,
            link: prepared.link,
            qrRendered: qr != null,
          },
          fmt
        );
      }
    });

  const statusAction = (_opts: unknown, cmd: Command) => {
    const fmt = getFormatOptions(cmd.optsWithGlobals());
    const status = currentStatus();
    if (fmt.pretty) {
      printTerminalStatus(status);
      if (!status.hasKeyPair || !status.isAuthorized) {
        console.log(`\n  Prepare access: ${CYAN}talkie terminal pair${RESET}`);
      }
      return;
    }
    output(status, fmt);
  };

  terminal
    .command("status")
    .description("Show SSH terminal pairing status")
    .action(statusAction);

  terminal
    .command("doctor")
    .description("Check SSH terminal pairing readiness")
    .action(statusAction);
}

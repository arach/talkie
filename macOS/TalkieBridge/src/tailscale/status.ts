import { $ } from "bun";
import { existsSync } from "fs";
import { networkInterfaces } from "os";

// Known Tailscale CLI locations (in priority order)
// Prefer standalone CLI over app bundle (app bundle needs GUI session)
const TAILSCALE_PATHS = [
  "/opt/homebrew/bin/tailscale", // Homebrew Apple Silicon
  "/usr/local/bin/tailscale", // Homebrew Intel
  "/usr/bin/tailscale", // System install
  "/Applications/Tailscale.app/Contents/MacOS/Tailscale", // macOS app bundle (last - needs GUI)
];

/**
 * Find the Tailscale CLI path.
 * Returns the first existing path from known locations.
 */
function findTailscalePath(): string | null {
  for (const path of TAILSCALE_PATHS) {
    if (existsSync(path)) {
      return path;
    }
  }
  return null;
}

/**
 * Fallback: Check for Tailscale via network interfaces.
 * Looks for 100.x.x.x IP (Tailscale CGNAT range).
 * Returns the IP if found, null otherwise.
 */
function getTailscaleIPFromNetwork(): string | null {
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      // Tailscale uses 100.64.0.0/10 (CGNAT range)
      if (net.family === "IPv4" && net.address.startsWith("100.")) {
        return net.address;
      }
    }
  }
  return null;
}

/**
 * Fallback: Get hostname from scutil (works in launchd context).
 */
async function getHostnameFromScutil(): Promise<string | null> {
  try {
    // Use full path - scutil is in /usr/sbin which isn't in launchd's PATH
    const result = await $`/usr/sbin/scutil --get LocalHostName`.quiet().nothrow();
    if (result.exitCode === 0) {
      const localName = result.stdout.toString().trim().toLowerCase().replace(/ /g, "-");
      // Try to find the tailnet domain from DNS
      const dnsResult = await $`/usr/sbin/scutil --dns`.quiet().nothrow();
      const dnsOutput = dnsResult.stdout.toString();
      const tailnetMatch = dnsOutput.match(/tail[a-z0-9]+\.ts\.net/);
      if (tailnetMatch) {
        return `${localName}.${tailnetMatch[0]}`;
      }
      // Fallback: just use local hostname
      return localName;
    }
  } catch {}
  return null;
}

export type TailscaleState =
  | { status: "not-installed" }
  | { status: "not-running" }
  | { status: "needs-login"; authUrl?: string }
  | { status: "offline" }
  | { status: "no-peers"; hostname: string }
  | { status: "ready"; hostname: string; peers: Peer[] };

export interface Peer {
  hostname: string;
  ip: string;
  online: boolean;
  os?: string;
}

export interface TailscaleStatus {
  BackendState: string;
  AuthURL?: string;
  Self?: {
    DNSName: string;
    TailscaleIPs: string[];
    Online: boolean;
  };
  Peer?: Record<
    string,
    {
      DNSName: string;
      TailscaleIPs: string[];
      Online: boolean;
      OS?: string;
    }
  >;
}

/**
 * Fallback: Detect Tailscale state via network interfaces.
 * Used when CLI is unavailable or fails (e.g., launchd context).
 */
async function getTailscaleStateFromNetwork(): Promise<TailscaleState> {
  const tailscaleIP = getTailscaleIPFromNetwork();
  if (!tailscaleIP) {
    return { status: "not-running" };
  }

  // We have a Tailscale IP, so it's running
  const hostname = await getHostnameFromScutil();
  if (!hostname) {
    // Can't determine hostname, but Tailscale is running
    return { status: "no-peers", hostname: tailscaleIP };
  }

  // We have IP and hostname - assume ready (can't check peers without CLI)
  return { status: "ready", hostname, peers: [] };
}

/**
 * Get the current Tailscale state with detailed information.
 * This is the primary function for checking if we can run the bridge.
 */
export async function getTailscaleState(): Promise<TailscaleState> {
  // Find tailscale CLI
  const tailscalePath = findTailscalePath();
  if (!tailscalePath) {
    // No CLI found - try network fallback
    return getTailscaleStateFromNetwork();
  }

  // Get tailscale status using full path
  const result = await $`${tailscalePath} status --json`.quiet().nothrow();
  if (result.exitCode !== 0) {
    // CLI failed (common in launchd context) - try network fallback
    return getTailscaleStateFromNetwork();
  }

  let status: TailscaleStatus;
  try {
    status = JSON.parse(result.stdout.toString());
  } catch {
    // Parse failed - try network fallback
    return getTailscaleStateFromNetwork();
  }

  // Check if we need to login
  if (status.BackendState === "NeedsLogin") {
    return { status: "needs-login", authUrl: status.AuthURL };
  }

  // Check if we're online
  if (!status.Self?.Online) {
    return { status: "offline" };
  }

  // Get our hostname (remove trailing dot)
  const hostname = status.Self.DNSName.replace(/\.$/, "");

  // Get online peers
  const peers: Peer[] = Object.values(status.Peer || {})
    .filter((p) => p.Online)
    .map((p) => ({
      hostname: p.DNSName.replace(/\.$/, ""),
      ip: p.TailscaleIPs?.[0] || "",
      online: p.Online,
      os: p.OS,
    }));

  if (peers.length === 0) {
    return { status: "no-peers", hostname };
  }

  return { status: "ready", hostname, peers };
}

/**
 * Get just the Tailscale hostname for this machine.
 * Returns null if Tailscale is not ready.
 */
export async function getTailscaleHostname(): Promise<string | null> {
  const state = await getTailscaleState();
  if (state.status === "ready" || state.status === "no-peers") {
    return state.hostname;
  }
  return null;
}

/**
 * Check if Tailscale is ready for the bridge to run.
 */
export async function isTailscaleReady(): Promise<boolean> {
  const state = await getTailscaleState();
  return state.status === "ready";
}

/**
 * Get a human-readable message for the current Tailscale state.
 */
export function getStateMessage(state: TailscaleState): string {
  switch (state.status) {
    case "not-installed":
      return "Tailscale is not installed. Download from https://tailscale.com/download";
    case "not-running":
      return "Tailscale is not running. Please start the Tailscale app.";
    case "needs-login":
      return `Tailscale requires login. ${state.authUrl ? `Visit: ${state.authUrl}` : "Open Tailscale to log in."}`;
    case "offline":
      return "Tailscale is offline. Check your network connection.";
    case "no-peers":
      return `Tailscale is running (${state.hostname}) but no other devices are online. Set up Tailscale on your iPhone.`;
    case "ready":
      return `Tailscale ready: ${state.hostname} (${state.peers.length} peer${state.peers.length === 1 ? "" : "s"} online)`;
  }
}

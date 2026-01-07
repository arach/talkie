import { $ } from "bun";
import { existsSync } from "fs";

// Known Tailscale CLI locations (in priority order)
const TAILSCALE_PATHS = [
  "/Applications/Tailscale.app/Contents/MacOS/Tailscale", // macOS app bundle
  "/usr/local/bin/tailscale", // Homebrew Intel
  "/opt/homebrew/bin/tailscale", // Homebrew Apple Silicon
  "/usr/bin/tailscale", // System install
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
 * Get the current Tailscale state with detailed information.
 * This is the primary function for checking if we can run the bridge.
 */
export async function getTailscaleState(): Promise<TailscaleState> {
  // Find tailscale CLI
  const tailscalePath = findTailscalePath();
  if (!tailscalePath) {
    return { status: "not-installed" };
  }

  // Get tailscale status using full path
  const result = await $`${tailscalePath} status --json`.quiet().nothrow();
  if (result.exitCode !== 0) {
    return { status: "not-running" };
  }

  let status: TailscaleStatus;
  try {
    status = JSON.parse(result.stdout.toString());
  } catch {
    return { status: "not-running" };
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

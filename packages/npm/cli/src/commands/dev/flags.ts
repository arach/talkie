import type { Command } from "commander";
import { getFormatOptions, output } from "../../format";

// ── Constants ────────────────────────────────────────────────

/** Compile-time defaults — must match FeatureFlags.swift `defaults` dict. */
const FLAG_DEFAULTS: Record<string, boolean> = {
  showConnectionCenter: false,
  showExtensionAPI: false,
  paywallEnabled: false,
  showProFeatures: false,
  enableCloudSync: false,
  enableAutoUpdates: true,
  showDebugInfo: false,
  enableCapture: false,
  enableCameraBubble: false,
  enableScreenshots: false,
  enableNotchComposer: true,
};

/** Parent → children for hierarchical display. */
const CHILD_FLAGS: Record<string, string[]> = {
  enableCapture: ["enableCameraBubble", "enableScreenshots"],
};

/** Flags that also need to be synced to the shared Agent suite. */
const SHARED_FLAG_KEYS: Record<string, string> = {
  enableCapture: "feature_capture_enabled",
  enableNotchComposer: "feature_notch_composer_enabled",
};

/** UserDefaults domain (dev build). */
const DEFAULTS_DOMAIN = "to.talkie.app.mac.dev";

/** Shared suite for Agent cross-process reads. */
const SHARED_SUITE = "to.talkie.app.shared.dev";

/** Keys inside UserDefaults. */
const REMOTE_KEY = "featureFlags.remote";
const OVERRIDES_KEY = "featureFlags.localOverrides";
const LAST_FETCH_KEY = "featureFlags.lastFetch";

/** Flags API URL (public, read-only). */
const FLAGS_URL = "https://api.usetalkie.com/api/flags";

/** Admin API base URL for flag management (CRUD). */
const ADMIN_URL =
  process.env.TALKIE_ADMIN_URL ?? "http://localhost:3200";

// ── UserDefaults helpers ─────────────────────────────────────

/**
 * Read a Data-typed key from UserDefaults.
 * `defaults export` outputs XML plist — we parse out the base64 <data> for our key,
 * then decode it as JSON.
 */
function readDefaultsData(key: string): Record<string, boolean> | null {
  const result = Bun.spawnSync(["defaults", "export", DEFAULTS_DOMAIN, "-"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) return null;

  const xml = result.stdout.toString();

  // Find the <key>…</key> then the next <data>…</data>
  const keyPattern = `<key>${escapeXml(key)}</key>`;
  const keyIdx = xml.indexOf(keyPattern);
  if (keyIdx === -1) return null;

  const afterKey = xml.substring(keyIdx + keyPattern.length);
  const dataMatch = afterKey.match(/<data>\s*([\s\S]*?)\s*<\/data>/);
  if (!dataMatch) return null;

  try {
    const base64 = dataMatch[1].replace(/\s/g, "");
    const decoded = Buffer.from(base64, "base64").toString("utf-8");
    return JSON.parse(decoded);
  } catch {
    return null;
  }
}

function escapeXml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => {
    switch (c) {
      case "&": return "&amp;";
      case "<": return "&lt;";
      case ">": return "&gt;";
      case '"': return "&quot;";
      case "'": return "&apos;";
      default: return c;
    }
  });
}

/**
 * Write a JSON dict as Data to a UserDefaults key.
 * Encodes JSON → bytes → hex, then uses `defaults write … -data <hex>`.
 */
function writeDefaultsData(key: string, value: Record<string, boolean>): boolean {
  const json = JSON.stringify(value);
  const hex = Buffer.from(json, "utf-8").toString("hex");
  const result = Bun.spawnSync(
    ["defaults", "write", DEFAULTS_DOMAIN, key, "-data", hex],
    { stdout: "pipe", stderr: "pipe" }
  );
  return result.exitCode === 0;
}

/** Delete a key from UserDefaults. */
function deleteDefaultsKey(key: string): boolean {
  const result = Bun.spawnSync(
    ["defaults", "delete", DEFAULTS_DOMAIN, key],
    { stdout: "pipe", stderr: "pipe" }
  );
  return result.exitCode === 0;
}

/** Read the lastFetch date from UserDefaults. */
function readLastFetch(): Date | null {
  const result = Bun.spawnSync(
    ["defaults", "read", DEFAULTS_DOMAIN, LAST_FETCH_KEY],
    { stdout: "pipe", stderr: "pipe" }
  );
  if (result.exitCode !== 0) return null;

  const raw = result.stdout.toString().trim();
  // `defaults read` prints dates as "2026-03-01 17:11:41 +0000"
  const date = new Date(raw);
  return isNaN(date.getTime()) ? null : date;
}

/** Sync a boolean flag to the shared Agent suite. */
function syncAgentFlag(sharedKey: string, value: boolean): void {
  Bun.spawnSync(
    ["defaults", "write", SHARED_SUITE, sharedKey, "-bool", value ? "YES" : "NO"],
    { stdout: "pipe", stderr: "pipe" }
  );
}

// ── Flag resolution ──────────────────────────────────────────

interface ResolvedFlag {
  value: boolean;
  source: "local" | "remote" | "default";
}

function resolveFlags(): { flags: Record<string, ResolvedFlag>; lastFetch: Date | null } {
  const remote = readDefaultsData(REMOTE_KEY) ?? {};
  const overrides = readDefaultsData(OVERRIDES_KEY) ?? {};
  const lastFetch = readLastFetch();

  const flags: Record<string, ResolvedFlag> = {};
  for (const [key, defaultVal] of Object.entries(FLAG_DEFAULTS)) {
    if (key in overrides) {
      flags[key] = { value: overrides[key], source: "local" };
    } else if (key in remote) {
      flags[key] = { value: remote[key], source: "remote" };
    } else {
      flags[key] = { value: defaultVal, source: "default" };
    }
  }

  return { flags, lastFetch };
}

// ── Pretty printing ──────────────────────────────────────────

function formatRelativeTime(date: Date): string {
  const diffMs = Date.now() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);

  if (diffDay > 0) return `${diffDay} day${diffDay !== 1 ? "s" : ""} ago`;
  if (diffHr > 0) return `${diffHr} hour${diffHr !== 1 ? "s" : ""} ago`;
  if (diffMin > 0) return `${diffMin} minute${diffMin !== 1 ? "s" : ""} ago`;
  return `${diffSec} second${diffSec !== 1 ? "s" : ""} ago`;
}

function flagIcon(value: boolean): string {
  return value ? "\x1b[32m●\x1b[0m" : "\x1b[90m○\x1b[0m";
}

function printFlagLine(key: string, flag: ResolvedFlag, indent: number = 0): void {
  const prefix = " ".repeat(indent);
  const icon = flagIcon(flag.value);
  const nameWidth = 40 - indent;
  const name = key.padEnd(nameWidth);
  const sourceColor = flag.source === "local" ? "\x1b[33m" : "\x1b[90m";
  console.log(`  ${prefix}${icon} ${name} ${sourceColor}${flag.source}\x1b[0m`);
}

function printFlags(flags: Record<string, ResolvedFlag>, lastFetch: Date | null): void {
  console.log("\n\x1b[1mFeature Flags\x1b[0m");
  console.log("═".repeat(55));

  const children = new Set(Object.values(CHILD_FLAGS).flat());
  const topLevel = Object.keys(FLAG_DEFAULTS)
    .filter((k) => !children.has(k))
    .sort();

  for (const key of topLevel) {
    const flag = flags[key];
    if (!flag) continue;
    printFlagLine(key, flag);

    // Print children indented
    const kids = CHILD_FLAGS[key];
    if (kids) {
      for (const child of kids) {
        const childFlag = flags[child];
        if (childFlag) {
          printFlagLine(child, childFlag, 2);
        }
      }
    }
  }

  if (lastFetch) {
    console.log(`\n\x1b[90mLast fetch: ${formatRelativeTime(lastFetch)}\x1b[0m`);
  } else {
    console.log(`\n\x1b[90mLast fetch: never\x1b[0m`);
  }
  console.log("");
}

// ── Subcommands ──────────────────────────────────────────────

function setFlag(flagName: string, rawValue: string): void {
  if (!(flagName in FLAG_DEFAULTS)) {
    console.error(`\x1b[31mUnknown flag: ${flagName}\x1b[0m`);
    console.error(`Valid flags: ${Object.keys(FLAG_DEFAULTS).sort().join(", ")}`);
    process.exit(1);
  }

  const value = rawValue === "true" || rawValue === "1" || rawValue === "yes";
  const overrides = readDefaultsData(OVERRIDES_KEY) ?? {};
  overrides[flagName] = value;
  writeDefaultsData(OVERRIDES_KEY, overrides);

  // Sync to Agent shared suite if applicable
  if (flagName in SHARED_FLAG_KEYS) {
    syncAgentFlag(SHARED_FLAG_KEYS[flagName], value);
  }

  console.log(`\x1b[32m✓\x1b[0m ${flagName} = ${value} \x1b[90m(local override)\x1b[0m`);
}

function clearFlag(flagName: string): void {
  if (!(flagName in FLAG_DEFAULTS)) {
    console.error(`\x1b[31mUnknown flag: ${flagName}\x1b[0m`);
    console.error(`Valid flags: ${Object.keys(FLAG_DEFAULTS).sort().join(", ")}`);
    process.exit(1);
  }

  const overrides = readDefaultsData(OVERRIDES_KEY) ?? {};
  delete overrides[flagName];
  writeDefaultsData(OVERRIDES_KEY, overrides);

  // Re-sync the resolved value (falls back to remote or default)
  if (flagName in SHARED_FLAG_KEYS) {
    const remote = readDefaultsData(REMOTE_KEY) ?? {};
    const resolved = remote[flagName] ?? FLAG_DEFAULTS[flagName] ?? false;
    syncAgentFlag(SHARED_FLAG_KEYS[flagName], resolved);
  }

  const fallback = FLAG_DEFAULTS[flagName] ?? false;
  console.log(`\x1b[32m✓\x1b[0m ${flagName} override cleared → ${fallback} \x1b[90m(default)\x1b[0m`);
}

async function fetchRemote(): Promise<void> {
  console.log("Fetching flags from API...");
  try {
    const response = await fetch(`${FLAGS_URL}?platform=macos`);
    if (!response.ok) {
      console.error(`\x1b[31mAPI returned ${response.status}\x1b[0m`);
      process.exit(1);
    }

    const data = (await response.json()) as { flags: Record<string, boolean> };
    const flags = data.flags;

    // Write to UserDefaults
    writeDefaultsData(REMOTE_KEY, flags);

    // Update lastFetch — write as date in macOS defaults format
    const now = new Date();
    const dateStr = now.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, " +0000");
    Bun.spawnSync(
      ["defaults", "write", DEFAULTS_DOMAIN, LAST_FETCH_KEY, "-date", dateStr],
      { stdout: "pipe", stderr: "pipe" }
    );

    // Sync shared flags
    const overrides = readDefaultsData(OVERRIDES_KEY) ?? {};
    for (const [flagKey, sharedKey] of Object.entries(SHARED_FLAG_KEYS)) {
      const resolved = overrides[flagKey] ?? flags[flagKey] ?? FLAG_DEFAULTS[flagKey] ?? false;
      syncAgentFlag(sharedKey, resolved);
    }

    console.log(`\x1b[32m✓\x1b[0m Fetched ${Object.keys(flags).length} flags from server`);

    // Show what came back
    for (const [key, value] of Object.entries(flags).sort(([a], [b]) => a.localeCompare(b))) {
      const icon = value ? "\x1b[32m●\x1b[0m" : "\x1b[90m○\x1b[0m";
      console.log(`  ${icon} ${key}: ${value}`);
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`\x1b[31mFailed to fetch flags: ${msg}\x1b[0m`);
    process.exit(1);
  }
}

// ── Server-side CRUD ─────────────────────────────────────────

interface ServerFlag {
  id: string;
  key: string;
  description: string | null;
  enabled: boolean;
  rules: unknown[];
  createdAt: string;
  updatedAt: string;
}

async function adminFetch(path: string, init?: RequestInit): Promise<Response> {
  const url = `${ADMIN_URL}${path}`;
  try {
    return await fetch(url, init);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`\x1b[31mCannot reach admin API at ${ADMIN_URL}: ${msg}\x1b[0m`);
    console.error(`\x1b[90mIs the admin server running? (cd admin && bun run dev)\x1b[0m`);
    console.error(`\x1b[90mOr set TALKIE_ADMIN_URL to point elsewhere.\x1b[0m`);
    process.exit(1);
  }
}

async function createFlag(
  key: string,
  opts: { description?: string; enabled?: boolean },
): Promise<void> {
  const body: Record<string, unknown> = { key };
  if (opts.description) body.description = opts.description;
  if (opts.enabled !== undefined) body.enabled = opts.enabled;

  const res = await adminFetch("/api/flags", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (res.status === 409) {
    console.error(`\x1b[31mFlag "${key}" already exists\x1b[0m`);
    process.exit(1);
  }
  if (!res.ok) {
    const text = await res.text();
    console.error(`\x1b[31mFailed to create flag (${res.status}): ${text}\x1b[0m`);
    process.exit(1);
  }

  const data = (await res.json()) as { flag: ServerFlag };
  console.log(`\x1b[32m✓\x1b[0m Created flag "${data.flag.key}" (${data.flag.enabled ? "enabled" : "disabled"})`);
}

async function deleteFlag(key: string): Promise<void> {
  // Look up the flag ID by key
  const listRes = await adminFetch("/api/flags");
  if (!listRes.ok) {
    console.error(`\x1b[31mFailed to list flags (${listRes.status})\x1b[0m`);
    process.exit(1);
  }
  const listData = (await listRes.json()) as { flags: ServerFlag[] };
  const flag = listData.flags.find((f) => f.key === key);
  if (!flag) {
    console.error(`\x1b[31mFlag "${key}" not found on server\x1b[0m`);
    process.exit(1);
  }

  const res = await adminFetch(`/api/flags/${flag.id}`, { method: "DELETE" });
  if (!res.ok) {
    const text = await res.text();
    console.error(`\x1b[31mFailed to delete flag (${res.status}): ${text}\x1b[0m`);
    process.exit(1);
  }

  console.log(`\x1b[32m✓\x1b[0m Deleted flag "${key}" from server`);
}

async function toggleServerFlag(key: string, enabled: boolean): Promise<void> {
  // Look up the flag ID by key
  const listRes = await adminFetch("/api/flags");
  if (!listRes.ok) {
    console.error(`\x1b[31mFailed to list flags (${listRes.status})\x1b[0m`);
    process.exit(1);
  }
  const listData = (await listRes.json()) as { flags: ServerFlag[] };
  const flag = listData.flags.find((f) => f.key === key);
  if (!flag) {
    console.error(`\x1b[31mFlag "${key}" not found on server\x1b[0m`);
    process.exit(1);
  }

  const res = await adminFetch(`/api/flags/${flag.id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled }),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error(`\x1b[31mFailed to update flag (${res.status}): ${text}\x1b[0m`);
    process.exit(1);
  }

  const verb = enabled ? "enabled" : "disabled";
  console.log(`\x1b[32m✓\x1b[0m Flag "${key}" ${verb} on server`);
}

async function listServerFlags(fmt: { pretty: boolean; json: boolean }): Promise<void> {
  const res = await adminFetch("/api/flags");
  if (!res.ok) {
    console.error(`\x1b[31mFailed to list flags (${res.status})\x1b[0m`);
    process.exit(1);
  }
  const data = (await res.json()) as { flags: ServerFlag[]; stats: { total: number; enabled: number; disabled: number } };

  if (!fmt.pretty) {
    output(data, fmt);
    return;
  }

  console.log(`\n\x1b[1mServer Flags\x1b[0m \x1b[90m(${ADMIN_URL})\x1b[0m`);
  console.log("═".repeat(60));
  for (const flag of data.flags.sort((a, b) => a.key.localeCompare(b.key))) {
    const icon = flag.enabled ? "\x1b[32m●\x1b[0m" : "\x1b[90m○\x1b[0m";
    const desc = flag.description ? `  \x1b[90m${flag.description}\x1b[0m` : "";
    const rules = flag.rules.length > 0 ? ` \x1b[33m(${flag.rules.length} rule${flag.rules.length !== 1 ? "s" : ""})\x1b[0m` : "";
    console.log(`  ${icon} ${flag.key.padEnd(35)}${rules}${desc}`);
  }
  console.log(`\n\x1b[90m${data.stats.total} flags: ${data.stats.enabled} enabled, ${data.stats.disabled} disabled\x1b[0m\n`);
}

function resetFlags(): void {
  let cleared = 0;
  if (deleteDefaultsKey(REMOTE_KEY)) cleared++;
  if (deleteDefaultsKey(OVERRIDES_KEY)) cleared++;
  if (deleteDefaultsKey(LAST_FETCH_KEY)) cleared++;

  console.log(`\x1b[32m✓\x1b[0m Cleared all cached and overridden flags (${cleared} keys removed)`);
  console.log("\x1b[90mFlags will use compile-time defaults until next fetch.\x1b[0m");
}

// ── Registration ─────────────────────────────────────────────

export function registerFlagsCommand(parent: Command): void {
  const flagsCmd = parent
    .command("flags")
    .description(
      "View and manage feature flags.\n\n" +
      "Shows all flags with their resolved values and sources (default, remote, local).\n" +
      "Local overrides take precedence over remote values, which take precedence over defaults.\n\n" +
      "Examples:\n" +
      "  talkie-dev flags                       List all flags\n" +
      "  talkie-dev flags set enableCapture true Set a local override\n" +
      "  talkie-dev flags clear enableCapture    Remove a local override\n" +
      "  talkie-dev flags remote                 Fetch latest from API\n" +
      "  talkie-dev flags reset                  Clear all cached + overridden flags\n" +
      "  talkie-dev flags create myFlag          Create a flag on the server\n" +
      "  talkie-dev flags enable myFlag           Enable a server flag\n" +
      "  talkie-dev flags disable myFlag          Disable a server flag\n" +
      "  talkie-dev flags delete myFlag           Delete a server flag\n" +
      "  talkie-dev flags server                  List all server flags"
    )
    .action((_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const { flags, lastFetch } = resolveFlags();

      if (fmt.pretty) {
        printFlags(flags, lastFetch);
      } else {
        output({
          flags,
          lastFetch: lastFetch?.toISOString() ?? null,
        }, fmt);
      }
    });

  flagsCmd
    .command("set <flag> <value>")
    .description("Set a local override for a flag (true/false)")
    .action((flagName: string, value: string) => {
      setFlag(flagName, value);
    });

  flagsCmd
    .command("clear <flag>")
    .description("Remove a local override (reverts to remote/default)")
    .action((flagName: string) => {
      clearFlag(flagName);
    });

  flagsCmd
    .command("remote")
    .description("Fetch current flag values from the API")
    .action(async () => {
      await fetchRemote();
    });

  flagsCmd
    .command("reset")
    .description("Clear all cached and overridden flags")
    .action(() => {
      resetFlags();
    });

  // ── Server-side commands ────────────────────────────────────

  flagsCmd
    .command("create <key>")
    .description("Create a new flag on the server")
    .option("-d, --description <text>", "Flag description")
    .option("-e, --enabled", "Create as enabled (default: disabled)")
    .action(async (key: string, opts: { description?: string; enabled?: boolean }) => {
      await createFlag(key, opts);
    });

  flagsCmd
    .command("delete <key>")
    .description("Delete a flag from the server")
    .action(async (key: string) => {
      await deleteFlag(key);
    });

  flagsCmd
    .command("enable <key>")
    .description("Enable a flag on the server")
    .action(async (key: string) => {
      await toggleServerFlag(key, true);
    });

  flagsCmd
    .command("disable <key>")
    .description("Disable a flag on the server (kill switch)")
    .action(async (key: string) => {
      await toggleServerFlag(key, false);
    });

  flagsCmd
    .command("server")
    .description("List all flags on the server")
    .action(async (_, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      await listServerFlags(fmt);
    });
}

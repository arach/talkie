import { homedir } from "os";
import { join } from "path";

export interface TalkieService {
  name: string;
  aliases: string[];
  devBundleId: string;
  prodBundleId: string | null;
  launchdLabel: string | null;
  machServices: string[] | null; // Mach service names for XPC — null = use `open`
  bridgePort: number | null; // WebSocket ServiceBridge port — null = no bridge
  xcodeWorkspace: string | null;
  xcodeProject: string | null;
  xcodeScheme: string | null;
  derivedDataPrefix: string | string[];
  preferredDerivedDataPrefix: string | null;
  appName: string;
  logSubsystem: string;
  sourceDir: string | null;
  /** Whether this service is included in `talkie-dev launch` (no args). Default: true */
  defaultLaunch: boolean;
}

/** All Talkie services managed by the dev CLI. */
export const SERVICES: TalkieService[] = [
  {
    name: "Talkie",
    aliases: ["talkie", "app"],
    devBundleId: "jdi.talkie.core.dev",
    prodBundleId: "jdi.talkie.core",
    launchdLabel: null, // App-launched, not launchd
    machServices: null,
    bridgePort: null,
    xcodeWorkspace: "TalkieSuite.xcworkspace",
    xcodeProject: "apps/macos/Talkie/Talkie.xcodeproj",
    xcodeScheme: "Talkie",
    derivedDataPrefix: ["Talkie-", "TalkieSuite-"],
    preferredDerivedDataPrefix: "TalkieSuite-",
    appName: "Talkie.app",
    logSubsystem: "jdi.talkie.core",
    sourceDir: "apps/macos/Talkie",
    defaultLaunch: true,
  },
  {
    name: "TalkieAgent",
    aliases: ["agent"],
    devBundleId: "jdi.talkie.agent.dev",
    prodBundleId: "jdi.talkie.agent",
    launchdLabel: "jdi.talkie.agent.xpc.dev",
    machServices: ["jdi.talkie.agent.xpc.dev"],
    bridgePort: null,
    xcodeWorkspace: null,
    xcodeProject: "apps/macos/TalkieAgent/TalkieAgent.xcodeproj",
    xcodeScheme: "TalkieAgent",
    derivedDataPrefix: "TalkieAgent-",
    preferredDerivedDataPrefix: null,
    appName: "TalkieAgent.app",
    logSubsystem: "jdi.talkie.agent",
    sourceDir: "apps/macos/TalkieAgent",
    defaultLaunch: true,
  },
  {
    name: "TalkieSync",
    aliases: ["sync"],
    devBundleId: "jdi.talkie.sync.dev",
    prodBundleId: "jdi.talkie.sync",
    launchdLabel: "jdi.talkie.sync.xpc.dev",
    machServices: ["jdi.talkie.sync.xpc.dev"],
    bridgePort: 19820,
    xcodeWorkspace: null,
    xcodeProject: "apps/macos/TalkieSync/TalkieSync.xcodeproj",
    xcodeScheme: "TalkieSync",
    derivedDataPrefix: "TalkieSync-",
    preferredDerivedDataPrefix: null,
    appName: "TalkieSync.app",
    logSubsystem: "jdi.talkie.sync",
    sourceDir: null,
    defaultLaunch: false,
  },
  {
    name: "TalkieRunner",
    aliases: ["runner"],
    devBundleId: "jdi.talkie.runner",
    prodBundleId: null,
    launchdLabel: null,
    machServices: null,
    bridgePort: null,
    xcodeWorkspace: null,
    xcodeProject: null,
    xcodeScheme: null,
    derivedDataPrefix: "TalkieRunner-",
    preferredDerivedDataPrefix: null,
    appName: "TalkieRunner.app",
    logSubsystem: "jdi.talkie.runner",
    sourceDir: null,
    defaultLaunch: false,
  },
];

/**
 * Directories containing shared Swift sources that affect all services.
 * Changes here make every service stale.
 */
export const SHARED_SOURCE_DIRS = ["Packages", "apps/macos/TalkieKit"];

const DERIVED_DATA_ROOT = join(
  homedir(),
  "Library",
  "Developer",
  "Xcode",
  "DerivedData"
);

/** Project root — uses git from cwd (works in compiled binary), falls back to relative path. */
export function getProjectRoot(): string {
  // Primary: git rev-parse (works from compiled binary when cwd is in repo)
  const git = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  if (git.exitCode === 0) {
    return git.stdout.toString().trim();
  }

  // Fallback: relative to this file (works in dev/unbundled mode only)
  return join(import.meta.dir, "..", "..", "..", "..");
}

export function getDerivedDataRoot(): string {
  return DERIVED_DATA_ROOT;
}

/** Resolve a service by name or alias (case-insensitive). */
export function resolveService(nameOrAlias: string): TalkieService | null {
  const lower = nameOrAlias.toLowerCase();
  return (
    SERVICES.find(
      (s) =>
        s.name.toLowerCase() === lower ||
        s.aliases.some((a) => a.toLowerCase() === lower)
    ) ?? null
  );
}

/** Get the current user's UID for launchctl commands. */
export function getUid(): number {
  return process.getuid?.() ?? parseInt(Bun.spawnSync(["id", "-u"]).stdout.toString().trim(), 10);
}

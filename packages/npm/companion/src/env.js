import { accessSync, constants, existsSync, readdirSync, readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

function run(command, args = []) {
  return spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}

let cachedLoginShellPathEntries = null;
let cachedApprovedShells = null;

function pathEntries(value) {
  return String(value ?? "")
    .split(path.delimiter)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function uniqueEntries(entries) {
  return [...new Set(entries)];
}

function executableAt(filePath) {
  if (!filePath) {
    return null;
  }

  try {
    accessSync(filePath, constants.X_OK);
    return filePath;
  } catch {
    return null;
  }
}

function approvedShells() {
  if (cachedApprovedShells) {
    return cachedApprovedShells;
  }

  try {
    cachedApprovedShells = readFileSync("/etc/shells", "utf8")
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#"));
  } catch {
    cachedApprovedShells = [];
  }

  if (cachedApprovedShells.length === 0) {
    cachedApprovedShells = ["/bin/zsh", "/bin/bash", "/bin/sh"];
  }

  return cachedApprovedShells;
}

function approvedShellPath(filePath) {
  const resolved = executableAt(filePath);
  if (!resolved) {
    return null;
  }

  return approvedShells().includes(resolved) ? resolved : null;
}

function fastSearchPaths(homeDirectory) {
  return uniqueEntries([
    ...pathEntries(process.env.PATH),
    path.join(homeDirectory, ".local/bin"),
    path.join(homeDirectory, ".opencode/bin"),
    path.join(homeDirectory, ".bun/bin"),
    path.join(homeDirectory, "bin"),
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ]);
}

function loginShellPathEntries() {
  if (cachedLoginShellPathEntries) {
    return cachedLoginShellPathEntries;
  }

  const result = run("/bin/zsh", ["-lc", "printf %s \"$PATH\""]);
  cachedLoginShellPathEntries = result.status === 0
    ? uniqueEntries(pathEntries(result.stdout))
    : [];
  return cachedLoginShellPathEntries;
}

function resolveExecutableInPaths(name, entries) {
  for (const entry of entries) {
    const resolved = executableAt(path.join(entry, name));
    if (resolved) {
      return resolved;
    }
  }

  return null;
}

function commandPath(name, homeDirectory = os.homedir()) {
  const fastResolved = resolveExecutableInPaths(name, fastSearchPaths(homeDirectory));
  if (fastResolved) {
    return fastResolved;
  }

  return resolveExecutableInPaths(name, loginShellPathEntries());
}

function detectUserShell() {
  const envShell = approvedShellPath(process.env.SHELL?.trim());
  if (envShell) {
    return envShell;
  }

  const result = run("/usr/bin/dscl", [".", "-read", `/Users/${os.userInfo().username}`, "UserShell"]);
  if (result.status === 0) {
    const match = result.stdout.match(/UserShell:\s+(.+)/);
    const dsclShell = approvedShellPath(match?.[1]?.trim());
    if (dsclShell) {
      return dsclShell;
    }
  }

  return resolveShellPath(undefined, "/bin/zsh");
}

function detectWorkspace(homeDirectory) {
  const candidates = [
    path.join(homeDirectory, "dev"),
    path.join(homeDirectory, "Developer"),
    path.join(homeDirectory, "Code"),
    path.join(homeDirectory, "Projects"),
    homeDirectory,
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return homeDirectory;
}

function detectTargets(homeDirectory) {
  return {
    claude: commandPath("claude", homeDirectory),
    opencode: commandPath("opencode", homeDirectory),
    tmux: commandPath("tmux", homeDirectory),
    npm: commandPath("npm", homeDirectory),
    node: commandPath("node", homeDirectory),
  };
}

function detectPreferredTarget(targets) {
  if (targets.claude && targets.opencode) return "claude";
  if (targets.claude) return "claude";
  if (targets.opencode) return "opencode";
  return "shell";
}

function detectTmuxSessions(tmuxPath) {
  if (!tmuxPath) {
    return {
      installed: false,
      sessions: [],
    };
  }

  const result = run(tmuxPath, [
    "list-sessions",
    "-F",
    "#{session_name}\t#{session_windows}\t#{?session_attached,1,0}",
  ]);

  if (result.status !== 0) {
    return {
      installed: true,
      sessions: [],
    };
  }

  const sessions = result.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [name, windows, attached] = line.split("\t");
      return {
        name,
        windows: Number.parseInt(windows ?? "0", 10) || 0,
        attached: attached === "1",
      };
    });

  return {
    installed: true,
    sessions,
  };
}

function detectHomeEntries(homeDirectory) {
  try {
    return readdirSync(homeDirectory, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
      .slice(0, 12)
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}

export function collectEnvironment() {
  const homeDirectory = os.homedir();
  const shellPath = detectUserShell();
  const targets = detectTargets(homeDirectory);
  const defaultWorkspace = detectWorkspace(homeDirectory);

  return {
    hostname: os.hostname(),
    username: os.userInfo().username,
    homeDirectory,
    shellPath,
    defaultWorkspace,
    targets,
    preferredTarget: detectPreferredTarget(targets),
    tmux: detectTmuxSessions(targets.tmux),
    homeEntries: detectHomeEntries(homeDirectory),
  };
}

export function resolveShellPath(preferredShellPath, fallbackShellPath = "/bin/zsh") {
  return approvedShellPath(preferredShellPath)
    ?? approvedShellPath(fallbackShellPath)
    ?? approvedShellPath("/bin/zsh")
    ?? "/bin/zsh";
}

export function runInShell(command) {
  return spawnSync("/bin/zsh", ["-lc", command], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}

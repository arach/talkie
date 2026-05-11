import type { Command } from "commander";
import { getFormatOptions, output } from "../format";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const GITHUB_OWNER = "arach";
const GITHUB_REPO = "usetalkie.com";
const APP_NAME = "Talkie.app";
const APP_PATH = `/Applications/${APP_NAME}`;
const PLIST_PATH = `${APP_PATH}/Contents/Info.plist`;

// Short URL for manual download — CLI uses GitHub API for asset URLs directly
const DOWNLOAD_URL = "https://go.usetalkie.com/download";

interface GithubRelease {
  tag_name: string;
  name: string;
  assets: { name: string; browser_download_url: string; size: number }[];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getInstalledVersion(): string | null {
  const result = Bun.spawnSync(["defaults", "read", PLIST_PATH, "CFBundleShortVersionString"]);
  if (result.exitCode !== 0) return null;
  return result.stdout.toString().trim();
}

async function fetchRelease(version?: string): Promise<GithubRelease> {
  const url = version
    ? `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/tags/${version}`
    : `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;

  // Try fetch() first (no auth needed, 60 req/hr)
  try {
    const resp = await fetch(url, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "talkie-cli" },
    });
    if (resp.ok) return (await resp.json()) as GithubRelease;
  } catch {}

  // Fallback: gh CLI (uses token, higher limits)
  const apiPath = version
    ? `repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/tags/${version}`
    : `repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
  const gh = Bun.spawnSync(["gh", "api", apiPath], { stdout: "pipe", stderr: "pipe" });
  if (gh.exitCode === 0) {
    return JSON.parse(gh.stdout.toString()) as GithubRelease;
  }

  throw new Error(version ? `Release "${version}" not found on GitHub` : "Could not fetch latest release from GitHub");
}

function findDmgAsset(release: GithubRelease): { url: string; size: number } | null {
  const asset = release.assets.find((a) => a.name.endsWith(".dmg"));
  if (!asset) return null;
  return { url: asset.browser_download_url, size: asset.size };
}

function stripLeadingV(tag: string): string {
  return tag.startsWith("v") ? tag.slice(1) : tag;
}

function normalizeVersion(version: string | null | undefined): string | null {
  if (!version) return null;
  return stripLeadingV(version.trim());
}

function findProdPids(processName: string): string[] {
  const pgrep = Bun.spawnSync(["pgrep", "-x", processName]);
  if (pgrep.exitCode !== 0) return [];

  const allPids = pgrep.stdout.toString().trim().split("\n").filter(Boolean);
  const prodPids: string[] = [];

  for (const pid of allPids) {
    const ps = Bun.spawnSync(["ps", "-o", "args=", "-p", pid]);
    const args = ps.stdout.toString().trim();
    if (args.includes("/Applications/")) {
      prodPids.push(pid);
    }
  }

  return prodPids;
}

function isAppRunning(): { running: boolean; pids: string[] } {
  const pids = findProdPids("Talkie");
  return { running: pids.length > 0, pids };
}

function restartServices(pretty: boolean): void {
  const agentPids = findProdPids("TalkieAgent");

  if (agentPids.length > 0) {
    if (pretty) process.stdout.write("    restarting TalkieAgent...");
    for (const pid of agentPids) {
      Bun.spawnSync(["kill", pid], { stdout: "pipe", stderr: "pipe" });
    }
    // TalkieAgent is a login item — macOS will relaunch it automatically,
    // but kick it explicitly to be safe
    setTimeout(() => {
      const agentPath = `${APP_PATH}/Contents/Library/LoginItems/TalkieAgent.app`;
      Bun.spawnSync(["open", agentPath], { stdout: "pipe", stderr: "pipe" });
    }, 1000);
    if (pretty) process.stdout.write(`\r    \x1b[32m✓ TalkieAgent restarted\x1b[0m\n`);
  }

  const appPids = findProdPids("Talkie");
  if (appPids.length > 0) {
    if (pretty) process.stdout.write("    relaunching Talkie...");
    Bun.spawnSync(
      ["osascript", "-e", 'tell application "Talkie" to quit'],
      { stdout: "pipe", stderr: "pipe" }
    );
    setTimeout(() => {
      Bun.spawnSync(["open", APP_PATH], { stdout: "pipe", stderr: "pipe" });
    }, 1500);
    if (pretty) process.stdout.write(`\r    \x1b[32m✓ Talkie relaunched\x1b[0m\n`);
  }
}

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// ---------------------------------------------------------------------------
// Core actions
// ---------------------------------------------------------------------------

async function downloadDmg(url: string, dest: string, knownSize: number, pretty: boolean): Promise<void> {
  const resp = await fetch(url, { redirect: "follow" });
  if (!resp.ok) throw new Error(`Download failed: HTTP ${resp.status}`);
  if (!resp.body) throw new Error("Download failed: empty response body");

  const totalSize = knownSize || parseInt(resp.headers.get("content-length") ?? "0", 10);
  const reader = resp.body.getReader();
  const chunks: Uint8Array[] = [];
  let received = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;

    if (pretty) {
      const progress = totalSize > 0
        ? `${formatBytes(received)} / ${formatBytes(totalSize)}`
        : formatBytes(received);
      process.stdout.write(`\r    downloading... ${progress}`);
    }
  }

  if (pretty) process.stdout.write(`\r    \x1b[32m✓ downloaded\x1b[0m ${formatBytes(received)}              \n`);

  const full = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) {
    full.set(chunk, offset);
    offset += chunk.length;
  }

  await Bun.write(dest, full);
}

function mountDmg(dmgPath: string): string {
  const result = Bun.spawnSync(
    ["hdiutil", "attach", dmgPath, "-nobrowse", "-noverify", "-noautoopen", "-plist"],
    { stdout: "pipe", stderr: "pipe" }
  );
  if (result.exitCode !== 0) {
    throw new Error(`DMG appears corrupted or could not be mounted: ${result.stderr.toString().trim()}`);
  }

  // Parse plist output to find mount point
  const plistOutput = result.stdout.toString();
  const mountPointMatch = plistOutput.match(/<key>mount-point<\/key>\s*<string>([^<]+)<\/string>/);
  if (mountPointMatch) return mountPointMatch[1];

  // Fallback: find /Volumes/Talkie*
  const volumes = Bun.spawnSync(["ls", "/Volumes"]);
  const talkieVol = volumes.stdout
    .toString()
    .split("\n")
    .find((l) => l.trim().startsWith("Talkie"));
  if (talkieVol) return `/Volumes/${talkieVol.trim()}`;

  throw new Error("Could not determine DMG mount point");
}

function unmountDmg(mountPoint: string): void {
  Bun.spawnSync(["hdiutil", "detach", mountPoint, "-quiet"], { stdout: "pipe", stderr: "pipe" });
}

function copyApp(mountPoint: string): void {
  // Find .app in mount point
  const ls = Bun.spawnSync(["ls", mountPoint]);
  const appDir = ls.stdout
    .toString()
    .split("\n")
    .find((l) => l.trim().endsWith(".app"));
  if (!appDir) throw new Error(`No .app found in mounted DMG at ${mountPoint}`);

  const src = `${mountPoint}/${appDir.trim()}`;

  // Remove old app
  const rmResult = Bun.spawnSync(["rm", "-rf", APP_PATH]);
  if (rmResult.exitCode !== 0) {
    throw new Error("Permission denied removing old app. Try: sudo talkie install");
  }

  // Copy new app
  const cpResult = Bun.spawnSync(["cp", "-R", src, APP_PATH]);
  if (cpResult.exitCode !== 0) {
    throw new Error("Permission denied copying app. Try: sudo talkie install");
  }
}

function removeQuarantine(): void {
  // Non-fatal — just try it
  Bun.spawnSync(["xattr", "-rd", "com.apple.quarantine", APP_PATH], { stdout: "pipe", stderr: "pipe" });
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

async function checkAction(opts: { target?: string }, pretty: boolean) {
  const installed = getInstalledVersion();
  const release = await fetchRelease();
  const latest = stripLeadingV(release.tag_name);

  const result = {
    installed: installed ?? null,
    latest,
    upToDate: installed === latest,
    release: release.name || release.tag_name,
  };

  if (pretty) {
    console.log(`  installed:  ${installed ?? "\x1b[90mnot installed\x1b[0m"}`);
    console.log(`  latest:     ${latest}`);
    if (!installed) {
      console.log(`  \x1b[33m→ not installed — run \`talkie install\`\x1b[0m`);
    } else if (result.upToDate) {
      console.log(`  \x1b[32m✓ up to date\x1b[0m`);
    } else {
      console.log(`  \x1b[33m→ update available — run \`talkie install\`\x1b[0m`);
    }
  } else {
    output(result, { pretty: false, json: true });
  }
}

async function installAction(opts: { target?: string; force?: boolean; launch?: boolean; check?: boolean; noRestart?: boolean }, pretty: boolean) {
  if (opts.check) return checkAction(opts, pretty);

  const installed = getInstalledVersion();
  const normalizedInstalled = normalizeVersion(installed);
  if (pretty && installed) console.log(`  installed: ${installed}`);

  // Resolve target version upfront so we can skip unnecessary downloads.
  let resolvedRelease: GithubRelease | null = null;
  let targetVersion: string | null = null;
  if (!opts.force) {
    if (opts.target) {
      if (pretty) process.stdout.write("  fetching release info...");
      resolvedRelease = await fetchRelease(opts.target);
      targetVersion = normalizeVersion(resolvedRelease.tag_name);
      if (pretty) process.stdout.write(`\r  \x1b[32m✓ found\x1b[0m ${resolvedRelease.name || resolvedRelease.tag_name}              \n`);
    } else if (normalizedInstalled) {
      resolvedRelease = await fetchRelease();
      targetVersion = normalizeVersion(resolvedRelease.tag_name);
    }

    if (normalizedInstalled && targetVersion && normalizedInstalled === targetVersion) {
      if (pretty) {
        const label = opts.target ? `target ${targetVersion}` : `latest (${targetVersion})`;
        console.log(`  \x1b[32m✓ already on ${label}\x1b[0m (use --force to reinstall)`);
      } else {
        output(
          {
            status: "up_to_date",
            installed: normalizedInstalled,
            target: targetVersion,
          },
          { pretty: false, json: true }
        );
      }
      return;
    }
  }

  // Resolve download URL
  let downloadUrl: string;
  let totalSize = 0;

  if (opts.target) {
    // Specific version: use resolved release if already fetched, else fetch now.
    if (!resolvedRelease) {
      if (pretty) process.stdout.write("  fetching release info...");
      resolvedRelease = await fetchRelease(opts.target);
      if (pretty) process.stdout.write(`\r  \x1b[32m✓ found\x1b[0m ${resolvedRelease.name || resolvedRelease.tag_name}              \n`);
    }

    const release = resolvedRelease;
    const dmg = findDmgAsset(release);
    if (!dmg) {
      throw new Error(`No DMG found in release ${release.tag_name}. Assets: ${release.assets.map((a) => a.name).join(", ")}`);
    }
    downloadUrl = dmg.url;
    totalSize = dmg.size;
  } else {
    // Latest: download directly from redirect URL — no API call needed
    downloadUrl = DOWNLOAD_URL;
  }

  // Download DMG
  const tmpDir = await mkdtemp(join(tmpdir(), "talkie-install-"));
  const dmgPath = join(tmpDir, "Talkie.dmg");
  let mountPoint: string | null = null;

  try {
    try {
      await downloadDmg(downloadUrl, dmgPath, totalSize, pretty);
    } catch (dlErr) {
      // If shortcut URL failed, fall back to GitHub API
      if (!opts.target) {
        if (pretty) console.log(`  \x1b[90mshortcut unavailable, resolving via GitHub...\x1b[0m`);
        const release = await fetchRelease();
        const dmg = findDmgAsset(release);
        if (!dmg) throw new Error(`No DMG found in latest release ${release.tag_name}`);
        await downloadDmg(dmg.url, dmgPath, dmg.size, pretty);
      } else {
        throw dlErr;
      }
    }

    // Mount DMG
    if (pretty) process.stdout.write("    mounting...");
    mountPoint = mountDmg(dmgPath);
    if (pretty) process.stdout.write(`\r    \x1b[32m✓ mounted\x1b[0m              \n`);

    // Copy to /Applications
    if (pretty) process.stdout.write("    installing...");
    copyApp(mountPoint);
    if (pretty) process.stdout.write(`\r    \x1b[32m✓ installed\x1b[0m to ${APP_PATH}\n`);

    // Remove quarantine (non-fatal)
    removeQuarantine();

    // Verify — read version from what we just installed
    const newVersion = getInstalledVersion();

    const wasUpgrade = installed && newVersion && installed !== newVersion;
    const wasFreshInstall = !installed && newVersion;

    if (!opts.force && installed && newVersion === installed) {
      if (pretty) {
        console.log(`  \x1b[32m✓ already on ${installed}\x1b[0m (use --force to reinstall)`);
      } else {
        output({ status: "up_to_date", version: installed }, { pretty: false, json: true });
      }
    } else if (pretty) {
      if (newVersion) {
        const action = wasUpgrade ? `updated ${installed} → ${newVersion}` : `Talkie ${newVersion} installed`;
        console.log(`  \x1b[32m✓ ${action}\x1b[0m`);
      } else {
        console.log(`  \x1b[33m⚠ installed but could not verify version\x1b[0m`);
      }
    } else {
      output(
        {
          status: "installed",
          version: newVersion,
          previousVersion: installed,
          path: APP_PATH,
        },
        { pretty: false, json: true }
      );
    }

    // After upgrade: restart running services so they pick up the new binary
    if ((wasUpgrade || opts.force) && !opts.noRestart) {
      restartServices(pretty);
    }

    // Only open Talkie when explicitly requested. Fresh installs should leave
    // the next action in the user's hands.
    if (opts.launch) {
      if (pretty) process.stdout.write("    launching Talkie...");
      const open = Bun.spawnSync(["open", APP_PATH]);
      if (pretty) {
        if (open.exitCode === 0) {
          process.stdout.write(`\r    \x1b[32m✓ Talkie launched\x1b[0m\n`);
        } else {
          process.stdout.write(`\r    \x1b[31m✗ launch failed\x1b[0m\n`);
        }
      }
    } else if (pretty && wasFreshInstall) {
      console.log("  \x1b[90mTalkie was not opened automatically. Run `talkie open` when you are ready.\x1b[0m");
    }
  } finally {
    // Cleanup: unmount + remove temp dir
    if (mountPoint) {
      try { unmountDmg(mountPoint); } catch {}
    }
    try { await rm(tmpDir, { recursive: true }); } catch {}
  }
}

async function uninstallAction(pretty: boolean) {
  const installed = getInstalledVersion();
  if (!installed) {
    if (pretty) {
      console.log("  \x1b[90mTalkie is not installed\x1b[0m");
    } else {
      output({ status: "not_installed" }, { pretty: false, json: true });
    }
    return;
  }

  // Check if running
  const { running, pids } = isAppRunning();
  if (running) {
    if (pretty) {
      console.log(`  \x1b[31m✗ Talkie is running\x1b[0m (pid ${pids.join(", ")})`);
      console.log(`    Quit it first, or run: osascript -e 'tell app "Talkie" to quit'`);
    } else {
      output({ error: "app_running", pids }, { pretty: false, json: true });
    }
    process.exit(1);
  }

  if (pretty) process.stdout.write(`  removing Talkie ${installed}...`);

  const result = Bun.spawnSync(["rm", "-rf", APP_PATH]);
  if (result.exitCode !== 0) {
    if (pretty) {
      process.stdout.write(`\r  \x1b[31m✗ permission denied\x1b[0m. Try: sudo talkie uninstall\n`);
    } else {
      output({ error: "permission_denied" }, { pretty: false, json: true });
    }
    process.exit(1);
  }

  if (pretty) {
    process.stdout.write(`\r  \x1b[32m✓ Talkie ${installed} removed\x1b[0m from ${APP_PATH}\n`);
    console.log(`  \x1b[90mTo also remove your data, run: talkie data clean\x1b[0m`);
  } else {
    output({ status: "uninstalled", version: installed, path: APP_PATH }, { pretty: false, json: true });
  }
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

export function registerInstallCommand(program: Command): void {
  program
    .command("install")
    .description("Download and install the latest Talkie.app to /Applications")
    .option("--check", "check for updates without installing")
    .option("--target <version>", "install a specific version (e.g. 2.0.23 or v2.0.23)")
    .option("--force", "reinstall even if already on the target version")
    .option("--launch", "launch Talkie after installing")
    .option("--no-restart", "skip restarting Talkie and TalkieAgent after upgrade")
    .action(async (opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      try {
        await installAction(opts, fmt.pretty);
      } catch (err: any) {
        if (fmt.pretty) {
          console.error(`  \x1b[31m✗ ${err.message}\x1b[0m`);
        } else {
          output({ error: err.message }, { pretty: false, json: true });
        }
        process.exit(1);
      }
    });

  const runInstallAction = async (opts: { target?: string; force?: boolean; launch?: boolean; check?: boolean; noRestart?: boolean }, cmd: Command) => {
    const globalOpts = cmd.optsWithGlobals();
    const fmt = getFormatOptions(globalOpts);
    try {
      await installAction(opts, fmt.pretty);
    } catch (err: any) {
      if (fmt.pretty) {
        console.error(`  \x1b[31m✗ ${err.message}\x1b[0m`);
      } else {
        output({ error: err.message }, { pretty: false, json: true });
      }
      process.exit(1);
    }
  };

  program
    .command("upgrade")
    .alias("update")
    .description("Upgrade Talkie.app if a newer version is available")
    .option("--check", "check for updates without installing")
    .option("--force", "reinstall even if already on the latest version")
    .option("--launch", "launch Talkie after installing")
    .option("--no-restart", "skip restarting Talkie and TalkieAgent after upgrade")
    .action(async (opts, cmd) => {
      await runInstallAction(opts, cmd);
    });

  program
    .command("uninstall")
    .description("Remove Talkie.app from /Applications")
    .action(async (_opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      try {
        await uninstallAction(fmt.pretty);
      } catch (err: any) {
        if (fmt.pretty) {
          console.error(`  \x1b[31m✗ ${err.message}\x1b[0m`);
        } else {
          output({ error: err.message }, { pretty: false, json: true });
        }
        process.exit(1);
      }
    });
}

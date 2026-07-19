#!/usr/bin/env node

// @talkie/app — shallow surface for Talkie on macOS.
//
// No args:    friendly welcome + next steps (Node only).
// With args:  forwards verbs to @talkie/cli via Bun.
//
// Kept deliberately thin: install logic, pairing, memos, etc. all live in
// @talkie/cli. This file never downloads or modifies anything on its own.

const { execSync, spawnSync } = require("child_process");
const { createRequire } = require("module");
const { dirname, join } = require("path");

const requireFromHere = createRequire(__filename);

// ─── Formatting ───────────────────────────────────────────────────────────

const isTTY = process.stdout.isTTY ?? false;
const color = (code) => (isTTY ? code : "");

const RESET = color("\x1b[0m");
const BOLD = color("\x1b[1m");
const DIM = color("\x1b[2m");
const REV = color("\x1b[7m");
const CYAN = color("\x1b[36m");
const GREEN = color("\x1b[32m");
const YELLOW = color("\x1b[33m");
const GRAY = color("\x1b[38;5;240m");

// ─── Paths & constants ────────────────────────────────────────────────────

const APP_PATH = "/Applications/Talkie.app";
const PLIST_PATH = `${APP_PATH}/Contents/Info.plist`;
const COMPANION_APP_STORE_URL = "https://apps.apple.com/us/app/talkie-mobile/id6755734109";

// ─── Helpers ──────────────────────────────────────────────────────────────

function getInstalledVersion() {
  try {
    return execSync(`defaults read "${PLIST_PATH}" CFBundleShortVersionString 2>/dev/null`, {
      encoding: "utf-8",
    }).trim();
  } catch {
    return null;
  }
}

function commandPath(name) {
  const result = spawnSync("/usr/bin/env", ["sh", "-lc", `command -v ${name}`], {
    encoding: "utf-8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  if (result.status !== 0) return null;
  const value = result.stdout.trim();
  return value.length > 0 ? value : null;
}

function hasCommand(name) {
  return commandPath(name) !== null;
}

// ─── Welcome (no-args) ────────────────────────────────────────────────────

function showWelcome() {
  const installed = getInstalledVersion();

  console.log();

  // Header badge
  if (installed) {
    console.log(`  ${REV}${BOLD} TALKIE ${RESET}  ${DIM}·${RESET}  ${BOLD}${installed}${RESET}  ${GREEN}●${RESET} ${DIM}installed${RESET}`);
  } else {
    console.log(`  ${REV}${BOLD} TALKIE ${RESET}  ${DIM}·${RESET}  ${YELLOW}○${RESET} ${DIM}not installed${RESET}`);
  }

  console.log();
  console.log(`  ${DIM}Voice-first capture for Mac, iPhone, and iPad.${RESET}`);
  console.log();

  // Primary CTA when not installed
  if (!installed) {
    console.log(`  ${GREEN}→${RESET}  ${BOLD}${CYAN}npx @talkie/app install${RESET}       ${DIM}download & install Talkie.app${RESET}`);
    console.log();
    console.log(`  ${DIM}Then:${RESET}`);
  }

  // Commands tree
  const rows = [
    ["open", "npx @talkie/app open", ""],
    ["agent", "npx @talkie/app agent", "launch TalkieAgent"],
    ["pro", "npx @talkie/app pro", "Pro Tools onboarding"],
    ["pair", "npx @talkie/app pair", "connect iPhone/iPad"],
    ["doctor", "npx @talkie/app doctor", "check setup"],
  ];
  if (installed) {
    rows.push(["install", "npx @talkie/app install", "check for updates"]);
  }

  const labelWidth = Math.max(...rows.map((r) => r[0].length));
  const cmdWidth = Math.max(...rows.map((r) => r[1].length));

  rows.forEach(([label, cmd, desc], i) => {
    const branch = i === rows.length - 1 ? "└─" : i === 0 ? "┌─" : "├─";
    const paddedLabel = label.padEnd(labelWidth);
    const paddedCmd = cmd.padEnd(cmdWidth);
    const descPart = desc ? `   ${DIM}${desc}${RESET}` : "";
    console.log(`  ${GRAY}${branch}${RESET} ${BOLD}${paddedLabel}${RESET}  ${CYAN}${paddedCmd}${RESET}${descPart}`);
  });

  console.log();
  console.log(`  ${DIM}More:${RESET} ${CYAN}npx @talkie/app --help${RESET}`);

  if (!hasCommand("bun")) {
    console.log();
    console.log(`  ${DIM}Tip: subcommands run on Bun — install with${RESET} ${CYAN}curl -fsSL https://bun.sh/install | bash${RESET}`);
  }

  console.log();
}

// ─── Main ─────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);

if (args.length === 0) {
  showWelcome();
  process.exit(0);
}

// Forward subcommand to @talkie/cli via Bun.
const bun = commandPath("bun");
if (!bun) {
  console.error();
  console.error(`  ${YELLOW}!${RESET} @talkie/cli requires Bun to run.`);
  console.error(`    Install Bun: ${CYAN}curl -fsSL https://bun.sh/install | bash${RESET}`);
  console.error(`    Then retry:  ${CYAN}npx @talkie/app ${args.join(" ")}${RESET}`);
  console.error();
  process.exit(1);
}

let cli;
try {
  const manifest = requireFromHere.resolve("@talkie/cli/package.json");
  cli = join(dirname(manifest), "dist", "index.js");
} catch {
  console.error("Could not find @talkie/cli inside @talkie/app. Try reinstalling:");
  console.error("  npm install -g @talkie/app");
  process.exit(1);
}

const child = spawnSync(bun, [cli, ...args], { stdio: "inherit" });
if (child.error) {
  console.error(child.error.message);
  process.exit(1);
}
process.exit(child.status ?? 0);

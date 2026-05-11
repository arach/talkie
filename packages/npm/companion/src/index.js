#!/usr/bin/env bun

import { execFileSync, spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline";
import React, { useState } from "react";
import { Command } from "commander";
import { createCliRenderer } from "@opentui/core";
import { createRoot, useKeyboard } from "@opentui/react";
import { collectEnvironment, resolveShellPath } from "./env.js";
import { ensureTalkieHome, getConfigPath, getTalkieHome, loadConfig, saveConfig } from "./config.js";

const RESET = "\u001B[0m";
const DIM = "\u001B[2m";
const CYAN = "\u001B[36m";
const GREEN = "\u001B[32m";
const YELLOW = "\u001B[33m";
const MAGENTA = "\u001B[35m";
const BOLD = "\u001B[1m";
const DEFAULT_TALKIE_SURFACE = "phone";
const APPLE_GLYPH = "";
const SOFT = "\u001B[38;5;250m";
const BRIGHT = "\u001B[38;5;255m";
const ACCENT = "\u001B[38;5;39m";

const TALKIE_SHELL_COMMAND = "talkie-shell";
const TALKIE_SESSION_COMMAND = "talkie-session";
const TALKIE_HOME_COMMAND = "talkie-home";
let alternateScreenActive = false;

function outputJson(data) {
  process.stdout.write(`${JSON.stringify(data, null, 2)}\n`);
}

function stylize(value, color) {
  return `${color}${value}${RESET}`;
}

function truncate(value, width) {
  if (width <= 0) {
    return "";
  }

  if (value.length <= width) {
    return value;
  }

  if (width <= 3) {
    return value.slice(0, width);
  }

  return `${value.slice(0, width - 3)}...`;
}

function pad(value, width) {
  const clipped = truncate(value, width);
  return clipped.length >= width ? clipped : clipped.padEnd(width, " ");
}

function makeCardLines(title, lines, width, selected = false) {
  const innerWidth = width - 2;
  const compact = isCompactMenuSurface();
  const rendered = [
    `┌${"─".repeat(innerWidth)}┐`,
    `│${pad(title, innerWidth)}│`,
  ];

  const visibleLines = compact ? lines.slice(0, 2) : lines;
  if (!compact) {
    rendered.push(`├${"─".repeat(innerWidth)}┤`);
  }

  for (const line of visibleLines) {
    rendered.push(`│${pad(line, innerWidth)}│`);
  }

  rendered.push(`└${"─".repeat(innerWidth)}┘`);
  if (!selected) {
    return rendered;
  }

  return rendered.map((line) => `${BOLD}${CYAN}${line}${RESET}`);
}

function gridLayout(preferredColumns = 2) {
  const terminalWidth = process.stdout.columns ?? 80;
  const columns = terminalWidth >= 76 ? preferredColumns : 1;
  const gutter = columns > 1 ? 2 : 0;
  const width = columns === 1
    ? Math.max(28, Math.min(terminalWidth, 52))
    : Math.max(28, Math.min(42, Math.floor((terminalWidth - gutter) / columns)));

  return { columns, width };
}

function printCardGrid(cards, options = {}) {
  const columns = options.columns ?? 2;
  const width = options.width ?? 34;
  const selectedId = options.selectedId ?? null;

  if (cards.length === 0) {
    return;
  }

  for (let index = 0; index < cards.length; index += columns) {
    const slice = cards.slice(index, index + columns);
    const rendered = slice.map((card) => makeCardLines(card.title, card.lines, width, card.id === selectedId));
    const maxLines = Math.max(...rendered.map((card) => card.length));

    for (let lineIndex = 0; lineIndex < maxLines; lineIndex += 1) {
      const line = rendered
        .map((card) => card[lineIndex] ?? " ".repeat(width))
        .join("  ");
      console.log(line);
    }

    console.log("");
  }
}

function centerText(text, width = process.stdout.columns ?? 80) {
  const padding = Math.max(0, Math.floor((width - text.length) / 2));
  return `${" ".repeat(padding)}${text}`;
}

function centerRenderedText(rendered, visibleWidth, width = process.stdout.columns ?? 80) {
  const padding = Math.max(0, Math.floor((width - visibleWidth) / 2));
  return `${" ".repeat(padding)}${rendered}`;
}

function styleWordmarkLine(line, accentStart, accentLength = 6) {
  return [...line].map((character, index) => {
    if (character === " ") {
      return character;
    }

    if (index >= accentStart && index < accentStart + accentLength) {
      return `${BOLD}${BRIGHT}${character}${RESET}`;
    }
    if (index >= accentStart - 1 && index < accentStart + accentLength + 1) {
      return `${ACCENT}${character}${RESET}`;
    }
    return `${SOFT}${character}${RESET}`;
  }).join("");
}

function enterAlternateScreen() {
  if (alternateScreenActive || !process.stdout.isTTY) {
    return;
  }

  process.stdout.write("\u001B[?1049h\u001B[?25l");
  alternateScreenActive = true;
}

function exitAlternateScreen() {
  if (!alternateScreenActive || !process.stdout.isTTY) {
    return;
  }

  process.stdout.write("\u001B[?25h\u001B[?1049l");
  alternateScreenActive = false;
}

function currentSurface() {
  return normalizeSurface(process.env.TALKIE_SURFACE);
}

function currentThemeMode() {
  const explicit = (process.env.TALKIE_THEME ?? "").trim().toLowerCase();
  if (explicit === "light" || explicit === "dark" || explicit === "auto") {
    return explicit;
  }

  if (isCompactMenuSurface()) {
    return "dark";
  }

  const colorfgbg = (process.env.COLORFGBG ?? "").trim();
  const backgroundIndex = Number.parseInt(colorfgbg.split(";").at(-1) ?? "", 10);
  if (Number.isFinite(backgroundIndex)) {
    return backgroundIndex >= 7 ? "light" : "dark";
  }

  if (process.platform === "darwin") {
    try {
      const appearance = execFileSync("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim().toLowerCase();
      return appearance === "dark" ? "dark" : "light";
    } catch {
      return "light";
    }
  }

  return "dark";
}

function currentThemePalette() {
  const mode = currentThemeMode();

  if (mode === "light") {
    return {
      background: "#ffffff",
      wordmark: "#111827",
      meta: "#374151",
      body: "#111827",
      detail: "#4b5563",
      selectedBackground: "#2563eb",
      selectedForeground: "#ffffff",
      selectedDetail: "#dbeafe",
    };
  }

  if (mode === "dark") {
    return {
      background: "#111827",
      wordmark: "#f8fafc",
      meta: "#9ca3af",
      body: "#e5e7eb",
      detail: "#9ca3af",
      selectedBackground: "#183a72",
      selectedForeground: "#f8fafc",
      selectedDetail: "#dbeafe",
    };
  }

  return {
    background: undefined,
    wordmark: undefined,
    meta: undefined,
    body: undefined,
    detail: undefined,
    selectedBackground: "#2563eb",
    selectedForeground: "#ffffff",
    selectedDetail: "#dbeafe",
  };
}

function isCompactMenuSurface() {
  return currentSurface() === DEFAULT_TALKIE_SURFACE;
}

function menuContextLine(environment, config) {
  const workspace = path.basename(config.workspace || environment.defaultWorkspace || environment.homeDirectory || "~");
  return environment.targets.tmux
    ? `${workspace} · reattach ready`
    : `${workspace} · shell ready`;
}

function printBanner(hostLabel, environment, config) {
  process.stdout.write("\u001Bc");
  console.log(`${BOLD}Talkie Terminal${RESET} ${DIM}on ${stylize(hostLabel, GREEN)}${RESET}`);
  console.log(`${DIM}${APPLE_GLYPH}  ${menuContextLine(environment, config)}${RESET}`);
  console.log("");
}

function buildConfig(environment, overrides = {}) {
  return {
    version: 1,
    updatedAt: new Date().toISOString(),
    username: environment.username,
    hostname: environment.hostname,
    shellPath: resolveShellPath(overrides.shell, environment.shellPath),
    homeDirectory: environment.homeDirectory,
    workspace: overrides.workspace ?? environment.defaultWorkspace,
    preferredTarget: overrides.preferredTarget ?? environment.preferredTarget,
    targets: environment.targets,
  };
}

function normalizedConfig(config, environment) {
  const preferredTarget = normalizeTarget(config?.preferredTarget) ?? environment.preferredTarget;
  const username = config?.username && config.username !== "unknown"
    ? config.username
    : environment.username;

  return {
    version: 1,
    updatedAt: config?.updatedAt ?? new Date().toISOString(),
    username,
    hostname: config?.hostname || environment.hostname,
    shellPath: resolveShellPath(config?.shellPath, environment.shellPath),
    homeDirectory: config?.homeDirectory || environment.homeDirectory,
    workspace: config?.workspace || environment.defaultWorkspace || environment.homeDirectory,
    preferredTarget,
    targets: environment.targets,
  };
}

function buildAppEntries(environment) {
  return [
    {
      id: "target:opencode",
      section: "apps",
      kind: "target",
      value: "opencode",
      title: "1  OpenCode",
      lines: [
        environment.targets.opencode ? "Installed and ready" : "Not installed yet",
        "Launch OpenCode in",
        "your Talkie workspace",
      ],
    },
    {
      id: "target:claude",
      section: "apps",
      kind: "target",
      value: "claude",
      title: "2  Claude Code",
      lines: [
        environment.targets.claude ? "Installed and ready" : "Not installed yet",
        "Launch Claude Code in",
        "your Talkie workspace",
      ],
    },
    {
      id: "target:shell",
      section: "apps",
      kind: "target",
      value: "shell",
      title: "3  Shell",
      lines: [
        "Return to your shell",
        "with Talkie bootstrap",
        "already completed",
      ],
    },
  ];
}

function buildTmuxEntries(environment) {
  if (!environment.tmux.installed) {
    return [];
  }

  return environment.tmux.sessions.map((session, index) => ({
    id: `tmux:${session.name}`,
    section: "tmux",
    kind: "tmux",
    value: session.name,
    title: `t${index + 1}  ${session.name}`,
    lines: [
      `${session.windows} window${session.windows === 1 ? "" : "s"}`,
      session.attached ? "Currently attached" : "Ready to attach",
      "Jump straight in",
    ],
  }));
}

function preferredTmuxSession(environment) {
  const preferredNames = [
    sessionNameForSurface(currentSurface()),
    sessionNameForSurface(DEFAULT_TALKIE_SURFACE),
    "talkie-shell",
  ];

  for (const name of preferredNames) {
    const session = environment.tmux.sessions.find((candidate) => candidate.name === name);
    if (session) {
      return session;
    }
  }

  return environment.tmux.sessions[0] ?? null;
}

function buildMenuEntries(environment) {
  const apps = buildAppEntries(environment);
  const tmuxEntries = buildTmuxEntries(environment);

  if (!isCompactMenuSurface()) {
    return [...apps, ...tmuxEntries];
  }

  const session = preferredTmuxSession(environment);
  if (!session) {
    return apps;
  }

  return [
    ...apps,
    {
      id: `tmux:${session.name}`,
      section: "tmux",
      kind: "tmux",
      value: session.name,
      title: "4  Reattach",
      lines: [
        session.attached ? "Return to your Talkie session" : "Resume your Talkie session",
        `${environment.tmux.sessions.length} session${environment.tmux.sessions.length === 1 ? "" : "s"} available`,
      ],
      isPrimary: false,
    },
  ];
}

function normalizeTarget(value) {
  switch ((value ?? "").trim().toLowerCase()) {
    case "1":
    case "opencode":
    case "open":
      return "opencode";
    case "2":
    case "claude":
      return "claude";
    case "3":
    case "":
    case "shell":
      return "shell";
    default:
      return null;
  }
}

function normalizeSurface(value) {
  const trimmed = (value ?? "").trim().toLowerCase();
  switch (trimmed) {
    case "ipad":
      return "ipad";
    case "phone":
    case "":
      return DEFAULT_TALKIE_SURFACE;
    default:
      return DEFAULT_TALKIE_SURFACE;
  }
}

function sessionNameForSurface(surface) {
  return `talkie-${surface}`;
}

function talkiePath(homeDirectory) {
  const talkieHome = getTalkieHome();
  return [
    path.join(talkieHome, "bin"),
    path.join(talkieHome, "runtime/bin"),
    path.join(homeDirectory, "bin"),
    path.join(homeDirectory, ".local/bin"),
    path.join(homeDirectory, ".opencode/bin"),
    path.join(homeDirectory, ".bun/bin"),
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
    process.env.PATH ?? "",
  ].filter(Boolean).join(":");
}

function shellEnvironment(config, environment) {
  const lang = process.env.LANG?.trim() || "en_US.UTF-8";
  const surface = normalizeSurface(process.env.TALKIE_SURFACE);
  const sessionName = process.env.TALKIE_SESSION_NAME?.trim() || sessionNameForSurface(surface);
  const term = (() => {
    const current = process.env.TERM?.trim();
    if (!current || current === "dumb" || current === "unknown") {
      return "xterm-256color";
    }
    return current;
  })();

  return {
    ...process.env,
    PATH: talkiePath(environment.homeDirectory),
    LANG: lang,
    LC_CTYPE: process.env.LC_CTYPE?.trim() || lang,
    TERM: term,
    COLORTERM: process.env.COLORTERM?.trim() || "truecolor",
    TERM_PROGRAM: process.env.TERM_PROGRAM?.trim() || "Talkie",
    TALKIE_HOME: getTalkieHome(),
    TALKIE_WORKSPACE: config.workspace || environment.defaultWorkspace || environment.homeDirectory,
    TALKIE_SURFACE: surface,
    TALKIE_SESSION_NAME: sessionName,
    TALKIE_USER_HOME: environment.homeDirectory,
    TALKIE_USER_ZDOTDIR: process.env.ZDOTDIR?.trim() || environment.homeDirectory,
    ZDOTDIR: getTalkieHome(),
  };
}

function ensureShellScaffold(config, environment) {
  const talkieHome = getTalkieHome();
  const talkieBin = path.join(talkieHome, "bin");
  const talkieRuntimeBin = path.join(talkieHome, "runtime/bin");
  const env = shellEnvironment(config, environment);
  const talkieHomeLiteral = JSON.stringify(talkieHome);
  const homeDirectoryLiteral = JSON.stringify(environment.homeDirectory);
  const userZdotdirLiteral = JSON.stringify(env.TALKIE_USER_ZDOTDIR || environment.homeDirectory);
  const pathLiteral = JSON.stringify(env.PATH);
  const langLiteral = JSON.stringify(env.LANG);
  const lcCtypeLiteral = JSON.stringify(env.LC_CTYPE);
  const termLiteral = JSON.stringify(env.TERM);
  const colorTermLiteral = JSON.stringify(env.COLORTERM);
  const termProgramLiteral = JSON.stringify(env.TERM_PROGRAM);
  const workspaceLiteral = JSON.stringify(env.TALKIE_WORKSPACE);
  const surfaceLiteral = JSON.stringify(env.TALKIE_SURFACE);
  const sessionNameLiteral = JSON.stringify(env.TALKIE_SESSION_NAME);

  mkdirSync(talkieHome, { recursive: true, mode: 0o700 });

  writeFileSync(path.join(talkieHome, ".zshenv"), `typeset -gx TALKIE_HOME=${talkieHomeLiteral}\ntypeset -gx TALKIE_USER_HOME=${homeDirectoryLiteral}\ntypeset -gx TALKIE_USER_ZDOTDIR=\${TALKIE_USER_ZDOTDIR:-${userZdotdirLiteral}}\n\n_talkie_source_user_file() {\n  local file_name="$1"\n  local user_zdotdir="\${TALKIE_USER_ZDOTDIR:-$TALKIE_USER_HOME}"\n  [[ -n "$user_zdotdir" ]] || user_zdotdir="$HOME"\n  [[ "$user_zdotdir" != "$TALKIE_HOME" ]] || return 0\n\n  local target="$user_zdotdir/$file_name"\n  [[ -f "$target" ]] || return 0\n\n  local previous_zdotdir="\${ZDOTDIR-}"\n  local had_zdotdir=$(( \${+ZDOTDIR} ))\n  export ZDOTDIR="$user_zdotdir"\n  builtin source "$target"\n  if (( had_zdotdir )); then\n    export ZDOTDIR="$previous_zdotdir"\n  else\n    unset ZDOTDIR\n  fi\n}\n\n_talkie_source_user_file ".zshenv"\n\nexport PATH=${pathLiteral}\n[[ -n "\${LANG:-}" ]] || export LANG=${langLiteral}\n[[ -n "\${LC_CTYPE:-}" ]] || export LC_CTYPE=${lcCtypeLiteral}\n[[ -n "\${TERM:-}" && "\${TERM:-}" != "dumb" && "\${TERM:-}" != "unknown" ]] || export TERM=${termLiteral}\n[[ -n "\${COLORTERM:-}" ]] || export COLORTERM=${colorTermLiteral}\n[[ -n "\${TERM_PROGRAM:-}" ]] || export TERM_PROGRAM=${termProgramLiteral}\nexport TALKIE_HOME=${talkieHomeLiteral}\nexport TALKIE_WORKSPACE=${workspaceLiteral}\nexport TALKIE_SURFACE=${surfaceLiteral}\nexport TALKIE_SESSION_NAME=${sessionNameLiteral}\nexport ZDOTDIR="$TALKIE_HOME"\n`, { mode: 0o600 });
  writeFileSync(path.join(talkieHome, ".zprofile"), `_talkie_source_user_file ".zprofile"\n`, { mode: 0o600 });
  writeFileSync(path.join(talkieHome, ".zshrc"), `_talkie_source_user_file ".zshrc"\nsetopt interactivecomments no_beep no_nomatch prompt_subst auto_cd\nexport CLICOLOR=1\nalias c='claude'\nalias o='opencode'\nalias tls='tmux list-sessions'\nalias ta='tmux attach -t'\nalias tsh='${path.join(talkieBin, TALKIE_SHELL_COMMAND)}'\nalias ts='${path.join(talkieBin, TALKIE_SESSION_COMMAND)}'\nalias th='${path.join(talkieBin, TALKIE_HOME_COMMAND)}'\nalias TH='${path.join(talkieBin, TALKIE_HOME_COMMAND)}'\nalias tdoctor='${path.join(talkieRuntimeBin, "talkie-companion")} doctor'\ntalkie_aliases() {\n  print -P ''\n  print -P "%B%F{250}Helpful aliases%f%b"\n  print -P "  %F{81}c%f       Claude"\n  print -P "  %F{81}o%f       OpenCode"\n  print -P "  %F{81}tls%f     tmux list-sessions"\n  print -P "  %F{81}ta NAME%f tmux attach -t NAME"\n  print -P "  %F{81}ts%f      Talkie tmux session"\n  print -P "  %F{81}tsh%f     Talkie shell"\n  print -P ''\n}\nalias talias='talkie_aliases'\nunalias reload 2>/dev/null\nreload() { exec "\${SHELL:-/bin/zsh}" -il }\n\n[[ -n "\${PROMPT:-}" ]] || PROMPT="%F{250}${APPLE_GLYPH}%f %F{250}>%f "\n[[ -n "\${RPROMPT:-}" ]] || RPROMPT=""\n`, { mode: 0o600 });
  writeFileSync(path.join(talkieHome, ".zlogin"), `_talkie_source_user_file ".zlogin"\n[[ -o interactive ]] || return 0\n\ntalkie_login_banner() {\n  print -P ''\n  print -P "%B%F{250}T A L K I E%f%b"\n  print -P "%F{244}Welcome to %m%f"\n  print -P "%F{244}We've placed a few helpful aliases for you.%f"\n  print -P "%F{244}Run %F{81}talias%F{244} to show them.%f"\n  print -P ''\n}\n\ntalkie_login_banner\n`, { mode: 0o600 });

  return env;
}

function shellEscape(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function controlledShellCommand(env, config, environment) {
  const shellPath = talkieShellPath(config, environment);
  const envAssignments = Object.entries(env)
    .map(([key, value]) => `${key}=${shellEscape(value)}`)
    .join(" ");

  return `/usr/bin/env ${envAssignments} ${shellEscape(shellPath)} -il`;
}

function controlledShellEnvironment(config, environment) {
  return {
    ...ensureShellScaffold(config, environment),
    TERM: "xterm-256color",
    COLORTERM: "truecolor",
    TERM_PROGRAM: "Talkie",
  };
}

function shellInvocation(executablePath, argumentsList = []) {
  return [shellEscape(executablePath), ...argumentsList.map(shellEscape)].join(" ");
}

function launchTargetDisplayName(target) {
  switch (target) {
    case "claude":
      return "Claude Code";
    case "opencode":
      return "OpenCode";
    case "shell":
    default:
      return "Shell";
  }
}

function shellFallbackScript(executablePath, argumentsList, shellPath, target) {
  const invocation = shellInvocation(executablePath, argumentsList);
  const label = launchTargetDisplayName(target);
  return `exec ${invocation}\nEXIT_CODE=$?\nprintf '\\n[Talkie] ${label} exited with status %s. Dropping into local shell.\\n' "$EXIT_CODE"\nexec ${shellEscape(shellPath)} -il`;
}

function spawnAndWait(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: "inherit",
      cwd: options.cwd,
      env: options.env ?? process.env,
    });

    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) {
        reject(new Error(`${command} exited with signal ${signal}`));
        return;
      }
      resolve(code ?? 0);
    });
  });
}

function loadOrCreateConfig(environment) {
  const existingConfig = loadConfig();
  const config = normalizedConfig(existingConfig, environment);

  if (!existingConfig || JSON.stringify(existingConfig) !== JSON.stringify(config)) {
    ensureTalkieHome();
    saveConfig({
      ...config,
      updatedAt: new Date().toISOString(),
    });
    return {
      ...config,
      updatedAt: new Date().toISOString(),
    };
  }

  return config;
}

function targetAvailable(target, environment) {
  switch (target) {
    case "opencode":
      return Boolean(environment.targets.opencode);
    case "claude":
      return Boolean(environment.targets.claude);
    case "shell":
      return true;
    default:
      return false;
  }
}

function talkieShellPath(config, environment) {
  return resolveShellPath(config?.shellPath, environment.shellPath);
}

function tmuxSessionNameForWorkspace(workspacePath) {
  const basename = path.basename(workspacePath || "console");
  const sanitized = basename
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^[-_]+|[-_]+$/g, "");

  return `talkie-${sanitized || "console"}`;
}

async function tmuxSessionExists(sessionName, environment) {
  if (!environment.targets.tmux) {
    return false;
  }

  const exitCode = await runSync(environment.targets.tmux, ["has-session", "-t", sessionName], {
    stdio: "ignore",
  });
  return exitCode === 0;
}

function openCodeAgentArguments(model, workspacePath) {
  const argumentsList = [];
  if (model) {
    argumentsList.push("-m", model);
  }
  argumentsList.push(workspacePath);
  return argumentsList;
}

function resolvedHarnessName(target) {
  switch (target) {
    case "opencode":
      return "openCode";
    case "claude":
      return "claude";
    case "shell":
      return "helloWorld";
    default:
      return "helloWorld";
  }
}

function requestedTargetForProfile(profileId, requestedTarget) {
  const normalizedRequestedTarget = normalizeTarget(requestedTarget);

  switch ((profileId ?? "").trim()) {
    case "claude-agent":
      return "claude";
    case "local-shell":
      return "shell";
    case "talkie-agent":
      if (normalizedRequestedTarget === "claude" || normalizedRequestedTarget === "opencode") {
        return normalizedRequestedTarget;
      }
      return "opencode";
    default:
      return normalizedRequestedTarget ?? "shell";
  }
}

function candidateTargetsForProfile(profileId, requestedTarget, config) {
  const configuredTarget = normalizeTarget(config?.preferredTarget);
  const configuredAgentTarget = configuredTarget && configuredTarget !== "shell"
    ? configuredTarget
    : null;
  const requested = requestedTargetForProfile(profileId, requestedTarget);

  switch ((profileId ?? "").trim()) {
    case "claude-agent":
      return ["claude", "shell"];
    case "local-shell":
      return ["shell"];
    case "talkie-agent":
      return [
        configuredAgentTarget,
        requested,
        "opencode",
        "claude",
        "shell",
      ].filter(Boolean);
    default:
      return [
        configuredTarget,
        requested,
        "claude",
        "opencode",
        "shell",
      ].filter(Boolean);
  }
}

function resolutionReason(profileId, configuredTarget, requestedTarget, resolvedTarget) {
  if (profileId === "local-shell") {
    return "Local Shell profile requested.";
  }

  if (configuredTarget && configuredTarget !== "shell" && configuredTarget === resolvedTarget && profileId === "talkie-agent") {
    return `Using configured Talkie agent target: ${resolvedTarget}.`;
  }

  if (requestedTarget && requestedTarget === resolvedTarget) {
    return `Using requested target: ${resolvedTarget}.`;
  }

  if (requestedTarget === "opencode" && resolvedTarget === "claude") {
    return "OpenCode unavailable; using Claude instead.";
  }

  if (requestedTarget && resolvedTarget === "shell") {
    return `${requestedTarget} unavailable; using Talkie shell instead.`;
  }

  return `Using resolved target: ${resolvedTarget}.`;
}

function shellLaunchSpec(shellPath, workspacePath, environmentOverrides = {}, sessionMode = { kind: "ephemeral" }) {
  return {
    executablePath: shellPath,
    arguments: ["-il"],
    environment: environmentOverrides,
    workingDirectory: workspacePath,
    sessionMode,
    shouldSendInitialPrompt: false,
  };
}

async function buildAgentLaunchSpec(options, config, environment) {
  const workspacePath = options.workspace || config.workspace || environment.defaultWorkspace || environment.homeDirectory;
  const requestedTarget = requestedTargetForProfile(options.profile, options.requestedTarget);
  const configuredTarget = normalizeTarget(config.preferredTarget);
  const candidates = candidateTargetsForProfile(options.profile, options.requestedTarget, config);
  const resolvedTarget = candidates.find((candidate) => targetAvailable(candidate, environment)) ?? "shell";
  const preferTmux = Boolean(options.tmux);
  const shellPath = talkieShellPath(config, environment);
  const environmentOverrides = controlledShellEnvironment(config, environment);

  let sessionMode = { kind: "ephemeral" };
  let shouldSendInitialPrompt = false;

  if (preferTmux && environment.targets.tmux) {
    const sessionName = tmuxSessionNameForWorkspace(workspacePath);
    const sessionExists = await tmuxSessionExists(sessionName, environment);
    sessionMode = {
      kind: "tmux",
      sessionName,
      executablePath: environment.targets.tmux,
    };
    shouldSendInitialPrompt = resolvedTarget === "opencode" && !sessionExists;

    const launchCommand = (() => {
      switch (resolvedTarget) {
        case "opencode":
          return shellEscape(environment.targets.opencode);
        case "claude":
          return shellEscape(environment.targets.claude);
        case "shell":
        default:
          return shellEscape(shellPath);
      }
    })();

    const launchArguments = (() => {
      switch (resolvedTarget) {
        case "opencode":
          return openCodeAgentArguments(
            options.preferredModel || process.env.TALKIE_OPENCODE_MODEL || "opencode/minimax-m2.5-free",
            workspacePath,
          ).map(shellEscape).join(" ");
        case "claude":
          return "";
        case "shell":
        default:
          return "-il";
      }
    })();

    const fallbackBanner = (() => {
      switch (resolvedTarget) {
        case "opencode":
          return "OpenCode";
        case "claude":
          return "Claude";
        case "shell":
        default:
          return "Shell";
      }
    })();

    const shellCommand = resolvedTarget === "shell"
      ? `${launchCommand} ${launchArguments}`.trim()
      : `${shellEscape(shellPath)} -ilc ${shellEscape(
        `export TERM=xterm-256color COLORTERM=truecolor TERM_PROGRAM=Talkie\n${`${launchCommand} ${launchArguments}`.trim()}\nEXIT_CODE=$?\nprintf '\\n[Talkie] ${fallbackBanner} exited with status %s. Dropping into local shell.\\n' \"$EXIT_CODE\"\nexec ${shellEscape(shellPath)} -il`,
      )}`;

    const script = [
      `TMUX_BIN=${shellEscape(environment.targets.tmux)}`,
      `SESSION_NAME=${shellEscape(sessionName)}`,
      `WORKSPACE=${shellEscape(workspacePath)}`,
      'if ! "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null; then',
      `  "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$WORKSPACE" "exec ${shellCommand}"`,
      "fi",
      '"$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true',
      'exec "$TMUX_BIN" attach-session -t "$SESSION_NAME"',
    ].join("\n");

    return {
      requestedTarget,
      resolvedTarget,
      resolvedHarness: resolvedHarnessName(resolvedTarget),
      reason: resolutionReason(options.profile, configuredTarget, requestedTarget, resolvedTarget),
      launchSpec: {
        executablePath: shellPath,
        arguments: ["-lc", script],
        environment: environmentOverrides,
        workingDirectory: workspacePath,
        sessionMode,
        shouldSendInitialPrompt,
      },
    };
  }

  if (resolvedTarget === "opencode") {
    return {
      requestedTarget,
      resolvedTarget,
      resolvedHarness: "openCode",
      reason: resolutionReason(options.profile, configuredTarget, requestedTarget, resolvedTarget),
      launchSpec: {
        executablePath: shellPath,
        arguments: [
          "-ilc",
          `exec ${shellInvocation(
            environment.targets.opencode,
            openCodeAgentArguments(
              options.preferredModel || process.env.TALKIE_OPENCODE_MODEL || "opencode/minimax-m2.5-free",
              workspacePath,
            ),
          )}`,
        ],
        environment: environmentOverrides,
        workingDirectory: workspacePath,
        sessionMode,
        shouldSendInitialPrompt: true,
      },
    };
  }

  if (resolvedTarget === "claude") {
    return {
      requestedTarget,
      resolvedTarget,
      resolvedHarness: "claude",
      reason: resolutionReason(options.profile, configuredTarget, requestedTarget, resolvedTarget),
      launchSpec: {
        executablePath: shellPath,
        arguments: ["-ilc", `exec ${shellInvocation(environment.targets.claude)}`],
        environment: environmentOverrides,
        workingDirectory: workspacePath,
        sessionMode,
        shouldSendInitialPrompt: false,
      },
    };
  }

  return {
    requestedTarget,
    resolvedTarget: "shell",
    resolvedHarness: "helloWorld",
    reason: resolutionReason(options.profile, configuredTarget, requestedTarget, "shell"),
    launchSpec: shellLaunchSpec(shellPath, workspacePath, environmentOverrides, sessionMode),
  };
}

async function launchControlledShell(config, environment) {
  const env = controlledShellEnvironment(config, environment);
  const shellPath = talkieShellPath(config, environment);
  return spawnAndWait(shellPath, ["-il"], {
    cwd: environment.homeDirectory,
    env,
  });
}

function runSync(command, args, options = {}) {
  const child = spawn(command, args, {
    stdio: options.stdio ?? "ignore",
    cwd: options.cwd,
    env: options.env ?? process.env,
  });

  return new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) {
        reject(new Error(`${command} exited with signal ${signal}`));
        return;
      }
      resolve(code ?? 0);
    });
  });
}

async function ensureContextSession(config, environment) {
  if (!environment.targets.tmux) {
    return launchControlledShell(config, environment);
  }

  const env = controlledShellEnvironment(config, environment);
  const tmuxPath = environment.targets.tmux;
  const sessionName = env.TALKIE_SESSION_NAME || sessionNameForSurface(DEFAULT_TALKIE_SURFACE);

  const hasSessionCode = await runSync(tmuxPath, ["has-session", "-t", sessionName], {
    env,
  });

  if (hasSessionCode !== 0) {
    const shellCommand = controlledShellCommand(env, config, environment);
    const createCode = await runSync(
      tmuxPath,
      ["new-session", "-d", "-s", sessionName, "-c", environment.homeDirectory, shellCommand],
      { env },
    );

    if (createCode !== 0) {
      throw new Error("Failed to create Talkie tmux session");
    }

    await runSync(tmuxPath, ["set-option", "-t", sessionName, "status", "off"], {
      env,
    });
  }

  return spawnAndWait(tmuxPath, ["attach", "-t", sessionName], {
    cwd: environment.homeDirectory,
    env,
  });
}

async function launchTarget(target, config, environment) {
  const cwd = config.workspace || environment.defaultWorkspace || environment.homeDirectory;
  const env = controlledShellEnvironment(config, environment);
  const shellPath = talkieShellPath(config, environment);
  switch (target) {
    case "claude":
      if (!environment.targets.claude) {
        console.log(`${YELLOW}Claude Code is not installed. Staying in the shell.${RESET}`);
        return launchControlledShell(config, environment);
      }
      return spawnAndWait(
        shellPath,
        ["-ilc", shellFallbackScript(environment.targets.claude, [], shellPath, target)],
        { cwd, env },
      );
    case "opencode":
      if (!environment.targets.opencode) {
        console.log(`${YELLOW}OpenCode is not installed. Staying in the shell.${RESET}`);
        return launchControlledShell(config, environment);
      }
      return spawnAndWait(
        shellPath,
        ["-ilc", shellFallbackScript(environment.targets.opencode, [], shellPath, target)],
        { cwd, env },
      );
    case "shell":
      return launchControlledShell(config, environment);
    default:
      throw new Error(`Unknown launch target: ${target}`);
  }
}

async function attachTmuxSession(sessionName, environment, config) {
  if (!environment.targets.tmux) {
    console.log(`${YELLOW}tmux is not installed on this Mac.${RESET}`);
    return 0;
  }

  const cwd = config.workspace || environment.defaultWorkspace || environment.homeDirectory;
  return spawnAndWait(environment.targets.tmux, ["attach", "-t", sessionName], { cwd });
}

function printDoctor(environment, config) {
  const surface = normalizeSurface(process.env.TALKIE_SURFACE);
  console.log(`${BOLD}Environment${RESET}`);
  console.log(`  user:      ${environment.username}`);
  console.log(`  host:      ${environment.hostname}`);
  console.log(`  home:      ${environment.homeDirectory}`);
  console.log(`  shell:     ${config?.shellPath ?? environment.shellPath}`);
  console.log(`  workspace: ${config?.workspace ?? environment.defaultWorkspace}`);
  console.log(`  surface:   ${surface}`);
  console.log(`  session:   ${sessionNameForSurface(surface)}`);
  console.log(`  config:    ${getConfigPath()}`);
  console.log(`  talkie:    ${getTalkieHome()}`);
  console.log("");
  console.log(`${BOLD}Tools${RESET}`);
  console.log(`  node:      ${environment.targets.node ?? "missing"}`);
  console.log(`  npm:       ${environment.targets.npm ?? "missing"}`);
  console.log(`  claude:    ${environment.targets.claude ?? "missing"}`);
  console.log(`  opencode:  ${environment.targets.opencode ?? "missing"}`);
  console.log(`  tmux:      ${environment.targets.tmux ?? "missing"}`);
  console.log("");
  console.log(`${BOLD}tmux${RESET}`);
  if (!environment.tmux.installed) {
    console.log("  tmux is not installed.");
  } else if (environment.tmux.sessions.length === 0) {
    console.log("  No tmux sessions found.");
  } else {
    for (const session of environment.tmux.sessions) {
      const attached = session.attached ? "attached" : "detached";
      console.log(`  ${session.name} (${session.windows} windows, ${attached})`);
    }
  }
}

function resolveMenuSelection(choice, environment) {
  const normalized = (choice ?? "").trim();
  if (normalized.length === 0) {
    return { kind: "target", value: "shell" };
  }

  const target = normalizeTarget(normalized);
  if (target) {
    return { kind: "target", value: target };
  }

  const tmuxMatch = normalized.match(/^t(\d+)$/i);
  if (tmuxMatch) {
    const index = Number.parseInt(tmuxMatch[1], 10) - 1;
    const session = environment.tmux.sessions[index];
    if (session) {
      return { kind: "tmux", value: session.name };
    }
  }

  const namedSession = environment.tmux.sessions.find((session) => session.name === normalized);
  if (namedSession) {
    return { kind: "tmux", value: namedSession.name };
  }

  return null;
}

function printAppBoard(cards, selectedId) {
  console.log(`${BOLD}Launch${RESET}`);
  printCardGrid(cards, {
    ...gridLayout(2),
    selectedId,
  });
}

function printTmuxBoard(environment, cards, selectedId) {
  console.log(`${BOLD}tmux Sessions${RESET}`);

  if (!environment.tmux.installed) {
    console.log(`${DIM}tmux is not installed on this Mac yet.${RESET}\n`);
    return;
  }

  if (cards.length === 0) {
    console.log(`${DIM}No tmux sessions found yet.${RESET}\n`);
    return;
  }

  printCardGrid(cards, {
    ...gridLayout(2),
    selectedId,
  });
}

function renderMenu(environment, config, entries, selectedIndex) {
  const selectedId = entries[selectedIndex]?.id ?? null;
  const appCards = entries.filter((entry) => entry.section === "apps");
  const tmuxCards = entries.filter((entry) => entry.section === "tmux");

  if (isCompactMenuSurface()) {
    renderCompactMenu(environment, config, entries, selectedIndex, renderMenu.frame ?? 0);
    return;
  }

  printBanner(environment.hostname, environment, config);
  printAppBoard(appCards, selectedId);
  printTmuxBoard(environment, tmuxCards, selectedId);
  console.log(`${DIM}Tab / arrows move · Return launches · q exits to shell${RESET}`);
}

function compactEntryLine(entry) {
  switch (entry.kind) {
    case "tmux":
      return "Reattach      Talkie session";
    case "target":
      switch (entry.value) {
        case "opencode":
          return "OpenCode      workspace";
        case "claude":
          return "Claude Code   workspace";
        case "shell":
          return "Shell         controlled";
        default:
          return `${entry.title}`;
      }
    default:
      return `${entry.title}`;
  }
}

function selectionForEntry(entry) {
  return entry
    ? { kind: entry.kind, value: entry.value }
    : { kind: "target", value: "shell" };
}

function compactEntryDetail(entry) {
  if (entry.kind === "tmux") {
    return "session";
  }

  switch (entry.value) {
    case "opencode":
    case "claude":
      return "workspace";
    case "shell":
      return "controlled";
    default:
      return "";
  }
}

function CompactMenuApp({ environment, config, entries, initialIndex, onSelect }) {
  const [selectedIndex, setSelectedIndex] = useState(Math.max(0, initialIndex));
  const workspace = path.basename(config.workspace || environment.defaultWorkspace || environment.homeDirectory || "~");
  const visibleEntries = entries.slice(0, 4);
  const palette = currentThemePalette();

  useKeyboard((key) => {
    if (!visibleEntries.length) {
      onSelect({ kind: "target", value: "shell" });
      return;
    }

    if (key.ctrl && key.name === "c") {
      onSelect({ kind: "target", value: "shell" });
      return;
    }

    switch (key.name) {
      case "1":
      case "2":
      case "3":
      case "4": {
        const numericIndex = Number.parseInt(key.name, 10) - 1;
        onSelect(selectionForEntry(visibleEntries[numericIndex] ?? visibleEntries[0]));
        return;
      }
      case "tab":
      case "down":
      case "j":
      case "right":
        setSelectedIndex((index) => (index + 1) % visibleEntries.length);
        return;
      case "up":
      case "k":
      case "left":
        setSelectedIndex((index) => (index - 1 + visibleEntries.length) % visibleEntries.length);
        return;
      case "return":
      case "enter":
        onSelect(selectionForEntry(visibleEntries[selectedIndex] ?? visibleEntries[0]));
        return;
      case "escape":
      case "q":
        onSelect({ kind: "target", value: "shell" });
        return;
      default:
        return;
    }
  });

  return React.createElement(
    "box",
    {
      style: {
        width: "100%",
        height: "100%",
        ...(palette.background ? { backgroundColor: palette.background } : {}),
        ...(palette.body ? { foregroundColor: palette.body } : {}),
        paddingLeft: 2,
        paddingRight: 2,
        paddingTop: 1,
        paddingBottom: 1,
        flexDirection: "column",
        justifyContent: "center",
      },
    },
    React.createElement(
      "box",
      {
        style: {
          width: "100%",
          flexDirection: "column",
          alignItems: "center",
          marginBottom: 1,
          ...(palette.wordmark ? { foregroundColor: palette.wordmark } : {}),
        },
      },
      React.createElement("ascii-font", {
        text: "TALKIE",
        font: "tiny",
      }),
      React.createElement("text", palette.meta ? { foregroundColor: palette.meta } : null, `Terminal on ${environment.hostname}`),
      React.createElement("text", palette.meta ? { foregroundColor: palette.meta } : null, `${APPLE_GLYPH}  ${workspace} · ready`),
    ),
    React.createElement(
      "box",
      {
        style: {
          width: "100%",
          flexDirection: "column",
          gap: 0,
        },
      },
      ...visibleEntries.map((entry, index) => {
        const selected = index === selectedIndex;
        return React.createElement(
          "box",
          {
            key: entry.id,
            style: {
              width: "100%",
              flexDirection: "row",
              justifyContent: "space-between",
              paddingLeft: 1,
              paddingRight: 1,
              marginBottom: 0,
              ...(selected && palette.selectedBackground ? { backgroundColor: palette.selectedBackground } : {}),
              ...(selected && palette.selectedForeground ? { foregroundColor: palette.selectedForeground } : {}),
              ...(!selected && palette.body ? { foregroundColor: palette.body } : {}),
            },
          },
          React.createElement(
            "text",
            selected
              ? (palette.selectedForeground ? { foregroundColor: palette.selectedForeground } : null)
              : (palette.body ? { foregroundColor: palette.body } : null),
            `${index + 1}  ${entry.title.replace(/^\d+\s+/, "")}`,
          ),
          React.createElement(
            "text",
            selected
              ? (palette.selectedDetail ? { foregroundColor: palette.selectedDetail } : null)
              : (palette.detail ? { foregroundColor: palette.detail } : null),
            compactEntryDetail(entry),
          ),
        );
      }),
    ),
    React.createElement(
      "box",
      {
        style: {
          width: "100%",
          marginTop: 1,
          alignItems: "center",
        },
      },
      React.createElement("text", palette.meta ? { foregroundColor: palette.meta } : null, "return · tab · q"),
    ),
  );
}

async function chooseSelectionWithOpenTUI(environment, config, entries, initialIndex) {
  const renderer = await createCliRenderer();
  const root = createRoot(renderer);
  const visibleEntries = entries.slice(0, 4);

  return await new Promise((resolve) => {
    let settled = false;

    const finish = (selection) => {
      if (settled) {
        return;
      }
      settled = true;
      root.unmount();
      if (typeof renderer.destroy === "function") {
        renderer.destroy();
      }
      resolve(selection);
    };

    root.render(React.createElement(CompactMenuApp, {
      environment,
      config,
      entries: visibleEntries,
      initialIndex,
      onSelect: finish,
    }));
  });
}

function renderCompactMenu(environment, config, entries, selectedIndex) {
  const workspace = path.basename(config.workspace || environment.defaultWorkspace || environment.homeDirectory || "~");
  const lines = [
    " _____     _ _    _      ",
    "|_   _|_ _| | | _(_) ___ ",
    "  | |/ _` | | |/ / |/ _ \\",
    "  | | (_| | |   <| |  __/",
    "  |_|\\__,_|_|_|\\_\\_|\\___|",
  ];

  process.stdout.write("\u001Bc");
  console.log("");
  for (const [index, line] of lines.entries()) {
    console.log(centerRenderedText(styleWordmarkLine(line, index + 7), line.length));
  }
  console.log("");
  const title = `${BOLD}Terminal${RESET} ${DIM}on ${stylize(environment.hostname, GREEN)}${RESET}`;
  const titlePlain = `Terminal on ${environment.hostname}`;
  console.log(centerRenderedText(title, titlePlain.length));
  const meta = `${DIM}${APPLE_GLYPH}  ${workspace} · ready${RESET}`;
  const metaPlain = `${APPLE_GLYPH}  ${workspace} · ready`;
  console.log(centerRenderedText(meta, metaPlain.length));
  console.log("");

  const visibleEntries = entries.slice(0, 4);
  for (const [index, entry] of visibleEntries.entries()) {
    const selected = index === selectedIndex;
    const plainBody = `${index + 1}  ${compactEntryLine(entry)}`;
    const prefix = selected ? `${BOLD}${ACCENT}›${RESET}` : `${DIM} ${RESET}`;
    const body = selected
      ? `${BOLD}${ACCENT}${plainBody}${RESET}`
      : `${SOFT}${plainBody}${RESET}`;
    console.log(centerRenderedText(`${prefix} ${body}`, plainBody.length + 2));
  }

  console.log("");
  const footer = `${DIM}return · tab · q${RESET}`;
  console.log(centerRenderedText(footer, "return · tab · q".length));
}

async function chooseSelectionInteractively(environment, config, entries) {
  const ttyReady = Boolean(process.stdin.isTTY && typeof process.stdin.setRawMode === "function");
  if (!ttyReady) {
    renderMenu(environment, config, entries, entries.findIndex((entry) => entry.id === "target:shell"));
    process.stdout.write(`${BOLD}> ${RESET}`);

    const choice = await new Promise((resolve) => {
      process.stdin.resume();
      process.stdin.setEncoding("utf8");
      process.stdin.once("data", (data) => resolve(String(data ?? "").trim()));
    });

    return resolveMenuSelection(choice, environment) ?? { kind: "target", value: "shell" };
  }

  let selectedIndex = entries.findIndex((entry) => entry.id === "target:shell");
  if (selectedIndex < 0) {
    selectedIndex = 0;
  }

  if (isCompactMenuSurface()) {
    try {
      return await chooseSelectionWithOpenTUI(environment, config, entries, selectedIndex);
    } catch (error) {
      console.error(`${DIM}OpenTUI fallback: ${error instanceof Error ? error.message : String(error)}${RESET}`);
    }
  }

  readline.emitKeypressEvents(process.stdin);
  enterAlternateScreen();
  process.stdin.setRawMode(true);
  process.stdin.resume();

  return new Promise((resolve) => {
    function cleanup(selection) {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdin.removeListener("keypress", handleKeypress);
      exitAlternateScreen();
      resolve(selection);
    }

    function move(delta) {
      if (entries.length === 0) {
        return;
      }
      selectedIndex = (selectedIndex + delta + entries.length) % entries.length;
      renderMenu(environment, config, entries, selectedIndex);
    }

    function handleKeypress(_, key = {}) {
      if (key.ctrl && key.name === "c") {
        cleanup({ kind: "target", value: "shell" });
        return;
      }

      if (key.name === "tab") {
        move(key.shift ? -1 : 1);
        return;
      }

      switch (key.name) {
        case "1":
          cleanup({ kind: "target", value: "opencode" });
          return;
        case "2":
          cleanup({ kind: "target", value: "claude" });
          return;
        case "3":
          cleanup({ kind: "target", value: "shell" });
          return;
        case "4":
          if (entries.some((entry) => entry.kind === "tmux")) {
            const tmuxEntry = entries.find((entry) => entry.kind === "tmux");
            if (tmuxEntry) {
              cleanup({ kind: "tmux", value: tmuxEntry.value });
              return;
            }
          }
          return;
        case "right":
        case "down":
        case "j":
          move(1);
          return;
        case "left":
        case "up":
        case "k":
          move(-1);
          return;
        case "return":
        case "enter":
          cleanup({
            kind: entries[selectedIndex].kind,
            value: entries[selectedIndex].value,
          });
          return;
        case "escape":
        case "q":
          cleanup({ kind: "target", value: "shell" });
          return;
        default:
          return;
      }
    }

    process.stdin.on("keypress", handleKeypress);
    renderMenu(environment, config, entries, selectedIndex);
  });
}

async function openMenu(environment, config, options = {}) {
  if (options.default) {
    return launchTarget(config.preferredTarget, config, environment);
  }

  const entries = buildMenuEntries(environment);
  const selection = await chooseSelectionInteractively(environment, config, entries);
  return selection.kind === "tmux"
    ? attachTmuxSession(selection.value, environment, config)
    : launchTarget(selection.value, config, environment);
}

async function main() {
  const program = new Command();
  program
    .name("talkie-companion")
    .description("Predictable SSH-side entrypoints for Talkie")
    .option("--json", "emit machine-readable output")
    .option("--pretty", "force human-readable output");

  program
    .command("bootstrap")
    .description("Detect shell/home/workspace defaults and write Talkie companion config")
    .option("--shell <path>", "override the detected login shell")
    .option("--workspace <path>", "override the default workspace")
    .option("--preferred-target <target>", "set claude, opencode, or shell as the default")
    .option("--quiet", "suppress human-readable output")
    .action((options, command) => {
      const globals = command.optsWithGlobals();
      const json = Boolean(globals.json) && !globals.pretty;
      const environment = collectEnvironment();
      const config = buildConfig(environment, {
        shell: options.shell,
        workspace: options.workspace,
        preferredTarget: normalizeTarget(options.preferredTarget) ?? undefined,
      });

      ensureTalkieHome();
      saveConfig(config);

      const result = {
        ok: true,
        config,
        environment: {
          shellPath: environment.shellPath,
          defaultWorkspace: environment.defaultWorkspace,
          targets: environment.targets,
        },
      };

      if (json) {
        outputJson(result);
        return;
      }

      if (!options.quiet) {
        console.log(`${GREEN}✓${RESET} Talkie companion is ready`);
        console.log(`  shell:     ${config.shellPath}`);
        console.log(`  workspace: ${config.workspace}`);
        console.log(`  target:    ${config.preferredTarget}`);
        console.log(`  config:    ${getConfigPath()}`);
      }
    });

  program
    .command("doctor")
    .description("Report the current SSH companion environment")
    .action((_, command) => {
      const globals = command.optsWithGlobals();
      const json = Boolean(globals.json) && !globals.pretty;
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const result = {
        ok: true,
        config,
        environment,
      };

      if (json) {
        outputJson(result);
        return;
      }

      printDoctor(environment, config);
    });

  const tmux = program.command("tmux").description("Inspect tmux from the SSH companion");
  tmux
    .command("list")
    .description("List available tmux sessions")
    .action((_, command) => {
      const globals = command.optsWithGlobals();
      const json = Boolean(globals.json) && !globals.pretty;
      const environment = collectEnvironment();
      const result = {
        ok: true,
        tmux: environment.tmux,
      };

      if (json) {
        outputJson(result);
        return;
      }

      if (!environment.tmux.installed) {
        console.log("tmux is not installed.");
        return;
      }

      if (environment.tmux.sessions.length === 0) {
        console.log("No tmux sessions found.");
        return;
      }

      for (const session of environment.tmux.sessions) {
        console.log(`- ${session.name} (${session.windows} windows${session.attached ? ", attached" : ""})`);
      }
    });

  tmux
    .command("attach <session>")
    .description("Attach to a tmux session by name")
    .action(async (session) => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await attachTmuxSession(session, environment, config);
      process.exit(exitCode);
    });

  program
    .command("launch <target>")
    .description("Launch claude, opencode, or return to the shell")
    .action(async (target) => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const normalizedTarget = normalizeTarget(target);
      if (!normalizedTarget) {
        console.error(`Unknown target: ${target}`);
        process.exit(1);
      }

      const exitCode = await launchTarget(normalizedTarget, config, environment);
      process.exit(exitCode);
    });

  const agent = program.command("agent").description("Resolve Talkie agent console launch policy");
  agent
    .command("resolve")
    .description("Resolve the preferred local agent harness into a concrete launch spec")
    .option("--profile <id>", "profile id such as talkie-agent, claude-agent, or local-shell")
    .option("--requested-target <target>", "requested target such as opencode, claude, or shell")
    .option("--workspace <path>", "workspace directory for the console session")
    .option("--preferred-model <model>", "preferred model override for OpenCode")
    .option("--tmux", "prefer tmux-backed persistence when available")
    .action(async (options, command) => {
      const globals = command.optsWithGlobals();
      const json = Boolean(globals.json) && !globals.pretty;
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const result = await buildAgentLaunchSpec(options, config, environment);
      const payload = {
        ok: true,
        profile: options.profile ?? null,
        config,
        environment: {
          shellPath: environment.shellPath,
          defaultWorkspace: environment.defaultWorkspace,
          targets: environment.targets,
          tmux: environment.tmux,
        },
        ...result,
      };

      if (json) {
        outputJson(payload);
        return;
      }

      console.log(`${GREEN}✓${RESET} Resolved Talkie agent launch`);
      console.log(`  requested: ${payload.requestedTarget}`);
      console.log(`  resolved:  ${payload.resolvedTarget}`);
      console.log(`  reason:    ${payload.reason}`);
      console.log(`  exec:      ${payload.launchSpec.executablePath}`);
      console.log(`  cwd:       ${payload.launchSpec.workingDirectory}`);
      console.log(`  tmux:      ${payload.launchSpec.sessionMode.kind}`);
    });

  program
    .command("shell")
    .description("Open Talkie's controlled shell without tmux")
    .action(async () => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await launchControlledShell(config, environment);
      process.exit(exitCode);
    });

  program
    .command("session")
    .description("Attach to Talkie's persistent tmux-backed Talkie session")
    .action(async () => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await ensureContextSession(config, environment);
      process.exit(exitCode);
    });

  program
    .command("enter")
    .description("Open the Talkie SSH landing menu")
    .action(async () => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await openMenu(environment, config);
      process.exit(exitCode);
    });

  program
    .command("clean")
    .description("Compatibility alias for `shell`")
    .action(async () => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await launchControlledShell(config, environment);
      process.exit(exitCode);
    });

  program
    .command("context")
    .description("Compatibility alias for `session`")
    .action(async () => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await ensureContextSession(config, environment);
      process.exit(exitCode);
    });

  program
    .command("menu")
    .description("Open the Talkie SSH landing menu")
    .option("--default", "launch the preferred target without prompting")
    .action(async (options) => {
      const environment = collectEnvironment();
      const config = loadOrCreateConfig(environment);
      const exitCode = await openMenu(environment, config, { default: options.default });
      process.exit(exitCode);
    });

  await program.parseAsync(process.argv);
}

main().catch((error) => {
  exitAlternateScreen();
  console.error(`${YELLOW}Talkie companion failed:${RESET} ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});

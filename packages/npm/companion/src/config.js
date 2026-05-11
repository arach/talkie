import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const TALKIE_HOME = path.join(os.homedir(), ".talkie-shell");
const CONFIG_PATH = path.join(TALKIE_HOME, "config.json");

export function getTalkieHome() {
  return TALKIE_HOME;
}

export function getConfigPath() {
  return CONFIG_PATH;
}

export function ensureTalkieHome() {
  mkdirSync(TALKIE_HOME, { recursive: true, mode: 0o700 });
}

export function loadConfig() {
  if (!existsSync(CONFIG_PATH)) {
    return null;
  }

  try {
    return JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  } catch {
    return null;
  }
}

export function saveConfig(config) {
  ensureTalkieHome();
  writeFileSync(CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`, {
    mode: 0o600,
  });
}

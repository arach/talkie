/**
 * labs/log.ts - File logger for TalkieBridge Labs server
 *
 * Separate log files to avoid mixing with main bridge logs.
 */

import { appendFile } from "node:fs/promises";
import { BRIDGE_DATA_DIR } from "../paths";

const LOG_FILE = `${BRIDGE_DATA_DIR}/labs.log`;
const DEV_LOG_FILE = `${BRIDGE_DATA_DIR}/labs.dev.log`;

function formatTimestamp(): string {
  return new Date().toISOString();
}

async function writeLog(level: string, message: string) {
  const line = `[${formatTimestamp()}] [${level}] ${message}\n`;

  if (level === "ERROR") {
    console.error(message);
  } else {
    console.log(message);
  }

  try {
    await appendFile(LOG_FILE, line);
  } catch (err) {
    console.error("Failed to write labs log:", err);
  }
}

async function writeDevLog(level: string, message: string) {
  const line = `[${formatTimestamp()}] [${level}] ${message}\n`;
  console.log(`[LABS] ${message}`);

  try {
    await appendFile(DEV_LOG_FILE, line);
  } catch (err) {
    console.error("Failed to write labs dev log:", err);
  }
}

export const labsLog = {
  info: (message: string) => writeLog("INFO", message),
  warn: (message: string) => writeLog("WARN", message),
  error: (message: string) => writeLog("ERROR", message),
  request: (method: string, path: string, status?: number) => {
    const msg = status ? `${method} ${path} -> ${status}` : `${method} ${path}`;
    writeLog("REQ", msg);
  },

  debug: (message: string) => writeDevLog("DEBUG", message),
};

export async function clearLabsLog() {
  const ts = formatTimestamp();
  try {
    await Bun.write(LOG_FILE, `[${ts}] [INFO] === Labs started ===\n`);
    await Bun.write(DEV_LOG_FILE, `[${ts}] [INFO] === Labs dev log started ===\n`);
  } catch (err) {
    console.error("Failed to clear labs logs:", err);
  }
}

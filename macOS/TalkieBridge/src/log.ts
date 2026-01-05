/**
 * log.ts - Simple file logger for TalkieBridge
 *
 * Writes timestamped logs to ~/Library/Application Support/TalkieBridge/bridge.log
 * Also outputs to console for debugging
 */

import { appendFile } from "fs/promises";
import { LOG_FILE } from "./paths";

function formatTimestamp(): string {
  return new Date().toISOString();
}

async function writeLog(level: string, message: string) {
  const line = `[${formatTimestamp()}] [${level}] ${message}\n`;

  // Console output
  if (level === "ERROR") {
    console.error(message);
  } else {
    console.log(message);
  }

  // File output (directories created by ensureDirectories in server.ts)
  try {
    await appendFile(LOG_FILE, line);
  } catch (err) {
    console.error("Failed to write log:", err);
  }
}

export const log = {
  info: (message: string) => writeLog("INFO", message),
  debug: (message: string) => writeLog("DEBUG", message),
  warn: (message: string) => writeLog("WARN", message),
  error: (message: string) => writeLog("ERROR", message),
  request: (method: string, path: string, status?: number) => {
    const msg = status
      ? `${method} ${path} -> ${status}`
      : `${method} ${path}`;
    writeLog("REQ", msg);
  },
};

// Clear log on startup (keep it fresh)
export async function clearLog() {
  try {
    await Bun.write(LOG_FILE, `[${formatTimestamp()}] [INFO] === Bridge started ===\n`);
  } catch (err) {
    console.error("Failed to clear log:", err);
  }
}

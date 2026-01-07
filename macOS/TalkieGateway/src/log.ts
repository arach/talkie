/**
 * log.ts - Simple file logger for TalkieGateway
 *
 * Two log files:
 * - gateway.log: User-facing logs (info, warn, error, requests)
 * - gateway.dev.log: Developer logs (auth, debug, verbose troubleshooting)
 */

import { appendFile } from "fs/promises";
import { LOG_FILE, DEV_LOG_FILE } from "./paths";

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

async function writeDevLog(level: string, message: string) {
  const line = `[${formatTimestamp()}] [${level}] ${message}\n`;

  // Console output (dev logs always to console for debugging)
  console.log(`[DEV] ${message}`);

  // Dev log file only
  try {
    await appendFile(DEV_LOG_FILE, line);
  } catch (err) {
    console.error("Failed to write dev log:", err);
  }
}

export const log = {
  // User-facing logs (bridge.log)
  info: (message: string) => writeLog("INFO", message),
  warn: (message: string) => writeLog("WARN", message),
  error: (message: string) => writeLog("ERROR", message),
  request: (method: string, path: string, status?: number) => {
    const msg = status
      ? `${method} ${path} -> ${status}`
      : `${method} ${path}`;
    writeLog("REQ", msg);
  },

  // Dev-only logs (bridge.dev.log)
  debug: (message: string) => writeDevLog("DEBUG", message),
  auth: (message: string, context?: Record<string, unknown>) => {
    const ctx = context ? ` ${JSON.stringify(context)}` : "";
    writeDevLog("AUTH", `${message}${ctx}`);
  },
  crypto: (message: string, context?: Record<string, unknown>) => {
    const ctx = context ? ` ${JSON.stringify(context)}` : "";
    writeDevLog("CRYPTO", `${message}${ctx}`);
  },
};

// Clear logs on startup (keep them fresh)
export async function clearLog() {
  const ts = formatTimestamp();
  try {
    await Bun.write(LOG_FILE, `[${ts}] [INFO] === Gateway started ===\n`);
    await Bun.write(DEV_LOG_FILE, `[${ts}] [INFO] === Dev log started ===\n`);
  } catch (err) {
    console.error("Failed to clear logs:", err);
  }
}

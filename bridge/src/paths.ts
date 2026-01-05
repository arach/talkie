/**
 * Central path configuration for TalkieBridge
 *
 * Uses ~/Library/Application Support/TalkieBridge/ for runtime data
 * This is the standard macOS location for app data
 */

const HOME = process.env.HOME || "";

// Base directory for all TalkieBridge data
export const BRIDGE_DATA_DIR = `${HOME}/Library/Application Support/TalkieBridge`;

// Subdirectories
export const KEYS_DIR = `${BRIDGE_DATA_DIR}/keys`;
export const LOGS_DIR = BRIDGE_DATA_DIR;  // logs in root for now

// Files
export const PID_FILE = `${BRIDGE_DATA_DIR}/bridge.pid`;
export const LOG_FILE = `${BRIDGE_DATA_DIR}/bridge.log`;
export const DEVICES_FILE = `${BRIDGE_DATA_DIR}/devices.json`;
export const MAPPINGS_FILE = `${BRIDGE_DATA_DIR}/confirmed-mappings.json`;

// Ensure directories exist
export async function ensureDirectories(): Promise<void> {
  const { mkdir } = await import("node:fs/promises");
  await mkdir(BRIDGE_DATA_DIR, { recursive: true });
  await mkdir(KEYS_DIR, { recursive: true });
}

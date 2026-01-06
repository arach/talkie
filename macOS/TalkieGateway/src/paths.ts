/**
 * Central path configuration for TalkieBridge
 *
 * Uses ~/Library/Application Support/Talkie/Bridge/ for runtime data
 * Follows Talkie's convention of storing under the Talkie app support folder
 * Sensitive files (keys, configs) are hidden with dot prefix
 */

const HOME = process.env.HOME || "";

// Base directories - nested under Talkie's app support
const TALKIE_APP_SUPPORT = `${HOME}/Library/Application Support/Talkie`;
export const BRIDGE_DATA_DIR = `${TALKIE_APP_SUPPORT}/Bridge`;

// Hidden directories for sensitive data
export const KEYS_DIR = `${BRIDGE_DATA_DIR}/.keys`;
export const CONFIG_DIR = `${BRIDGE_DATA_DIR}/.config`;

// Files (sensitive ones hidden)
export const PID_FILE = `${BRIDGE_DATA_DIR}/bridge.pid`;
export const LOG_FILE = `${BRIDGE_DATA_DIR}/bridge.log`;
export const DEV_LOG_FILE = `${BRIDGE_DATA_DIR}/bridge.dev.log`;
export const DEVICES_FILE = `${CONFIG_DIR}/devices.json`;
export const MAPPINGS_FILE = `${CONFIG_DIR}/mappings.json`;

// Ensure directories exist
export async function ensureDirectories(): Promise<void> {
  const { mkdir } = await import("node:fs/promises");
  await mkdir(BRIDGE_DATA_DIR, { recursive: true });
  await mkdir(KEYS_DIR, { recursive: true });
  await mkdir(CONFIG_DIR, { recursive: true });
}

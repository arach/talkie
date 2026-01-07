/**
 * Central path configuration for TalkieGateway
 *
 * Uses ~/Library/Application Support/Talkie/Gateway/ for runtime data
 * Follows Talkie's convention of storing under the Talkie app support folder
 * Sensitive files (keys, configs) are hidden with dot prefix
 */

const HOME = process.env.HOME || "";

// Base directories - nested under Talkie's app support
const TALKIE_APP_SUPPORT = `${HOME}/Library/Application Support/Talkie`;
export const GATEWAY_DATA_DIR = `${TALKIE_APP_SUPPORT}/Gateway`;

// Legacy alias for gradual migration
export const BRIDGE_DATA_DIR = GATEWAY_DATA_DIR;

// Hidden directories for sensitive data
export const KEYS_DIR = `${GATEWAY_DATA_DIR}/.keys`;
export const CONFIG_DIR = `${GATEWAY_DATA_DIR}/.config`;

// Files (sensitive ones hidden)
export const PID_FILE = `${GATEWAY_DATA_DIR}/gateway.pid`;
export const LOG_FILE = `${GATEWAY_DATA_DIR}/gateway.log`;
export const DEV_LOG_FILE = `${GATEWAY_DATA_DIR}/gateway.dev.log`;
export const DEVICES_FILE = `${CONFIG_DIR}/devices.json`;
export const MAPPINGS_FILE = `${CONFIG_DIR}/mappings.json`;

// Ensure directories exist
export async function ensureDirectories(): Promise<void> {
  const { mkdir } = await import("node:fs/promises");
  await mkdir(GATEWAY_DATA_DIR, { recursive: true });
  await mkdir(KEYS_DIR, { recursive: true });
  await mkdir(CONFIG_DIR, { recursive: true });
}

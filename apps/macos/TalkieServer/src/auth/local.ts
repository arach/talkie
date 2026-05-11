/**
 * Local Mode Authentication
 *
 * Provides simple bearer token authentication for local mode.
 * Token is generated on startup and written to a file that the Swift client can read.
 *
 * This ensures that even in local mode, only authorized processes (that can read
 * the token file) can access sensitive gateway endpoints.
 */

import { LOCAL_AUTH_TOKEN_FILE } from "../paths";
import { log } from "../log";

let localAuthToken: string | null = null;

/**
 * Generate a cryptographically secure random token
 */
function generateToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Initialize local auth token - generates and writes to file
 * Call this on server startup in local mode
 */
export async function initLocalAuthToken(): Promise<string> {
  localAuthToken = generateToken();

  // Write token to file (readable by Swift client)
  await Bun.write(LOCAL_AUTH_TOKEN_FILE, localAuthToken);
  const { chmod } = await import("node:fs/promises");
  await chmod(LOCAL_AUTH_TOKEN_FILE, 0o600);
  log.info(`Local auth token written to ${LOCAL_AUTH_TOKEN_FILE}`);

  return localAuthToken;
}

/**
 * Get the current local auth token (for logging/debugging only)
 */
export function getLocalAuthToken(): string | null {
  return localAuthToken;
}

/**
 * Verify a bearer token matches the local auth token
 */
export function verifyLocalAuthToken(authHeader: string | null): boolean {
  if (!localAuthToken) {
    log.warn("Local auth token not initialized");
    return false;
  }

  if (!authHeader) {
    return false;
  }

  // Expect "Bearer <token>" format
  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0] !== "Bearer") {
    return false;
  }

  const providedToken = parts[1];

  // Timing-safe comparison
  if (providedToken.length !== localAuthToken.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < providedToken.length; i++) {
    result |= providedToken.charCodeAt(i) ^ localAuthToken.charCodeAt(i);
  }

  return result === 0;
}

/**
 * Check if a path requires local auth (even in local mode)
 * Gateway inference endpoints should always require auth
 */
export function requiresLocalAuth(path: string): boolean {
  // Gateway inference endpoints require auth even in local mode
  if (path === "/inference") return true;
  if (path.startsWith("/inference/")) return true;
  if (path === "/workflows/run") return true;
  if (path.startsWith("/workflows/")) return true;
  if (path === "/cli") return true;
  if (path === "/headless") return true;

  return false;
}

export function requiresLocalOnlyAuth(path: string, method: string): boolean {
  return path === "/security/events" && method === "POST";
}

/**
 * Clean up token file on shutdown
 */
export async function cleanupLocalAuthToken(): Promise<void> {
  try {
    const { unlink } = await import("node:fs/promises");
    await unlink(LOCAL_AUTH_TOKEN_FILE);
    log.info("Local auth token file cleaned up");
  } catch {
    // File may not exist, ignore
  }
  localAuthToken = null;
}

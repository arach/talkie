/**
 * HMAC Request Authentication Middleware
 *
 * Verifies HMAC-SHA256 signatures on incoming requests.
 * Uses timestamp-based replay protection (30s window) + nonce tracking.
 *
 * Signature format: HMAC-SHA256(authKey, "{method}\n{path+query}\n{timestamp}\n{nonce}\n{bodyHash}")
 */

import { getDeviceAuthKey, updateLastSeen } from "../devices/registry";
import { nonceStore } from "./nonce";
import { log } from "../log";

const TIMESTAMP_TOLERANCE_SECONDS = 30;

export interface AuthResult {
  authenticated: boolean;
  deviceId?: string;
  error?: string;
  serverTime?: number;
}

/**
 * Verify HMAC signature on a request
 */
export async function verifyRequest(req: Request): Promise<AuthResult> {
  const deviceId = req.headers.get("X-Device-ID");
  const timestamp = req.headers.get("X-Timestamp");
  const nonce = req.headers.get("X-Nonce");
  const signature = req.headers.get("X-Signature");

  // 1. Check headers present
  if (!deviceId || !timestamp || !nonce || !signature) {
    log.auth("REJECT: Missing headers", { deviceId, hasTimestamp: !!timestamp, hasNonce: !!nonce, hasSig: !!signature });
    return { authenticated: false, error: "Missing auth headers" };
  }

  // 2. Check timestamp freshness (replay protection layer 1)
  const now = Math.floor(Date.now() / 1000);
  const reqTime = parseInt(timestamp, 10);
  if (isNaN(reqTime) || Math.abs(now - reqTime) > TIMESTAMP_TOLERANCE_SECONDS) {
    log.auth("REJECT: Expired", { deviceId, reqTime, now, drift: now - reqTime });
    return { authenticated: false, error: "Request expired", serverTime: now };
  }

  // 3. Check nonce uniqueness (replay protection layer 2)
  if (!nonceStore.check(nonce)) {
    log.auth("REJECT: Replay", { deviceId, nonce: nonce.slice(0, 16) });
    return { authenticated: false, error: "Replay detected" };
  }

  // 4. Look up device and get auth key
  let authKey: CryptoKey | null;
  try {
    authKey = await getDeviceAuthKey(deviceId);
  } catch (err) {
    log.auth("REJECT: Key derivation failed", { deviceId, error: String(err) });
    return { authenticated: false, error: "Key derivation failed - please re-pair device" };
  }

  if (!authKey) {
    log.auth("REJECT: Unknown device", { deviceId });
    return { authenticated: false, error: "Unknown device" };
  }

  // 5. Recompute signature (includes nonce)
  const url = new URL(req.url);
  const pathWithQuery = url.pathname + url.search;
  const bodyClone = req.clone();
  const bodyBytes = await bodyClone.arrayBuffer();
  const bodyHash = await sha256Hex(bodyBytes);

  // Debug: log POST body (truncated for large payloads)
  if (req.method === "POST") {
    const bodyText = new TextDecoder().decode(bodyBytes);
    const truncated = bodyText.length > 200 ? bodyText.slice(0, 200) + "..." : bodyText;
    log.info(`POST body: ${truncated}`);
  }

  const message = `${req.method}\n${pathWithQuery}\n${timestamp}\n${nonce}\n${bodyHash}`;
  const expectedSig = await hmacSha256Hex(authKey, message);

  // 6. Compare (timing-safe)
  if (!timingSafeEqual(signature, expectedSig)) {
    log.auth("REJECT: Signature mismatch", { deviceId, path: pathWithQuery });
    return { authenticated: false, error: "Invalid signature" };
  }

  log.auth("OK", { deviceId, path: pathWithQuery });

  // Update last seen (fire and forget)
  updateLastSeen(deviceId).catch(() => {});

  return { authenticated: true, deviceId };
}

/**
 * Create an authentication error response
 */
export function authErrorResponse(result: AuthResult): Response {
  const body: Record<string, unknown> = { error: result.error };
  if (result.serverTime !== undefined) {
    body.serverTime = result.serverTime;
  }
  return Response.json(body, { status: 401 });
}

/**
 * Check if a path is exempt from authentication
 */
export function isExemptPath(path: string, method: string): boolean {
  // Pairing and health endpoints don't require auth
  if (path === "/health" && method === "GET") return true;
  if (path === "/pair/info" && method === "GET") return true;
  if (path === "/pair" && method === "POST") return true;
  if (path === "/pair/pending" && method === "GET") return true;
  if (path.match(/^\/pair\/[^/]+\/approve$/) && method === "POST") return true;
  if (path.match(/^\/pair\/[^/]+\/reject$/) && method === "POST") return true;
  if (path === "/devices" && method === "GET") return true;

  // Extensions module has its own token-based auth at WebSocket layer
  if (path.startsWith("/extensions")) return true;

  return false;
}

// --- Crypto Helpers ---

/**
 * SHA256 hash to hex string
 */
async function sha256Hex(data: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", data);
  return bufferToHex(hash);
}

/**
 * HMAC-SHA256 to hex string
 */
async function hmacSha256Hex(key: CryptoKey, message: string): Promise<string> {
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message)
  );
  return bufferToHex(sig);
}

/**
 * Convert ArrayBuffer to lowercase hex string
 */
function bufferToHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Timing-safe string comparison
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

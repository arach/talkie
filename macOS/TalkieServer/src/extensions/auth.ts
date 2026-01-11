/**
 * Extensions Module - Authentication
 *
 * Token generation and validation for extension connections.
 * Tokens are rotated periodically and stored in memory.
 */

import { log } from "../log";

// ===== Configuration =====

const TOKEN_LENGTH = 32;
const TOKEN_ROTATION_INTERVAL_MS = 60 * 60 * 1000; // 1 hour
const AUTH_TIMEOUT_MS = 5000; // 5 seconds to authenticate

// ===== State =====

let currentToken: string | null = null;
let tokenGeneratedAt: number = 0;

// ===== Token Generation =====

/**
 * Generate a cryptographically secure token
 */
function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(TOKEN_LENGTH));
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Get or generate the current auth token.
 * Rotates token if it's too old.
 */
export function getAuthToken(): string {
  const now = Date.now();
  const tokenAge = now - tokenGeneratedAt;

  if (!currentToken || tokenAge > TOKEN_ROTATION_INTERVAL_MS) {
    currentToken = generateToken();
    tokenGeneratedAt = now;
    log.info(`Extensions: New auth token generated (${currentToken.slice(0, 8)}...)`);
  }

  return currentToken;
}

/**
 * Validate a token from an extension
 */
export function validateToken(token: string): boolean {
  if (!currentToken) {
    // No token generated yet - generate one and compare
    getAuthToken();
  }

  // Constant-time comparison to prevent timing attacks
  if (token.length !== currentToken!.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < token.length; i++) {
    result |= token.charCodeAt(i) ^ currentToken!.charCodeAt(i);
  }

  return result === 0;
}

/**
 * Force rotation of the auth token
 */
export function rotateToken(): string {
  currentToken = null;
  return getAuthToken();
}

/**
 * Get auth timeout in milliseconds
 */
export function getAuthTimeout(): number {
  return AUTH_TIMEOUT_MS;
}

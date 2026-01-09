/**
 * Simple Nonce Store for Replay Protection
 *
 * Tracks seen nonces with automatic TTL-based cleanup.
 * Reusable pattern for any request authentication.
 *
 * Usage:
 *   const nonces = new NonceStore({ ttlMs: 60_000 });
 *   if (!nonces.check(requestNonce)) {
 *     return { error: "Replay detected" };
 *   }
 */

export interface NonceStoreOptions {
  /** Time-to-live for nonces in milliseconds (default: 60s) */
  ttlMs?: number;
  /** How often to run cleanup in milliseconds (default: 30s) */
  cleanupIntervalMs?: number;
  /** Maximum nonces to store before forcing cleanup (default: 10000) */
  maxSize?: number;
}

export class NonceStore {
  private seen = new Map<string, number>(); // nonce -> expiry timestamp
  private readonly ttlMs: number;
  private readonly maxSize: number;
  private lastCleanup = 0;
  private readonly cleanupIntervalMs: number;

  constructor(options: NonceStoreOptions = {}) {
    this.ttlMs = options.ttlMs ?? 60_000; // 1 minute default
    this.cleanupIntervalMs = options.cleanupIntervalMs ?? 30_000;
    this.maxSize = options.maxSize ?? 10_000;
  }

  /**
   * Check if a nonce is valid (not seen before).
   * Automatically records the nonce if valid.
   *
   * @returns true if nonce is fresh, false if replay detected
   */
  check(nonce: string): boolean {
    this.maybeCleanup();

    // Reject if already seen
    if (this.seen.has(nonce)) {
      return false;
    }

    // Record the nonce
    this.seen.set(nonce, Date.now() + this.ttlMs);
    return true;
  }

  /**
   * Check if a nonce has been seen (without recording it)
   */
  hasSeen(nonce: string): boolean {
    return this.seen.has(nonce);
  }

  /**
   * Current number of tracked nonces
   */
  get size(): number {
    return this.seen.size;
  }

  /**
   * Clear all tracked nonces
   */
  clear(): void {
    this.seen.clear();
  }

  /**
   * Run cleanup if needed (time-based or size-based)
   */
  private maybeCleanup(): void {
    const now = Date.now();

    // Time-based cleanup
    if (now - this.lastCleanup > this.cleanupIntervalMs) {
      this.cleanup(now);
      return;
    }

    // Size-based cleanup (emergency)
    if (this.seen.size > this.maxSize) {
      this.cleanup(now);
    }
  }

  /**
   * Remove expired nonces
   */
  private cleanup(now: number): void {
    for (const [nonce, expiry] of this.seen) {
      if (expiry < now) {
        this.seen.delete(nonce);
      }
    }
    this.lastCleanup = now;
  }
}

// Singleton for the bridge (could also instantiate per-use)
export const nonceStore = new NonceStore({
  ttlMs: 60_000, // 1 minute - generous given 30s timestamp window
});

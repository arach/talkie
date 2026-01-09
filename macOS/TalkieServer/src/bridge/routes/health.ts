/**
 * Health Check Route
 *
 * GET /health - Returns server status and time for iOS clock synchronization
 */

// ===== Types =====

export interface HealthResponse {
  status: "ok";
  version: string;
  hostname: string;
  port: number;
  time: number;      // Unix epoch seconds
  timestamp: string; // ISO 8601
}

// ===== Handlers =====

/**
 * GET /health
 * Returns server time (Unix epoch seconds) for iOS clock synchronization
 */
export function healthRoute(hostname: string): HealthResponse {
  return {
    status: "ok",
    version: "0.1.0",
    hostname,
    port: 8765,
    time: Math.floor(Date.now() / 1000),
    timestamp: new Date().toISOString(),
  };
}

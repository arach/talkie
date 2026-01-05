/**
 * Health check endpoint
 * GET /health
 *
 * Returns server time (Unix epoch seconds) for iOS clock synchronization.
 */
export function healthRoute(req: Request, hostname: string): Response {
  return Response.json({
    status: "ok",
    version: "0.1.0",
    hostname,
    port: 8765,
    time: Math.floor(Date.now() / 1000), // Unix epoch seconds for clock sync
    timestamp: new Date().toISOString(),
  });
}

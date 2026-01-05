/**
 * Health check endpoint
 * GET /health
 */
export function healthRoute(req: Request, hostname: string): Response {
  return Response.json({
    status: "ok",
    version: "0.1.0",
    hostname,
    port: 8765,
    timestamp: new Date().toISOString(),
  });
}

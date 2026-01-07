export function healthRoute(port: number): Response {
  return Response.json({
    status: "ok",
    version: "0.1.0",
    port,
    time: Math.floor(Date.now() / 1000),
    timestamp: new Date().toISOString(),
  });
}

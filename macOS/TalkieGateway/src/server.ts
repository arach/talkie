/**
 * TalkieGateway Server
 *
 * Containerized LLM router. Runs in Apple container via Virtualization.framework.
 *
 * Endpoints:
 * - GET  /health         - Health check
 * - POST /llm/chat       - Chat completions
 * - GET  /llm/providers  - List providers
 * - GET  /llm/models     - List models
 */

import { chatRoute, providersRoute, modelsRoute } from "./routes/llm";

const PORT = parseInt(process.env.PORT || "8080", 10);
const VERSION = "0.3.0";

async function main() {
  console.log(`TalkieGateway v${VERSION} starting...`);

  const server = Bun.serve({
    port: PORT,
    async fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname;
      const method = req.method;
      const startTime = performance.now();

      const logResponse = (response: Response) => {
        const duration = Math.round(performance.now() - startTime);
        console.log(`${method} ${path} → ${response.status} (${duration}ms)`);
        return response;
      };

      try {
        // Health check
        if (path === "/health" && method === "GET") {
          return logResponse(
            Response.json({
              status: "ok",
              version: VERSION,
              uptime: process.uptime(),
              timestamp: new Date().toISOString(),
            })
          );
        }

        // LLM Router
        if (path === "/llm/chat" && method === "POST") {
          return logResponse(await chatRoute(req));
        }

        if (path === "/llm/providers" && method === "GET") {
          return logResponse(await providersRoute(req));
        }

        if (path === "/llm/models" && method === "GET") {
          return logResponse(await modelsRoute(req));
        }

        // 404
        console.warn(`404: ${path}`);
        return logResponse(
          Response.json({ error: "Not found" }, { status: 404 })
        );
      } catch (error) {
        const duration = Math.round(performance.now() - startTime);
        console.error(`${method} ${path} → ERROR (${duration}ms):`, error);
        return Response.json({ error: "Internal server error" }, { status: 500 });
      }
    },
  });

  console.log(`TalkieGateway running at http://0.0.0.0:${PORT}`);
  console.log("Endpoints:");
  console.log(`  GET  /health`);
  console.log(`  POST /llm/chat`);
  console.log(`  GET  /llm/providers`);
  console.log(`  GET  /llm/models`);

  // Graceful shutdown
  process.on("SIGINT", () => {
    console.log("Shutting down...");
    process.exit(0);
  });

  process.on("SIGTERM", () => {
    console.log("Shutting down...");
    process.exit(0);
  });
}

main().catch((err) => {
  console.error("Failed to start:", err);
  process.exit(1);
});

import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";
import fs from "node:fs/promises";

const saveBezierPlugin = (): Plugin => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const versionsDir = path.resolve(repoRoot, "assets", "logo-bezier", "versions");

  const toSlug = (label: string) => {
    const cleaned = label
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return cleaned.length > 0 ? cleaned : "version";
  };

  const timestamp = () =>
    new Date().toISOString().replace(/[:.]/g, "-");

  return {
    name: "save-bezier-endpoint",
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const url = new URL(req.url ?? "", "http://localhost");
        const pathname = url.pathname;

        if (req.method === "GET" && pathname === "/api/list-bezier-versions") {
          try {
            const entries = await fs.readdir(versionsDir, { withFileTypes: true });
            const versions = await Promise.all(
              entries
                .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
                .map(async (entry) => {
                  const absolutePath = path.join(versionsDir, entry.name);
                  const stats = await fs.stat(absolutePath);
                  return {
                    fileName: entry.name,
                    relativePath: path.relative(repoRoot, absolutePath),
                    absolutePath,
                    size: stats.size,
                    lastModified: stats.mtime.toISOString(),
                  };
                })
            );
            versions.sort(
              (a, b) =>
                new Date(b.lastModified).getTime() -
                new Date(a.lastModified).getTime()
            );
            res.statusCode = 200;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify(versions));
            return;
          } catch (error) {
            const code = (error as { code?: string }).code;
            if (code === "ENOENT") {
              res.statusCode = 200;
              res.setHeader("Content-Type", "application/json");
              res.end("[]");
              return;
            }
            const message = error instanceof Error ? error.message : "Unknown error";
            res.statusCode = 500;
            res.setHeader("Content-Type", "text/plain");
            res.end(message);
            return;
          }
        }

        if (req.method === "GET" && pathname === "/api/load-bezier") {
          try {
            const fileName = url.searchParams.get("file");
            if (!fileName) {
              res.statusCode = 400;
              res.setHeader("Content-Type", "text/plain");
              res.end("Missing file parameter.");
              return;
            }
            const safeName = path.basename(fileName);
            if (safeName !== fileName) {
              res.statusCode = 400;
              res.setHeader("Content-Type", "text/plain");
              res.end("Invalid file name.");
              return;
            }
            const absolutePath = path.join(versionsDir, safeName);
            const contents = await fs.readFile(absolutePath, "utf8");
            res.statusCode = 200;
            res.setHeader("Content-Type", "application/json");
            res.end(contents);
            return;
          } catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            res.statusCode = 500;
            res.setHeader("Content-Type", "text/plain");
            res.end(message);
            return;
          }
        }

        if (req.method === "POST" && pathname === "/api/save-bezier") {
          try {
            let body = "";
            for await (const chunk of req) {
              body += chunk;
            }
            const payload = JSON.parse(body) as { contents?: string; label?: string };
            if (!payload.contents || typeof payload.contents !== "string") {
              res.statusCode = 400;
              res.setHeader("Content-Type", "text/plain");
              res.end("Missing contents payload.");
              return;
            }
            const label = toSlug(payload.label ?? "");
            const fileName = `bowtie_bezier_${label}_${timestamp()}.json`;
            const absolutePath = path.join(versionsDir, fileName);
            await fs.mkdir(path.dirname(absolutePath), { recursive: true });
            await fs.writeFile(absolutePath, payload.contents, "utf8");
            const saved = await fs.readFile(absolutePath, "utf8");
            const stats = await fs.stat(absolutePath);

            const response = {
              ok: saved === payload.contents,
              fileName,
              relativePath: path.relative(repoRoot, absolutePath),
              absolutePath,
              size: stats.size,
              lastModified: stats.mtime.toISOString(),
            };
            res.statusCode = 200;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify(response));
            return;
          } catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            res.statusCode = 500;
            res.setHeader("Content-Type", "text/plain");
            res.end(message);
            return;
          }
        }

        next();
      });
    },
  };
};

export default defineConfig({
  plugins: [react(), saveBezierPlugin()],
  server: {
    fs: {
      allow: [path.resolve(__dirname, "..", "..")],
    },
  },
});

import { readFile } from "node:fs/promises";
import path from "node:path";

import { NextResponse } from "next/server";

export const runtime = "nodejs";

const moduleAssets = new Set([
  "state.js",
  "geometry.js",
  "layers.js",
  "hitTesting.js",
  "renderer.js",
  "bridge.js",
]);
const allowedAssets = new Set(["overlay.html", "overlay.css", "overlay.js", ...moduleAssets]);

const contentTypes: Record<string, string> = {
  "overlay.html": "text/html; charset=utf-8",
  "overlay.css": "text/css; charset=utf-8",
  "overlay.js": "application/javascript; charset=utf-8",
};

const overlayDir = path.resolve(
  process.cwd(),
  "..",
  "..",
  "apps",
  "macos",
  "TalkieAgent",
  "TalkieAgent",
  "Resources",
  "CaptureMarkup"
);

export async function GET(
  request: Request,
  context: { params: Promise<{ asset: string }> | { asset: string } }
) {
  const params = await context.params;
  const asset = params.asset;

  if (!allowedAssets.has(asset)) {
    return new NextResponse("Not found", { status: 404 });
  }

  const file = await readFile(
    moduleAssets.has(asset) ? path.join(overlayDir, "js", asset) : path.join(overlayDir, asset),
    "utf8"
  );
  const body = asset === "overlay.html"
    ? injectStudioHost(file, new URL(request.url).searchParams.get("theme"))
    : file;

  return new NextResponse(body, {
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": contentTypes[asset] ?? (asset.endsWith(".js") ? "application/javascript; charset=utf-8" : "text/plain; charset=utf-8"),
    },
  });
}

function injectStudioHost(html: string, theme: string | null) {
  const bridge = `
  <script>
    window.webkit = {
      messageHandlers: {
        talkie: {
          postMessage(message) {
            window.parent.postMessage({ source: "talkieLiveMarkup", message }, "*");
          }
        }
      }
    };
  </script>`;
  const themeStyle = `<style>${themeCss(theme)}</style>`;
  return html
    .replace('let base = "js/";', 'let base = "";')
    .replace("</head>", `${themeStyle}\n${bridge}</head>`);
}

function themeCss(theme: string | null) {
  switch (theme) {
  case "graphite":
    return `
      :root {
        --surface: #0F1012;
        --well: rgba(255, 255, 255, 0.03);
        --hairline: rgba(255, 255, 255, 0.08);
        --hairline-soft: rgba(255, 255, 255, 0.06);
      }
    `;
  case "warm":
    return `
      :root {
        --surface: #1E1B16;
        --well: rgba(0, 0, 0, 0.26);
        --hairline: rgba(223, 161, 58, 0.24);
        --hairline-soft: rgba(223, 161, 58, 0.12);
        --lift: 0 6px 20px rgba(0, 0, 0, 0.50);
      }
    `;
  case "paper":
    return `
      :root {
        color-scheme: light;
        --talkie-accent: #C47D1C;
        --talkie-accent-bright: #8A5A12;
        --talkie-ink: #FFF7E8;
        --surface: #F6F1E7;
        --well: rgba(40, 33, 20, 0.05);
        --active-fill: rgba(196, 125, 28, 0.13);
        --active-edge: rgba(196, 125, 28, 0.58);
        --hairline: rgba(40, 33, 20, 0.16);
        --hairline-soft: rgba(40, 33, 20, 0.09);
      }
      button { color: rgba(40, 33, 20, 0.74); }
      .tool { color: rgba(40, 33, 20, 0.74); }
      .action.cancel { color: rgba(40, 33, 20, 0.45); }
      .style-label { color: rgba(138, 90, 18, 0.85); }
      .style-panel-kicker { color: rgba(138, 90, 18, 0.85); }
      .style-panel-tool { color: rgba(40, 33, 20, 0.82); }
      .style-toggle { color: rgba(40, 33, 20, 0.74); }
      .style-chip-label { color: rgba(40, 33, 20, 0.82); }
      .style-chip-detail { color: rgba(40, 33, 20, 0.50); }
    `;
  default:
    return "";
  }
}

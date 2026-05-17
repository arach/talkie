import { readdir, readFile, stat } from "node:fs/promises";
import { basename, join } from "node:path";

const home = process.env.HOME ?? "";
const root =
  process.env.HYPER_SCAN_ROOT ??
  join(home, "Library/Application Support/Talkie/Bridge/HyperScan");
const transientRoot = join(root, ".transient");
const port = Number(process.env.PORT ?? "8787");

type BundleScope = "retained" | "transient";

interface BundleRef {
  id: string;
  scope: BundleScope;
  dir: string;
}

interface BundleSummary {
  id: string;
  scope: BundleScope;
  createdAt: string;
  receivedAt: string;
  captureKind: string;
  snapCount: number;
  fragmentCount: number;
  candidateCount: number;
  progress: number;
  expiresAt?: string;
}

function scopeDir(scope: BundleScope): string {
  return scope === "transient" ? transientRoot : root;
}

function safeSegment(value: string): string | null {
  const decoded = decodeURIComponent(value);
  if (!/^[A-Za-z0-9._-]+$/.test(decoded)) return null;
  if (decoded === "." || decoded === "..") return null;
  return decoded;
}

async function readManifest(ref: BundleRef): Promise<any | null> {
  try {
    const data = await readFile(join(ref.dir, "manifest.json"), "utf8");
    return JSON.parse(data);
  } catch {
    return null;
  }
}

function coverageOf(manifest: any): any {
  return manifest.coverage ?? manifest.terrain ?? {};
}

function captureKindOf(manifest: any): string {
  return manifest.captureKind ?? manifest.providerId ?? "hyper-scan";
}

function createdAtOf(manifest: any): string {
  return manifest.createdAt ?? manifest.receivedAt ?? "";
}

function receivedAtOf(manifest: any): string {
  return manifest.receivedAt ?? manifest.createdAt ?? "";
}

function progressOf(manifest: any): number {
  const coverage = coverageOf(manifest);
  const progress = Number(coverage.progress ?? manifest.progress ?? 0);
  if (!Number.isFinite(progress)) return 0;
  return progress > 1 ? Math.min(progress / 100, 1) : Math.min(Math.max(progress, 0), 1);
}

function summarize(ref: BundleRef, manifest: any): BundleSummary {
  return {
    id: ref.id,
    scope: ref.scope,
    createdAt: createdAtOf(manifest),
    receivedAt: receivedAtOf(manifest),
    captureKind: captureKindOf(manifest),
    snapCount: Array.isArray(manifest.snaps) ? manifest.snaps.length : 0,
    fragmentCount: Array.isArray(manifest.fragments) ? manifest.fragments.length : 0,
    candidateCount: Array.isArray(manifest.stitchCandidates)
      ? manifest.stitchCandidates.length
      : 0,
    progress: progressOf(manifest),
    expiresAt: manifest.expiresAt,
  };
}

async function bundleRefsFor(scope: BundleScope): Promise<BundleRef[]> {
  try {
    const dir = scopeDir(scope);
    const entries = await readdir(dir, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isDirectory())
      .filter((entry) => scope === "transient" || !entry.name.startsWith("."))
      .map((entry) => ({
        id: entry.name,
        scope,
        dir: join(dir, entry.name),
      }));
  } catch {
    return [];
  }
}

async function listBundles(): Promise<BundleSummary[]> {
  const refs = [
    ...(await bundleRefsFor("transient")),
    ...(await bundleRefsFor("retained")),
  ];
  const bundles: BundleSummary[] = [];

  for (const ref of refs) {
    const manifest = await readManifest(ref);
    if (!manifest) continue;
    bundles.push(summarize(ref, manifest));
  }

  return bundles.sort((left, right) => {
    const leftTime = Date.parse(left.receivedAt || left.createdAt || "0");
    const rightTime = Date.parse(right.receivedAt || right.createdAt || "0");
    return rightTime - leftTime;
  });
}

async function detailFor(scope: BundleScope, id: string) {
  const ref: BundleRef = { id, scope, dir: join(scopeDir(scope), id) };
  const manifest = await readManifest(ref);
  if (!manifest) return null;

  const snaps = Array.isArray(manifest.snaps) ? manifest.snaps : [];
  const images = await Promise.all(
    snaps.map(async (snap: any) => {
      const filename = safeSegment(String(snap.filename ?? ""));
      const filePath = filename ? join(ref.dir, filename) : "";
      let size = Number(snap.fileSizeBytes ?? 0);
      if (filePath) {
        try {
          size = (await stat(filePath)).size;
        } catch {
          size = Number(snap.fileSizeBytes ?? 0);
        }
      }

      return {
        id: snap.id ?? filename ?? "",
        filename,
        url: filename
          ? `/images/${scope}/${encodeURIComponent(id)}/${encodeURIComponent(filename)}`
          : null,
        size,
        role: snap.role ?? "detail",
        captureIndex: snap.captureIndex ?? 0,
        status: snap.status ?? "",
        displayFragment: snap.displayFragment ?? "",
        recognizedText: snap.recognizedText ?? "",
        fragments: Array.isArray(snap.fragments) ? snap.fragments : [],
        textLines: Array.isArray(snap.textLines) ? snap.textLines : [],
        pixelWidth: snap.pixelWidth ?? 0,
        pixelHeight: snap.pixelHeight ?? 0,
        quality: snap.quality ?? {},
        geometry: snap.geometry ?? null,
        motion: snap.motion ?? null,
      };
    })
  );

  return {
    root,
    id,
    scope,
    summary: summarize(ref, manifest),
    manifest: {
      ...manifest,
      captureKind: captureKindOf(manifest),
      coverage: coverageOf(manifest),
    },
    images,
  };
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function notFound(message: string): Response {
  return json({ ok: false, error: message }, 404);
}

async function serveImage(scope: BundleScope, id: string, filename: string): Promise<Response> {
  const safeId = safeSegment(id);
  const safeFile = safeSegment(filename);
  if (!safeId || !safeFile) return notFound("Invalid image path.");

  const filePath = join(scopeDir(scope), safeId, safeFile);
  const file = Bun.file(filePath);
  if (!(await file.exists())) return notFound("Image not found.");

  return new Response(file, {
    headers: {
      "content-type": file.type || "image/jpeg",
      "cache-control": "no-store",
    },
  });
}

function page(): Response {
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

const html = String.raw`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Hyper Scan Viewer</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1110;
      --panel: #151d19;
      --panel-2: #101713;
      --line: #2b3831;
      --text: #ecf4ee;
      --muted: #9baaa1;
      --soft: #c5d2ca;
      --green: #63d68d;
      --blue: #7fc7ff;
      --amber: #efc56c;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: 0;
    }

    button {
      color: inherit;
      font: inherit;
    }

    .app {
      min-height: 100vh;
      display: grid;
      grid-template-columns: 330px minmax(0, 1fr);
    }

    aside {
      border-right: 1px solid var(--line);
      background: #0f1512;
      min-height: 100vh;
      position: sticky;
      top: 0;
      align-self: start;
    }

    header {
      padding: 18px 20px;
      border-bottom: 1px solid var(--line);
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 16px;
    }

    h1 {
      margin: 0;
      font-size: 22px;
      line-height: 1.1;
    }

    .root {
      margin-top: 6px;
      color: var(--muted);
      font-size: 12px;
      word-break: break-all;
    }

    .refresh {
      border: 1px solid var(--line);
      background: #1d2a22;
      border-radius: 8px;
      padding: 9px 12px;
      cursor: pointer;
    }

    .list {
      padding: 14px;
      display: grid;
      gap: 10px;
    }

    .bundle {
      width: 100%;
      text-align: left;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      padding: 12px;
      cursor: pointer;
    }

    .bundle:hover,
    .bundle.active {
      border-color: color-mix(in srgb, var(--green), white 16%);
      background: #19241f;
    }

    .bundle-id {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
      font-weight: 800;
      word-break: break-all;
    }

    .bundle-meta {
      margin-top: 8px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.45;
    }

    .scope {
      display: inline-flex;
      padding: 2px 7px;
      border-radius: 999px;
      background: #223128;
      color: var(--green);
      font-size: 11px;
      font-weight: 800;
      text-transform: uppercase;
    }

    main {
      padding: 18px;
      min-width: 0;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 16px;
    }

    .metric,
    .panel {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
    }

    .metric {
      padding: 12px;
      min-height: 76px;
    }

    .label {
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
    }

    .value {
      font-size: 20px;
      font-weight: 800;
      word-break: break-word;
    }

    .value.small {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 13px;
      line-height: 1.45;
    }

    .two {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(320px, 0.9fr);
      gap: 12px;
    }

    .panel {
      padding: 14px;
      margin-bottom: 14px;
    }

    h2 {
      margin: 0 0 12px;
      font-size: 16px;
    }

    pre {
      white-space: pre-wrap;
      word-break: break-word;
      margin: 0;
      color: var(--soft);
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }

    th,
    td {
      border-bottom: 1px solid var(--line);
      padding: 9px 8px;
      text-align: left;
      vertical-align: top;
    }

    th {
      color: var(--muted);
      font-size: 12px;
    }

    .mono {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }

    .guess {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 22px;
      line-height: 1.35;
      font-weight: 800;
      color: var(--green);
      word-break: break-all;
    }

    .subtle {
      color: var(--muted);
      font-size: 12px;
      margin-top: 6px;
    }

    .snaps {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(270px, 1fr));
      gap: 12px;
    }

    .snap {
      border: 1px solid var(--line);
      background: var(--panel-2);
      border-radius: 8px;
      padding: 12px;
      min-width: 0;
    }

    .image-wrap {
      width: 100%;
      height: 260px;
      display: grid;
      place-items: center;
      background: #050706;
      border: 1px solid #223028;
      border-radius: 8px;
      overflow: hidden;
      margin-bottom: 10px;
    }

    .image-wrap img {
      width: 100%;
      height: 100%;
      object-fit: contain;
      image-rendering: auto;
    }

    .snap-title {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-weight: 800;
      font-size: 12px;
      word-break: break-all;
    }

    .snap-meta {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
      margin: 7px 0 10px;
    }

    .empty {
      height: 70vh;
      display: grid;
      place-items: center;
      color: var(--muted);
      text-align: center;
    }

    @media (max-width: 900px) {
      .app {
        grid-template-columns: 1fr;
      }

      aside {
        position: static;
        min-height: auto;
        border-right: none;
        border-bottom: 1px solid var(--line);
      }

      .grid,
      .two {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="app">
    <aside>
      <header>
        <div>
          <h1>Hyper Scan Viewer</h1>
          <div class="root" id="root"></div>
        </div>
        <button class="refresh" id="refresh">Refresh</button>
      </header>
      <div class="list" id="bundleList"></div>
    </aside>
    <main id="content">
      <div class="empty">Waiting for Hyper Scan captures.</div>
    </main>
  </div>

  <script>
    const state = { bundles: [], selected: null };
    const fmt = new Intl.DateTimeFormat(undefined, {
      month: "numeric",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit"
    });

    const rootEl = document.querySelector("#root");
    const listEl = document.querySelector("#bundleList");
    const contentEl = document.querySelector("#content");
    const refreshEl = document.querySelector("#refresh");

    refreshEl.addEventListener("click", () => load());

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function dateLabel(value) {
      const time = Date.parse(value ?? "");
      return Number.isFinite(time) ? fmt.format(new Date(time)) : "unknown";
    }

    function percent(value) {
      const number = Number(value ?? 0);
      return Math.round(Math.max(0, Math.min(1, number)) * 100) + "%";
    }

    function shortId(value) {
      const text = String(value ?? "");
      return text.length > 28 ? text.slice(0, 13) + "..." + text.slice(-10) : text;
    }

    function candidateText(candidate) {
      if (!candidate) return "No candidate yet";
      if (candidate.apiKey) return candidate.apiKey;
      if (candidate.bestGuess) return candidate.bestGuess;
      if (candidate.apiKeyLength) return "Candidate length " + candidate.apiKeyLength + " (raw key stripped)";
      return JSON.stringify(candidate);
    }

    function bestGuess(manifest) {
      if (manifest?.puzzle?.bestGuess) return manifest.puzzle.bestGuess;
      const first = Array.isArray(manifest?.stitchCandidates) ? manifest.stitchCandidates[0] : null;
      return candidateText(first);
    }

    async function load() {
      const response = await fetch("/api/bundles", { cache: "no-store" });
      const payload = await response.json();
      state.bundles = payload.bundles ?? [];
      rootEl.textContent = payload.root ?? "";
      renderList();

      if (!state.selected && state.bundles.length) {
        await selectBundle(state.bundles[0].scope, state.bundles[0].id);
      } else if (state.selected) {
        await selectBundle(state.selected.scope, state.selected.id, true);
      } else {
        contentEl.innerHTML = '<div class="empty">Waiting for Hyper Scan captures.</div>';
      }
    }

    function renderList() {
      listEl.innerHTML = state.bundles.map((bundle) => {
        const active = state.selected &&
          state.selected.id === bundle.id &&
          state.selected.scope === bundle.scope;
        return '<button class="bundle ' + (active ? "active" : "") + '" data-scope="' + bundle.scope + '" data-id="' + bundle.id + '">' +
          '<div class="bundle-id">' + escapeHtml(shortId(bundle.id)) + '</div>' +
          '<div class="bundle-meta">' +
          '<span class="scope">' + escapeHtml(bundle.scope) + '</span><br />' +
          escapeHtml(bundle.captureKind) + ' · ' + dateLabel(bundle.receivedAt || bundle.createdAt) + '<br />' +
          escapeHtml(bundle.snapCount) + ' snaps · ' + escapeHtml(bundle.fragmentCount) + ' fragments · ' + percent(bundle.progress) +
          (bundle.expiresAt ? '<br />expires ' + dateLabel(bundle.expiresAt) : '') +
          '</div>' +
          '</button>';
      }).join("");

      listEl.querySelectorAll(".bundle").forEach((button) => {
        button.addEventListener("click", () => selectBundle(button.dataset.scope, button.dataset.id));
      });
    }

    async function selectBundle(scope, id, keepScroll = false) {
      state.selected = { scope, id };
      renderList();
      const previousScroll = document.documentElement.scrollTop;
      const response = await fetch("/api/bundles/" + scope + "/" + encodeURIComponent(id), { cache: "no-store" });
      if (!response.ok) {
        contentEl.innerHTML = '<div class="empty">Bundle not found.</div>';
        return;
      }
      const detail = await response.json();
      renderDetail(detail);
      if (keepScroll) document.documentElement.scrollTop = previousScroll;
    }

    function renderMetric(label, value, extraClass = "") {
      return '<div class="metric"><div class="label">' + escapeHtml(label) + '</div><div class="value ' + extraClass + '">' + value + '</div></div>';
    }

    function renderCandidates(candidates) {
      if (!Array.isArray(candidates) || !candidates.length) {
        return '<p class="subtle">No stitch candidates.</p>';
      }

      return '<table><thead><tr><th>Candidate</th><th>Fragments</th><th>Confidence</th><th>Shape</th></tr></thead><tbody>' +
        candidates.map((candidate) => (
          '<tr>' +
          '<td class="mono">' + escapeHtml(candidateText(candidate)) + '</td>' +
          '<td>' + escapeHtml(candidate.fragmentCount ?? candidate.fragments?.length ?? "") + '</td>' +
          '<td>' + escapeHtml(candidate.confidencePercent ?? "") + '%</td>' +
          '<td>' + escapeHtml(candidate.isValidShape === true ? "valid" : candidate.isValidShape === false ? "invalid" : "") + '</td>' +
          '</tr>'
        )).join("") +
        '</tbody></table>';
    }

    function renderSnaps(images) {
      if (!images.length) return '<p class="subtle">No images in this bundle.</p>';

      return '<div class="snaps">' + images.map((image) => {
        const lines = image.textLines?.map((line) => line.text).filter(Boolean).join("\\n") ?? "";
        return '<article class="snap">' +
          '<div class="image-wrap">' + (image.url ? '<img src="' + image.url + '" alt="' + escapeHtml(image.filename) + '" />' : '') + '</div>' +
          '<div class="snap-title">' + escapeHtml(image.captureIndex) + ' · ' + escapeHtml(image.filename ?? image.id) + '</div>' +
          '<div class="snap-meta">' +
          escapeHtml(image.role) + ' · ' + escapeHtml(image.status) + ' · ' +
          escapeHtml(image.pixelWidth) + 'x' + escapeHtml(image.pixelHeight) + ' · ' +
          escapeHtml(Math.round((image.size ?? 0) / 1024)) + ' KB' +
          '</div>' +
          '<pre>Display: ' + escapeHtml(image.displayFragment || "none") + '\\n\\nOCR:\\n' + escapeHtml(image.recognizedText || lines || "No OCR text") + '\\n\\nFragments:\\n' + escapeHtml((image.fragments ?? []).join("\\n") || "none") + '\\n\\nQuality:\\n' + escapeHtml(JSON.stringify(image.quality ?? {}, null, 2)) + '\\n\\nGeometry:\\n' + escapeHtml(JSON.stringify(image.geometry ?? {}, null, 2)) + '</pre>' +
          '</article>';
      }).join("") + '</div>';
    }

    function renderDetail(detail) {
      const manifest = detail.manifest ?? {};
      const coverage = manifest.coverage ?? {};
      const guess = bestGuess(manifest);
      const ocrText = manifest.recognizedText || (detail.images ?? []).map((image) => image.recognizedText).filter(Boolean).join("\\n\\n");

      contentEl.innerHTML =
        '<div class="grid">' +
          renderMetric("Capture", escapeHtml(shortId(detail.id)), "small") +
          renderMetric("Kind", escapeHtml(manifest.captureKind ?? "hyper-scan")) +
          renderMetric("Received", escapeHtml(dateLabel(manifest.receivedAt || manifest.createdAt))) +
          renderMetric("Progress", escapeHtml(percent(coverage.progress ?? detail.summary?.progress))) +
          renderMetric("Snaps", escapeHtml(detail.images?.length ?? 0)) +
          renderMetric("Fragments", escapeHtml((manifest.fragments ?? []).length)) +
          renderMetric("Candidates", escapeHtml((manifest.stitchCandidates ?? []).length)) +
          renderMetric("Scope", '<span class="scope">' + escapeHtml(detail.scope) + '</span>') +
        '</div>' +
        '<section class="panel">' +
          '<h2>Best Guess</h2>' +
          '<div class="guess">' + escapeHtml(guess) + '</div>' +
          '<div class="subtle">Confidence ' + escapeHtml(manifest.puzzle?.confidencePercent ?? manifest.stitchCandidates?.[0]?.confidencePercent ?? 0) + '%</div>' +
        '</section>' +
        '<div class="two">' +
          '<section class="panel"><h2>Manifest Summary</h2><pre>' + escapeHtml(JSON.stringify({ captureId: manifest.captureId, kind: manifest.captureKind, createdAt: manifest.createdAt, receivedAt: manifest.receivedAt, retain: manifest.retain, expiresAt: manifest.expiresAt, coverage }, null, 2)) + '</pre></section>' +
          '<section class="panel"><h2>OCR Text</h2><pre>' + escapeHtml(ocrText || "No OCR text") + '</pre></section>' +
        '</div>' +
        '<section class="panel"><h2>Stitch Candidates</h2>' + renderCandidates(manifest.stitchCandidates ?? []) + '</section>' +
        '<section class="panel"><h2>Fragments</h2><pre>' + escapeHtml((manifest.fragments ?? []).join("\\n") || "No fragments") + '</pre></section>' +
        '<section class="panel"><h2>Snaps</h2>' + renderSnaps(detail.images ?? []) + '</section>';
    }

    load();
    setInterval(load, 5000);
  </script>
</body>
</html>`;

Bun.serve({
  port,
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/" || path === "/index.html") {
      return page();
    }

    if (path === "/api/bundles") {
      return json({ root, bundles: await listBundles() });
    }

    const bundleMatch = path.match(/^\/api\/bundles\/(retained|transient)\/([^/]+)$/);
    if (bundleMatch) {
      const scope = bundleMatch[1] as BundleScope;
      const id = safeSegment(bundleMatch[2]);
      if (!id) return notFound("Invalid bundle ID.");
      const detail = await detailFor(scope, id);
      if (!detail) return notFound("Bundle not found.");
      return json(detail);
    }

    const imageMatch = path.match(/^\/images\/(retained|transient)\/([^/]+)\/([^/]+)$/);
    if (imageMatch) {
      return serveImage(
        imageMatch[1] as BundleScope,
        imageMatch[2],
        imageMatch[3]
      );
    }

    return notFound("Not found.");
  },
});

console.log(`Hyper Scan viewer listening on http://127.0.0.1:${port}`);
console.log(`Reading ${root}`);

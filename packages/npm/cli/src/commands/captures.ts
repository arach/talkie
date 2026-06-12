import type { Command } from "commander";
import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
} from "fs";
import { basename, dirname, extname, join, resolve } from "path";
import { homedir } from "os";
import { getDb, queryAll, resolveDbPath } from "../db";
import {
  formatDate,
  formatDuration,
  getFormatOptions,
  output,
  outputTable,
  truncate,
  type FormatOptions,
} from "../format";
import { parseSince } from "./shared";

type CaptureKind = "screenshot" | "clip";
type CaptureSource = "recording" | "library" | "tray";

interface RecordingRef {
  id: string;
  type?: string;
  title?: string | null;
  createdAt?: string | null;
}

interface CaptureItem {
  id: string;
  kind: CaptureKind;
  source: CaptureSource;
  path: string;
  filename: string;
  exists: boolean;
  createdAt?: string;
  modifiedAt?: string;
  sizeBytes?: number;
  width?: number;
  height?: number;
  durationMs?: number;
  timestampMs?: number;
  captureMode?: string;
  windowTitle?: string;
  appName?: string;
  appBundleID?: string;
  displayName?: string;
  pinned?: boolean;
  hasOCR?: boolean;
  ocrText?: string;
  sidecarPath?: string;
  markupPath?: string;
  recording?: RecordingRef;
}

interface CaptureCommandOptions {
  limit: string;
  since?: string;
  kind?: string;
  source?: string;
  recording?: string;
  app?: string;
  ocr?: boolean;
  path?: boolean;
  open?: boolean;
  reveal?: boolean;
}

interface ParsedFilename {
  id?: string;
  createdAt?: string;
  captureMode?: string;
  width?: number;
  height?: number;
  timestampMs?: number;
  part?: number;
  appName?: string;
  displayName?: string;
}

const HOME = homedir();
const APP_SUPPORT = join(HOME, "Library", "Application Support", "Talkie");
const SCREENSHOTS_DIR = join(APP_SUPPORT, "Screenshots");
const VIDEOS_DIR = join(APP_SUPPORT, "Videos");
const TRAY_SCREENSHOTS_DIR = join(APP_SUPPORT, "Tray", "screenshots");
const TRAY_CLIPS_DIR = join(APP_SUPPORT, "Tray", "clips");
const BUFFER_SCREENSHOTS_DIR = join(APP_SUPPORT, "Buffer", "screenshots");
const BUFFER_CLIPS_DIR = join(APP_SUPPORT, "Buffer", "clips");

const IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".heic"]);
const VIDEO_EXTS = new Set([".mp4", ".mov", ".m4v"]);

const SOURCE_PRIORITY: Record<CaptureSource, number> = {
  recording: 3,
  tray: 2,
  library: 1,
};

export function registerCapturesCommand(program: Command): void {
  program
    .command("captures [id]")
    .description("List screenshots and video captures, or get a specific capture")
    .option("--limit <n>", "max results", "50")
    .option("--since <date>", "filter by capture/file date (e.g. 2026-06-01 or 7d)")
    .option("--kind <kind>", "screenshot, clip, video, or all", "all")
    .option("--source <source>", "recording, library, tray, or all", "all")
    .option("--recording <id>", "filter captures attached to a recording ID prefix")
    .option("--app <name>", "filter by app, window, display, or filename")
    .option("--ocr", "include OCR text when available")
    .option("--path", "print only capture file paths")
    .option("--open", "open the matched capture file(s)")
    .option("--reveal", "reveal the matched capture file(s) in Finder")
    .action((id: string | undefined, opts: CaptureCommandOptions) => {
      const globalOpts = program.opts();
      const fmt = getFormatOptions(globalOpts);
      const limit = parsePositiveInt(opts.limit, 50);

      let items = collectCaptures(globalOpts.db);
      items = filterCaptures(items, opts);
      items.sort(compareCapturesNewestFirst);

      if (id) {
        const item = findCapture(items, id);
        if (!item) {
          console.error(`Capture not found: ${id}`);
          process.exit(1);
        }
        return outputSelection([item], opts, fmt, true);
      }

      outputSelection(items.slice(0, limit), opts, fmt, false);
    });
}

function collectCaptures(dbOverride?: string): CaptureItem[] {
  const byPath = new Map<string, CaptureItem>();

  for (const item of collectDatabaseCaptures(dbOverride)) {
    mergeItem(byPath, item);
  }

  for (const item of collectTrayManifestCaptures(TRAY_SCREENSHOTS_DIR, "screenshot")) {
    mergeItem(byPath, item);
  }
  for (const item of collectTrayManifestCaptures(TRAY_CLIPS_DIR, "clip")) {
    mergeItem(byPath, item);
  }

  for (const item of collectFileCaptures(SCREENSHOTS_DIR, "screenshot", "library")) {
    mergeItem(byPath, item);
  }
  for (const item of collectFileCaptures(VIDEOS_DIR, "clip", "library")) {
    mergeItem(byPath, item);
  }
  for (const item of collectFileCaptures(TRAY_SCREENSHOTS_DIR, "screenshot", "tray")) {
    mergeItem(byPath, item);
  }
  for (const item of collectFileCaptures(TRAY_CLIPS_DIR, "clip", "tray")) {
    mergeItem(byPath, item);
  }
  for (const item of collectFileCaptures(BUFFER_SCREENSHOTS_DIR, "screenshot", "tray")) {
    mergeItem(byPath, item);
  }
  for (const item of collectFileCaptures(BUFFER_CLIPS_DIR, "clip", "tray")) {
    mergeItem(byPath, item);
  }

  return Array.from(byPath.values());
}

function collectDatabaseCaptures(dbOverride?: string): CaptureItem[] {
  const dbPath = resolveDbPath(dbOverride);
  if (!existsSync(dbPath)) return [];

  getDb(dbOverride);
  const columns = new Set(
    queryAll("PRAGMA table_info(recordings)").map((row) => String(row.name))
  );

  const hasAssets = columns.has("assetsJSON");
  const hasScreenshots = columns.has("screenshotsJSON");
  const hasClips = columns.has("clipsJSON");
  if (!hasAssets && !hasScreenshots && !hasClips) return [];

  const select = [
    "id",
    columns.has("type") ? "type" : null,
    columns.has("title") ? "title" : null,
    columns.has("createdAt") ? "createdAt" : null,
    hasAssets ? "assetsJSON" : null,
    hasScreenshots ? "screenshotsJSON" : null,
    hasClips ? "clipsJSON" : null,
  ].filter((column): column is string => Boolean(column)).join(", ");

  const mediaClauses: string[] = [];
  if (hasAssets) {
    mediaClauses.push(
      "(assetsJSON LIKE '%\"screenshots\"%' OR assetsJSON LIKE '%\"clips\"%')"
    );
  }
  if (hasScreenshots) mediaClauses.push("screenshotsJSON IS NOT NULL");
  if (hasClips) mediaClauses.push("clipsJSON IS NOT NULL");

  const where = [
    columns.has("deletedAt") ? "deletedAt IS NULL" : null,
    `(${mediaClauses.join(" OR ")})`,
  ].filter(Boolean).join(" AND ");

  const rows = queryAll(`
    SELECT ${select}
    FROM recordings
    WHERE ${where}
    ORDER BY ${columns.has("createdAt") ? "createdAt DESC" : "id DESC"}
  `);

  const items: CaptureItem[] = [];
  for (const row of rows) {
    const recording: RecordingRef = {
      id: String(row.id),
      type: stringOrUndefined(row.type),
      title: typeof row.title === "string" ? row.title : null,
      createdAt: typeof row.createdAt === "string" ? row.createdAt : null,
    };

    const assets = parseObject(row.assetsJSON);
    const screenshots = [
      ...arrayFrom(assets?.screenshots),
      ...arrayFrom(parseJSON(row.screenshotsJSON)),
    ];
    const clips = [
      ...arrayFrom(assets?.clips),
      ...arrayFrom(parseJSON(row.clipsJSON)),
    ];

    screenshots.forEach((asset, index) => {
      const path = resolveCapturePath(asset.filename, SCREENSHOTS_DIR);
      items.push(
        withFileMetadata({
          ...itemFromAsset(asset, "screenshot", path, recording, index),
          recording,
        })
      );
    });

    clips.forEach((asset, index) => {
      const path = resolveCapturePath(asset.filename, VIDEOS_DIR);
      items.push(
        withFileMetadata({
          ...itemFromAsset(asset, "clip", path, recording, index),
          recording,
        })
      );
    });
  }

  return items;
}

function collectTrayManifestCaptures(dir: string, kind: CaptureKind): CaptureItem[] {
  const manifestPath = join(dir, "manifest.json");
  const manifest = parseJSONFile(manifestPath);
  const entries = arrayFrom(manifest);
  return entries.map((entry, index) => {
    const path = resolveCapturePath(entry.filename, dir);
    const parsed = parseCaptureFilename(path, kind);
    const id = stringOrUndefined(entry.id) ?? captureIdFor(path, parsed, index);
    return withFileMetadata({
      id,
      kind,
      source: "tray",
      path,
      filename: basename(path),
      exists: existsSync(path),
      createdAt: stringOrUndefined(entry.capturedAt) ?? parsed.createdAt,
      width: numberOrUndefined(entry.width) ?? parsed.width,
      height: numberOrUndefined(entry.height) ?? parsed.height,
      durationMs: numberOrUndefined(entry.durationMs),
      timestampMs: parsed.timestampMs,
      captureMode: stringOrUndefined(entry.mode)
        ?? stringOrUndefined(entry.captureMode)
        ?? parsed.captureMode,
      windowTitle: stringOrUndefined(entry.windowTitle),
      appName: stringOrUndefined(entry.appName) ?? parsed.appName,
      appBundleID: stringOrUndefined(entry.appBundleID),
      displayName: stringOrUndefined(entry.displayName) ?? parsed.displayName,
      pinned: booleanOrUndefined(entry.pinned),
      ocrText: stringOrUndefined(entry.ocrText),
      hasOCR: typeof entry.ocrText === "string" && entry.ocrText.length > 0,
      ...sidecarPaths(path),
    });
  });
}

function collectFileCaptures(
  root: string,
  kind: CaptureKind,
  source: CaptureSource
): CaptureItem[] {
  if (!existsSync(root)) return [];

  const exts = kind === "screenshot" ? IMAGE_EXTS : VIDEO_EXTS;
  const paths = listFiles(root, exts);

  return paths.map((path, index) => {
    const parsed = parseCaptureFilename(path, kind);
    return withFileMetadata({
      id: captureIdFor(path, parsed, index),
      kind,
      source,
      path,
      filename: basename(path),
      exists: true,
      createdAt: parsed.createdAt,
      width: parsed.width,
      height: parsed.height,
      timestampMs: parsed.timestampMs,
      captureMode: parsed.captureMode,
      appName: parsed.appName,
      displayName: parsed.displayName,
      ...sidecarPaths(path),
    });
  });
}

function itemFromAsset(
  asset: Record<string, unknown>,
  kind: CaptureKind,
  path: string,
  recording: RecordingRef,
  index: number
): CaptureItem {
  const parsed = parseCaptureFilename(path, kind);
  return {
    id: captureIdFor(path, parsed, index),
    kind,
    source: "recording",
    path,
    filename: basename(path),
    exists: existsSync(path),
    createdAt: parsed.createdAt ?? datePlusMs(recording.createdAt, numberOrUndefined(asset.timestampMs)),
    width: numberOrUndefined(asset.width) ?? parsed.width,
    height: numberOrUndefined(asset.height) ?? parsed.height,
    durationMs: numberOrUndefined(asset.durationMs),
    timestampMs: numberOrUndefined(asset.timestampMs) ?? parsed.timestampMs,
    captureMode: stringOrUndefined(asset.captureMode) ?? parsed.captureMode,
    windowTitle: stringOrUndefined(asset.windowTitle),
    appName: stringOrUndefined(asset.appName) ?? parsed.appName,
    appBundleID: stringOrUndefined(asset.appBundleID),
    displayName: stringOrUndefined(asset.displayName) ?? parsed.displayName,
    ...sidecarPaths(path),
  };
}

function filterCaptures(
  items: CaptureItem[],
  opts: CaptureCommandOptions
): CaptureItem[] {
  const kind = normalizeKind(opts.kind);
  const source = normalizeSource(opts.source);
  const since = opts.since ? Date.parse(parseSince(opts.since)) : null;
  const recording = opts.recording?.toLowerCase();
  const app = opts.app?.toLowerCase();

  return items.filter((item) => {
    if (kind && item.kind !== kind) return false;
    if (source && item.source !== source) return false;
    if (since && captureTime(item) < since) return false;
    if (recording && !item.recording?.id.toLowerCase().startsWith(recording)) return false;
    if (app && !matchesAppFilter(item, app)) return false;
    return true;
  });
}

function outputSelection(
  items: CaptureItem[],
  opts: CaptureCommandOptions,
  fmt: FormatOptions,
  detail: boolean
): void {
  const existingItems = items.filter((item) => item.exists);

  if (opts.reveal) {
    for (const item of existingItems) {
      Bun.spawnSync(["open", "-R", item.path]);
    }
  }

  if (opts.open) {
    for (const item of existingItems) {
      Bun.spawnSync(["open", item.path]);
    }
  }

  if (opts.path) {
    for (const item of items) {
      console.log(item.path);
    }
    return;
  }

  const includeOCR = opts.ocr ?? false;

  if (!fmt.pretty) {
    output(detail ? serializeItem(items[0], includeOCR) : items.map((item) => serializeItem(item, includeOCR)), fmt);
    return;
  }

  if (detail) {
    prettyPrintDetail(items[0], includeOCR);
    return;
  }

  outputTable(items.map((item) => serializeItem(item, false)), [
    { key: "id", label: "ID", width: 14, format: (v) => String(v ?? "").slice(0, 14) },
    { key: "kind", label: "Kind", width: 10 },
    { key: "source", label: "Source", width: 10 },
    { key: "createdAt", label: "Created", width: 20, format: (v) => formatDate(v as string) },
    { key: "target", label: "Target", width: 28, format: (v) => truncate(String(v ?? ""), 28) },
    { key: "dimensions", label: "Size", width: 12 },
    { key: "duration", label: "Duration", width: 10 },
    { key: "path", label: "Path", width: 44, format: (v) => truncate(String(v ?? ""), 44) },
  ], fmt);
}

function prettyPrintDetail(item: CaptureItem, includeOCR: boolean): void {
  const label = item.kind === "clip" ? "Video Capture" : "Screenshot";
  console.log(`# ${label}\n`);
  console.log(`ID:       ${item.id}`);
  console.log(`Source:   ${item.source}`);
  console.log(`Path:     ${item.path}`);
  console.log(`Exists:   ${item.exists ? "yes" : "no"}`);
  console.log(`Created:  ${formatDate(item.createdAt)}`);
  if (item.modifiedAt) console.log(`Modified: ${formatDate(item.modifiedAt)}`);
  if (item.width && item.height) console.log(`Size:     ${item.width}x${item.height}`);
  if (item.durationMs) console.log(`Duration: ${formatDuration(item.durationMs / 1000)}`);
  if (item.captureMode) console.log(`Mode:     ${item.captureMode}`);
  if (item.appName) console.log(`App:      ${item.appName}`);
  if (item.appBundleID) console.log(`Bundle:   ${item.appBundleID}`);
  if (item.windowTitle) console.log(`Window:   ${item.windowTitle}`);
  if (item.displayName) console.log(`Display:  ${item.displayName}`);
  if (typeof item.pinned === "boolean") console.log(`Pinned:   ${item.pinned ? "yes" : "no"}`);
  if (item.recording) {
    const title = item.recording.title ? ` — ${item.recording.title}` : "";
    console.log(`Recording: ${item.recording.id}${title}`);
  }
  if (item.sidecarPath) console.log(`Sidecar:  ${item.sidecarPath}`);
  if (item.markupPath) console.log(`Markup:   ${item.markupPath}`);
  if (includeOCR && item.ocrText) {
    console.log(`\n## OCR\n${item.ocrText}`);
  }
}

function serializeItem(item: CaptureItem, includeOCR: boolean): Record<string, unknown> {
  const target = captureTarget(item);
  const dimensions = item.width && item.height ? `${item.width}x${item.height}` : null;
  const out: Record<string, unknown> = {
    id: item.id,
    kind: item.kind,
    source: item.source,
    path: item.path,
    filename: item.filename,
    exists: item.exists,
    createdAt: item.createdAt ?? null,
    modifiedAt: item.modifiedAt ?? null,
    sizeBytes: item.sizeBytes ?? null,
    width: item.width ?? null,
    height: item.height ?? null,
    dimensions,
    durationMs: item.durationMs ?? null,
    duration: item.durationMs ? formatDuration(item.durationMs / 1000) : null,
    timestampMs: item.timestampMs ?? null,
    captureMode: item.captureMode ?? null,
    target,
    windowTitle: item.windowTitle ?? null,
    appName: item.appName ?? null,
    appBundleID: item.appBundleID ?? null,
    displayName: item.displayName ?? null,
    pinned: item.pinned ?? null,
    hasOCR: item.hasOCR ?? false,
    sidecarPath: item.sidecarPath ?? null,
    markupPath: item.markupPath ?? null,
    recording: item.recording ?? null,
  };
  if (includeOCR && item.ocrText !== undefined) {
    out.ocrText = item.ocrText;
  }
  return out;
}

function mergeItem(byPath: Map<string, CaptureItem>, next: CaptureItem): void {
  const key = resolve(next.path);
  const current = byPath.get(key);
  if (!current) {
    byPath.set(key, next);
    return;
  }

  const preferred = SOURCE_PRIORITY[next.source] > SOURCE_PRIORITY[current.source]
    ? next
    : current;
  const fallback = preferred === next ? current : next;
  byPath.set(key, {
    ...fallback,
    ...preferred,
    exists: current.exists || next.exists,
    sizeBytes: preferred.sizeBytes ?? fallback.sizeBytes,
    modifiedAt: preferred.modifiedAt ?? fallback.modifiedAt,
    sidecarPath: preferred.sidecarPath ?? fallback.sidecarPath,
    markupPath: preferred.markupPath ?? fallback.markupPath,
    ocrText: preferred.ocrText ?? fallback.ocrText,
    hasOCR: preferred.hasOCR || fallback.hasOCR,
    recording: preferred.recording ?? fallback.recording,
  });
}

function withFileMetadata(item: CaptureItem): CaptureItem {
  if (!existsSync(item.path)) return item;
  try {
    const stats = statSync(item.path);
    return {
      ...item,
      exists: true,
      sizeBytes: stats.size,
      modifiedAt: stats.mtime.toISOString(),
      createdAt: item.createdAt ?? stats.birthtime.toISOString(),
    };
  } catch {
    return item;
  }
}

function listFiles(root: string, exts: Set<string>): string[] {
  const result: string[] = [];
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop()!;
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === ".tk") continue;
        stack.push(path);
      } else if (exts.has(extname(entry.name).toLowerCase())) {
        result.push(path);
      }
    }
  }
  return result;
}

function parseCaptureFilename(path: string, kind: CaptureKind): ParsedFilename {
  const name = basename(path, extname(path));
  const prefix = kind === "clip" ? "Talkie Screen Clip" : "Talkie Capture";
  const readable = new RegExp(
    `^${escapeRegExp(prefix)} - (\\d{4}-\\d{2}-\\d{2}) (\\d{2}\\.\\d{2}\\.\\d{2}) - (.+) - (\\d+)x(\\d+) - ([A-Fa-f0-9-]{8,36})(?: t(\\d+)ms)?(?: part(\\d+))?$`
  ).exec(name);

  if (readable) {
    const [, date, time, modeAndTarget, width, height, id, timestampMs, part] = readable;
    const modeParts = modeAndTarget.split(/\s+/);
    const captureMode = modeParts.shift()?.toLowerCase();
    const target = modeParts.join(" ").trim();
    return {
      id: id.toLowerCase(),
      createdAt: localFilenameDateToISO(date, time),
      captureMode,
      width: parseInt(width, 10),
      height: parseInt(height, 10),
      timestampMs: timestampMs ? parseInt(timestampMs, 10) : undefined,
      part: part ? parseInt(part, 10) : undefined,
      appName: captureMode === "window" && target ? target : undefined,
      displayName: captureMode !== "window" && target ? target : undefined,
    };
  }

  const legacy = /^([A-Fa-f0-9-]{36})_(\d+)(?:_(\d+))?$/.exec(name);
  if (legacy) {
    return {
      id: legacy[1].toLowerCase(),
      timestampMs: parseInt(legacy[2], 10),
      part: legacy[3] ? parseInt(legacy[3], 10) : undefined,
    };
  }

  return {};
}

function captureIdFor(path: string, parsed: ParsedFilename, index: number): string {
  if (parsed.id) {
    const suffixes: string[] = [];
    if (parsed.timestampMs && parsed.timestampMs > 0) suffixes.push(`t${parsed.timestampMs}`);
    if (parsed.part !== undefined) suffixes.push(`p${parsed.part}`);
    return [parsed.id, ...suffixes].join("-").toLowerCase();
  }

  const name = basename(path, extname(path))
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `${name || "capture"}-${index}`;
}

function findCapture(items: CaptureItem[], id: string): CaptureItem | null {
  const needle = id.toLowerCase();
  const pathNeedle = resolve(id);
  const matches = items.filter((item) => {
    return item.id.toLowerCase().startsWith(needle)
      || item.filename.toLowerCase() === needle
      || item.path.toLowerCase() === id.toLowerCase()
      || resolve(item.path) === pathNeedle;
  });

  if (matches.length === 0) return null;
  matches.sort(compareCapturesNewestFirst);
  return matches[0];
}

function compareCapturesNewestFirst(a: CaptureItem, b: CaptureItem): number {
  return captureTime(b) - captureTime(a);
}

function captureTime(item: CaptureItem): number {
  const value = item.createdAt ?? item.modifiedAt;
  const parsed = value ? Date.parse(value) : NaN;
  return Number.isFinite(parsed) ? parsed : 0;
}

function matchesAppFilter(item: CaptureItem, app: string): boolean {
  return [
    item.appName,
    item.appBundleID,
    item.windowTitle,
    item.displayName,
    item.filename,
  ].some((value) => value?.toLowerCase().includes(app));
}

function captureTarget(item: CaptureItem): string {
  return item.windowTitle
    ?? item.appName
    ?? item.displayName
    ?? item.captureMode
    ?? "";
}

function normalizeKind(value?: string): CaptureKind | null {
  if (!value || value === "all") return null;
  if (value === "screenshot" || value === "screenshots" || value === "image") return "screenshot";
  if (value === "clip" || value === "clips" || value === "video" || value === "videos") return "clip";
  console.error("Unknown --kind value. Use screenshot, clip, video, or all.");
  process.exit(1);
}

function normalizeSource(value?: string): CaptureSource | null {
  if (!value || value === "all") return null;
  if (value === "recording" || value === "recordings") return "recording";
  if (value === "library" || value === "libraries") return "library";
  if (value === "tray" || value === "buffer") return "tray";
  console.error("Unknown --source value. Use recording, library, tray, or all.");
  process.exit(1);
}

function parsePositiveInt(value: string, fallback: number): number {
  const parsed = parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function resolveCapturePath(filename: unknown, root: string): string {
  const value = String(filename ?? "");
  if (value.startsWith("/")) return value;
  return join(root, value);
}

function sidecarPaths(path: string): Pick<CaptureItem, "sidecarPath" | "markupPath"> {
  const dir = dirname(path);
  const base = basename(path, extname(path));
  const sidecarPath = join(dir, ".tk", `${base}.json`);
  const markupPath = join(dir, `${base}.markup.json`);
  return {
    sidecarPath: existsSync(sidecarPath) ? sidecarPath : undefined,
    markupPath: existsSync(markupPath) ? markupPath : undefined,
  };
}

function parseJSONFile(path: string): unknown {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function parseJSON(value: unknown): unknown {
  if (typeof value !== "string" || value.length === 0) return null;
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function parseObject(value: unknown): Record<string, unknown> | null {
  const parsed = parseJSON(value);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  return parsed as Record<string, unknown>;
}

function arrayFrom(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object" && !Array.isArray(item))
    : [];
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function booleanOrUndefined(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function datePlusMs(date: string | null | undefined, ms: number | undefined): string | undefined {
  if (!date) return undefined;
  const parsed = Date.parse(date);
  if (!Number.isFinite(parsed)) return undefined;
  return new Date(parsed + (ms ?? 0)).toISOString();
}

function localFilenameDateToISO(date: string, dottedTime: string): string | undefined {
  const parsed = new Date(`${date}T${dottedTime.replace(/\./g, ":")}`);
  return Number.isFinite(parsed.getTime()) ? parsed.toISOString() : undefined;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

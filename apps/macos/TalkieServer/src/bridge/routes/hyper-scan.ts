/**
 * Hyper Scan Debug Routes
 *
 * POST /debug/hyper-scan
 * Receives iPhone HyperScan capture payloads (JPEG snaps + manifest) and
 * stores them under Talkie's Bridge data directory for debugging.
 *
 * Captures are ephemeral by default: when `retain` is false (the default)
 * the payload is written under `${HYPER_SCAN_DIR}/.transient/<captureId>/`
 * and auto-deleted after TRANSIENT_TTL_MS. When `retain` is true the
 * payload is written to the durable `${HYPER_SCAN_DIR}/<captureId>/` path
 * with no TTL.
 *
 * On module load we sweep `.transient/` and unlink any expired entries
 * (e.g. items left over after a server restart).
 */

import { mkdir, readdir, readFile, rm, stat } from "node:fs/promises";
import { basename } from "node:path";

import { log } from "../../log";
import { HYPER_SCAN_DIR } from "../../paths";
import { badRequest, serverError } from "./responses";

/** Transient capture TTL: 15 minutes from receivedAt. */
const TRANSIENT_TTL_MS = 15 * 60 * 1000;

/** Subdirectory under HYPER_SCAN_DIR where ephemeral captures live. */
const TRANSIENT_SUBDIR = ".transient";

const TRANSIENT_DIR = `${HYPER_SCAN_DIR}/${TRANSIENT_SUBDIR}`;

// Track in-process deletion timers so we can dedupe.
const pendingDeletions = new Map<string, ReturnType<typeof setTimeout>>();

interface HyperScanUploadSummary {
  targetSnapCount: number;
  targetSegmentCount: number;
  snapCount: number;
  processedSnapCount: number;
  queuedSnapCount: number;
  readySnapCount: number;
  segmentCount: number;
  progress: number;
  hasTargetCoverage: boolean;
}

interface HyperScanUploadStitchCandidate {
  apiKey: string;
  confidencePercent: number;
  fragmentCount: number;
  isValidShape: boolean;
}

interface HyperScanUploadPuzzle {
  bestGuess?: string;
  confidencePercent: number;
  isKnownGoodMatch?: boolean;
  similarityPercent?: number;
  editDistance?: number;
  candidateLength?: number;
  expectedLength?: number;
}

interface HyperScanUploadGeometry {
  normalizedX: number;
  normalizedY: number;
  normalizedWidth: number;
  normalizedHeight: number;
  centerX: number;
  centerY: number;
  angleDegrees: number;
}

interface HyperScanUploadMotion {
  capturedAt: string;
  roll: number;
  pitch: number;
  yaw: number;
  rotationRateX: number;
  rotationRateY: number;
  rotationRateZ: number;
  userAccelerationX: number;
  userAccelerationY: number;
  userAccelerationZ: number;
  gravityX: number;
  gravityY: number;
  gravityZ: number;
}

interface HyperScanUploadQuality {
  recognizedCharacterCount: number;
  fragmentCount: number;
  geometryArea?: number;
  orientationClass?: string;
  isLikelyUsable: boolean;
  note?: string;
}

interface HyperScanUploadTextLine {
  blockIndex: number;
  lineIndex: number;
  text: string;
  fragments: string[];
  geometry?: HyperScanUploadGeometry;
}

interface HyperScanUploadSnap {
  id: string;
  captureIndex: number;
  role: string;
  addedAt: string;
  status: string;
  displayFragment: string;
  recognizedText: string;
  textLines: HyperScanUploadTextLine[];
  fragments: string[];
  pixelWidth: number;
  pixelHeight: number;
  mimeType: string;
  dataBase64: string;
  geometry?: HyperScanUploadGeometry;
  motion?: HyperScanUploadMotion;
  quality?: HyperScanUploadQuality;
}

export interface HyperScanUploadRequest {
  schemaVersion: number;
  captureId: string;
  captureKind: string;
  createdAt: string;
  recognizedText: string;
  coverage: HyperScanUploadSummary;
  fragments: string[];
  stitchCandidates: HyperScanUploadStitchCandidate[];
  puzzle?: HyperScanUploadPuzzle;
  snaps: HyperScanUploadSnap[];
  /** Whether the user opted-in to keep this capture on the Mac. Default false. */
  retain?: boolean;
}

export interface HyperScanUploadResponse {
  ok: true;
  captureId: string;
  savedCount: number;
  storedAt: string;
  storedPath: string;
  retain: boolean;
  expiresAt?: string;
}

interface StoredManifest {
  captureId: string;
  captureKind: string;
  createdAt: string;
  sourceDeviceId?: string;
  receivedAt: string;
  retain: boolean;
  expiresAt?: string;
  recognizedText: string;
  coverage: HyperScanUploadSummary;
  fragments: string[];
  stitchCandidates: Array<{
    apiKeyLength: number;
    confidencePercent: number;
    fragmentCount: number;
    isValidShape: boolean;
  }>;
  puzzle?: HyperScanUploadPuzzle;
  snaps: Array<{
    id: string;
    captureIndex: number;
    role: string;
    addedAt: string;
    status: string;
    displayFragment: string;
    recognizedText: string;
    filename: string;
    fileSizeBytes: number;
    pixelWidth: number;
    pixelHeight: number;
    mimeType: string;
    fragments: string[];
    textLines: HyperScanUploadTextLine[];
    geometry?: HyperScanUploadGeometry;
    motion?: HyperScanUploadMotion;
    quality?: HyperScanUploadQuality;
  }>;
}

export async function hyperScanUploadRoute(
  body: HyperScanUploadRequest,
  sourceDeviceId?: string | null
): Promise<HyperScanUploadResponse | Response> {
  if (!body || typeof body !== "object") {
    return badRequest("HyperScan payload is required.");
  }

  const captureId = sanitizedCaptureId(body.captureId);
  if (!captureId) {
    return badRequest("Capture ID is required.");
  }

  if (!Array.isArray(body.snaps) || body.snaps.length === 0) {
    return badRequest("At least one snap is required.");
  }

  const retain = body.retain === true;
  const receivedAt = new Date().toISOString();
  const expiresAt = retain
    ? undefined
    : new Date(Date.now() + TRANSIENT_TTL_MS).toISOString();

  const storedPath = retain
    ? `${HYPER_SCAN_DIR}/${captureId}`
    : `${TRANSIENT_DIR}/${captureId}`;

  try {
    await mkdir(storedPath, { recursive: true });

    const manifest: StoredManifest = {
      captureId,
      captureKind: body.captureKind,
      createdAt: body.createdAt,
      sourceDeviceId: sourceDeviceId ?? undefined,
      receivedAt,
      retain,
      expiresAt,
      recognizedText: body.recognizedText,
      coverage: body.coverage,
      fragments: body.fragments,
      // Drop raw apiKey strings from manifest — those are sensitive and the
      // payload already includes recognized text + JPEGs for forensic review.
      stitchCandidates: (body.stitchCandidates ?? []).map((candidate) => ({
        apiKeyLength: typeof candidate.apiKey === "string" ? candidate.apiKey.length : 0,
        confidencePercent: candidate.confidencePercent,
        fragmentCount: candidate.fragmentCount,
        isValidShape: candidate.isValidShape,
      })),
      puzzle: body.puzzle,
      snaps: [],
    };

    for (const snap of body.snaps) {
      if (!snap.id || !snap.dataBase64) {
        return badRequest("Snap payload is incomplete.");
      }

      const binary = Buffer.from(snap.dataBase64, "base64");
      if (binary.length === 0) {
        return badRequest("Snap data could not be decoded.");
      }

      const extension = extensionForMimeType(snap.mimeType);
      const filename = `${sanitizedCaptureId(snap.id) || "snap"}.${extension}`;

      await Bun.write(`${storedPath}/${filename}`, binary);

      manifest.snaps.push({
        id: snap.id,
        captureIndex: snap.captureIndex,
        role: snap.role,
        addedAt: snap.addedAt,
        status: snap.status,
        displayFragment: snap.displayFragment,
        recognizedText: snap.recognizedText,
        filename,
        fileSizeBytes: binary.length,
        pixelWidth: snap.pixelWidth,
        pixelHeight: snap.pixelHeight,
        mimeType: snap.mimeType,
        fragments: snap.fragments ?? [],
        textLines: snap.textLines ?? [],
        geometry: snap.geometry,
        motion: snap.motion,
        quality: snap.quality,
      });
    }

    await Bun.write(
      `${storedPath}/manifest.json`,
      JSON.stringify(manifest, null, 2)
    );

    if (!retain) {
      scheduleTransientDeletion(captureId, TRANSIENT_TTL_MS);
      log.info(
        `Saved ephemeral HyperScan capture ${captureId} (${manifest.snaps.length} snap(s), expires ${expiresAt})` +
          (sourceDeviceId ? ` from device ${sourceDeviceId}` : "")
      );
    } else {
      log.info(
        `Saved retained HyperScan capture ${captureId} (${manifest.snaps.length} snap(s))` +
          (sourceDeviceId ? ` from device ${sourceDeviceId}` : "")
      );
    }

    return {
      ok: true,
      captureId,
      savedCount: manifest.snaps.length,
      storedAt: receivedAt,
      storedPath,
      retain,
      expiresAt,
    };
  } catch (error) {
    log.error(`HyperScan upload failed: ${String(error)}`);
    return serverError("Could not save HyperScan capture.", String(error));
  }
}

function scheduleTransientDeletion(captureId: string, delayMs: number): void {
  const existing = pendingDeletions.get(captureId);
  if (existing) clearTimeout(existing);

  const timer = setTimeout(async () => {
    pendingDeletions.delete(captureId);
    const target = `${TRANSIENT_DIR}/${captureId}`;
    try {
      await rm(target, { recursive: true, force: true });
      log.info(`Deleted ephemeral HyperScan capture ${captureId}`);
    } catch (err) {
      log.warn(`Failed to delete ephemeral HyperScan capture ${captureId}: ${String(err)}`);
    }
  }, delayMs);

  // Don't keep the event loop alive solely for this timer.
  if (typeof (timer as { unref?: () => void }).unref === "function") {
    (timer as { unref: () => void }).unref();
  }

  pendingDeletions.set(captureId, timer);
}

/**
 * Sweep the `.transient/` directory and unlink any entries whose
 * manifest expiresAt has passed (e.g. left over from a previous process).
 * Re-schedules an in-process timer for entries not yet expired.
 */
export async function sweepTransientCaptures(): Promise<void> {
  let entries: string[];
  try {
    entries = await readdir(TRANSIENT_DIR);
  } catch (err) {
    // Directory may not exist yet — that's fine, nothing to sweep.
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
    log.warn(`HyperScan transient sweep: could not list directory: ${String(err)}`);
    return;
  }

  let deletedCount = 0;
  let scheduledCount = 0;
  const now = Date.now();

  for (const entry of entries) {
    if (entry.startsWith(".")) continue;
    const captureDir = `${TRANSIENT_DIR}/${entry}`;
    const manifestPath = `${captureDir}/manifest.json`;

    let expiresAtMs: number | null = null;
    try {
      const raw = await readFile(manifestPath, "utf-8");
      const parsed = JSON.parse(raw) as { expiresAt?: string; receivedAt?: string };
      if (typeof parsed.expiresAt === "string") {
        const t = Date.parse(parsed.expiresAt);
        if (!Number.isNaN(t)) expiresAtMs = t;
      } else if (typeof parsed.receivedAt === "string") {
        const t = Date.parse(parsed.receivedAt);
        if (!Number.isNaN(t)) expiresAtMs = t + TRANSIENT_TTL_MS;
      }
    } catch {
      // No readable manifest — fall back to directory mtime.
      try {
        const info = await stat(captureDir);
        expiresAtMs = info.mtimeMs + TRANSIENT_TTL_MS;
      } catch {
        expiresAtMs = null;
      }
    }

    if (expiresAtMs === null) continue;

    if (expiresAtMs <= now) {
      try {
        await rm(captureDir, { recursive: true, force: true });
        deletedCount += 1;
      } catch (err) {
        log.warn(`HyperScan transient sweep: could not delete ${entry}: ${String(err)}`);
      }
    } else {
      scheduleTransientDeletion(entry, expiresAtMs - now);
      scheduledCount += 1;
    }
  }

  if (deletedCount > 0 || scheduledCount > 0) {
    log.info(
      `HyperScan transient sweep: deleted ${deletedCount}, rescheduled ${scheduledCount}`
    );
  }
}

function sanitizedCaptureId(input: string | undefined): string {
  if (!input) return "";
  const cleaned = basename(input)
    .trim()
    .replace(/[^a-zA-Z0-9_.-]/g, "_")
    .replace(/^\.+/, "");
  return cleaned;
}

function extensionForMimeType(mimeType: string | undefined): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/heic":
      return "heic";
    default:
      return "jpg";
  }
}

// Kick off a startup sweep when this route module is imported. We don't
// await it — `ensureDirectories()` will have created the parent directory
// before HTTP traffic starts, and the sweep will silently no-op if the
// transient dir does not yet exist.
sweepTransientCaptures().catch((err) => {
  log.warn(`HyperScan transient sweep failed at startup: ${String(err)}`);
});

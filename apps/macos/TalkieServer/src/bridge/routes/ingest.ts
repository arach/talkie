/**
 * Content Ingestion Route
 *
 * POST /ingest
 * Receives content from iOS (URL text, OCR screenshots, photos) and
 * stores it as a TalkieObject on the Mac for readout/TTS workflows.
 *
 * The Mac is the brain — iOS captures, Mac processes.
 */

import { mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";

import { log } from "../../log";
import { BRIDGE_DATA_DIR } from "../../paths";
import { badRequest } from "./responses";

// ===== Types =====

export type IngestSourceType = "url" | "ocr" | "photo" | "text";

export interface IngestRequestBody {
  /** What kind of content is being ingested */
  sourceType: IngestSourceType;

  /** The extracted/readable text content */
  text: string;

  /** Display title (page title, "Screenshot 4/12", etc.) */
  title?: string;

  /** Where the content came from */
  sourceURL?: string;

  /** Optional image attachment as base64 (for OCR/photo sources) */
  imageBase64?: string;

  /** Image filename if provided */
  imageFilename?: string;
}

export interface IngestResponseEnvelope {
  ok: boolean;
  objectId?: string;
  storedAt?: string;
  error?: string;
}

// ===== Storage =====

const INGEST_DIR = `${BRIDGE_DATA_DIR}/Ingested`;

async function ensureIngestDir(): Promise<void> {
  await mkdir(INGEST_DIR, { recursive: true });
}

// ===== Route Handler =====

export async function ingestRoute(
  body: IngestRequestBody,
  deviceId: string | null
): Promise<IngestResponseEnvelope | Response> {
  // Validate required fields
  if (!body.sourceType) {
    return badRequest("sourceType is required (url, ocr, photo, text)");
  }
  if (!body.text || body.text.trim().length === 0) {
    return badRequest("text is required");
  }

  const objectId = randomUUID();
  const now = new Date();

  try {
    await ensureIngestDir();

    // Save image attachment if present
    let imageFilename: string | undefined;
    if (body.imageBase64) {
      const ext = body.imageFilename?.split(".").pop() ?? "png";
      imageFilename = `${objectId}.${ext}`;
      const imageData = Buffer.from(body.imageBase64, "base64");
      await Bun.write(`${INGEST_DIR}/${imageFilename}`, imageData);
      log.info(`Saved ingest image: ${imageFilename} (${imageData.length} bytes)`);
    }

    // Write the content manifest (TalkieObject-shaped JSON)
    // The Swift app watches this directory and imports into GRDB.
    const manifest = {
      id: objectId,
      type: "selection",
      sourceType: body.sourceType,
      text: body.text,
      title: body.title ?? defaultTitle(body),
      sourceURL: body.sourceURL,
      imageFilename,
      source: "iphone",
      sourceDeviceId: deviceId,
      createdAt: now.toISOString(),
    };

    await Bun.write(
      `${INGEST_DIR}/${objectId}.json`,
      JSON.stringify(manifest, null, 2)
    );

    log.info(
      `Ingested ${body.sourceType} content from ${deviceId ?? "unknown"}: ` +
      `${objectId} (${body.text.length} chars, title: "${manifest.title}")`
    );

    return {
      ok: true,
      objectId,
      storedAt: now.toISOString(),
    };
  } catch (error) {
    log.error(`Ingest failed: ${String(error)}`);
    return {
      ok: false,
      error: `Ingestion failed: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
}

// ===== Helpers =====

function defaultTitle(body: IngestRequestBody): string {
  switch (body.sourceType) {
    case "url": {
      if (body.sourceURL) {
        try {
          return new URL(body.sourceURL).hostname;
        } catch {
          return "Web content";
        }
      }
      return "Web content";
    }
    case "ocr":
      return "Screenshot";
    case "photo":
      return "Photo";
    case "text":
      return "Pasted text";
  }
}

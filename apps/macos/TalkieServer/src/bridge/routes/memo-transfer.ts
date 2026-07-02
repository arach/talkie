/**
 * Direct Memo Transfer Route
 *
 * POST /memos/:memoId
 * Receives a full iPhone memo package over the paired Bridge link and drops
 * it into the existing Bridge ingest directory for Talkie.app to import.
 */

import { randomUUID } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { basename, extname } from "node:path";

import { log } from "../../log";
import { BRIDGE_DATA_DIR } from "../../paths";
import { badRequest, serverError } from "./responses";

export interface MemoTransferAudio {
  filename?: string;
  mimeType?: string;
  fileSizeBytes?: number;
  dataBase64: string;
}

export interface MemoTransferAttachment {
  id: string;
  originalName: string;
  addedAt: string;
  fileSizeBytes: number;
  pixelWidth?: number;
  pixelHeight?: number;
  recordingOffsetSeconds?: number;
  mimeType?: string;
  dataBase64: string;
}

export interface MemoTransferRequest {
  schemaVersion?: number;
  memoId: string;
  title?: string;
  transcript?: string;
  notes?: string;
  summary?: string;
  durationSeconds?: number;
  createdAt?: string;
  lastModified?: string;
  originDeviceId?: string;
  sourceDeviceName?: string;
  audio?: MemoTransferAudio;
  attachments?: MemoTransferAttachment[];
}

export interface MemoTransferResponse {
  success: true;
  memoId: string;
  storedAt: string;
  attachmentCount: number;
  hasAudio: boolean;
}

interface StoredMemoTransferAttachment {
  id: string;
  originalName: string;
  filename: string;
  fileSizeBytes: number;
  addedAt: string;
  pixelWidth?: number;
  pixelHeight?: number;
  recordingOffsetSeconds?: number;
  mimeType?: string;
}

const INGEST_DIR = `${BRIDGE_DATA_DIR}/Ingested`;

export async function memoTransferRoute(
  memoId: string,
  body: MemoTransferRequest,
  sourceDeviceId?: string | null
): Promise<MemoTransferResponse | Response> {
  const resolvedMemoId = (memoId || body.memoId || "").trim();
  if (!resolvedMemoId) {
    return badRequest("Memo ID is required.");
  }

  const hasText = Boolean((body.transcript || body.notes || body.summary || "").trim());
  const hasAudio = Boolean(body.audio?.dataBase64);
  if (!hasText && !hasAudio) {
    return badRequest("Memo transfer requires transcript text, notes, summary, or audio.");
  }

  try {
    await mkdir(INGEST_DIR, { recursive: true });

    const storedAt = new Date().toISOString();
    const attachments: StoredMemoTransferAttachment[] = [];
    const memoFileToken = sanitizedFileToken(resolvedMemoId);
    let audioFilename: string | undefined;
    let audioFileSizeBytes: number | undefined;

    if (body.audio?.dataBase64) {
      const audioData = Buffer.from(body.audio.dataBase64, "base64");
      if (audioData.length === 0) {
        return badRequest("Audio data could not be decoded.");
      }

      audioFilename = `${memoFileToken}.${audioExtensionFor(body.audio)}`;
      await Bun.write(`${INGEST_DIR}/${audioFilename}`, audioData);
      audioFileSizeBytes = body.audio.fileSizeBytes || audioData.length;
    }

    for (const attachment of body.attachments ?? []) {
      if (!attachment.id || !attachment.dataBase64) {
        return badRequest("Attachment payload is incomplete.");
      }

      const binary = Buffer.from(attachment.dataBase64, "base64");
      if (binary.length === 0) {
        return badRequest("Attachment data could not be decoded.");
      }

      const extension = fileExtensionFor(attachment);
      const cleanedId = sanitizedFileToken(attachment.id);
      const cleanedName = sanitizedBaseName(attachment.originalName || `Attachment_${attachment.id}`);
      const filename = `${memoFileToken}_${cleanedId}_${cleanedName}.${extension}`;
      await Bun.write(`${INGEST_DIR}/${filename}`, binary);

      attachments.push({
        id: attachment.id,
        originalName: attachment.originalName,
        filename,
        fileSizeBytes: attachment.fileSizeBytes || binary.length,
        addedAt: attachment.addedAt,
        pixelWidth: attachment.pixelWidth,
        pixelHeight: attachment.pixelHeight,
        recordingOffsetSeconds: attachment.recordingOffsetSeconds,
        mimeType: attachment.mimeType,
      });
    }

    const manifest = {
      id: resolvedMemoId,
      type: "memo",
      sourceType: "memo",
      text: body.transcript ?? "",
      notes: body.notes,
      summary: body.summary,
      title: body.title,
      source: "iphone",
      sourceDeviceId: sourceDeviceId ?? body.originDeviceId,
      sourceDeviceName: body.sourceDeviceName,
      createdAt: body.createdAt ?? storedAt,
      lastModified: body.lastModified,
      durationSeconds: body.durationSeconds ?? 0,
      audioFilename,
      audioFileSizeBytes,
      attachments,
      receivedAt: storedAt,
      schemaVersion: body.schemaVersion ?? 1,
    };

    await Bun.write(
      `${INGEST_DIR}/${memoFileToken}.json`,
      JSON.stringify(manifest, null, 2)
    );

    log.info(
      `Received direct memo ${resolvedMemoId} from ${sourceDeviceId ?? "unknown"} ` +
      `(audio=${audioFilename ? "yes" : "no"}, attachments=${attachments.length})`
    );

    return {
      success: true,
      memoId: resolvedMemoId,
      storedAt,
      attachmentCount: attachments.length,
      hasAudio: Boolean(audioFilename),
    };
  } catch (error) {
    log.error(`Memo transfer failed: ${String(error)}`);
    return serverError("Could not receive memo.", String(error));
  }
}

function sanitizedBaseName(input: string): string {
  const trimmed = basename(input, extname(input))
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_-]/g, "_")
    .replace(/^_+|_+$/g, "");

  return trimmed.length > 0 ? trimmed : "attachment";
}

function sanitizedFileToken(input: string): string {
  const trimmed = input
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, "_")
    .replace(/^_+|_+$/g, "");

  return trimmed.length > 0 ? trimmed : randomUUID();
}

function audioExtensionFor(audio: MemoTransferAudio): string {
  const explicitExtension = extname(audio.filename || "").replace(/^\./, "").toLowerCase();
  if (explicitExtension) return explicitExtension;

  switch (audio.mimeType) {
    case "audio/wav":
    case "audio/x-wav":
      return "wav";
    case "audio/aac":
      return "aac";
    case "audio/mpeg":
      return "mp3";
    default:
      return "m4a";
  }
}

function fileExtensionFor(attachment: MemoTransferAttachment): string {
  const explicitExtension = extname(attachment.originalName || "").replace(/^\./, "").toLowerCase();
  if (explicitExtension) return explicitExtension;

  switch (attachment.mimeType) {
    case "image/png":
      return "png";
    case "image/heic":
      return "heic";
    default:
      return "jpg";
  }
}

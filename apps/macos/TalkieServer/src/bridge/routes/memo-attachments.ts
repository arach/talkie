/**
 * Memo Attachment Routes
 *
 * POST /memos/:memoId/attachments
 * Receives iPhone memo image attachments directly over the paired Bridge link
 * and stores them as sidecar files under Talkie's Bridge data directory.
 */

import { mkdir } from "node:fs/promises";
import { basename, extname } from "node:path";

import { log } from "../../log";
import { MEMO_ATTACHMENTS_DIR } from "../../paths";
import { badRequest, serverError } from "./responses";

export interface MemoAttachmentUpload {
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

export interface MemoAttachmentsUploadRequest {
  memoTitle?: string;
  memoCreatedAt?: string;
  attachments: MemoAttachmentUpload[];
}

export interface MemoAttachmentsUploadResponse {
  success: true;
  memoId: string;
  savedCount: number;
  storedAt: string;
}

interface StoredMemoAttachmentManifest {
  memoId: string;
  memoTitle?: string;
  memoCreatedAt?: string;
  sourceDeviceId?: string;
  receivedAt: string;
  attachments: Array<{
    id: string;
    originalName: string;
    filename: string;
    fileSizeBytes: number;
    addedAt: string;
    pixelWidth?: number;
    pixelHeight?: number;
    recordingOffsetSeconds?: number;
    mimeType?: string;
  }>;
}

export async function memoAttachmentsUploadRoute(
  memoId: string,
  body: MemoAttachmentsUploadRequest,
  sourceDeviceId?: string | null
): Promise<MemoAttachmentsUploadResponse | Response> {
  if (!memoId.trim()) {
    return badRequest("Memo ID is required.");
  }

  if (!Array.isArray(body.attachments) || body.attachments.length === 0) {
    return badRequest("At least one attachment is required.");
  }

  try {
    const memoDirectory = `${MEMO_ATTACHMENTS_DIR}/${memoId}`;
    await mkdir(memoDirectory, { recursive: true });

    const receivedAt = new Date().toISOString();
    const manifest: StoredMemoAttachmentManifest = {
      memoId,
      memoTitle: body.memoTitle,
      memoCreatedAt: body.memoCreatedAt,
      sourceDeviceId: sourceDeviceId ?? undefined,
      receivedAt,
      attachments: [],
    };

    for (const attachment of body.attachments) {
      if (!attachment.id || !attachment.dataBase64) {
        return badRequest("Attachment payload is incomplete.");
      }

      const binary = Buffer.from(attachment.dataBase64, "base64");
      if (binary.length === 0) {
        return badRequest("Attachment data could not be decoded.");
      }

      const extension = fileExtensionFor(attachment);
      const cleanedName = sanitizedBaseName(attachment.originalName || `Attachment_${attachment.id}`);
      const filename = `${attachment.id}_${cleanedName}.${extension}`;

      await Bun.write(`${memoDirectory}/${filename}`, binary);

      manifest.attachments.push({
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

    await Bun.write(
      `${memoDirectory}/manifest.json`,
      JSON.stringify(manifest, null, 2)
    );

    log.info(
      `Saved ${manifest.attachments.length} memo attachment(s) for memo ${memoId}` +
      (sourceDeviceId ? ` from device ${sourceDeviceId}` : "")
    );

    return {
      success: true,
      memoId,
      savedCount: manifest.attachments.length,
      storedAt: receivedAt,
    };
  } catch (error) {
    log.error(`Memo attachment upload failed: ${String(error)}`);
    return serverError("Could not save memo attachments.", String(error));
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

function fileExtensionFor(attachment: MemoAttachmentUpload): string {
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

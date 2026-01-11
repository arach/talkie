/**
 * Extensions Module - Message Handlers
 *
 * Handles all inbound messages from extensions and routes to appropriate services.
 */

import { log } from "../log";
import { inference } from "../gateway/providers";
import type { InferenceRequest, Message } from "../gateway/providers/types";
import { computeDiff } from "./diff";
import { validateToken } from "./auth";
import type {
  Capability,
  CAPABILITIES,
  InboundMessage,
  OutboundMessage,
  ExtensionConnection,
  LLMCompleteMessage,
  LLMReviseMessage,
  DiffComputeMessage,
  StorageClipboardWriteMessage,
  StorageMemoSaveMessage,
  DiffOperation,
} from "./types";

// ===== Types =====

export interface HandlerContext {
  connection: ExtensionConnection;
  send: (message: OutboundMessage) => void;
}

// ===== Authentication Handler =====

export function handleAuth(
  ctx: HandlerContext,
  name: string,
  capabilities: string[],
  token: string,
  version?: string
): boolean {
  // Validate token
  if (!validateToken(token)) {
    log.warn(`Extensions: Auth failed for "${name}" - invalid token`);
    ctx.send({
      type: "error",
      error: "Invalid authentication token",
      code: "AUTH_FAILED",
    });
    return false;
  }

  // Update connection
  ctx.connection.name = name;
  ctx.connection.authenticated = true;

  // Grant requested capabilities (validate each one)
  const validCapabilities = ["transcribe", "llm", "diff", "storage"] as const;
  ctx.connection.grantedCapabilities = capabilities.filter((cap) =>
    validCapabilities.includes(cap as Capability)
  ) as Capability[];

  log.info(
    `Extensions: "${name}" authenticated (v${version || "1.0"}) - capabilities: ${ctx.connection.grantedCapabilities.join(", ")}`
  );

  ctx.send({
    type: "ext:connected",
    granted: ctx.connection.grantedCapabilities,
  });

  return true;
}

// ===== Capability Check =====

function hasCapability(ctx: HandlerContext, capability: Capability): boolean {
  if (!ctx.connection.authenticated) {
    ctx.send({
      type: "error",
      error: "Not authenticated",
      code: "NOT_AUTHENTICATED",
    });
    return false;
  }

  if (!ctx.connection.grantedCapabilities.includes(capability)) {
    ctx.send({
      type: "error",
      error: `Capability not granted: ${capability}`,
      code: "CAPABILITY_DENIED",
    });
    return false;
  }

  return true;
}

// ===== LLM Handlers =====

export async function handleLLMComplete(
  ctx: HandlerContext,
  msg: LLMCompleteMessage
): Promise<void> {
  if (!hasCapability(ctx, "llm")) return;

  try {
    // Convert messages to Gateway format
    const messages: Message[] = msg.messages.map((m) => ({
      role: m.role as "system" | "user" | "assistant",
      content: m.content,
    }));

    // Use default provider/model if not specified
    const provider = msg.provider || "anthropic";
    const model = msg.model || "claude-sonnet-4-20250514";

    const request: InferenceRequest = {
      provider: provider as any,
      model,
      messages,
    };

    log.info(`Extensions: LLM complete via ${provider}/${model}`);

    const result = await inference(request);

    ctx.send({
      type: "llm:result",
      content: result.content,
      provider: result.provider,
      model: result.model,
    });
  } catch (error) {
    log.error(`Extensions: LLM complete failed: ${error}`);
    ctx.send({
      type: "error",
      error: `LLM completion failed: ${error}`,
      code: "LLM_ERROR",
    });
  }
}

export async function handleLLMRevise(
  ctx: HandlerContext,
  msg: LLMReviseMessage
): Promise<void> {
  if (!hasCapability(ctx, "llm")) return;

  try {
    // Build system prompt with constraints
    let systemPrompt =
      "You are a writing assistant. Revise the user's text according to their instruction. " +
      "Return ONLY the revised text, no explanations or commentary.";

    if (msg.constraints) {
      if (msg.constraints.maxLength) {
        systemPrompt += ` Keep the response under ${msg.constraints.maxLength} characters.`;
      }
      if (msg.constraints.style) {
        systemPrompt += ` Write in a ${msg.constraints.style} style.`;
      }
      if (msg.constraints.format) {
        systemPrompt += ` Format: ${msg.constraints.format}`;
      }
    }

    const messages: Message[] = [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: `Text to revise:\n${msg.content}\n\nInstruction: ${msg.instruction}`,
      },
    ];

    const provider = msg.provider || "anthropic";
    const model = msg.model || "claude-sonnet-4-20250514";

    const request: InferenceRequest = {
      provider: provider as any,
      model,
      messages,
      maxTokens: msg.constraints?.maxTokens,
    };

    log.info(`Extensions: LLM revise via ${provider}/${model}`);

    const result = await inference(request);
    const diff = computeDiff(msg.content, result.content);

    ctx.send({
      type: "llm:revision",
      before: msg.content,
      after: result.content,
      diff,
      instruction: msg.instruction,
      provider: result.provider,
      model: result.model,
    });
  } catch (error) {
    log.error(`Extensions: LLM revise failed: ${error}`);
    ctx.send({
      type: "error",
      error: `LLM revision failed: ${error}`,
      code: "LLM_ERROR",
    });
  }
}

// ===== Diff Handler =====

export function handleDiffCompute(
  ctx: HandlerContext,
  msg: DiffComputeMessage
): void {
  if (!hasCapability(ctx, "diff")) return;

  try {
    const operations = computeDiff(msg.before, msg.after);

    ctx.send({
      type: "diff:result",
      operations,
    });
  } catch (error) {
    log.error(`Extensions: Diff compute failed: ${error}`);
    ctx.send({
      type: "error",
      error: `Diff computation failed: ${error}`,
      code: "DIFF_ERROR",
    });
  }
}

// ===== Storage Handlers =====

export async function handleClipboardWrite(
  ctx: HandlerContext,
  msg: StorageClipboardWriteMessage
): Promise<void> {
  if (!hasCapability(ctx, "storage")) return;

  try {
    // Use Bun's native clipboard API or shell command
    const proc = Bun.spawn(["pbcopy"], {
      stdin: "pipe",
    });
    proc.stdin.write(msg.content);
    proc.stdin.end();
    await proc.exited;

    log.info(`Extensions: Clipboard write (${msg.content.length} chars)`);
  } catch (error) {
    log.error(`Extensions: Clipboard write failed: ${error}`);
    ctx.send({
      type: "error",
      error: `Clipboard write failed: ${error}`,
      code: "STORAGE_ERROR",
    });
  }
}

export async function handleClipboardRead(ctx: HandlerContext): Promise<void> {
  if (!hasCapability(ctx, "storage")) return;

  try {
    const proc = Bun.spawn(["pbpaste"]);
    const content = await new Response(proc.stdout).text();
    await proc.exited;

    ctx.send({
      type: "storage:clipboard:content",
      content,
    });
  } catch (error) {
    log.error(`Extensions: Clipboard read failed: ${error}`);
    ctx.send({
      type: "error",
      error: `Clipboard read failed: ${error}`,
      code: "STORAGE_ERROR",
    });
  }
}

export async function handleMemoSave(
  ctx: HandlerContext,
  msg: StorageMemoSaveMessage
): Promise<void> {
  if (!hasCapability(ctx, "storage")) return;

  // TODO: Integrate with Talkie's memo system
  // For now, generate a unique ID and log
  const id = crypto.randomUUID();
  log.info(`Extensions: Memo save request - "${msg.title || "(untitled)"}" (${msg.content.length} chars) - ID: ${id}`);

  // In a full implementation, this would communicate with the main Talkie app
  // via XPC or HTTP to save the memo to GRDB

  ctx.send({
    type: "storage:memo:saved",
    id,
  });
}

// ===== Transcription Handlers =====
// Note: These require communication with TalkieEngine, which isn't directly accessible from here.
// For now, we return errors. A full implementation would use XPC or HTTP to TalkieEngine.

export async function handleTranscribeStart(ctx: HandlerContext): Promise<void> {
  if (!hasCapability(ctx, "transcribe")) return;

  // TODO: Integrate with TalkieEngine via XPC or HTTP
  log.warn("Extensions: Transcription not yet wired to TalkieEngine");
  ctx.send({
    type: "error",
    error: "Transcription not yet available in TalkieServer. Use Talkie app directly.",
    code: "NOT_IMPLEMENTED",
  });
}

export async function handleTranscribeStop(ctx: HandlerContext): Promise<void> {
  if (!hasCapability(ctx, "transcribe")) return;

  // TODO: Integrate with TalkieEngine via XPC or HTTP
  log.warn("Extensions: Transcription not yet wired to TalkieEngine");
  ctx.send({
    type: "error",
    error: "Transcription not yet available in TalkieServer. Use Talkie app directly.",
    code: "NOT_IMPLEMENTED",
  });
}

// ===== Legacy v1 Handlers =====
// Map old draft:* messages to new API

export async function handleLegacyRefine(
  ctx: HandlerContext,
  instruction: string,
  constraints?: { maxLength?: number; style?: string; format?: string }
): Promise<void> {
  // Legacy refine doesn't have content, so we can't do much
  // In the Swift version, this operated on current draft state
  log.warn("Extensions: Legacy draft:refine received but no content context available");
  ctx.send({
    type: "draft:error",
    error: "Legacy draft:refine not supported without content. Use llm:revise instead.",
    code: "LEGACY_NOT_SUPPORTED",
  });
}

export function handleLegacyUpdate(ctx: HandlerContext, content: string): void {
  // No-op in server context - drafts are client-side
  log.info(`Extensions: Legacy draft:update received (${content.length} chars) - ignored`);
}

export function handleLegacyAcceptReject(ctx: HandlerContext, accepted: boolean): void {
  // No-op in server context - revision state is client-side
  log.info(`Extensions: Legacy draft:${accepted ? "accept" : "reject"} received - ignored`);
}

export async function handleLegacySave(
  ctx: HandlerContext,
  destination: "memo" | "clipboard"
): Promise<void> {
  // Can't save without content
  log.warn("Extensions: Legacy draft:save received but no content context available");
  ctx.send({
    type: "draft:error",
    error: "Legacy draft:save not supported without content. Use storage:* instead.",
    code: "LEGACY_NOT_SUPPORTED",
  });
}

export async function handleLegacyCapture(
  ctx: HandlerContext,
  action: "start" | "stop"
): Promise<void> {
  // Route to transcription handlers
  if (action === "start") {
    await handleTranscribeStart(ctx);
  } else {
    await handleTranscribeStop(ctx);
  }
}

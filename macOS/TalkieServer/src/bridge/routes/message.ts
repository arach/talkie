/**
 * Message Routes
 *
 * POST /sessions/:id/message  - Send text to a Claude session
 * POST /inject                - Legacy endpoint (alias)
 *
 * Smart message delivery using the best available method:
 * - Screen unlocked → UI mode (Talkie → TalkieLive → paste into terminal)
 * - Screen locked → Headless mode (Claude CLI --resume --print)
 */

import { log } from "../../log";
import { getSession, type ClaudeSession } from "../../discovery/sessions";
import { badRequest, serverError, serviceUnavailable } from "./responses";
import { spawn } from "bun";

// ===== Types =====

export interface MessageBody {
  message?: string;
  projectDir?: string;
  sessionId?: string;  // For legacy /inject route
  // Audio message fields
  audio?: string;      // Base64 encoded audio
  format?: string;     // "m4a", "wav", etc.
}

export interface MessageResponse {
  success: boolean;
  mode: "headless" | "ui";
  modeReason: string;
  screenLocked: boolean;
  response?: string;
  error?: string;
  verified?: boolean;
  verifyAttempts?: number;
}

// ===== Config =====

const TALKIE_SERVER_PORT = 8766;
const TALKIE_SERVER_HOST = "127.0.0.1";  // Use IPv4 explicitly to avoid IPv6 resolution issues
const MAX_RETRIES = 2;
const RETRY_DELAY_MS = 500;
const FETCH_TIMEOUT_MS = 30000;

const LOG_VERIFY_TIMEOUT_MS = 3000;
const LOG_VERIFY_POLL_MS = 200;
const LOG_VERIFY_ENABLED = true;

// ===== Helpers =====

async function isScreenLocked(): Promise<boolean> {
  try {
    const proc = spawn({
      cmd: ["ioreg", "-r", "-k", "CGSSessionScreenIsLocked"],
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(proc.stdout).text();
    return output.includes('"CGSSessionScreenIsLocked" = Yes');
  } catch {
    return false;
  }
}

async function isTalkieAvailable(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    const start = Date.now();
    const response = await fetch(`http://${TALKIE_SERVER_HOST}:${TALKIE_SERVER_PORT}/health`, {
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const elapsed = Date.now() - start;
    if (elapsed > 500) {
      log.warn(`Talkie health check slow: ${elapsed}ms`);
    }
    return response.ok;
  } catch (err) {
    log.warn(`Talkie health check failed: ${err}`);
    return false;
  }
}

async function sendHeadless(
  sessionId: string,
  message: string,
  projectDir?: string
): Promise<{ success: boolean; response?: string; error?: string }> {
  const args = [
    "--resume", sessionId,
    "--print",
    "--output-format", "stream-json",
    "--verbose",
    message,
  ];

  const proc = spawn({
    cmd: ["npx", "claude", ...args],
    cwd: projectDir || process.cwd(),
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, TERM: "dumb", NO_COLOR: "1" },
  });

  try {
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;

    if (exitCode !== 0) {
      log.error(`Headless CLI error (exit ${exitCode}): ${stderr}`);
      return { success: false, error: `CLI exited with code ${exitCode}` };
    }

    let response = "";
    for (const line of stdout.split("\n")) {
      if (line.trim()) {
        try {
          const msg = JSON.parse(line) as {
            type?: string;
            message?: { content?: Array<{ type: string; text?: string }> };
          };
          if (msg.type === "assistant") {
            const text = msg.message?.content
              ?.filter((b) => b.type === "text")
              ?.map((b) => b.text)
              ?.join("") || "";
            response += text;
          }
        } catch {
          // Skip malformed
        }
      }
    }

    return { success: true, response };
  } catch (error) {
    return { success: false, error: String(error) };
  }
}

async function verifyMessageInLogs(
  session: ClaudeSession,
  messageText: string,
  timeoutMs: number = LOG_VERIFY_TIMEOUT_MS
): Promise<{ verified: boolean; attempts: number }> {
  const startTime = Date.now();
  let attempts = 0;
  const normalizedMessage = messageText.trim().toLowerCase().slice(0, 100);

  while (Date.now() - startTime < timeoutMs) {
    attempts++;

    try {
      const file = Bun.file(session.transcriptPath);
      const text = await file.text();
      const lines = text.trim().split("\n");
      const recentLines = lines.slice(-10);

      for (const line of recentLines) {
        try {
          const entry = JSON.parse(line) as {
            type?: string;
            message?: { role?: string };
            content?: unknown;
          };

          if (entry.type === "user" || entry.message?.role === "user") {
            const content = extractMessageContent(entry);
            if (content.toLowerCase().includes(normalizedMessage)) {
              log.info(`Log verified: message found after ${attempts} attempts`);
              return { verified: true, attempts };
            }
          }
        } catch {
          // Skip malformed lines
        }
      }
    } catch (err) {
      log.warn(`Log verification read error: ${err}`);
    }

    await new Promise((resolve) => setTimeout(resolve, LOG_VERIFY_POLL_MS));
  }

  log.warn(`Log verification failed: message not found after ${attempts} attempts`);
  return { verified: false, attempts };
}

function extractMessageContent(entry: { content?: unknown; message?: { content?: unknown } }): string {
  if (typeof entry.content === "string") {
    return entry.content;
  }
  if (Array.isArray(entry.content)) {
    return entry.content
      .filter((c: { type?: string; text?: string }) => c.type === "text")
      .map((c: { text?: string }) => c.text)
      .join(" ");
  }
  if (entry.message?.content) {
    return extractMessageContent({ content: entry.message.content });
  }
  return "";
}

async function fetchWithRetry(
  url: string,
  options: RequestInit,
  retries = MAX_RETRIES
): Promise<Response> {
  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        ...options,
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      clearTimeout(timeoutId);
      lastError = error as Error;

      if (controller.signal.aborted) {
        log.error(`TalkieServer request timed out after ${FETCH_TIMEOUT_MS}ms`);
        throw new Error(`Request timed out after ${FETCH_TIMEOUT_MS}ms`);
      }

      if (attempt < retries) {
        const delay = RETRY_DELAY_MS * Math.pow(2, attempt);
        log.info(`TalkieServer connection failed, retrying in ${delay}ms (attempt ${attempt + 1}/${retries + 1})`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}

// ===== Handlers =====

/**
 * POST /sessions/:id/message
 * Send text to a Claude session
 */
export async function sendMessageRoute(
  sessionId: string | undefined,
  body: MessageBody
): Promise<Response> {
  const resolvedSessionId = sessionId || body.sessionId;

  if (!resolvedSessionId || typeof resolvedSessionId !== "string") {
    return badRequest("sessionId is required");
  }

  // Handle audio messages - forward to Swift Talkie server (has Parakeet transcription)
  if (body.audio) {
    log.info(`Audio message received: ${body.audio.length} chars base64, format: ${body.format}`);

    const session = await getSession(resolvedSessionId);
    const projectPath = body.projectDir || session?.projectPath;

    try {
      const payload = {
        sessionId: resolvedSessionId,
        projectPath,
        audio: body.audio,
        format: body.format || "m4a",
      };

      const response = await fetchWithRetry(`http://${TALKIE_SERVER_HOST}:${TALKIE_SERVER_PORT}/message`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const errorBody = await response.json().catch(() => ({})) as { error?: string };
        log.error(`Talkie audio error: ${response.status}: ${JSON.stringify(errorBody)}`);
        return Response.json({
          success: false,
          error: errorBody.error || `Talkie returned ${response.status}`,
          mode: "ui",
          modeReason: "audio via Talkie",
          screenLocked: false,
        });
      }

      const result = await response.json() as Record<string, unknown>;
      log.info(`Audio transcribed and sent: ${JSON.stringify(result)}`);

      return Response.json({
        ...result,
        success: true,
        mode: "ui",
        modeReason: "audio via Talkie/Parakeet",
        screenLocked: false,
      });
    } catch (error) {
      log.error(`Could not send audio to Talkie: ${error}`);
      return Response.json({
        success: false,
        error: `Could not connect to Talkie for transcription: ${error}`,
        mode: "ui",
        modeReason: "Talkie unavailable",
        screenLocked: false,
      });
    }
  }

  const messageText = body.message || "";
  const session = await getSession(resolvedSessionId);
  const projectPath = body.projectDir || session?.projectPath;

  const screenLocked = await isScreenLocked();
  const talkieAvailable = screenLocked ? false : await isTalkieAvailable();
  const useHeadless = screenLocked || !talkieAvailable;

  const modeReason = screenLocked
    ? "screen locked"
    : !talkieAvailable
    ? "Talkie unavailable"
    : "screen unlocked";

  log.info(`Mode: ${useHeadless ? "headless" : "ui"} (${modeReason})`);

  // HEADLESS MODE
  if (useHeadless && messageText.length > 0) {
    log.info(`Headless: session=${resolvedSessionId}, message=${messageText.slice(0, 50)}...`);

    const result = await sendHeadless(resolvedSessionId, messageText, projectPath);

    return Response.json({
      success: result.success,
      error: result.error,
      response: result.response,
      mode: "headless",
      modeReason,
      screenLocked,
    } satisfies MessageResponse);
  }

  // UI MODE
  log.info(`Message: forwarding to TalkieServer (session: ${resolvedSessionId}, project: ${projectPath || "unknown"}, ${messageText.length} chars)`);

  try {
    const payload = {
      sessionId: resolvedSessionId,
      projectPath,
      text: messageText,
    };

    const jsonPayload = JSON.stringify(payload);
    log.info(`Sending to TalkieServer: ${jsonPayload.length} bytes`);

    const response = await fetchWithRetry(`http://${TALKIE_SERVER_HOST}:${TALKIE_SERVER_PORT}/message`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: jsonPayload,
    });

    if (!response.ok) {
      const errorBody = await response.json().catch(() => ({})) as { error?: string };
      log.error(`TalkieServer returned ${response.status}: ${JSON.stringify(errorBody)}`);
      return Response.json({
        success: false,
        error: errorBody.error || `TalkieServer returned ${response.status}`,
        mode: "ui",
        modeReason,
        screenLocked,
      } satisfies MessageResponse, { status: response.status });
    }

    const result = await response.json() as Record<string, unknown>;
    log.info(`Message sent: ${JSON.stringify(result)}`);

    let verified: boolean | undefined;
    let verifyAttempts: number | undefined;

    if (LOG_VERIFY_ENABLED && messageText.length > 0 && session) {
      const verification = await verifyMessageInLogs(session, messageText);
      verified = verification.verified;
      verifyAttempts = verification.attempts;
    }

    return Response.json({
      ...result,
      success: true,
      mode: "ui",
      modeReason,
      screenLocked,
      verified,
      verifyAttempts,
    } satisfies MessageResponse);
  } catch (error) {
    log.error(`Could not connect to TalkieServer: ${error}`);
    return serviceUnavailable(
      `Could not connect to Talkie Bridge (port 8766): ${error}`,
      `Troubleshooting:\n1. Is Talkie running? Check for Talkie icon in menu bar\n2. Is Bridge enabled? Settings → iOS Bridge → Enable\n3. If Talkie was just restarted, wait a few seconds\n4. Try: Restart Talkie from menu bar`
    );
  }
}

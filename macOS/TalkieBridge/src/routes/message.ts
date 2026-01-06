/**
 * message.ts - Smart message delivery to Claude sessions
 *
 * POST /sessions/:id/message delivers a message using the best available method:
 * - Screen unlocked → UI mode (Talkie → TalkieLive → paste into terminal)
 * - Screen locked → Headless mode (Claude CLI --resume --print)
 *
 * iOS doesn't need to know or care about modes. Just send the message.
 */

import { log } from "../log";
import { getSession, type ClaudeSession } from "../discovery/sessions";
import { spawn } from "bun";

const TALKIE_SERVER_PORT = 8766;
const MAX_RETRIES = 2;
const RETRY_DELAY_MS = 500;
const FETCH_TIMEOUT_MS = 30000;  // 30 second timeout for each attempt

// Log verification settings
const LOG_VERIFY_TIMEOUT_MS = 3000;  // How long to wait for message to appear
const LOG_VERIFY_POLL_MS = 200;      // Poll interval
const LOG_VERIFY_ENABLED = true;     // Can disable for debugging

/**
 * Check if the screen is locked using ioreg (more reliable than Python/Quartz)
 */
async function isScreenLocked(): Promise<boolean> {
  try {
    // Use ioreg which works without pyobjc
    const proc = spawn({
      cmd: ["ioreg", "-r", "-k", "CGSSessionScreenIsLocked"],
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(proc.stdout).text();
    // If CGSSessionScreenIsLocked = Yes appears, screen is locked
    return output.includes('"CGSSessionScreenIsLocked" = Yes');
  } catch {
    return false;  // Assume unlocked if we can't determine
  }
}

/**
 * Check if Talkie app is available (responding on its port)
 */
async function isTalkieAvailable(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000); // 3 second timeout
    const start = Date.now();
    const response = await fetch(`http://localhost:${TALKIE_SERVER_PORT}/health`, {
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

/**
 * Send message via headless mode (Claude CLI)
 */
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

    // Parse streaming JSON and extract assistant response
    let response = "";
    for (const line of stdout.split("\n")) {
      if (line.trim()) {
        try {
          const msg = JSON.parse(line);
          if (msg.type === "assistant") {
            const text = msg.message?.content
              ?.filter((b: any) => b.type === "text")
              ?.map((b: any) => b.text)
              ?.join("") || "";
            response += text;
          }
        } catch { /* skip malformed */ }
      }
    }

    return { success: true, response };
  } catch (error) {
    return { success: false, error: String(error) };
  }
}

/**
 * Verify a message appeared in the session's JSONL log
 * Polls the log file looking for the message text in recent entries
 */
async function verifyMessageInLogs(
  session: ClaudeSession,
  messageText: string,
  timeoutMs: number = LOG_VERIFY_TIMEOUT_MS
): Promise<{ verified: boolean; attempts: number }> {
  const startTime = Date.now();
  let attempts = 0;

  // Normalize message for comparison (trim, lowercase)
  const normalizedMessage = messageText.trim().toLowerCase().slice(0, 100);

  while (Date.now() - startTime < timeoutMs) {
    attempts++;

    try {
      const file = Bun.file(session.transcriptPath);
      const text = await file.text();
      const lines = text.trim().split("\n");

      // Check last 10 lines for the message
      const recentLines = lines.slice(-10);

      for (const line of recentLines) {
        try {
          const entry = JSON.parse(line);

          // Check if it's a user message containing our text
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

/**
 * Extract text content from a log entry
 */
function extractMessageContent(entry: any): string {
  if (typeof entry.content === "string") {
    return entry.content;
  }
  if (Array.isArray(entry.content)) {
    return entry.content
      .filter((c: any) => c.type === "text")
      .map((c: any) => c.text)
      .join(" ");
  }
  if (entry.message?.content) {
    return extractMessageContent(entry.message);
  }
  return "";
}

/**
 * Fetch with retry and timeout - retries on connection errors with backoff
 */
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

      // Don't retry on abort (timeout)
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

interface MessageBody {
  text?: string;  // Direct text to send (empty = submit/Enter only)
  audio?: string;  // Base64 encoded audio (alternative to text)
  format?: string;  // Audio format: "wav", "m4a", etc.
  sessionId?: string;  // For legacy /inject route
}

/**
 * POST /sessions/:id/message - Send text or audio to a Claude session
 *
 * @param req - Request with JSON body { text: string } OR { audio: string, format: string }
 * @param sessionId - Session ID from URL path (optional, can also be in body for legacy /inject)
 */
export async function sendMessageRoute(req: Request, sessionId?: string): Promise<Response> {
  let body: MessageBody;

  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  // sessionId from URL takes precedence, fall back to body for legacy /inject route
  const resolvedSessionId = sessionId || body.sessionId;

  if (!resolvedSessionId || typeof resolvedSessionId !== "string") {
    return Response.json({ error: "sessionId is required" }, { status: 400 });
  }

  // Validate: either text (can be empty for submit-only) or audio must be provided
  const hasText = typeof body.text === "string";  // Empty string is valid (submit only)
  const hasAudio = body.audio && typeof body.audio === "string" && body.audio.length > 0;

  if (!hasText && !hasAudio) {
    return Response.json({ error: "Either 'text' or 'audio' is required" }, { status: 400 });
  }

  // Look up session to get projectPath for terminal matching
  const session = await getSession(resolvedSessionId);
  const projectPath = session?.projectPath;

  // Detect mode: screen locked → headless, otherwise → UI
  const screenLocked = await isScreenLocked();
  const talkieAvailable = screenLocked ? false : await isTalkieAvailable();
  const useHeadless = screenLocked || !talkieAvailable;

  const modeReason = screenLocked
    ? "screen locked"
    : !talkieAvailable
    ? "Talkie unavailable"
    : "screen unlocked";

  log.info(`Mode: ${useHeadless ? "headless" : "ui"} (${modeReason})`);

  // HEADLESS MODE: Use Claude CLI directly
  if (useHeadless && hasText && body.text && body.text.length > 0) {
    log.info(`Headless: session=${resolvedSessionId}, message=${body.text.slice(0, 50)}...`);

    const result = await sendHeadless(resolvedSessionId, body.text, projectPath);

    return Response.json({
      success: result.success,
      error: result.error,
      response: result.response,
      mode: "headless",
      modeReason,
      screenLocked,
    });
  }

  // Audio in headless mode not supported yet - need Talkie for transcription
  if (useHeadless && hasAudio) {
    return Response.json({
      success: false,
      error: "Audio transcription requires Talkie app (screen must be unlocked)",
      mode: "headless",
      modeReason,
      screenLocked,
    }, { status: 503 });
  }

  // UI MODE: Forward to Talkie app
  if (hasAudio) {
    const format = body.format || "m4a";
    log.info(`Audio message: forwarding to TalkieServer (session: ${resolvedSessionId}, project: ${projectPath || "unknown"}, ${body.audio!.length} chars base64, format: ${format})`);
  } else if (body.text!.length === 0) {
    log.info(`Submit only: forwarding to TalkieServer (session: ${resolvedSessionId}, project: ${projectPath || "unknown"})`);
  } else {
    log.info(`Message: forwarding to TalkieServer (session: ${resolvedSessionId}, project: ${projectPath || "unknown"}, ${body.text!.length} chars)`);
  }

  // Forward to TalkieServer - it handles transcription (if audio) + XPC to TalkieLive
  try {
    const payload: Record<string, unknown> = {
      sessionId: resolvedSessionId,
      projectPath,
    };

    if (hasAudio) {
      payload.audio = body.audio;
      payload.format = body.format || "m4a";
    } else {
      payload.text = body.text;
    }

    const jsonPayload = JSON.stringify(payload);
    log.info(`Sending to TalkieServer: ${jsonPayload.length} bytes`);
    // Debug: dump first 200 and last 200 chars of payload
    if (jsonPayload.length > 500) {
      log.info(`Payload start: ${jsonPayload.slice(0, 200)}`);
      log.info(`Payload end: ${jsonPayload.slice(-200)}`);
    } else {
      log.info(`Full payload: ${jsonPayload}`);
    }

    const response = await fetchWithRetry(`http://localhost:${TALKIE_SERVER_PORT}/message`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: jsonPayload,
    });

    if (!response.ok) {
      const errorBody = await response.json().catch(() => ({}));
      log.error(`TalkieServer returned ${response.status}: ${JSON.stringify(errorBody)}`);
      return Response.json(
        {
          success: false,
          error: errorBody.error || `TalkieServer returned ${response.status}`,
          transcript: errorBody.transcript,
        },
        { status: response.status }
      );
    }

    const result = await response.json();
    log.info(`Message sent: ${JSON.stringify(result)}`);

    // Verify message appeared in logs (for text messages only)
    let verified: boolean | undefined;
    let verifyAttempts: number | undefined;

    if (LOG_VERIFY_ENABLED && hasText && body.text && body.text.length > 0 && session) {
      const verification = await verifyMessageInLogs(session, body.text);
      verified = verification.verified;
      verifyAttempts = verification.attempts;
    }

    return Response.json({
      ...result,
      mode: "ui",
      modeReason,
      screenLocked,
      verified,
      verifyAttempts,
    });
  } catch (error) {
    log.error(`Could not connect to TalkieServer: ${error}`);
    return Response.json(
      {
        success: false,
        error: `Could not connect to TalkieServer: ${error}`,
        hint: "Is Talkie running with Bridge enabled?",
      },
      { status: 502 }
    );
  }
}

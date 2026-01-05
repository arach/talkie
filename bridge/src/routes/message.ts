/**
 * message.ts - Forward messages to Talkie
 *
 * Bridge is a dumb pipe:
 * - Forwards { sessionId, text, projectPath } OR { sessionId, audio, format, projectPath }
 * - Talkie forwards to TalkieLive via XPC
 * - TalkieLive handles terminal lookup and text insertion
 * - If audio provided, Talkie transcribes first via TalkieEngine
 */

import { log } from "../log";
import { getSession } from "../discovery/sessions";

const TALKIE_SERVER_PORT = 8766;
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 1000;

/**
 * Fetch with retry - retries on connection errors with exponential backoff
 */
async function fetchWithRetry(
  url: string,
  options: RequestInit,
  retries = MAX_RETRIES
): Promise<Response> {
  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const response = await fetch(url, options);
      return response;
    } catch (error) {
      lastError = error as Error;

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
    return Response.json(result);
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

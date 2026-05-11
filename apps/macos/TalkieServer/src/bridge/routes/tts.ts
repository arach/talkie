/**
 * Text-to-Speech Route
 *
 * POST /tts
 * Runs TTS on the Mac using configured API keys and returns audio data.
 * The iOS app stays thin — no API clients needed on the phone.
 *
 * Returns audio as base64-encoded MP3 in the response envelope.
 */

import { log } from "../../log";
import { readProviderAPIKey } from "../../talkie/settings";
import { badRequest } from "./responses";

// ===== Types =====

export interface TTSRequestBody {
  /** Text to synthesize */
  text: string;

  /** TTS voice (OpenAI: alloy, echo, fable, onyx, nova, shimmer; Kokoro: af_heart, etc.) */
  voice?: string;

  /** TTS provider */
  provider?: "openai" | "local";
}

export interface TTSResponseEnvelope {
  ok: boolean;
  /** Base64-encoded audio data (MP3) */
  audioBase64?: string;
  /** Duration hint in seconds (if available) */
  durationHint?: number;
  /** Voice used */
  voice?: string;
  error?: string;
}

// ===== Route Handler =====

export async function ttsRoute(
  body: TTSRequestBody
): Promise<TTSResponseEnvelope | Response> {
  if (!body.text || body.text.trim().length === 0) {
    return badRequest("text is required");
  }

  const provider = body.provider || "openai";
  log.info(`TTS route: provider=${provider}, voice=${body.voice || "(default)"}`);

  if (provider === "local") {
    return localTtsRoute(body);
  }

  return openaiTtsRoute(body);
}

// MARK: - Local Kokoro TTS (via TalkieSpeech on :8780)

const SPEECH_PORT = 8780;
const SPEECH_HOST = process.env.TALKIE_SPEECH_HOST || "127.0.0.1";

async function localTtsRoute(
  body: TTSRequestBody
): Promise<TTSResponseEnvelope> {
  const text = body.text.slice(0, 10000);
  const voice = body.voice || "af_heart";

  try {
    log.info(`Local TTS request: ${text.length} chars, voice=${voice}`);

    const speechToken = process.env.TALKIE_SPEECH_TOKEN || "";
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (speechToken) {
      headers["Authorization"] = `Bearer ${speechToken}`;
    }

    const response = await fetch(
      `http://${SPEECH_HOST}:${SPEECH_PORT}/synthesize`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ text, voice }),
        signal: AbortSignal.timeout(120_000),
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`TalkieSpeech failed (${response.status}): ${errorText}`);
      return {
        ok: false,
        error: `Local TTS failed (${response.status}): ${errorText.slice(0, 200)}`,
      };
    }

    const audioBuffer = await response.arrayBuffer();
    const audioBase64 = Buffer.from(audioBuffer).toString("base64");

    log.info(`Local TTS complete: ${audioBuffer.byteLength} bytes, voice=${voice}`);

    return { ok: true, audioBase64, voice };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Local TTS error: ${message}`);
    return { ok: false, error: `Local TTS failed: ${message}` };
  }
}

// MARK: - OpenAI Cloud TTS

async function openaiTtsRoute(
  body: TTSRequestBody
): Promise<TTSResponseEnvelope> {
  const maxChars = 4096;
  const text = body.text.length > maxChars
    ? body.text.slice(0, maxChars)
    : body.text;

  const voice = body.voice || "echo";

  try {
    const apiKey = readProviderAPIKey("openai");
    if (!apiKey) {
      return {
        ok: false,
        error: "No OpenAI API key configured on this Mac. Add one in Talkie settings.",
      };
    }

    log.info(`TTS request: ${text.length} chars, voice=${voice}`);

    const response = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "tts-1",
        input: text,
        voice,
        response_format: "mp3",
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`OpenAI TTS failed (${response.status}): ${errorText}`);
      return {
        ok: false,
        error: `TTS failed (${response.status}): ${errorText.slice(0, 200)}`,
      };
    }

    const audioBuffer = await response.arrayBuffer();
    const audioBase64 = Buffer.from(audioBuffer).toString("base64");

    log.info(
      `TTS complete: ${audioBuffer.byteLength} bytes, voice=${voice}`
    );

    return {
      ok: true,
      audioBase64,
      voice,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`TTS route error: ${message}`);
    return {
      ok: false,
      error: `TTS failed: ${message}`,
    };
  }
}

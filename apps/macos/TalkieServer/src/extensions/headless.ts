/**
 * TalkieHeadless HTTP Client
 *
 * Communicates with TalkieHeadless for transcription and native capabilities.
 */

import { log } from "../log";

const HEADLESS_URL = "http://localhost:7848";

export interface HeadlessHealthResponse {
  status: string;
  service: string;
  engineConnected: boolean;
}

export interface TranscribeStartResponse {
  sessionId: string;
  status: string;
}

export interface TranscribeStopResponse {
  text: string;
  duration: number;
}

export interface DiffComputeResponse {
  diff: { type: "equal" | "insert" | "delete"; text: string }[];
}

export interface PreflightCheck {
  name: string;
  ok: boolean;
  detail: string;
}

export interface PreflightResponse {
  ready: boolean;
  checks: PreflightCheck[];
}

/**
 * Check if TalkieHeadless is running and healthy
 */
export async function isHeadlessAvailable(): Promise<boolean> {
  try {
    const response = await fetch(`${HEADLESS_URL}/health`, {
      signal: AbortSignal.timeout(1000),
    });
    if (!response.ok) return false;
    const data = (await response.json()) as HeadlessHealthResponse;
    return data.status === "ok";
  } catch {
    return false;
  }
}

/**
 * Preflight check - validates entire transcription pipeline
 * Returns detailed status of each component (TalkieAgent, Microphone, TalkieEngine)
 */
export async function transcribePreflight(): Promise<PreflightResponse> {
  const response = await fetch(`${HEADLESS_URL}/transcribe/preflight`, {
    signal: AbortSignal.timeout(5000), // Allow time for reconnection attempts
  });

  if (!response.ok) {
    throw new Error(`TalkieHeadless transcribe/preflight failed: ${response.status}`);
  }

  return (await response.json()) as PreflightResponse;
}

/**
 * Start transcription capture via TalkieHeadless
 */
export async function transcribeStart(): Promise<TranscribeStartResponse> {
  const response = await fetch(`${HEADLESS_URL}/transcribe/start`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });

  if (!response.ok) {
    throw new Error(`TalkieHeadless transcribe/start failed: ${response.status}`);
  }

  return (await response.json()) as TranscribeStartResponse;
}

/**
 * Stop transcription and get result via TalkieHeadless
 */
export async function transcribeStop(): Promise<TranscribeStopResponse> {
  const response = await fetch(`${HEADLESS_URL}/transcribe/stop`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });

  if (!response.ok) {
    throw new Error(`TalkieHeadless transcribe/stop failed: ${response.status}`);
  }

  return (await response.json()) as TranscribeStopResponse;
}

/**
 * Compute diff via TalkieHeadless (native Swift implementation)
 */
export async function computeDiffViaHeadless(
  original: string,
  proposed: string
): Promise<DiffComputeResponse> {
  const response = await fetch(`${HEADLESS_URL}/diff/compute`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ original, proposed }),
  });

  if (!response.ok) {
    throw new Error(`TalkieHeadless diff/compute failed: ${response.status}`);
  }

  return (await response.json()) as DiffComputeResponse;
}

/**
 * Write to clipboard via TalkieHeadless (native NSPasteboard)
 */
export async function clipboardWrite(content: string): Promise<void> {
  const response = await fetch(`${HEADLESS_URL}/storage/clipboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content }),
  });

  if (!response.ok) {
    throw new Error(`TalkieHeadless clipboard/write failed: ${response.status}`);
  }
}

/**
 * Read clipboard via TalkieHeadless (native NSPasteboard)
 */
export async function clipboardRead(): Promise<string> {
  const response = await fetch(`${HEADLESS_URL}/storage/clipboard/read`);

  if (!response.ok) {
    throw new Error(`TalkieHeadless clipboard/read failed: ${response.status}`);
  }

  const data = (await response.json()) as { content: string };
  return data.content;
}


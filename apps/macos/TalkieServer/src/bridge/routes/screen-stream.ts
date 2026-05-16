import { log } from "../../log";
import { talkieServerFetch } from "../talkie-local-client";

const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;
const TALKIEAGENT_PORT = 8767;
const TALKIEAGENT_URL = `http://127.0.0.1:${TALKIEAGENT_PORT}`;
const DEFAULT_FPS = 2;
const DEFAULT_MAX_DIMENSION = 1400;
const DEFAULT_QUALITY = 0.6;
const MIN_FPS = 1;
const MAX_FPS = 6;

type ScreenStreamSocket = {
  send(payload: string): void;
  close(): void;
  data?: unknown;
  raw?: object;
};

type ScreenStreamConfig = {
  fps: number;
  maxDimension: number;
  quality: number;
};

type FrameFetchResult = {
  response: Response;
  source: "agent" | "talkie";
};

const streamTimers = new WeakMap<object, Timer>();
const streamInflight = new WeakSet<object>();
const streamConfigBySocket = new WeakMap<object, ScreenStreamConfig>();

export const companionScreenStreamSocket = {
  open(ws: ScreenStreamSocket) {
    const socketKey = rawSocketKey(ws);
    const config = configFromSocket(ws);
    streamConfigBySocket.set(socketKey, config);

    sendJSON(ws, {
      type: "screen:ready",
      fps: config.fps,
      maxDimension: config.maxDimension,
      quality: config.quality,
    });

    startStreaming(ws);
  },

  message(ws: ScreenStreamSocket, rawMessage: unknown) {
    const socketKey = rawSocketKey(ws);

    let message: { type?: string; fps?: number; maxDimension?: number; quality?: number } | null = null;
    try {
      if (typeof rawMessage === "string") {
        message = JSON.parse(rawMessage);
      } else if (rawMessage instanceof Buffer) {
        message = JSON.parse(rawMessage.toString());
      } else if (rawMessage && typeof rawMessage === "object") {
        message = rawMessage as { type?: string; fps?: number; maxDimension?: number; quality?: number };
      }
    } catch {
      sendJSON(ws, { type: "screen:error", error: "Invalid screen stream message" });
      return;
    }

    if (!message?.type) {
      return;
    }

    if (message.type === "screen:config") {
      const currentConfig = streamConfigBySocket.get(socketKey) ?? configFromSocket(ws);
      const nextConfig = normalizeConfig({
        fps: message.fps ?? currentConfig.fps,
        maxDimension: message.maxDimension ?? currentConfig.maxDimension,
        quality: message.quality ?? currentConfig.quality,
      });
      streamConfigBySocket.set(socketKey, nextConfig);
      restartStreaming(ws);
      sendJSON(ws, {
        type: "screen:config:applied",
        fps: nextConfig.fps,
        maxDimension: nextConfig.maxDimension,
        quality: nextConfig.quality,
      });
      return;
    }

    if (message.type === "screen:request-frame") {
      void pushFrame(ws);
    }
  },

  close(ws: ScreenStreamSocket) {
    stopStreaming(ws);
  },
};

function rawSocketKey(ws: ScreenStreamSocket): object {
  return ws.raw ?? ws;
}

function configFromSocket(ws: ScreenStreamSocket): ScreenStreamConfig {
  const query = ((ws as any).data?.query ?? {}) as Record<string, string | undefined>;
  return normalizeConfig({
    fps: query.fps ? Number.parseInt(query.fps, 10) : DEFAULT_FPS,
    maxDimension: query.maxDimension ? Number.parseInt(query.maxDimension, 10) : DEFAULT_MAX_DIMENSION,
    quality: query.quality ? Number.parseFloat(query.quality) : DEFAULT_QUALITY,
  });
}

function normalizeConfig(config: Partial<ScreenStreamConfig>): ScreenStreamConfig {
  const fps = clampInteger(config.fps, MIN_FPS, MAX_FPS, DEFAULT_FPS);
  const maxDimension = clampInteger(config.maxDimension, 320, 2048, DEFAULT_MAX_DIMENSION);
  const qualityValue = Number.isFinite(config.quality) ? Number(config.quality) : DEFAULT_QUALITY;
  const quality = Math.max(0.2, Math.min(0.95, qualityValue));
  return { fps, maxDimension, quality };
}

function clampInteger(value: number | undefined, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, Math.round(Number(value))));
}

function startStreaming(ws: ScreenStreamSocket) {
  const socketKey = rawSocketKey(ws);
  stopStreaming(ws);
  void pushFrame(ws);

  const config = streamConfigBySocket.get(socketKey) ?? configFromSocket(ws);
  const intervalMs = Math.max(150, Math.round(1000 / config.fps));
  const timer = setInterval(() => {
    void pushFrame(ws);
  }, intervalMs);
  streamTimers.set(socketKey, timer);
}

function restartStreaming(ws: ScreenStreamSocket) {
  startStreaming(ws);
}

function stopStreaming(ws: ScreenStreamSocket) {
  const socketKey = rawSocketKey(ws);
  const timer = streamTimers.get(socketKey);
  if (timer) {
    clearInterval(timer);
    streamTimers.delete(socketKey);
  }
  streamInflight.delete(socketKey);
}

async function pushFrame(ws: ScreenStreamSocket) {
  const socketKey = rawSocketKey(ws);
  if (streamInflight.has(socketKey)) {
    return;
  }
  streamInflight.add(socketKey);

  try {
    const config = streamConfigBySocket.get(socketKey) ?? configFromSocket(ws);
    const { response, source } = await fetchDisplayFrame(config);

    if (!response.ok) {
      const errorText = await responseErrorText(response);
      sendJSON(ws, {
        type: "screen:error",
        error: errorText || "Unable to fetch screen frame",
        status: response.status,
        source,
      });
      return;
    }

    const bytes = await response.bytes();
    const frameBase64 = Buffer.from(bytes).toString("base64");
    sendJSON(ws, {
      type: "screen:frame",
      mimeType: "image/jpeg",
      frameBase64,
      capturedAt: new Date().toISOString(),
    });
  } catch (error) {
    log.warn(`Companion screen stream frame failed: ${error}`);
    sendJSON(ws, {
      type: "screen:error",
      error: error instanceof Error ? error.message : String(error),
    });
  } finally {
    streamInflight.delete(socketKey);
  }
}

async function fetchDisplayFrame(config: ScreenStreamConfig): Promise<FrameFetchResult> {
  const query = `maxDimension=${config.maxDimension}&quality=${config.quality.toFixed(2)}`;
  const agentURL = `${TALKIEAGENT_URL}/v1/agent/screenshot/display?${query}`;

  try {
    const response = await fetch(agentURL, {
      signal: AbortSignal.timeout(4500),
    });

    if (response.ok) {
      return { response, source: "agent" };
    }

    const errorText = await responseErrorText(response);
    log.debug(`Companion screen stream agent route unavailable (${response.status}): ${errorText}`);
  } catch (error) {
    log.debug(`Companion screen stream agent route failed, falling back to Talkie.app: ${error}`);
  }

  const response = await talkieServerFetch(`${TALKIESERVER_URL}/screenshot/display?${query}`, {
    signal: AbortSignal.timeout(8000),
  });
  return { response, source: "talkie" };
}

async function responseErrorText(response: Response): Promise<string> {
  return await response
    .text()
    .then((text) => {
      if (!text) {
        return "Unable to fetch screen frame";
      }

      try {
        const payload = JSON.parse(text) as { error?: string };
        return payload.error || text;
      } catch {
        return text;
      }
    })
    .catch(() => "Unable to fetch screen frame");
}

function sendJSON(ws: ScreenStreamSocket, payload: Record<string, unknown>) {
  try {
    ws.send(JSON.stringify(payload));
  } catch (error) {
    log.warn(`Companion screen stream send failed: ${error}`);
    try {
      ws.close();
    } catch {}
  }
}

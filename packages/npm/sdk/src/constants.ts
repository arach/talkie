import { join } from "path";
import { homedir } from "os";

/** Default WebSocket bridge ports for each Talkie service. */
export const SERVICE_PORTS = {
  sync: 19820,
  engine: 19821,
  inference: 19822,
  agent: 19823,
} as const;

export type ServiceName = keyof typeof SERVICE_PORTS;

/** Path to the services discovery file written by TalkieAgent. */
export const SERVICES_JSON_PATH = join(homedir(), ".talkie", "services.json");

/** Default timeout for standard RPC calls (ms). */
export const DEFAULT_CALL_TIMEOUT = 30_000;

/** Default timeout for streaming RPC calls (ms). Resets on each progress event. */
export const STREAMING_CALL_TIMEOUT = 120_000;

/** Reconnect timing. */
export const RECONNECT_BASE_DELAY = 500;
export const RECONNECT_MAX_DELAY = 10_000;

/** How long to wait for the WebSocket to open (ms). */
export const CONNECT_TIMEOUT = 5_000;

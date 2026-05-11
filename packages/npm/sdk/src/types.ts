import type { ServiceName } from "./constants";

// ── Wire protocol ──────────────────────────────────────────────────

export interface RpcRequest {
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export interface RpcResponse {
  id?: string;
  result?: Record<string, unknown>;
  error?: string;
}

export interface RpcEvent {
  event: string;
  data?: Record<string, unknown>;
  id?: string;
}

/** A raw WebSocket message is one of these. */
export type WireMessage = RpcResponse | RpcEvent;

// ── Discovery ──────────────────────────────────────────────────────

export interface ServiceEntry {
  port: number;
  serviceKey?: string;
}

export interface ServicesFile {
  version: number;
  services: Partial<Record<ServiceName, ServiceEntry>>;
}

// ── Auth ────────────────────────────────────────────────────────────

export type Capability = "status" | "dictation" | "control";

export interface RegisterParams {
  serviceKey: string;
  capabilities: Capability[];
  clientId: string;
}

export interface RegisterResult {
  sessionToken: string;
  grantedCapabilities: Capability[];
}

export type AuthState =
  | { mode: "legacy" }
  | { mode: "authenticated"; sessionToken: string; grantedCapabilities: Capability[] };

// ── Client options ──────────────────────────────────────────────────

export interface TalkieClientOptions {
  /** Which service to connect to. */
  service: ServiceName;
  /** Capabilities this client wants. Sent during register. */
  capabilities?: Capability[];
  /** Identifier for this client (e.g. "hudson", "lattices", "cli"). */
  clientId?: string;
  /** Override the port (skips discovery). */
  port?: number;
  /** Whether to auto-reconnect on disconnect. Default: true. */
  autoReconnect?: boolean;
}

// ── Dictation ───────────────────────────────────────────────────────

export type DictationState = "idle" | "starting" | "recording" | "processing" | "done" | "cancelled" | "error";

export interface DictationOptions {
  /** If false, TalkieAgent skips memo creation (ephemeral dictation). Default: true. */
  persist?: boolean;
  /** Additional params forwarded to startDictation. */
  [key: string]: unknown;
}

export interface DictationEvents {
  stateChange: { state: DictationState; previous: DictationState };
  partialTranscript: { text: string };
  finalTranscript: { text: string };
  error: { error: Error };
}

// ── Transport ───────────────────────────────────────────────────────

export interface TransportEvents {
  open: undefined;
  close: { code: number; reason: string };
  error: { error: Error };
  event: { event: string; data: Record<string, unknown> };
}

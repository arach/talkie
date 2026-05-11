/**
 * TalkieClient — high-level API for connecting to a Talkie service.
 *
 * Wires together discovery, transport, and auth into a clean interface.
 * Handles auto-reconnect with exponential backoff.
 *
 * Usage:
 *   const client = new TalkieClient({ service: 'engine', clientId: 'hudson' });
 *   await client.connect();
 *   const status = await client.call('status');
 *   await client.disconnect();
 */

import { WebSocketTransport } from "./transport";
import { ServiceDiscovery } from "./discovery";
import { authenticate, type AuthOptions } from "./auth";
import { DictationSession } from "./dictation";
import { Emitter } from "./events";
import { ConnectionError } from "./errors";
import { RECONNECT_BASE_DELAY, RECONNECT_MAX_DELAY } from "./constants";
import type { TalkieClientOptions, AuthState, Capability } from "./types";

export interface ClientEvents {
  connected: undefined;
  disconnected: { code: number; reason: string };
  reconnecting: { attempt: number; delay: number };
  authStateChange: { auth: AuthState };
  serviceEvent: { event: string; data: Record<string, unknown> };
}

export class TalkieClient extends Emitter<ClientEvents> {
  private transport = new WebSocketTransport();
  private discovery = new ServiceDiscovery();
  private options: Required<TalkieClientOptions>;
  private auth: AuthState = { mode: "legacy" };
  private reconnectAttempt = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private intentionalDisconnect = false;
  private resolvedPort: number | null = null;

  constructor(options: TalkieClientOptions) {
    super();
    this.options = {
      service: options.service,
      capabilities: options.capabilities ?? ["status"],
      clientId: options.clientId ?? "talkie-sdk",
      port: options.port ?? 0,
      autoReconnect: options.autoReconnect ?? true,
    };

    // Forward push events from the transport
    this.transport.on("event", ({ event, data }) => {
      this.emit("serviceEvent", { event, data });
    });

    // Handle unexpected disconnects
    this.transport.on("close", ({ code, reason }) => {
      this.auth = { mode: "legacy" };
      this.emit("disconnected", { code, reason });

      if (!this.intentionalDisconnect && this.options.autoReconnect) {
        this.scheduleReconnect();
      }
    });
  }

  /** Whether the client is currently connected. */
  get connected(): boolean {
    return this.transport.connected;
  }

  /** Current auth state. */
  get authState(): AuthState {
    return this.auth;
  }

  /**
   * Connect to the service. Discovers the port, opens the WebSocket,
   * and runs the auth handshake.
   */
  async connect(): Promise<void> {
    this.intentionalDisconnect = false;
    this.reconnectAttempt = 0;
    await this.doConnect();
  }

  /** Cleanly disconnect. Stops auto-reconnect. */
  async disconnect(): Promise<void> {
    this.intentionalDisconnect = true;
    this.clearReconnect();
    this.discovery.stopWatching();
    this.transport.disconnect();
    this.auth = { mode: "legacy" };
  }

  /** Ping the service. Shorthand for `call('ping')`. */
  async ping(): Promise<Record<string, unknown>> {
    return this.call("ping");
  }

  /**
   * Call an RPC method on the service.
   * If authenticated, the session token is injected into params automatically.
   */
  async call(
    method: string,
    params?: Record<string, unknown>,
    timeoutMs?: number,
  ): Promise<Record<string, unknown>> {
    return this.transport.call(method, this.injectAuth(params), timeoutMs);
  }

  /**
   * Call a streaming RPC method. Progress events fire the callback;
   * the promise resolves with the final result.
   */
  async callStreaming(
    method: string,
    params: Record<string, unknown> | undefined,
    onProgress: (event: string, data: Record<string, unknown>) => void,
    timeoutMs?: number,
  ): Promise<Record<string, unknown>> {
    return this.transport.callStreaming(method, this.injectAuth(params), onProgress, timeoutMs);
  }

  /**
   * Listen for push events from the service (events with no request id).
   * Returns an unsubscribe function.
   */
  onServiceEvent(
    listener: (event: string, data: Record<string, unknown>) => void,
  ): () => void {
    return this.on("serviceEvent", ({ event, data }) => listener(event, data));
  }

  /** Create a DictationSession bound to this client. */
  createDictationSession(): DictationSession {
    return new DictationSession(this);
  }

  // ── Internals ─────────────────────────────────────────────────────

  /** Full connect sequence: discover → WebSocket → auth. */
  private async doConnect(): Promise<void> {
    // Resolve port
    if (this.options.port) {
      this.resolvedPort = this.options.port;
    } else {
      const entry = this.discovery.resolve(this.options.service);
      this.resolvedPort = entry.port;
    }

    // Open WebSocket
    await this.transport.connect(this.resolvedPort);

    // Auth handshake — discover serviceKey
    const entry = this.options.port
      ? { port: this.options.port }
      : this.discovery.resolve(this.options.service);

    const authOptions: AuthOptions = {
      serviceKey: entry.serviceKey,
      capabilities: this.options.capabilities,
      clientId: this.options.clientId,
    };

    this.auth = await authenticate(this.transport, authOptions);
    this.emit("authStateChange", { auth: this.auth });

    // Start watching for discovery changes
    this.discovery.startWatching();
    this.discovery.on("change", () => {
      // If port changed, reconnect
      const fresh = this.discovery.resolve(this.options.service);
      if (fresh.port !== this.resolvedPort) {
        this.transport.disconnect(); // Will trigger reconnect
      }
    });

    this.reconnectAttempt = 0;
    this.emit("connected", undefined);
  }

  /** Inject _sessionToken into params if authenticated. */
  private injectAuth(
    params?: Record<string, unknown>,
  ): Record<string, unknown> | undefined {
    if (this.auth.mode !== "authenticated") return params;
    return { ...params, _sessionToken: this.auth.sessionToken };
  }

  private scheduleReconnect(): void {
    this.reconnectAttempt++;
    const delay = Math.min(
      RECONNECT_BASE_DELAY * 2 ** (this.reconnectAttempt - 1),
      RECONNECT_MAX_DELAY,
    );

    this.emit("reconnecting", { attempt: this.reconnectAttempt, delay });

    this.reconnectTimer = setTimeout(async () => {
      try {
        await this.doConnect();
      } catch {
        // doConnect failed — schedule another attempt
        if (!this.intentionalDisconnect && this.options.autoReconnect) {
          this.scheduleReconnect();
        }
      }
    }, delay);
  }

  private clearReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }
}

/**
 * Persistent, multiplexed WebSocket transport.
 *
 * Single connection to a Talkie service. Multiple concurrent calls are
 * routed by `id`. Push events (no `id`, has `event`) are forwarded to
 * subscribers.
 */

import { Emitter } from "./events";
import { ConnectionError, TimeoutError, CallError } from "./errors";
import { DEFAULT_CALL_TIMEOUT, STREAMING_CALL_TIMEOUT, CONNECT_TIMEOUT } from "./constants";
import type { RpcRequest, TransportEvents } from "./types";

interface PendingCall {
  resolve: (result: Record<string, unknown>) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  onProgress?: (event: string, data: Record<string, unknown>) => void;
}

export class WebSocketTransport extends Emitter<TransportEvents> {
  private ws: WebSocket | null = null;
  private pending = new Map<string, PendingCall>();
  private _connected = false;

  get connected(): boolean {
    return this._connected;
  }

  /**
   * Open a WebSocket to the given port. Resolves when the socket is open.
   * Rejects if connection fails or times out.
   */
  connect(port: number): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.ws) {
        this.doClose();
      }

      const url = `ws://127.0.0.1:${port}`;
      const ws = new WebSocket(url);

      const timeout = setTimeout(() => {
        ws.close();
        reject(new ConnectionError(`Connection to ${url} timed out`, port));
      }, CONNECT_TIMEOUT);

      ws.onopen = () => {
        clearTimeout(timeout);
        this._connected = true;
        this.ws = ws;
        this.emit("open", undefined);
        resolve();
      };

      ws.onmessage = (ev) => {
        this.handleMessage(String(ev.data));
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        if (!this._connected) {
          reject(new ConnectionError(`WebSocket error — is the service running? (${url})`, port));
        } else {
          this.emit("error", { error: new ConnectionError("WebSocket error", port) });
        }
      };

      ws.onclose = (ev) => {
        clearTimeout(timeout);
        const wasConnected = this._connected;
        this._connected = false;
        this.ws = null;
        this.rejectAllPending("Connection closed");
        if (wasConnected) {
          this.emit("close", { code: ev.code, reason: ev.reason });
        }
      };
    });
  }

  /** Close the WebSocket cleanly. */
  disconnect(): void {
    this.doClose();
  }

  /**
   * Send an RPC call. Returns when the service responds with a result or error.
   */
  call(
    method: string,
    params?: Record<string, unknown>,
    timeoutMs = DEFAULT_CALL_TIMEOUT,
  ): Promise<Record<string, unknown>> {
    return new Promise((resolve, reject) => {
      if (!this.ws || !this._connected) {
        reject(new ConnectionError("Not connected"));
        return;
      }

      const id = crypto.randomUUID();
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new TimeoutError(method, timeoutMs));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      const request: RpcRequest = { id, method };
      if (params) request.params = params;
      this.ws.send(JSON.stringify(request));
    });
  }

  /**
   * Send a streaming RPC call. Progress events trigger the callback;
   * the promise resolves with the final result. Timeout resets on each
   * progress event.
   */
  callStreaming(
    method: string,
    params: Record<string, unknown> | undefined,
    onProgress: (event: string, data: Record<string, unknown>) => void,
    timeoutMs = STREAMING_CALL_TIMEOUT,
  ): Promise<Record<string, unknown>> {
    return new Promise((resolve, reject) => {
      if (!this.ws || !this._connected) {
        reject(new ConnectionError("Not connected"));
        return;
      }

      const id = crypto.randomUUID();

      const makeTimer = () =>
        setTimeout(() => {
          this.pending.delete(id);
          reject(new TimeoutError(method, timeoutMs));
        }, timeoutMs);

      let timer = makeTimer();

      this.pending.set(id, {
        resolve,
        reject,
        timer,
        onProgress: (event, data) => {
          // Reset timeout on progress — the service is alive, just working
          clearTimeout(timer);
          timer = makeTimer();
          // Update stored timer reference
          const entry = this.pending.get(id);
          if (entry) entry.timer = timer;
          onProgress(event, data);
        },
      });

      const request: RpcRequest = { id, method };
      if (params) request.params = params;
      this.ws.send(JSON.stringify(request));
    });
  }

  // ── Internals ─────────────────────────────────────────────────────

  private handleMessage(raw: string): void {
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(raw);
    } catch {
      return; // Malformed — ignore
    }

    const id = data.id as string | undefined;
    const event = data.event as string | undefined;

    // Push event with no matching pending call → broadcast
    if (event && !id) {
      this.emit("event", {
        event,
        data: (data.data as Record<string, unknown>) ?? {},
      });
      return;
    }

    // Progress event with an id → route to pending call's onProgress
    if (event && id) {
      const entry = this.pending.get(id);
      if (entry?.onProgress) {
        entry.onProgress(event, (data.data as Record<string, unknown>) ?? {});
      }
      return;
    }

    // Final response — resolve or reject
    if (id) {
      const entry = this.pending.get(id);
      if (!entry) return;
      this.pending.delete(id);
      clearTimeout(entry.timer);

      if (data.error) {
        entry.reject(new CallError(String(data.error), ""));
        return;
      }
      entry.resolve((data.result as Record<string, unknown>) ?? {});
    }
  }

  private rejectAllPending(reason: string): void {
    for (const [id, entry] of this.pending) {
      clearTimeout(entry.timer);
      entry.reject(new ConnectionError(reason));
    }
    this.pending.clear();
  }

  private doClose(): void {
    this._connected = false;
    if (this.ws) {
      this.ws.onopen = null;
      this.ws.onmessage = null;
      this.ws.onerror = null;
      this.ws.onclose = null;
      this.ws.close();
      this.ws = null;
    }
    this.rejectAllPending("Disconnected");
  }
}

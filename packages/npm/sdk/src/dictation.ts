/**
 * DictationSession — typed event stream for voice dictation.
 *
 * Wraps a streaming RPC call to the dictation service with strongly-typed
 * events for state changes, partial/final transcripts, and errors.
 *
 * Usage:
 *   const session = client.createDictationSession();
 *   session.on('stateChange', ({ state }) => console.log(state));
 *   session.on('partialTranscript', ({ text }) => process.stdout.write(text));
 *   const transcript = await session.start({ persist: false });
 */

import { Emitter } from "./events";
import { MicBusyError } from "./errors";
import type { TalkieClient } from "./client";
import type { DictationState, DictationOptions, DictationEvents } from "./types";

export class DictationSession extends Emitter<DictationEvents> {
  private client: TalkieClient;
  private _state: DictationState = "idle";

  constructor(client: TalkieClient) {
    super();
    this.client = client;
  }

  /** Current dictation state. */
  get state(): DictationState {
    return this._state;
  }

  /**
   * Start a dictation session. Returns the final transcript when done.
   *
   * @param options.persist — If false, TalkieAgent skips memo creation
   *   (ephemeral dictation for live typing). Default: true.
   *
   * Emits events throughout the session:
   * - `stateChange` — when the session moves between states
   * - `partialTranscript` — interim recognition results
   * - `finalTranscript` — the completed transcript
   * - `error` — if something goes wrong (including MicBusyError)
   *
   * @throws MicBusyError if another client holds the mic
   */
  async start(options?: DictationOptions): Promise<string> {
    this.setState("starting");

    // Build params — persist defaults to true
    const { persist = true, ...rest } = options ?? {};
    const params: Record<string, unknown> = { ...rest, persist };

    try {
      const result = await this.client.callStreaming(
        "startDictation",
        params,
        (event, data) => this.handleProgress(event, data),
      );

      const transcript = (result.transcript as string) ?? "";
      this.setState("done");
      this.emit("finalTranscript", { text: transcript });
      return transcript;
    } catch (err) {
      const error = this.parseError(err);
      this.setState("error");
      this.emit("error", { error });
      throw error;
    }
  }

  /** Request the service to finish and finalize the current dictation. */
  async stop(): Promise<void> {
    await this.client.call("stopDictation");
  }

  /** Cancel the current dictation without finalizing. */
  async cancel(): Promise<void> {
    await this.client.call("cancelDictation");
    this.setState("cancelled");
  }

  // ── Internals ─────────────────────────────────────────────────────

  private handleProgress(event: string, data: Record<string, unknown>): void {
    switch (event) {
      case "stateChange": {
        const state = data.state as DictationState | undefined;
        if (state) this.setState(state);
        break;
      }
      case "partialTranscript": {
        const text = (data.text as string) ?? "";
        this.emit("partialTranscript", { text });
        break;
      }
      case "finalTranscript": {
        const text = (data.text as string) ?? "";
        this.emit("finalTranscript", { text });
        break;
      }
    }
  }

  /** Convert a raw error into a typed SDK error when possible. */
  private parseError(err: unknown): Error {
    if (err instanceof Error) {
      // "mic_busy:owner_id" or error message containing mic_busy
      const msg = err.message;
      const busyMatch = msg.match(/mic_busy(?::(\S+))?/);
      if (busyMatch) {
        return new MicBusyError(busyMatch[1] ?? "unknown");
      }
      return err;
    }
    return new Error(String(err));
  }

  private setState(newState: DictationState): void {
    const previous = this._state;
    if (newState === previous) return;
    this._state = newState;
    this.emit("stateChange", { state: newState, previous });
  }
}

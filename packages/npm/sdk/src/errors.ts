/** Base error for all Talkie SDK errors. */
export class TalkieError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TalkieError";
  }
}

/** WebSocket connection failed or was lost. */
export class ConnectionError extends TalkieError {
  constructor(
    message: string,
    public readonly port?: number,
  ) {
    super(message);
    this.name = "ConnectionError";
  }
}

/** An RPC call returned an error from the service. */
export class CallError extends TalkieError {
  constructor(
    message: string,
    public readonly method: string,
  ) {
    super(message);
    this.name = "CallError";
  }
}

/** An RPC call exceeded its timeout. */
export class TimeoutError extends TalkieError {
  constructor(
    public readonly method: string,
    public readonly timeoutMs: number,
  ) {
    super(`Call '${method}' timed out after ${timeoutMs}ms`);
    this.name = "TimeoutError";
  }
}

/** Auth registration failed (non-legacy). */
export class AuthError extends TalkieError {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

/** Another client already holds the mic. */
export class MicBusyError extends TalkieError {
  constructor(
    /** The clientId that currently owns the mic. */
    public readonly owner: string,
  ) {
    super(`Mic is busy — held by '${owner}'`);
    this.name = "MicBusyError";
  }
}

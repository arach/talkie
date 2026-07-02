export interface TalkieClientErrorOptions {
  cause?: unknown;
  code?: string;
  details?: unknown;
  status?: number;
}

export class TalkieClientError extends Error {
  readonly code?: string;
  readonly details?: unknown;
  readonly status?: number;

  constructor(message: string, options: TalkieClientErrorOptions = {}) {
    super(message, { cause: options.cause });
    this.name = "TalkieClientError";
    this.code = options.code;
    this.details = options.details;
    this.status = options.status;
  }
}

export class TalkieCapabilityUnavailableError extends TalkieClientError {
  constructor(capability: string, options: TalkieClientErrorOptions = {}) {
    super(
      `Talkie capability is unavailable: ${capability}`,
      { ...options, code: options.code ?? "capability_unavailable" },
    );
    this.name = "TalkieCapabilityUnavailableError";
  }
}

export class TalkieHTTPError extends TalkieClientError {
  constructor(message: string, options: TalkieClientErrorOptions = {}) {
    super(message, { ...options, code: options.code ?? "http_error" });
    this.name = "TalkieHTTPError";
  }
}

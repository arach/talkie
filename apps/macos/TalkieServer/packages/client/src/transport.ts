import { TalkieHTTPError } from "./errors";

export type TalkieHTTPMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface TalkieTransportRequest {
  method: TalkieHTTPMethod;
  path: string;
  query?: Record<string, boolean | number | string | undefined>;
  body?: unknown;
  signal?: AbortSignal;
}

export interface TalkieTransport {
  request<T>(request: TalkieTransportRequest): Promise<T>;
}

export interface TalkieFetchTransportOptions {
  baseURL?: string;
  fetch?: typeof fetch;
  headers?: Record<string, string>;
  timeoutMs?: number;
}

const defaultBridgeURL = "http://127.0.0.1:8765";

export function createFetchTransport(options: TalkieFetchTransportOptions = {}): TalkieTransport {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  const baseURL = options.baseURL ?? process.env.TALKIE_BRIDGE_URL ?? defaultBridgeURL;
  const timeoutMs = options.timeoutMs ?? 30_000;

  if (!fetchImpl) {
    throw new TalkieHTTPError("No fetch implementation is available for Talkie client transport.");
  }

  return {
    async request<T>(request: TalkieTransportRequest): Promise<T> {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), timeoutMs);

      const signal = request.signal
        ? linkedAbortSignal(request.signal, controller)
        : controller.signal;

      try {
        const response = await fetchImpl(buildURL(baseURL, request), {
          method: request.method,
          headers: {
            Accept: "application/json",
            ...(request.body === undefined ? {} : { "Content-Type": "application/json" }),
            ...options.headers,
          },
          body: request.body === undefined ? undefined : JSON.stringify(request.body),
          signal,
        });

        const payload = await readResponsePayload(response);

        if (!response.ok) {
          throw new TalkieHTTPError(
            responseErrorMessage(response.status, payload),
            {
              status: response.status,
              details: payload,
            },
          );
        }

        return payload as T;
      } catch (error) {
        if (error instanceof TalkieHTTPError) {
          throw error;
        }

        throw new TalkieHTTPError(
          error instanceof Error ? error.message : "Talkie transport request failed.",
          { cause: error },
        );
      } finally {
        clearTimeout(timeout);
      }
    },
  };
}

function buildURL(baseURL: string, request: TalkieTransportRequest): string {
  const url = new URL(request.path, baseURL.endsWith("/") ? baseURL : `${baseURL}/`);

  for (const [key, value] of Object.entries(request.query ?? {})) {
    if (value !== undefined) {
      url.searchParams.set(key, String(value));
    }
  }

  return url.toString();
}

async function readResponsePayload(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    return response.json();
  }

  const text = await response.text();
  return text.length > 0 ? text : undefined;
}

function responseErrorMessage(status: number, payload: unknown): string {
  if (isErrorPayload(payload)) {
    return payload.error;
  }

  if (typeof payload === "string" && payload.length > 0) {
    return payload;
  }

  return `Talkie request failed with HTTP ${status}.`;
}

function isErrorPayload(payload: unknown): payload is { error: string } {
  return typeof payload === "object"
    && payload !== null
    && "error" in payload
    && typeof (payload as { error?: unknown }).error === "string";
}

function linkedAbortSignal(source: AbortSignal, controller: AbortController): AbortSignal {
  if (source.aborted) {
    controller.abort(source.reason);
    return controller.signal;
  }

  source.addEventListener("abort", () => controller.abort(source.reason), { once: true });
  return controller.signal;
}

import { TalkieCapabilityUnavailableError, TalkieHTTPError } from "./errors";
import type {
  CaptureGetOptions,
  CaptureGetResponse,
  CapturePrepareVisualContextRequest,
  CapturePrepareVisualContextResponse,
  CaptureSearchQuery,
  CaptureSearchResponse,
} from "./protocol";
import { createFetchTransport, type TalkieTransport } from "./transport";

export interface TalkieClientOptions {
  transport?: TalkieTransport;
  baseURL?: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}

export interface TalkieClient {
  readonly captures: TalkieCapturesClient;
}

export interface TalkieCapturesClient {
  search(query: CaptureSearchQuery): Promise<CaptureSearchResponse>;
  get(captureId: string, options?: CaptureGetOptions): Promise<CaptureGetResponse>;
  prepareVisualContext(
    captureId: string,
    request?: CapturePrepareVisualContextRequest,
  ): Promise<CapturePrepareVisualContextResponse>;
}

export function createTalkieClient(options: TalkieClientOptions = {}): TalkieClient {
  const transport = options.transport ?? createFetchTransport({
    baseURL: options.baseURL,
    fetch: options.fetch,
    timeoutMs: options.timeoutMs,
  });

  return {
    captures: createCapturesClient(transport),
  };
}

function createCapturesClient(transport: TalkieTransport): TalkieCapturesClient {
  return {
    async search(query: CaptureSearchQuery): Promise<CaptureSearchResponse> {
      return captureRequest(() => transport.request<CaptureSearchResponse>({
        method: "POST",
        path: "/captures/search",
        body: query,
      }));
    },

    async get(captureId: string, options: CaptureGetOptions = {}): Promise<CaptureGetResponse> {
      return captureRequest(() => transport.request<CaptureGetResponse>({
        method: "GET",
        path: `/captures/${encodeURIComponent(captureId)}`,
        query: options.include?.length ? { include: options.include.join(",") } : undefined,
      }));
    },

    async prepareVisualContext(
      captureId: string,
      request: CapturePrepareVisualContextRequest = {},
    ): Promise<CapturePrepareVisualContextResponse> {
      return captureRequest(() => transport.request<CapturePrepareVisualContextResponse>({
        method: "POST",
        path: `/captures/${encodeURIComponent(captureId)}/prepare-visual-context`,
        body: request,
      }));
    },
  };
}

async function captureRequest<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof TalkieHTTPError && error.status === 404) {
      throw new TalkieCapabilityUnavailableError("captures", { cause: error, status: 404 });
    }

    throw error;
  }
}

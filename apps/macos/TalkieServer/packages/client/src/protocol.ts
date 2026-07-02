export const captureKinds = ["screenshot", "video", "clip"] as const;
export type CaptureKind = (typeof captureKinds)[number];

export const captureIncludeValues = [
  "metadata",
  "resources",
  "transcript",
  "visualContext",
  "contactSheet",
  "frames",
  "ocr",
  "captions",
] as const;
export type CaptureInclude = (typeof captureIncludeValues)[number];

export const captureMatchedSignalValues = [
  "metadata",
  "transcript",
  "notes",
  "ocr",
  "caption",
  "visualContext",
  "filename",
  "appContext",
] as const;
export type CaptureMatchedSignal = (typeof captureMatchedSignalValues)[number];

export const captureResourceRoles = [
  "source",
  "manifest",
  "summary",
  "contactSheet",
  "thumbnail",
  "frame",
  "framesDirectory",
  "markup",
] as const;
export type CaptureResourceRole = (typeof captureResourceRoles)[number];

export interface TalkieResourceRef {
  uri: string;
  name?: string;
  description?: string;
  mimeType?: string;
  role?: CaptureResourceRole | string;
  lastModified?: string;
}

export interface CaptureSearchQuery {
  query?: string;
  kinds?: CaptureKind[];
  since?: string;
  until?: string;
  apps?: string[];
  bundleIds?: string[];
  scope?: string;
  limit?: number;
  include?: CaptureInclude[];
}

export interface CaptureSearchResult {
  captureId: string;
  kind: CaptureKind;
  createdAt: string;
  title?: string;
  appName?: string;
  bundleId?: string;
  windowTitle?: string;
  durationMs?: number;
  score?: number;
  reason?: string;
  matchedSignals?: CaptureMatchedSignal[];
  resources?: Partial<Record<CaptureResourceRole, TalkieResourceRef | TalkieResourceRef[]>>;
}

export interface CaptureSearchResponse {
  results: CaptureSearchResult[];
  meta: {
    count: number;
    generatedAt: string;
    query: CaptureSearchQuery;
  };
}

export interface CaptureGetOptions {
  include?: CaptureInclude[];
}

export interface CaptureGetResponse {
  capture: CaptureSearchResult & {
    metadata?: Record<string, unknown>;
    transcriptText?: string;
    notes?: string;
  };
}

export interface CapturePrepareVisualContextRequest {
  force?: boolean;
  include?: Extract<CaptureInclude, "contactSheet" | "frames" | "ocr" | "captions">[];
}

export interface CapturePrepareVisualContextResponse {
  captureId: string;
  status: "ready" | "processing" | "failed";
  resources?: Partial<Record<CaptureResourceRole, TalkieResourceRef | TalkieResourceRef[]>>;
  errorMessage?: string;
}

export const captureSearchQuerySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    query: { type: "string" },
    kinds: {
      type: "array",
      items: { type: "string", enum: [...captureKinds] },
    },
    since: { type: "string" },
    until: { type: "string" },
    apps: {
      type: "array",
      items: { type: "string" },
    },
    bundleIds: {
      type: "array",
      items: { type: "string" },
    },
    scope: { type: "string" },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 100,
    },
    include: {
      type: "array",
      items: { type: "string", enum: [...captureIncludeValues] },
    },
  },
} as const;

export const talkieResourceRefSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    uri: { type: "string" },
    name: { type: "string" },
    description: { type: "string" },
    mimeType: { type: "string" },
    role: { type: "string" },
    lastModified: { type: "string" },
  },
  required: ["uri"],
} as const;

export const captureSearchResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    results: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          captureId: { type: "string" },
          kind: { type: "string", enum: [...captureKinds] },
          createdAt: { type: "string" },
          title: { type: "string" },
          appName: { type: "string" },
          bundleId: { type: "string" },
          windowTitle: { type: "string" },
          durationMs: { type: "integer" },
          score: { type: "number" },
          reason: { type: "string" },
          matchedSignals: {
            type: "array",
            items: { type: "string", enum: [...captureMatchedSignalValues] },
          },
          resources: { type: "object" },
        },
        required: ["captureId", "kind", "createdAt"],
      },
    },
    meta: {
      type: "object",
      additionalProperties: false,
      properties: {
        count: { type: "integer" },
        generatedAt: { type: "string" },
        query: captureSearchQuerySchema,
      },
      required: ["count", "generatedAt", "query"],
    },
  },
  required: ["results", "meta"],
} as const;

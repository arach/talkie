/**
 * Extensions Module - Types
 *
 * Protocol v2 message types for the Extension API.
 *
 * Message namespaces:
 *   ext:*        - Connection lifecycle
 *   transcribe:* - Voice transcription
 *   llm:*        - Language model operations
 *   diff:*       - Text diff computation
 *   storage:*    - Clipboard and memo storage
 *   draft:*      - Legacy v1 compatibility
 */

// ===== Protocol Constants =====

export const PROTOCOL_VERSION = "2.0";

export const CAPABILITIES = [
  "transcribe",
  "llm",
  "diff",
  "storage",
] as const;

export type Capability = (typeof CAPABILITIES)[number];

// ===== Connection Types =====

export interface ExtensionConnection {
  id: string;
  name: string;
  authenticated: boolean;
  capabilities: Capability[];
  grantedCapabilities: Capability[];
  connectedAt: Date;
}

// ===== Inbound Messages (Extension → Server) =====

export interface ExtConnectMessage {
  type: "ext:connect";
  name: string;
  capabilities: string[];
  token: string;
  version?: string;
}

export interface TranscribeStartMessage {
  type: "transcribe:start";
}

export interface TranscribeStopMessage {
  type: "transcribe:stop";
}

export interface LLMCompleteMessage {
  type: "llm:complete";
  messages: Array<{ role: string; content: string }>;
  provider?: string;
  model?: string;
  stream?: boolean;
}

export interface LLMReviseMessage {
  type: "llm:revise";
  content: string;
  instruction: string;
  constraints?: {
    maxLength?: number;
    maxTokens?: number;
    style?: string;
    format?: string;
  };
  provider?: string;
  model?: string;
}

export interface DiffComputeMessage {
  type: "diff:compute";
  before: string;
  after: string;
}

export interface StorageClipboardWriteMessage {
  type: "storage:clipboard:write";
  content: string;
}

export interface StorageClipboardReadMessage {
  type: "storage:clipboard:read";
}

export interface StorageMemoSaveMessage {
  type: "storage:memo:save";
  content: string;
  title?: string;
}

// Legacy v1 messages
export interface DraftUpdateMessage {
  type: "draft:update";
  content: string;
}

export interface DraftRefineMessage {
  type: "draft:refine";
  instruction: string;
  constraints?: {
    maxLength?: number;
    style?: string;
    format?: string;
  };
}

export interface DraftAcceptMessage {
  type: "draft:accept";
}

export interface DraftRejectMessage {
  type: "draft:reject";
}

export interface DraftSaveMessage {
  type: "draft:save";
  destination: "memo" | "clipboard";
}

export interface DraftCaptureMessage {
  type: "draft:capture";
  action: "start" | "stop";
}

export type InboundMessage =
  | ExtConnectMessage
  | TranscribeStartMessage
  | TranscribeStopMessage
  | LLMCompleteMessage
  | LLMReviseMessage
  | DiffComputeMessage
  | StorageClipboardWriteMessage
  | StorageClipboardReadMessage
  | StorageMemoSaveMessage
  | DraftUpdateMessage
  | DraftRefineMessage
  | DraftAcceptMessage
  | DraftRejectMessage
  | DraftSaveMessage
  | DraftCaptureMessage;

// ===== Outbound Messages (Server → Extension) =====

export interface AuthRequiredMessage {
  type: "auth:required";
  version: string;
  capabilities: string[];
}

export interface ExtConnectedMessage {
  type: "ext:connected";
  granted: string[];
}

export interface TranscribeStartedMessage {
  type: "transcribe:started";
}

export interface TranscribeResultMessage {
  type: "transcribe:result";
  text: string;
}

export interface LLMResultMessage {
  type: "llm:result";
  content: string;
  provider: string;
  model: string;
}

export interface LLMRevisionMessage {
  type: "llm:revision";
  before: string;
  after: string;
  diff: DiffOperation[];
  instruction: string;
  provider: string;
  model: string;
}

export interface LLMChunkMessage {
  type: "llm:chunk";
  content: string;
  done: boolean;
}

export interface DiffResultMessage {
  type: "diff:result";
  operations: DiffOperation[];
}

export interface StorageClipboardContentMessage {
  type: "storage:clipboard:content";
  content: string;
}

export interface StorageMemoSavedMessage {
  type: "storage:memo:saved";
  id: string;
}

// Legacy v1 outbound messages
export interface DraftStateMessage {
  type: "draft:state";
  content: string;
  mode: "editing" | "reviewing";
  wordCount: number;
  charCount: number;
}

export interface DraftRevisionMessage {
  type: "draft:revision";
  before: string;
  after: string;
  diff: DiffOperation[];
  instruction: string;
  provider: string;
  model: string;
}

export interface DraftResolvedMessage {
  type: "draft:resolved";
  accepted: boolean;
  content: string;
}

export interface DraftTranscriptionMessage {
  type: "draft:transcription";
  text: string;
  append: boolean;
}

export interface ErrorMessage {
  type: "error";
  error: string;
  code?: string;
}

export interface DraftErrorMessage {
  type: "draft:error";
  error: string;
  code?: string;
}

export type OutboundMessage =
  | AuthRequiredMessage
  | ExtConnectedMessage
  | TranscribeStartedMessage
  | TranscribeResultMessage
  | LLMResultMessage
  | LLMRevisionMessage
  | LLMChunkMessage
  | DiffResultMessage
  | StorageClipboardContentMessage
  | StorageMemoSavedMessage
  | DraftStateMessage
  | DraftRevisionMessage
  | DraftResolvedMessage
  | DraftTranscriptionMessage
  | ErrorMessage
  | DraftErrorMessage;

// ===== Diff Types =====

export interface DiffOperation {
  type: "equal" | "insert" | "delete";
  text: string;
}

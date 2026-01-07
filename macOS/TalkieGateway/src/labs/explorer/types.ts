export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "thinking"; text?: string }
  | { type: "tool_use"; id?: string; name?: string; input?: unknown }
  | { type: "tool_result"; tool_use_id?: string; content?: unknown }
  | { type: "image"; source?: unknown }
  | { type: "unknown"; raw: unknown };

export interface NormalizedMessage {
  role: "user" | "assistant";
  content: ContentBlock[];
  text?: string;
}

export interface NormalizedEvent {
  id: string;
  type: string;
  timestamp?: string;
  sessionId?: string;
  agentId?: string;
  slug?: string;
  isSidechain?: boolean;
  cwd?: string;
  gitBranch?: string;
  version?: string;
  message?: NormalizedMessage;
  summary?: string;
  toolUseResult?: unknown;
  source: {
    file: string;
    line: number;
  };
}

export interface SessionFileInfo {
  name: string;
  path: string;
  sizeBytes: number;
  modifiedAt: string;
  isAgent: boolean;
  isPrimary: boolean;
  sessionId?: string;
}

export interface SessionContext {
  sessionId: string;
  folderName: string;
  projectDir: string;
  files: SessionFileInfo[];
  toolResultsDir?: string;
}

export interface TimelineOptions {
  limit?: number;
  before?: string;
  includeSidechains?: boolean;
  types?: string[];
}

export interface ToolSliceItem {
  id: string;
  name?: string;
  input?: unknown;
  outputPreview?: string;
  output?: string;
  outputRef?: string;
  timestamp?: string;
  eventId: string;
}

export interface MessageSliceItem {
  id: string;
  role: "user" | "assistant";
  text: string;
  timestamp?: string;
  blocks?: ContentBlock[];
}

export interface SummarySliceItem {
  id: string;
  summary: string;
  timestamp?: string;
  type: string;
}

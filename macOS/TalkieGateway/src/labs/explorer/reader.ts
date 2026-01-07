import {
  type ContentBlock,
  type NormalizedEvent,
  type NormalizedMessage,
  type TimelineOptions,
} from "./types";
import { getSessionContext } from "./session-files";
import { sessionCache } from "../../discovery/session-cache";

function normalizeContentBlocks(content: unknown): ContentBlock[] {
  if (typeof content === "string") {
    return [{ type: "text", text: content }];
  }

  if (Array.isArray(content)) {
    return content.map((block) => {
      if (typeof block === "string") {
        return { type: "text", text: block } as ContentBlock;
      }
      if (block && typeof block === "object") {
        const kind = (block as any).type;
        if (kind === "text") {
          return { type: "text", text: (block as any).text ?? "" };
        }
        if (kind === "thinking") {
          return {
            type: "thinking",
            text: (block as any).thinking ?? (block as any).text,
          };
        }
        if (kind === "tool_use") {
          return {
            type: "tool_use",
            id: (block as any).id,
            name: (block as any).name,
            input: (block as any).input,
          };
        }
        if (kind === "tool_result") {
          return {
            type: "tool_result",
            tool_use_id: (block as any).tool_use_id ?? (block as any).toolUseId,
            content: (block as any).content,
          };
        }
        if (kind === "image") {
          return { type: "image", source: (block as any).source ?? block };
        }
      }
      return { type: "unknown", raw: block } as ContentBlock;
    });
  }

  if (content && typeof content === "object") {
    const obj = content as any;
    if (obj.content) {
      return normalizeContentBlocks(obj.content);
    }
    if (obj.text) {
      return [{ type: "text", text: String(obj.text) }];
    }
  }

  return [];
}

function extractTextFromBlocks(blocks: ContentBlock[]): string {
  return blocks
    .filter((block) => block.type === "text")
    .map((block) => (block as any).text ?? "")
    .filter((text) => text.length > 0)
    .join("\n");
}

function normalizeMessage(entry: any): NormalizedMessage | undefined {
  const role =
    entry?.message?.role ||
    (entry?.type === "user" || entry?.type === "assistant"
      ? entry.type
      : undefined);

  if (role !== "user" && role !== "assistant") return undefined;

  const rawContent = entry?.message?.content ?? entry?.content;
  const blocks = normalizeContentBlocks(rawContent);
  const text = extractTextFromBlocks(blocks);

  return {
    role,
    content: blocks,
    text: text.length > 0 ? text : undefined,
  };
}

function normalizeEvent(entry: any, file: string, line: number): NormalizedEvent {
  const message = normalizeMessage(entry);
  const type = entry?.type ?? message?.role ?? "unknown";

  return {
    id: entry?.uuid ?? entry?.messageId ?? `${file}:${line}`,
    type,
    timestamp: entry?.timestamp,
    sessionId: entry?.sessionId,
    agentId: entry?.agentId,
    slug: entry?.slug,
    isSidechain: entry?.isSidechain,
    cwd: entry?.cwd,
    gitBranch: entry?.gitBranch,
    version: entry?.version,
    message,
    summary: entry?.summary,
    toolUseResult: entry?.toolUseResult,
    source: {
      file,
      line,
    },
  };
}

function toTimestamp(value?: string): number | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.getTime();
}

export async function readSessionEvents(
  sessionId: string,
  options: TimelineOptions = {}
): Promise<{ session: any; events: NormalizedEvent[]; files: string[] } | null> {
  const context = await getSessionContext(sessionId);
  if (!context) return null;

  const session = await sessionCache.getSession(sessionId);
  if (!session) return null;

  const includeSidechains = options.includeSidechains !== false;
  const types = options.types?.map((t) => t.trim()).filter(Boolean);
  const beforeTs = options.before ? toTimestamp(options.before) : null;

  const relevantFiles = includeSidechains
    ? context.files
    : context.files.filter((file) => !file.isAgent);

  const events: NormalizedEvent[] = [];

  for (let fileIndex = 0; fileIndex < relevantFiles.length; fileIndex++) {
    const fileInfo = relevantFiles[fileIndex];
    const file = Bun.file(fileInfo.path);
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    for (let i = 0; i < lines.length; i++) {
      try {
        const entry = JSON.parse(lines[i]);
        const event = normalizeEvent(entry, fileInfo.name, i);

        if (types && types.length > 0 && !types.includes(event.type)) {
          continue;
        }

        if (beforeTs) {
          const eventTs = toTimestamp(event.timestamp);
          if (eventTs && eventTs >= beforeTs) {
            continue;
          }
        }

        events.push(event);
      } catch {
        continue;
      }
    }
  }

  events.sort((a, b) => {
    const aTs = toTimestamp(a.timestamp);
    const bTs = toTimestamp(b.timestamp);

    if (aTs !== null && bTs !== null) {
      return aTs - bTs;
    }

    if (aTs !== null) return -1;
    if (bTs !== null) return 1;

    if (a.source.file !== b.source.file) {
      return a.source.file.localeCompare(b.source.file);
    }

    return a.source.line - b.source.line;
  });

  if (options.limit && options.limit > 0 && events.length > options.limit) {
    return {
      session,
      events: events.slice(-options.limit),
      files: relevantFiles.map((file) => file.name),
    };
  }

  return {
    session,
    events,
    files: relevantFiles.map((file) => file.name),
  };
}

import {
  type MessageSliceItem,
  type SummarySliceItem,
  type TimelineOptions,
  type ToolSliceItem,
} from "./types";
import { getSessionContext, listToolResultFiles } from "./session-files";
import { readSessionEvents } from "./reader";

function extractPreview(content: unknown, limit = 200): string | undefined {
  if (typeof content === "string") {
    return content.length > limit ? `${content.slice(0, limit)}...` : content;
  }

  if (Array.isArray(content)) {
    for (const item of content) {
      if (typeof item === "string") {
        return extractPreview(item, limit);
      }
      if (item && typeof item === "object") {
        if ((item as any).type === "text" && (item as any).text) {
          return extractPreview((item as any).text, limit);
        }
      }
    }
  }

  if (content && typeof content === "object") {
    const obj = content as any;
    if (obj.text) return extractPreview(obj.text, limit);
    if (obj.result) return extractPreview(obj.result, limit);
  }

  return undefined;
}

function extractMessageText(blocks: { type: string; [key: string]: any }[]): string {
  const texts = blocks
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .filter((text) => text.length > 0);
  return texts.join("\n");
}

export async function getTimelineSlice(
  sessionId: string,
  options: TimelineOptions
) {
  const result = await readSessionEvents(sessionId, options);
  if (!result) return null;

  return {
    session: result.session,
    events: result.events,
    meta: {
      count: result.events.length,
      files: result.files,
    },
  };
}

export async function getMessageSlice(
  sessionId: string,
  options: TimelineOptions
): Promise<{ session: any; messages: MessageSliceItem[]; meta: any } | null> {
  const result = await readSessionEvents(sessionId, options);
  if (!result) return null;

  const messages: MessageSliceItem[] = result.events
    .filter((event) => event.message && event.message.role)
    .map((event) => {
      const blocks = event.message?.content ?? [];
      const text = event.message?.text ?? extractMessageText(blocks as any);

      return {
        id: event.id,
        role: event.message!.role,
        text,
        timestamp: event.timestamp,
        blocks,
      };
    })
    .filter((message) => message.text.length > 0);

  return {
    session: result.session,
    messages,
    meta: {
      count: messages.length,
      files: result.files,
    },
  };
}

export async function getSummarySlice(
  sessionId: string,
  options: TimelineOptions
): Promise<{ session: any; summaries: SummarySliceItem[]; meta: any } | null> {
  const result = await readSessionEvents(sessionId, options);
  if (!result) return null;

  const summaries: SummarySliceItem[] = result.events
    .filter((event) => event.type === "summary" || event.type === "system")
    .map((event) => {
      const summary =
        event.summary ||
        event.message?.text ||
        extractPreview(event.message?.content ?? event.summary, 500) ||
        "";

      return {
        id: event.id,
        summary,
        timestamp: event.timestamp,
        type: event.type,
      };
    })
    .filter((item) => item.summary.length > 0);

  return {
    session: result.session,
    summaries,
    meta: {
      count: summaries.length,
      files: result.files,
    },
  };
}

export async function getToolSlice(
  sessionId: string,
  options: TimelineOptions & { includeOutput?: boolean; outputLimit?: number }
): Promise<{ session: any; tools: ToolSliceItem[]; meta: any } | null> {
  const result = await readSessionEvents(sessionId, options);
  if (!result) return null;

  const context = await getSessionContext(sessionId);
  const toolResults = context ? await listToolResultFiles(context) : new Map();

  const tools = new Map<string, ToolSliceItem>();
  const outputLimit = options.outputLimit ?? 2000;

  for (const event of result.events) {
    if (!event.message) continue;

    for (const block of event.message.content) {
      if (block.type === "tool_use") {
        const id = block.id ?? `${event.id}-tool`;
        const item = tools.get(id) ?? {
          id,
          name: block.name,
          input: block.input,
          timestamp: event.timestamp,
          eventId: event.id,
        };
        item.name = item.name ?? block.name;
        item.input = item.input ?? block.input;
        tools.set(id, item);
      }

      if (block.type === "tool_result") {
        const id = block.tool_use_id ?? `${event.id}-result`;
        const item = tools.get(id) ?? {
          id,
          timestamp: event.timestamp,
          eventId: event.id,
        };

        const preview = extractPreview(block.content);
        if (preview) {
          item.outputPreview = item.outputPreview ?? preview;
        }

        tools.set(id, item);
      }
    }
  }

  for (const item of tools.values()) {
    const outputPath = toolResults.get(item.id);
    if (outputPath) {
      item.outputRef = outputPath;

      if (options.includeOutput && !item.output) {
        try {
          const text = await Bun.file(outputPath).text();
          item.output =
            text.length > outputLimit ? `${text.slice(0, outputLimit)}...` : text;
          item.outputPreview = item.outputPreview ?? extractPreview(text);
        } catch {
          item.output = item.output ?? undefined;
        }
      }
    }
  }

  return {
    session: result.session,
    tools: Array.from(tools.values()),
    meta: {
      count: tools.size,
      files: result.files,
    },
  };
}

export async function getFilesSlice(sessionId: string) {
  const context = await getSessionContext(sessionId);
  if (!context) return null;

  const toolResults = await listToolResultFiles(context);

  return {
    sessionId: context.sessionId,
    folderName: context.folderName,
    files: context.files,
    toolResults: {
      count: toolResults.size,
    },
  };
}

export async function getToolResult(
  sessionId: string,
  toolUseId: string,
  outputLimit = 2000
): Promise<{ id: string; output: string } | null> {
  const context = await getSessionContext(sessionId);
  if (!context) return null;

  const toolResults = await listToolResultFiles(context);
  const filePath = toolResults.get(toolUseId);
  if (!filePath) return null;

  const text = await Bun.file(filePath).text();
  const output = text.length > outputLimit ? `${text.slice(0, outputLimit)}...` : text;

  return {
    id: toolUseId,
    output,
  };
}

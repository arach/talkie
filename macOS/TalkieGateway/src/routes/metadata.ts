import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { getSession } from "../discovery/sessions";

const CLAUDE_PROJECTS_DIR = `${process.env.HOME}/.claude/projects`;

/**
 * Extract readable text from Claude's content format
 * Handles: string, array of content blocks, nested message objects
 */
function extractTextContent(content: unknown): string {
  if (typeof content === "string") {
    return content.substring(0, 200);
  }

  if (Array.isArray(content)) {
    // Array of content blocks: [{type: "text", text: "..."}, ...]
    const texts = content
      .map((block: any) => {
        if (typeof block === "string") return block;
        if (block.type === "text" && block.text) return block.text;
        if (block.type === "tool_use") return `[Tool: ${block.name}]`;
        if (block.type === "tool_result") return `[Tool Result]`;
        return "";
      })
      .filter(Boolean);
    return texts.join(" ").substring(0, 200);
  }

  if (content && typeof content === "object") {
    // Try common fields
    const obj = content as any;
    if (obj.text) return String(obj.text).substring(0, 200);
    if (obj.content) return extractTextContent(obj.content);
  }

  return "";
}

export interface SessionMetadata {
  session: {
    id: string;
    project: string;
    projectPath: string;
    folderName: string;
    isLive: boolean;
    lastSeen: string;
  };
  files: FileInfo[];
  entries: EntryInfo[];
  stats: {
    totalEntries: number;
    entryTypes: Record<string, number>;
    firstEntry: string | null;
    lastEntry: string | null;
    fileSizeBytes: number;
  };
}

export interface FileInfo {
  name: string;
  path: string;
  sizeBytes: number;
  modifiedAt: string;
  isSession: boolean; // true if this is the main session file
}

export interface EntryInfo {
  index: number;
  type: string;
  timestamp?: string;
  sessionId?: string;
  cwd?: string;
  summary?: string; // First 200 chars of content or description
  keys: string[];
  sizeBytes: number;
}

/**
 * Get full metadata for a session including all JSONL entries
 * GET /sessions/:id/metadata
 */
export async function sessionMetadataRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const session = await getSession(sessionId);

  if (!session) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  try {
    const projectDir = join(CLAUDE_PROJECTS_DIR, session.folderName);

    // Get all files in the project directory
    const fileNames = await readdir(projectDir);
    const files: FileInfo[] = [];

    for (const fileName of fileNames) {
      const filePath = join(projectDir, fileName);
      const stats = await stat(filePath);
      if (stats.isFile()) {
        files.push({
          name: fileName,
          path: filePath,
          sizeBytes: stats.size,
          modifiedAt: stats.mtime.toISOString(),
          isSession: filePath === session.transcriptPath,
        });
      }
    }

    // Parse all entries from the session file
    const entries: EntryInfo[] = [];
    const entryTypes: Record<string, number> = {};
    let firstEntry: string | null = null;
    let lastEntry: string | null = null;
    let fileSizeBytes = 0;

    const file = Bun.file(session.transcriptPath);
    fileSizeBytes = file.size;
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    for (let i = 0; i < lines.length; i++) {
      try {
        const line = lines[i];
        const entry = JSON.parse(line);
        const entryType = entry.type || entry.role || "unknown";

        // Count entry types
        entryTypes[entryType] = (entryTypes[entryType] || 0) + 1;

        // Track timestamps
        if (entry.timestamp) {
          if (!firstEntry) firstEntry = entry.timestamp;
          lastEntry = entry.timestamp;
        }

        // Create summary based on entry type
        let summary = "";
        if (entry.content) {
          summary = extractTextContent(entry.content);
        } else if (entry.message?.content) {
          summary = extractTextContent(entry.message.content);
        } else if (entry.tool_calls) {
          summary = `Tools: ${entry.tool_calls.map((t: any) => t.name || t.function?.name).join(", ")}`;
        } else if (entry.cwd) {
          summary = `cwd: ${entry.cwd}`;
        } else if (entry.path) {
          summary = `Path: ${entry.path}`;
        }

        entries.push({
          index: i,
          type: entryType,
          timestamp: entry.timestamp,
          sessionId: entry.sessionId,
          cwd: entry.cwd,
          summary: summary || undefined,
          keys: Object.keys(entry),
          sizeBytes: line.length,
        });
      } catch {
        // Skip malformed lines
        entries.push({
          index: i,
          type: "parse_error",
          keys: [],
          sizeBytes: lines[i].length,
        });
      }
    }

    const metadata: SessionMetadata = {
      session: {
        id: session.id,
        project: session.project,
        projectPath: session.projectPath,
        folderName: session.folderName,
        isLive: session.isLive,
        lastSeen: session.lastSeen,
      },
      files,
      entries,
      stats: {
        totalEntries: entries.length,
        entryTypes,
        firstEntry,
        lastEntry,
        fileSizeBytes,
      },
    };

    return Response.json(metadata);
  } catch (err) {
    console.error("Error getting session metadata:", err);
    return Response.json(
      { error: "Failed to get metadata", details: String(err) },
      { status: 500 }
    );
  }
}

/**
 * Get raw entry at a specific index
 * GET /sessions/:id/entry/:index
 */
export async function sessionEntryRoute(
  req: Request,
  sessionId: string,
  entryIndex: number
): Promise<Response> {
  const session = await getSession(sessionId);

  if (!session) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  try {
    const file = Bun.file(session.transcriptPath);
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    if (entryIndex < 0 || entryIndex >= lines.length) {
      return Response.json({ error: "Entry index out of range" }, { status: 404 });
    }

    const entry = JSON.parse(lines[entryIndex]);
    return Response.json({ index: entryIndex, entry });
  } catch (err) {
    return Response.json(
      { error: "Failed to get entry", details: String(err) },
      { status: 500 }
    );
  }
}

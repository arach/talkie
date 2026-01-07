import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { sessionCache } from "../../discovery/session-cache";
import { type SessionContext, type SessionFileInfo } from "./types";

const CLAUDE_PROJECTS_DIR = `${process.env.HOME}/.claude/projects`;

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

async function readFirstJsonLine(filePath: string): Promise<any | null> {
  try {
    const file = Bun.file(filePath);
    const text = await file.slice(0, 65536).text();
    const line = text.split("\n").find((l) => l.trim().length > 0);
    if (!line) return null;
    return JSON.parse(line);
  } catch {
    return null;
  }
}

async function looksLikeJsonl(filePath: string): Promise<boolean> {
  const entry = await readFirstJsonLine(filePath);
  if (!entry || typeof entry !== "object") return false;
  return Boolean(entry.type || entry.sessionId || entry.message);
}

async function resolveFileSessionId(
  filePath: string,
  filename: string
): Promise<string | undefined> {
  if (isUUID(filename)) {
    return filename;
  }

  const entry = await readFirstJsonLine(filePath);
  if (!entry || typeof entry !== "object") return undefined;
  if (typeof entry.sessionId === "string") return entry.sessionId;
  if (typeof entry.message?.sessionId === "string") return entry.message.sessionId;

  return undefined;
}

export async function getSessionContext(
  sessionId: string,
  forceRefresh = false
): Promise<SessionContext | null> {
  const session = await sessionCache.getSession(sessionId, forceRefresh);
  if (!session) return null;

  const projectDir = join(CLAUDE_PROJECTS_DIR, session.folderName);
  const files: SessionFileInfo[] = [];

  let fileNames: string[] = [];
  try {
    fileNames = await readdir(projectDir);
  } catch {
    return null;
  }

  for (const fileName of fileNames) {
    const isJsonl = fileName.endsWith(".jsonl");
    const isJson = fileName.endsWith(".json");
    if (!isJsonl && !isJson) continue;

    const filePath = join(projectDir, fileName);
    let stats;
    try {
      stats = await stat(filePath);
    } catch {
      continue;
    }

    if (!stats.isFile()) continue;

    if (isJson && !(await looksLikeJsonl(filePath))) {
      continue;
    }

    const filename = fileName.replace(/\.jsonl$|\.json$/i, "");
    const fileSessionId = await resolveFileSessionId(filePath, filename);

    const isPrimary = filePath === session.transcriptPath || fileSessionId === session.id;
    const isAgent = fileName.startsWith("agent-");

    if (fileSessionId && fileSessionId !== session.id && fileSessionId !== sessionId) {
      continue;
    }

    files.push({
      name: fileName,
      path: filePath,
      sizeBytes: stats.size,
      modifiedAt: stats.mtime.toISOString(),
      isAgent,
      isPrimary,
      sessionId: fileSessionId,
    });
  }

  files.sort((a, b) => new Date(a.modifiedAt).getTime() - new Date(b.modifiedAt).getTime());

  const toolResultsDir = join(projectDir, session.id, "tool-results");

  return {
    sessionId: session.id,
    folderName: session.folderName,
    projectDir,
    files,
    toolResultsDir,
  };
}

export async function listToolResultFiles(
  context: SessionContext
): Promise<Map<string, string>> {
  const results = new Map<string, string>();
  if (!context.toolResultsDir) return results;

  try {
    const stats = await stat(context.toolResultsDir);
    if (!stats.isDirectory()) return results;
  } catch {
    return results;
  }

  let files: string[] = [];
  try {
    files = await readdir(context.toolResultsDir);
  } catch {
    return results;
  }

  for (const fileName of files) {
    if (!fileName.startsWith("toolu_") || !fileName.endsWith(".txt")) continue;
    const toolUseId = fileName.replace(/\.txt$/i, "");
    results.set(toolUseId, join(context.toolResultsDir, fileName));
  }

  return results;
}

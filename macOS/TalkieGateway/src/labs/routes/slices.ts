import {
  getFilesSlice,
  getMessageSlice,
  getSummarySlice,
  getTimelineSlice,
  getToolResult,
  getToolSlice,
} from "../explorer/slices";
import { labsLog } from "../log";

function parseBool(value: string | null, defaultValue: boolean): boolean {
  if (value === null) return defaultValue;
  return value === "1" || value.toLowerCase() === "true";
}

function parseLimit(value: string | null, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed <= 0) return fallback;
  return parsed;
}

export async function timelineRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"), 200);
  const before = url.searchParams.get("before") || undefined;
  const includeSidechains = parseBool(url.searchParams.get("includeSidechains"), true);
  const typesParam = url.searchParams.get("types");
  const types = typesParam ? typesParam.split(",") : undefined;

  const result = await getTimelineSlice(sessionId, {
    limit,
    before,
    includeSidechains,
    types,
  });

  if (!result) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  return Response.json(result);
}

export async function messagesRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"), 200);
  const before = url.searchParams.get("before") || undefined;
  const includeSidechains = parseBool(url.searchParams.get("includeSidechains"), true);

  const result = await getMessageSlice(sessionId, {
    limit,
    before,
    includeSidechains,
  });

  if (!result) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  return Response.json(result);
}

export async function toolsRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"), 500);
  const before = url.searchParams.get("before") || undefined;
  const includeSidechains = parseBool(url.searchParams.get("includeSidechains"), true);
  const includeOutput = parseBool(url.searchParams.get("includeOutput"), false);
  const outputLimit = parseLimit(url.searchParams.get("outputLimit"), 2000);

  const result = await getToolSlice(sessionId, {
    limit,
    before,
    includeSidechains,
    includeOutput,
    outputLimit,
  });

  if (!result) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  return Response.json(result);
}

export async function summariesRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"), 200);
  const before = url.searchParams.get("before") || undefined;
  const includeSidechains = parseBool(url.searchParams.get("includeSidechains"), true);

  const result = await getSummarySlice(sessionId, {
    limit,
    before,
    includeSidechains,
  });

  if (!result) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  return Response.json(result);
}

export async function filesRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const result = await getFilesSlice(sessionId);

  if (!result) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  return Response.json(result);
}

export async function toolResultRoute(
  req: Request,
  sessionId: string,
  toolUseId: string
): Promise<Response> {
  const url = new URL(req.url);
  const outputLimit = parseLimit(url.searchParams.get("outputLimit"), 2000);

  const result = await getToolResult(sessionId, toolUseId, outputLimit);
  if (!result) {
    return Response.json({ error: "Tool result not found" }, { status: 404 });
  }

  labsLog.info(`Tool result: ${sessionId} ${toolUseId}`);
  return Response.json(result);
}

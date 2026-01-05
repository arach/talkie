/**
 * Session Matching Routes
 *
 * Endpoints for fuzzy matching terminals to Claude sessions.
 * iOS can trigger scans and confirm/correct matches.
 */

import { fuzzyMatchTerminals, type TerminalInfo, type MatchResult, type MatchSummary } from "../matching/fuzzy-matcher";
import { log } from "../log";
import { $ } from "bun";

// Cached results
let lastScan: MatchSummary | null = null;
let confirmedMappings: Map<string, string> = new Map(); // fingerprint -> sessionId

/**
 * GET /match
 * Get current match results (cached or fresh if stale)
 */
export async function matchRoute(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const fresh = url.searchParams.get("fresh") === "true";

  if (fresh || !lastScan || isStale(lastScan.timestamp)) {
    lastScan = await performScan();
  }

  return Response.json({
    ...lastScan,
    confirmedCount: confirmedMappings.size,
  });
}

/**
 * POST /match/scan
 * Trigger a fresh scan (iOS pokes when unsure)
 */
export async function matchScanRoute(req: Request): Promise<Response> {
  log.info("Match scan triggered by client");
  lastScan = await performScan();

  return Response.json({
    success: true,
    ...lastScan,
  });
}

/**
 * POST /match/confirm
 * Confirm a match (user verified on iOS)
 * Body: { terminalFingerprint: string, sessionId: string }
 */
export async function matchConfirmRoute(req: Request): Promise<Response> {
  try {
    const body = await req.json() as { terminalFingerprint: string; sessionId: string };
    const { terminalFingerprint, sessionId } = body;

    if (!terminalFingerprint || !sessionId) {
      return Response.json({ error: "Missing terminalFingerprint or sessionId" }, { status: 400 });
    }

    confirmedMappings.set(terminalFingerprint, sessionId);
    await saveConfirmedMappings();

    log.info(`Match confirmed: ${terminalFingerprint} -> ${sessionId}`);

    return Response.json({
      success: true,
      confirmedCount: confirmedMappings.size,
    });
  } catch (err) {
    return Response.json({ error: "Invalid request body" }, { status: 400 });
  }
}

/**
 * GET /match/confirmed
 * Get all confirmed mappings
 */
export async function matchConfirmedRoute(req: Request): Promise<Response> {
  const mappings: Record<string, string> = {};
  confirmedMappings.forEach((sessionId, fingerprint) => {
    mappings[fingerprint] = sessionId;
  });

  return Response.json({
    mappings,
    count: confirmedMappings.size,
  });
}

/**
 * DELETE /match/confirmed/:fingerprint
 * Remove a confirmed mapping
 */
export async function matchDeleteRoute(req: Request, fingerprint: string): Promise<Response> {
  if (confirmedMappings.has(fingerprint)) {
    confirmedMappings.delete(fingerprint);
    await saveConfirmedMappings();
    return Response.json({ success: true });
  }
  return Response.json({ error: "Mapping not found" }, { status: 404 });
}

// MARK: - Helpers

async function performScan(): Promise<MatchSummary> {
  // Get terminal windows from osascript (fast, doesn't need full AX scan)
  const terminals = await getTerminalWindows();
  log.info(`Scanning ${terminals.length} terminal windows for matches`);

  const results = await fuzzyMatchTerminals(terminals);

  // Merge with confirmed mappings
  for (const match of results.matches) {
    const fingerprint = makeFingerprint(match.terminal);
    const confirmedSession = confirmedMappings.get(fingerprint);
    if (confirmedSession) {
      match.confidence = 100;
      match.matchMethod = "user-confirmed";
      match.details = "Confirmed by user";
    }
  }

  return results;
}

async function getTerminalWindows(): Promise<TerminalInfo[]> {
  const terminals: TerminalInfo[] = [];

  // Use osascript to quickly get window titles from terminal apps
  const terminalBundleIds = [
    "com.mitchellh.ghostty",
    "com.googlecode.iterm2",
    "com.apple.Terminal",
    "dev.warp.Warp-Stable",
    "com.github.wez.wezterm",
  ];

  for (const bundleId of terminalBundleIds) {
    try {
      const appName = bundleIdToAppName(bundleId);
      const result = await $`osascript -e 'tell application "System Events" to tell process "${appName}" to get name of every window'`.quiet().nothrow();

      if (result.exitCode === 0 && result.stdout) {
        const windowTitles = result.stdout.toString().trim();
        if (windowTitles && windowTitles !== "missing value") {
          // Parse comma-separated list
          const titles = windowTitles.split(", ").map(t => t.trim()).filter(t => t);
          for (const title of titles) {
            terminals.push({
              bundleId,
              windowTitle: title,
            });
          }
        }
      }
    } catch (err) {
      // Skip apps that aren't running
    }
  }

  return terminals;
}

function bundleIdToAppName(bundleId: string): string {
  const map: Record<string, string> = {
    "com.mitchellh.ghostty": "Ghostty",
    "com.googlecode.iterm2": "iTerm2",
    "com.apple.Terminal": "Terminal",
    "dev.warp.Warp-Stable": "Warp",
    "com.github.wez.wezterm": "WezTerm",
  };
  return map[bundleId] || bundleId;
}

function makeFingerprint(terminal: TerminalInfo): string {
  return `${terminal.bundleId}|${terminal.windowTitle}`;
}

function isStale(timestamp: string): boolean {
  const age = Date.now() - new Date(timestamp).getTime();
  return age > 60_000; // 1 minute
}

async function saveConfirmedMappings(): Promise<void> {
  const mappings: Record<string, string> = {};
  confirmedMappings.forEach((sessionId, fingerprint) => {
    mappings[fingerprint] = sessionId;
  });

  const file = Bun.file(`${process.env.HOME}/.talkie-bridge/confirmed-mappings.json`);
  await Bun.write(file, JSON.stringify(mappings, null, 2));
}

async function loadConfirmedMappings(): Promise<void> {
  try {
    const file = Bun.file(`${process.env.HOME}/.talkie-bridge/confirmed-mappings.json`);
    if (await file.exists()) {
      const data = await file.json() as Record<string, string>;
      confirmedMappings = new Map(Object.entries(data));
      log.info(`Loaded ${confirmedMappings.size} confirmed mappings`);
    }
  } catch (err) {
    // No saved mappings yet
  }
}

// Load on startup
loadConfirmedMappings();

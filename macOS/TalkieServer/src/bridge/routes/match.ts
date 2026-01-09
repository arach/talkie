/**
 * Session Matching Routes
 *
 * Endpoints for fuzzy matching terminals to Claude sessions.
 * iOS can trigger scans and confirm/correct matches.
 */

import { fuzzyMatchTerminals, type TerminalInfo, type MatchSummary } from "../../matching/fuzzy-matcher";
import { log } from "../../log";
import { MAPPINGS_FILE } from "../../paths";
import { notFound } from "./responses";
import { $ } from "bun";

// ===== Types =====

export interface MatchConfirmRequest {
  terminalFingerprint: string;
  sessionId: string;
}

export interface MatchResponse {
  matches: MatchSummary["matches"];
  timestamp: string;
  confirmedCount: number;
}

export interface MatchScanResponse extends MatchResponse {
  success: true;
}

export interface MatchConfirmResponse {
  success: true;
  confirmedCount: number;
}

export interface MatchConfirmedResponse {
  mappings: Record<string, string>;
  count: number;
}

// ===== Module State =====

let lastScan: MatchSummary | null = null;
let confirmedMappings: Map<string, string> = new Map();

// ===== Handlers =====

/**
 * GET /match
 * Get current match results (cached or fresh if stale)
 */
export async function matchRoute(fresh: boolean = false): Promise<MatchResponse> {
  if (fresh || !lastScan || isStale(lastScan.timestamp)) {
    lastScan = await performScan();
  }

  return {
    ...lastScan,
    confirmedCount: confirmedMappings.size,
  };
}

/**
 * POST /match/scan
 * Trigger a fresh scan (iOS pokes when unsure)
 */
export async function matchScanRoute(): Promise<MatchScanResponse> {
  log.info("Match scan triggered by client");
  lastScan = await performScan();

  return {
    success: true,
    ...lastScan,
    confirmedCount: confirmedMappings.size,
  };
}

/**
 * POST /match/confirm
 * Confirm a match (user verified on iOS)
 */
export async function matchConfirmRoute(body: MatchConfirmRequest): Promise<MatchConfirmResponse> {
  const { terminalFingerprint, sessionId } = body;

  confirmedMappings.set(terminalFingerprint, sessionId);
  await saveConfirmedMappings();

  log.info(`Match confirmed: ${terminalFingerprint} -> ${sessionId}`);

  return {
    success: true,
    confirmedCount: confirmedMappings.size,
  };
}

/**
 * GET /match/confirmed
 * Get all confirmed mappings
 */
export function matchConfirmedRoute(): MatchConfirmedResponse {
  const mappings: Record<string, string> = {};
  confirmedMappings.forEach((sessionId, fingerprint) => {
    mappings[fingerprint] = sessionId;
  });

  return {
    mappings,
    count: confirmedMappings.size,
  };
}

/**
 * DELETE /match/confirmed/:fingerprint
 * Remove a confirmed mapping
 */
export async function matchDeleteRoute(fingerprint: string): Promise<{ success: true } | Response> {
  if (confirmedMappings.has(fingerprint)) {
    confirmedMappings.delete(fingerprint);
    await saveConfirmedMappings();
    return { success: true };
  }
  return notFound("Mapping not found");
}

// ===== Helpers =====

async function performScan(): Promise<MatchSummary> {
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
          const titles = windowTitles.split(", ").map(t => t.trim()).filter(t => t);
          for (const title of titles) {
            terminals.push({ bundleId, windowTitle: title });
          }
        }
      }
    } catch {
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

  const file = Bun.file(MAPPINGS_FILE);
  await Bun.write(file, JSON.stringify(mappings, null, 2));
}

async function loadConfirmedMappings(): Promise<void> {
  try {
    const file = Bun.file(MAPPINGS_FILE);
    if (await file.exists()) {
      const data = await file.json() as Record<string, string>;
      confirmedMappings = new Map(Object.entries(data));
      log.info(`Loaded ${confirmedMappings.size} confirmed mappings`);
    }
  } catch {
    // No saved mappings yet
  }
}

// Load on startup
loadConfirmedMappings();

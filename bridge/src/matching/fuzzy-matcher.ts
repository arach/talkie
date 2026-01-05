/**
 * Fuzzy Session Matcher
 *
 * Tries multiple techniques to match terminal windows to Claude sessions.
 * Returns confidence-scored matches for user confirmation.
 */

import { discoverSessions, type Session } from "../discovery/sessions";

export interface TerminalInfo {
  bundleId: string;
  windowTitle: string;
  pid?: number;
}

export interface MatchResult {
  terminal: TerminalInfo;
  session: Session;
  confidence: number; // 0-100
  matchMethod: string;
  details: string;
}

export interface MatchSummary {
  matches: MatchResult[];
  unmatched: TerminalInfo[];
  timestamp: string;
}

/**
 * Try to match terminals to Claude sessions using multiple techniques
 */
export async function fuzzyMatchTerminals(
  terminals: TerminalInfo[]
): Promise<MatchSummary> {
  const sessions = await discoverSessions();
  const matches: MatchResult[] = [];
  const unmatched: TerminalInfo[] = [];

  for (const terminal of terminals) {
    const bestMatch = findBestMatch(terminal, sessions);

    if (bestMatch && bestMatch.confidence >= 30) {
      matches.push(bestMatch);
    } else {
      unmatched.push(terminal);
    }
  }

  // Sort by confidence (highest first)
  matches.sort((a, b) => b.confidence - a.confidence);

  return {
    matches,
    unmatched,
    timestamp: new Date().toISOString(),
  };
}

/**
 * Find the best matching session for a terminal
 */
function findBestMatch(
  terminal: TerminalInfo,
  sessions: Session[]
): MatchResult | null {
  let bestMatch: MatchResult | null = null;

  for (const session of sessions) {
    const results = [
      tryPathInTitleMatch(terminal, session),
      tryProjectNameMatch(terminal, session),
      tryFuzzyTitleMatch(terminal, session),
      tryClaudeKeywordMatch(terminal, session),
    ];

    for (const result of results) {
      if (result && (!bestMatch || result.confidence > bestMatch.confidence)) {
        bestMatch = result;
      }
    }
  }

  return bestMatch;
}

/**
 * Technique 1: Look for the project path in the window title
 * e.g., "~/dev/talkie-tailscale" in title matches session path "/Users/arach/dev/talkie-tailscale"
 */
function tryPathInTitleMatch(
  terminal: TerminalInfo,
  session: Session
): MatchResult | null {
  const title = terminal.windowTitle.toLowerCase();
  const sessionPath = session.projectPath.toLowerCase();

  // Extract potential paths from title
  const pathPatterns = [
    // After colon: "user@host:~/dev/project"
    /:\s*(~?\/[^\s]+)/,
    // After dash: "zsh - ~/dev/project"
    /\s-\s+(~?\/[^\s]+)/,
    // Standalone path
    /(~\/[^\s]+)/,
    /(\/(Users|home)\/[^\s]+)/i,
  ];

  for (const pattern of pathPatterns) {
    const match = terminal.windowTitle.match(pattern);
    if (match) {
      let extractedPath = match[1].toLowerCase();

      // Expand ~ to /Users/username (approximate)
      if (extractedPath.startsWith("~")) {
        // Try to match the part after ~
        const afterTilde = extractedPath.slice(1); // "/dev/project"
        if (sessionPath.includes(afterTilde)) {
          return {
            terminal,
            session,
            confidence: 90,
            matchMethod: "path-in-title",
            details: `Path "${match[1]}" found in title matches session`,
          };
        }
      } else if (sessionPath.includes(extractedPath)) {
        return {
          terminal,
          session,
          confidence: 95,
          matchMethod: "path-in-title",
          details: `Exact path "${match[1]}" matches session`,
        };
      }
    }
  }

  return null;
}

/**
 * Technique 2: Match project name to parts of window title
 * e.g., session "talkie-tailscale" appears in window title
 */
function tryProjectNameMatch(
  terminal: TerminalInfo,
  session: Session
): MatchResult | null {
  const title = terminal.windowTitle.toLowerCase();
  const projectName = session.project.toLowerCase();

  // Exact project name in title
  if (title.includes(projectName)) {
    return {
      terminal,
      session,
      confidence: 75,
      matchMethod: "project-name",
      details: `Project name "${session.project}" found in title`,
    };
  }

  // Try folder name from path
  const folderName = session.projectPath.split("/").pop()?.toLowerCase();
  if (folderName && title.includes(folderName)) {
    return {
      terminal,
      session,
      confidence: 70,
      matchMethod: "folder-name",
      details: `Folder name "${folderName}" found in title`,
    };
  }

  return null;
}

/**
 * Technique 3: Fuzzy string matching using Levenshtein-ish similarity
 * For when there's partial matches or typos
 */
function tryFuzzyTitleMatch(
  terminal: TerminalInfo,
  session: Session
): MatchResult | null {
  const title = terminal.windowTitle.toLowerCase();
  const projectName = session.project.toLowerCase();

  // Split title into words and check overlap
  const titleWords = title.split(/[\s\-_\/]+/).filter((w) => w.length > 2);
  const projectWords = projectName.split(/[\s\-_]+/).filter((w) => w.length > 2);

  if (projectWords.length === 0) return null;

  // Count matching words
  let matchingWords = 0;
  for (const pw of projectWords) {
    if (titleWords.some((tw) => tw.includes(pw) || pw.includes(tw))) {
      matchingWords++;
    }
  }

  const matchRatio = matchingWords / projectWords.length;

  if (matchRatio >= 0.5) {
    return {
      terminal,
      session,
      confidence: Math.round(40 + matchRatio * 30), // 40-70
      matchMethod: "fuzzy-words",
      details: `${matchingWords}/${projectWords.length} words match`,
    };
  }

  return null;
}

/**
 * Technique 4: Look for "claude" keyword in window title
 * Some terminals show the running command
 */
function tryClaudeKeywordMatch(
  terminal: TerminalInfo,
  session: Session
): MatchResult | null {
  const title = terminal.windowTitle.toLowerCase();

  // Check for claude-related keywords
  const claudePatterns = [
    /\bclaude\b/,
    /\bclaude\s+code\b/,
    /\banthrop/,
  ];

  const hasClaudeKeyword = claudePatterns.some((p) => p.test(title));

  if (hasClaudeKeyword) {
    // If this is a live session, higher confidence
    if (session.isLive) {
      return {
        terminal,
        session,
        confidence: 50,
        matchMethod: "claude-keyword",
        details: `"claude" in title + session is live`,
      };
    }

    // Otherwise lower confidence (could be any claude session)
    return {
      terminal,
      session,
      confidence: 35,
      matchMethod: "claude-keyword",
      details: `"claude" in title`,
    };
  }

  return null;
}

/**
 * Calculate similarity between two strings (0-1)
 * Simple Jaccard-like similarity based on character n-grams
 */
function stringSimilarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length < 2 || b.length < 2) return 0;

  const aNgrams = new Set<string>();
  const bNgrams = new Set<string>();

  for (let i = 0; i < a.length - 1; i++) {
    aNgrams.add(a.slice(i, i + 2));
  }
  for (let i = 0; i < b.length - 1; i++) {
    bNgrams.add(b.slice(i, i + 2));
  }

  let intersection = 0;
  for (const ng of aNgrams) {
    if (bNgrams.has(ng)) intersection++;
  }

  return (2 * intersection) / (aNgrams.size + bNgrams.size);
}

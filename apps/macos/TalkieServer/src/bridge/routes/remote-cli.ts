/**
 * Remote CLI Routes
 *
 * POST /cli - Execute a talkie CLI command on the Mac
 *
 * Allows paired iOS devices to run talkie CLI commands remotely.
 * Only executes `talkie` and `talkie-dev` — no arbitrary shell access.
 */

import { spawn } from "bun";
import { log } from "../../log";

// ===== Types =====

export interface CLIRequest {
  command: string;       // Full command string, e.g. "talkie memos --limit 5 --pretty"
  timeout?: number;      // Max execution time in ms (default 30000)
}

export interface CLIResponse {
  success: boolean;
  output?: string;
  error?: string;
  exitCode?: number;
  durationMs?: number;
}

// ===== Allowed commands =====

const ALLOWED_COMMANDS = new Set(["talkie", "talkie-dev"]);
const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_TIMEOUT_MS = 120_000;

function parseCommandLine(command: string): string[] | null {
  const args: string[] = [];
  let current = "";
  let quote: "\"" | "'" | null = null;
  let escaping = false;

  for (const char of command.trim()) {
    if (escaping) {
      current += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote) {
      if (char === quote) {
        quote = null;
      } else {
        current += char;
      }
      continue;
    }

    if (char === "\"" || char === "'") {
      quote = char;
      continue;
    }

    if (/\s/.test(char)) {
      if (current.length > 0) {
        args.push(current);
        current = "";
      }
      continue;
    }

    current += char;
  }

  if (escaping || quote) {
    return null;
  }

  if (current.length > 0) {
    args.push(current);
  }

  return args;
}

function allowedCommandArgs(command: string): string[] | null {
  const args = parseCommandLine(command);
  if (!args || args.length === 0 || !ALLOWED_COMMANDS.has(args[0])) {
    return null;
  }
  return args;
}

function normalizedTimeout(timeout: number | undefined): number {
  if (!Number.isFinite(timeout)) {
    return DEFAULT_TIMEOUT_MS;
  }
  return Math.min(Math.max(timeout ?? DEFAULT_TIMEOUT_MS, 1_000), MAX_TIMEOUT_MS);
}

// ===== Handler =====

/**
 * POST /cli
 * Execute a talkie CLI command and return the output
 */
export async function cliRoute(body: CLIRequest): Promise<CLIResponse> {
  const { command } = body;
  const timeout = normalizedTimeout(body.timeout);

  if (!command || !command.trim()) {
    return { success: false, error: "No command provided", exitCode: -1 };
  }

  const commandArgs = allowedCommandArgs(command);
  if (!commandArgs) {
    return {
      success: false,
      error: "Only 'talkie' and 'talkie-dev' commands are allowed",
      exitCode: -1,
    };
  }

  log.info(`CLI: ${commandArgs.map((arg) => arg.includes(" ") ? `"${arg}"` : arg).join(" ").slice(0, 200)}`);

  const start = Date.now();

  try {
    const [executable, ...args] = commandArgs;
    const proc = spawn({
      cmd: [executable, ...args],
      cwd: process.env.HOME,
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...process.env,
        TERM: "dumb",
        NO_COLOR: "1",
        FORCE_COLOR: "0",
      },
    });

    // Race against timeout
    const timeoutPromise = new Promise<never>((_, reject) =>
      setTimeout(() => {
        proc.kill();
        reject(new Error(`Command timed out after ${timeout}ms`));
      }, timeout)
    );

    const [stdout, stderr, exitCode] = await Promise.race([
      Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
        proc.exited,
      ]),
      timeoutPromise,
    ]) as [string, string, number];

    const durationMs = Date.now() - start;

    // Strip ANSI escape codes from output
    const cleanOutput = (stdout || "").replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
    const cleanError = (stderr || "").replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();

    if (exitCode !== 0) {
      log.warn(`CLI failed (exit ${exitCode}): ${cleanError.slice(0, 200)}`);
      return {
        success: false,
        output: cleanOutput || undefined,
        error: cleanError || `Exited with code ${exitCode}`,
        exitCode,
        durationMs,
      };
    }

    log.info(`CLI completed in ${durationMs}ms (${cleanOutput.length} chars)`);

    return {
      success: true,
      output: cleanOutput,
      exitCode: 0,
      durationMs,
    };
  } catch (error) {
    const durationMs = Date.now() - start;
    const message = error instanceof Error ? error.message : String(error);
    log.error(`CLI error: ${message}`);
    return {
      success: false,
      error: message,
      exitCode: -1,
      durationMs,
    };
  }
}

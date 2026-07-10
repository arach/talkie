#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import process from "node:process";

class ToolError extends Error {}
class UsageError extends ToolError {}

const command = process.argv[2];
const args = process.argv.slice(3);

const legacyDatabaseCommands = new Set([
  "list-memos",
  "search-memos",
  "list-failed-memos",
  "show-memo",
  "retranscribe-memo",
  "list-workflow-runs",
]);

function main() {
  if (legacyDatabaseCommands.has(command ?? "")) {
    throw new UsageError(
      `AgentKit no longer exposes '${command}' because generated database helpers are not a supported agent interface.\n` +
        "Use the Talkie CLI instead: talkie memos, talkie dictations, talkie search, talkie workflows, or talkie captures.\n" +
        "If the CLI is missing the capability you need, add the supported CLI/API surface rather than querying talkie.sqlite directly.",
    );
  }

  switch (command) {
    case "capture-markup-describe":
      return captureMarkupDescribe(args);
    case "capture-markup-plan":
      return captureMarkupPlan(args);
    case "capture-markup-apply":
      return captureMarkupApply(args);
    case "capture-markup-render":
      return captureMarkupRender(args);
    default:
      throw new UsageError(
        "Usage: agent-tools.ts <command> [args]\n" +
          "Commands: capture-markup-describe, capture-markup-plan, capture-markup-apply, capture-markup-render",
      );
  }
}

try {
  main();
} catch (error) {
  const message =
    error instanceof Error ? error.message : "Unknown agent tool failure";
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function captureMarkupDescribe(commandArgs: string[]) {
  if (commandArgs.length < 1) {
    throw new UsageError("Usage: capture-markup-describe <image-path>");
  }
  writeStdout(runTalkieDebug("capture-markup-describe", commandArgs));
}

function captureMarkupPlan(commandArgs: string[]) {
  if (commandArgs.length < 2) {
    throw new UsageError("Usage: capture-markup-plan <image-path> <instruction>");
  }
  writeStdout(runTalkieDebug("capture-markup-plan", commandArgs));
}

function captureMarkupApply(commandArgs: string[]) {
  if (commandArgs.length < 2) {
    throw new UsageError("Usage: capture-markup-apply <image-path> <plan-json-path>");
  }
  writeStdout(runTalkieDebug("capture-markup-apply", commandArgs));
}

function captureMarkupRender(commandArgs: string[]) {
  if (commandArgs.length < 1) {
    throw new UsageError("Usage: capture-markup-render <image-path> [output-path]");
  }
  writeStdout(runTalkieDebug("capture-markup-render", commandArgs));
}

function requireTalkieExecutablePath(): string {
  const executablePath = process.env.TALKIE_EXECUTABLE_PATH?.trim();
  if (!executablePath) {
    throw new ToolError("TALKIE_EXECUTABLE_PATH is not configured.");
  }
  if (!existsSync(executablePath)) {
    throw new ToolError(`Talkie executable not available at '${executablePath}'.`);
  }
  return executablePath;
}

function runTalkieDebug(commandName: string, commandArgs: string[]): string {
  const executablePath = requireTalkieExecutablePath();
  const result = spawnSync(executablePath, [`--debug=${commandName}`, ...commandArgs], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });

  if (result.error) {
    throw commandError(result.error, executablePath);
  }

  const combinedOutput = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  if ((result.status ?? 1) !== 0) {
    throw new ToolError(combinedOutput.trim() || `${commandName} failed`);
  }

  return result.stdout ?? "";
}

function commandError(error: Error, commandName: string): ToolError {
  const code = (error as NodeJS.ErrnoException).code;
  if (code === "ENOENT") {
    return new ToolError(`${commandName} is required but was not found on PATH.`);
  }

  return new ToolError(error.message);
}

function writeStdout(text: string) {
  if (text.length > 0) {
    process.stdout.write(text);
  }
}

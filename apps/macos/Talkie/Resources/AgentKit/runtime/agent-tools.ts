#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import process from "node:process";

type OutputMode = "raw" | "table" | "line";

class ToolError extends Error {}
class UsageError extends ToolError {}

const command = process.argv[2];
const args = process.argv.slice(3);

function main() {
  switch (command) {
    case "list-memos":
      return listMemos(args);
    case "search-memos":
      return searchMemos(args);
    case "list-failed-memos":
      return listFailedMemos(args);
    case "show-memo":
      return showMemo(args);
    case "retranscribe-memo":
      return retranscribeMemo(args);
    case "list-workflow-runs":
      return listWorkflowRuns(args);
    default:
      throw new UsageError(
        "Usage: agent-tools.ts <command> [args]\n" +
          "Commands: list-memos, search-memos, list-failed-memos, show-memo, retranscribe-memo, list-workflow-runs",
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

function listMemos(commandArgs: string[]) {
  const databasePath = requireDatabasePath();
  const limit = normalizedLimit(commandArgs[0], 20);
  const sql = `
SELECT substr(${normalizedIdExpression("id")}, 1, 8) AS id,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at,
       CASE
         WHEN title IS NULL OR trim(title) = '' THEN '(untitled)'
         ELSE replace(title, char(10), ' ')
       END AS title,
       printf('%.1fs', duration) AS duration,
       CASE WHEN transcription IS NULL OR trim(transcription) = '' THEN 'no' ELSE 'yes' END AS transcript,
       COALESCE(originDeviceId, '') AS source
FROM voice_memos
WHERE deletedAt IS NULL
ORDER BY datetime(createdAt) DESC
LIMIT ${limit};
`;
  writeStdout(runSqlite(databasePath, "table", sql));
}

function searchMemos(commandArgs: string[]) {
  if (commandArgs.length < 1) {
    throw new UsageError("Usage: search-memos <query> [limit]");
  }

  const databasePath = requireDatabasePath();
  const query = sqlText(commandArgs[0]);
  const limit = normalizedLimit(commandArgs[1], 20);
  const sql = `
SELECT substr(${normalizedIdExpression("id")}, 1, 8) AS id,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at,
       CASE
         WHEN title IS NULL OR trim(title) = '' THEN '(untitled)'
         ELSE replace(title, char(10), ' ')
       END AS title,
       printf('%.1fs', duration) AS duration
FROM voice_memos
WHERE deletedAt IS NULL
  AND (
    COALESCE(title, '') LIKE '%' || ${query} || '%'
    OR COALESCE(transcription, '') LIKE '%' || ${query} || '%'
    OR COALESCE(notes, '') LIKE '%' || ${query} || '%'
    OR COALESCE(summary, '') LIKE '%' || ${query} || '%'
  )
ORDER BY datetime(createdAt) DESC
LIMIT ${limit};
`;
  writeStdout(runSqlite(databasePath, "table", sql));
}

function listFailedMemos(commandArgs: string[]) {
  const databasePath = requireDatabasePath();
  const limit = normalizedLimit(commandArgs[0], 20);
  const sql = `
SELECT substr(${normalizedIdExpression("vm.id")}, 1, 8) AS id,
       strftime('%Y-%m-%d %H:%M', vm.createdAt) AS created_at,
       CASE
         WHEN vm.title IS NULL OR trim(vm.title) = '' THEN '(untitled)'
         ELSE replace(vm.title, char(10), ' ')
       END AS title,
       printf('%.1fs', vm.duration) AS duration,
       COALESCE(r.transcriptionStatus, 'failed') AS mirror_status,
       CASE
         WHEN vm.audioFilePath IS NULL OR trim(vm.audioFilePath) = '' THEN 'missing'
         ELSE 'saved'
       END AS audio
FROM voice_memos vm
LEFT JOIN recordings r
  ON r.id = vm.id
 AND r.type = 'memo'
WHERE vm.deletedAt IS NULL
  AND COALESCE(vm.audioFilePath, '') != ''
  AND COALESCE(vm.transcription, '') = ''
  AND COALESCE(vm.isTranscribing, 0) = 0
ORDER BY datetime(vm.createdAt) DESC
LIMIT ${limit};
`;
  writeStdout(runSqlite(databasePath, "table", sql));
}

function showMemo(commandArgs: string[]) {
  if (commandArgs.length < 1) {
    throw new UsageError("Usage: show-memo <uuid-or-prefix>");
  }

  const databasePath = requireDatabasePath();
  const lookup = commandArgs[0];
  const memoId = resolveMemoId(databasePath, lookup);
  if (!memoId) {
    throw new ToolError(`No memo found for '${lookup}'`);
  }

  writeStdout("Memo\n----\n");
  writeStdout(
    runSqlite(
      databasePath,
      "line",
      `
SELECT ${normalizedIdExpression("id")} AS id,
       createdAt,
       lastModified,
       COALESCE(title, '') AS title,
       duration,
       isTranscribing,
       COALESCE(originDeviceId, '') AS originDeviceId,
       COALESCE(audioFilePath, '') AS audioFilePath,
       COALESCE(transcription, '') AS transcription,
       COALESCE(notes, '') AS notes,
       COALESCE(summary, '') AS summary,
       COALESCE(tasks, '') AS tasks,
       COALESCE(reminders, '') AS reminders
FROM voice_memos
WHERE ${normalizedIdExpression("id")} = ${sqlText(memoId)}
LIMIT 1;
`,
    ),
  );

  writeStdout("\nMirror Row\n----------\n");
  writeStdout(
    runSqlite(
      databasePath,
       "line",
       `
SELECT COALESCE(transcriptionStatus, '') AS transcriptionStatus,
       COALESCE(transcriptionError, '') AS transcriptionError,
       COALESCE(transcriptionModel, '') AS transcriptionModel
FROM recordings
WHERE ${normalizedIdExpression("id")} = ${sqlText(memoId)}
  AND type = 'memo'
LIMIT 1;
`,
    ),
  );

  writeStdout("\nWorkflow Runs\n-------------\n");
  writeStdout(
    runSqlite(
      databasePath,
      "table",
      `
SELECT substr(${normalizedIdExpression("id")}, 1, 8) AS run_id,
       status,
       workflowName AS workflow,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at,
       COALESCE(backendId, '') AS backend
FROM workflow_runs
WHERE ${normalizedIdExpression("memoId")} = ${sqlText(memoId)}
ORDER BY datetime(createdAt) DESC
LIMIT 20;
`,
    ),
  );

  writeStdout("\nTranscript Versions\n-------------------\n");
  writeStdout(
    runSqlite(
      databasePath,
      "table",
      `
SELECT version,
       sourceType,
       COALESCE(engine, '') AS engine,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at
FROM transcript_versions
WHERE ${normalizedIdExpression("memoId")} = ${sqlText(memoId)}
ORDER BY version DESC
LIMIT 20;
`,
    ),
  );
}

function retranscribeMemo(commandArgs: string[]) {
  if (commandArgs.length < 1) {
    throw new UsageError("Usage: retranscribe-memo <uuid-or-prefix> [model-id]");
  }

  const databasePath = requireDatabasePath();
  const talkieExecutablePath = requireTalkieExecutablePath();
  const lookup = commandArgs[0];
  const modelId = commandArgs[1] ?? "parakeet:v3";
  const memoId = resolveMemoId(databasePath, lookup);

  if (!memoId) {
    throw new ToolError(`No memo found for '${lookup}'`);
  }

  const result = spawnSync(
    talkieExecutablePath,
    ["--debug=retranscribe-memo", uuidStringFromNormalizedId(memoId), modelId],
    { stdio: "inherit" },
  );

  if (result.error) {
    throw commandError(result.error, talkieExecutablePath);
  }

  process.exit(result.status ?? 1);
}

function listWorkflowRuns(commandArgs: string[]) {
  const databasePath = requireDatabasePath();

  let memoId = "";
  let limitArg = "";

  if (commandArgs.length >= 1) {
    if (commandArgs.length >= 2) {
      limitArg = commandArgs[1];
      memoId = resolveMemoId(databasePath, commandArgs[0]) ?? "";
      if (!memoId) {
        throw new ToolError(`No memo found for '${commandArgs[0]}'`);
      }
    } else {
      memoId = resolveMemoId(databasePath, commandArgs[0]) ?? "";
      if (!memoId && isPositiveInteger(commandArgs[0])) {
        limitArg = commandArgs[0];
      } else if (!memoId) {
        throw new ToolError(`No memo found for '${commandArgs[0]}'`);
      }
    }
  }

  const limit = normalizedLimit(limitArg, 20);

  if (memoId) {
    const sql = `
SELECT substr(${normalizedIdExpression("id")}, 1, 8) AS run_id,
       status,
       workflowName AS workflow,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at,
       COALESCE(backendId, '') AS backend,
       COALESCE(errorMessage, '') AS error
FROM workflow_runs
WHERE ${normalizedIdExpression("memoId")} = ${sqlText(memoId)}
ORDER BY datetime(createdAt) DESC
LIMIT ${limit};
`;
    writeStdout(runSqlite(databasePath, "table", sql));
    return;
  }

  const sql = `
SELECT substr(${normalizedIdExpression("id")}, 1, 8) AS run_id,
       substr(${normalizedIdExpression("memoId")}, 1, 8) AS memo_id,
       status,
       workflowName AS workflow,
       strftime('%Y-%m-%d %H:%M', createdAt) AS created_at,
       COALESCE(backendId, '') AS backend
FROM workflow_runs
ORDER BY datetime(createdAt) DESC
LIMIT ${limit};
`;
  writeStdout(runSqlite(databasePath, "table", sql));
}

function resolveMemoId(databasePath: string, lookup: string): string | undefined {
  const normalizedLookup = normalizedId(lookup);
  const sql = `
SELECT ${normalizedIdExpression("id")}
FROM voice_memos
WHERE deletedAt IS NULL
  AND (
    ${normalizedIdExpression("id")} = ${sqlText(normalizedLookup)}
    OR ${normalizedIdExpression("id")} LIKE ${sqlText(normalizedLookup)} || '%'
  )
ORDER BY datetime(createdAt) DESC
LIMIT 1;
`;

  const value = runSqlite(databasePath, "raw", sql).trim();
  return value.length > 0 ? value : undefined;
}

function requireDatabasePath(): string {
  const databasePath = requireEnvironmentValue("TALKIE_DATABASE_PATH");
  const displayPath =
    process.env.TALKIE_DATABASE_DISPLAY_PATH?.trim() || databasePath;

  if (!existsSync(databasePath)) {
    throw new ToolError(`Talkie database not found at ${displayPath}`);
  }

  return databasePath;
}

function requireTalkieExecutablePath(): string {
  const executablePath = requireEnvironmentValue("TALKIE_EXECUTABLE_PATH");

  if (!existsSync(executablePath)) {
    throw new ToolError(
      `Talkie executable not available for headless recovery at '${executablePath}'`,
    );
  }

  return executablePath;
}

function requireEnvironmentValue(name: string): string {
  const value = process.env[name]?.trim() ?? "";
  if (!value) {
    throw new ToolError(`Required environment variable '${name}' is missing.`);
  }
  return value;
}

function runSqlite(
  databasePath: string,
  mode: OutputMode,
  sql: string,
): string {
  const sqliteArgs = ["-readonly"];

  switch (mode) {
    case "table":
      sqliteArgs.push("-header", "-column");
      break;
    case "line":
      sqliteArgs.push("-line");
      break;
    case "raw":
      break;
  }

  sqliteArgs.push(databasePath);

  const result = spawnSync("sqlite3", sqliteArgs, {
    encoding: "utf8",
    input: sql,
  });

  if (result.error) {
    throw commandError(result.error, "sqlite3");
  }

  if ((result.status ?? 1) !== 0) {
    const message =
      result.stderr.trim() ||
      result.stdout.trim() ||
      `sqlite3 exited with status ${result.status ?? 1}`;
    throw new ToolError(message);
  }

  return result.stdout;
}

function commandError(error: Error, commandName: string): ToolError {
  const code = (error as NodeJS.ErrnoException).code;
  if (code === "ENOENT") {
    return new ToolError(`${commandName} is required but was not found on PATH.`);
  }

  return new ToolError(error.message);
}

function normalizedLimit(candidate: string | undefined, fallback: number): number {
  return isPositiveInteger(candidate) ? Number(candidate) : fallback;
}

function isPositiveInteger(value: string | undefined): value is string {
  return value !== undefined && /^[1-9]\d*$/.test(value);
}

function sqlText(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

function normalizedId(value: string): string {
  return value.toLowerCase().replaceAll("-", "");
}

function normalizedIdExpression(column: string): string {
  return `CASE
    WHEN typeof(${column}) = 'blob' THEN lower(hex(${column}))
    ELSE lower(replace(CAST(${column} AS TEXT), '-', ''))
  END`;
}

function uuidStringFromNormalizedId(value: string): string {
  if (value.length !== 32) {
    return value;
  }

  return [
    value.slice(0, 8),
    value.slice(8, 12),
    value.slice(12, 16),
    value.slice(16, 20),
    value.slice(20, 32),
  ].join("-");
}

function writeStdout(text: string) {
  if (text.length > 0) {
    process.stdout.write(text);
  }
}

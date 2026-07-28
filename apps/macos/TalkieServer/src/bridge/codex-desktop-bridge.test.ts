import { afterEach, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { listTasks } = require("./codex-desktop-bridge.cjs") as {
  listTasks: (limit: number) => Array<Record<string, unknown>>;
};

const originalCodexHome = process.env.CODEX_HOME;
let fixtureHome: string | undefined;

afterEach(() => {
  if (originalCodexHome === undefined) delete process.env.CODEX_HOME;
  else process.env.CODEX_HOME = originalCodexHome;
  if (fixtureHome) rmSync(fixtureHome, { recursive: true, force: true });
  fixtureHome = undefined;
});

describe("Codex task catalog", () => {
  test("returns recognizable user task identity and hides internal tasks", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-catalog-"));
    mkdirSync(fixtureHome, { recursive: true });
    process.env.CODEX_HOME = fixtureHome;

    const database = new Database(path.join(fixtureHome, "state_5.sqlite"), { create: true });
    database.exec(`
      CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        archived INTEGER NOT NULL,
        name TEXT,
        title TEXT NOT NULL,
        first_user_message TEXT NOT NULL,
        preview TEXT NOT NULL,
        cwd TEXT NOT NULL,
        git_branch TEXT,
        git_origin_url TEXT,
        agent_role TEXT,
        thread_source TEXT,
        recency_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    `);
    const insert = database.prepare(`
      INSERT INTO threads VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    insert.run(
      "user-task", "Add steer and queue support", "fallback title", "original request",
      "original request", "/Users/arach/.codex/worktrees/1234/talkie", "codex/deck",
      "https://github.com/arach/talkie.git", null, "user", 3000, 3000, 3,
    );
    insert.run(
      "subagent-task", "Background critique", "Background critique", "delegated work",
      "delegated work", "/Users/arach/dev/talkie", "codex/deck",
      "https://github.com/arach/talkie.git", "subagent", "subagent", 2000, 2000, 2,
    );
    insert.run(
      "empty-task", null, "Untitled", "", "", "/Users/arach/dev/talkie", null,
      null, null, "user", 1000, 1000, 1,
    );
    insert.run(
      "managed-agent", null, "[Base]\nYou are a managed agent", "[Base]\nYou are a managed agent",
      "[Base]\nYou are a managed agent", "/Users/arach/.buzz", null, null, null, null,
      500, 500, 1,
    );
    database.close();

    expect(listTasks(25)).toEqual([
      {
        id: "user-task",
        title: "Add steer and queue support",
        preview: "original request",
        cwd: "/Users/arach/.codex/worktrees/1234/talkie",
        gitBranch: "codex/deck",
        gitOriginURL: "https://github.com/arach/talkie.git",
        updatedAt: 3,
        project: "talkie",
      },
    ]);
  });
});

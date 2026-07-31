import { describe, expect, test } from "bun:test";
import { renderCodexStatusDocument } from "./codex-status-document";

describe("Codex status document", () => {
  test("renders public commentary separately from the final response", () => {
    const document = renderCodexStatusDocument({
      host: "studio-mac",
      renderedAt: new Date("2026-07-30T12:00:00Z"),
      task: {
        id: "task-1",
        title: "Polish status",
        preview: "Preview",
        cwd: "/Users/example/talkie",
        project: "talkie",
      },
      repository: {
        root: "/Users/example/talkie",
        branch: "codex/status",
        head: "12ab34cd",
        subject: "Polish status display",
        upstream: "origin/codex/status",
        ahead: 1,
        behind: 0,
        files: [{ path: "Status.swift", state: "M", additions: 8, deletions: 2 }],
        additions: 8,
        deletions: 2,
        clean: false,
      },
      turn: {
        id: "job-1",
        status: "running",
        mode: "steer",
        createdAt: "2026-07-30T11:58:00Z",
        updatedAt: "2026-07-30T11:59:00Z",
        updates: [
          { id: "note-1", kind: "commentary", text: "That sounds good." },
          { id: "tool-1", kind: "tool", text: "Built the status renderer." },
        ],
        response: "The implementation is ready.",
      },
      history: [
        {
          id: "turn-previous",
          status: "completed",
          startedAt: "2026-07-30T11:40:00Z",
          completedAt: "2026-07-30T11:45:00Z",
          durationMs: 300_000,
          instructions: ["Fix the stale route on the phone."],
          updates: [
            { id: "history-note", kind: "commentary", text: "Inspected the bridge route.", timestamp: "2026-07-30T11:41:00Z" },
            { id: "history-tool", kind: "tool", text: "PATCH APPLIED", timestamp: "2026-07-30T11:43:00Z" },
          ],
          response: "Fixed the stale route.\n\n<oai-mem-citation>internal metadata</oai-mem-citation>",
        },
      ],
    });

    expect(document).toContain("AGENT NOTE");
    expect(document).toContain("That sounds good.");
    expect(document).toContain("TOOL");
    expect(document).toContain("PREVIOUS RESPONSE");
    expect(document).toContain("The implementation is ready.");
    expect(document).toContain("WORK HISTORY");
    expect(document).toContain("<details class=\"history-turn\">");
    expect(document).toContain("YOU ASKED");
    expect(document).toContain("Fix the stale route on the phone.");
    expect(document).toContain("Inspected the bridge route.");
    expect(document).toContain("Fixed the stale route.");
    expect(document).toContain("Private reasoning is never included.");
    expect(document).not.toContain("internal metadata");
    expect(document).not.toContain("EVERYTHING TRACE");
  });

  test("escapes host data and ships a script-free constrained document", () => {
    const document = renderCodexStatusDocument({
      host: "<host>",
      task: {
        id: "task-1",
        title: "<script>alert('x')</script>",
        preview: "preview",
        cwd: "/tmp/<repo>",
        project: "talkie",
      },
      repository: {
        root: "/tmp/repo",
        branch: "main",
        head: "abc12345",
        subject: "subject",
        files: [],
        additions: 0,
        deletions: 0,
        clean: true,
      },
    });

    expect(document).toContain("Content-Security-Policy");
    expect(document).toContain("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;");
    expect(document).not.toContain("<script>");
    expect(document).not.toContain("<form");
    expect(document).not.toContain("href=");
  });
});

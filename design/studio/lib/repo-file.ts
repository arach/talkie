/**
 * Repo file reader for the engineering-doc code viewer.
 *
 * The viewer is read-only and only intended for files committed to
 * this repo. Two safety properties this module enforces:
 *
 *  1. The requested path, once resolved, must live INSIDE the repo
 *     root. A `..` traversal that escapes the root is rejected.
 *  2. Only files matching a known extension allowlist are served —
 *     no `.env`, no SQLite DBs, no binary blobs.
 *
 * If either check fails, callers get `null` and the page surfaces a
 * 404. We deliberately do not bubble up "why" — security errors are
 * the same shape as missing-file errors to the caller.
 */

import { readFile, stat } from "node:fs/promises";
import path from "node:path";

const REPO_ROOT = path.resolve(process.cwd(), "..", "..");

/** Extensions the viewer is willing to render. */
const ALLOWED_EXTENSIONS = new Set([
  "swift",
  "ts",
  "tsx",
  "js",
  "jsx",
  "mjs",
  "cjs",
  "md",
  "mdx",
  "json",
  "css",
  "scss",
  "html",
  "htm",
  "sh",
  "bash",
  "zsh",
  "yaml",
  "yml",
  "toml",
  "txt",
]);

/** ~512 KB upper bound — keeps the viewer responsive and avoids loading
 *  huge generated files into the browser. */
const MAX_BYTES = 512 * 1024;

export interface RepoFile {
  relativePath: string;
  filename: string;
  content: string;
  truncated: boolean;
  bytes: number;
}

export async function loadRepoFile(parts: string[]): Promise<RepoFile | null> {
  if (parts.length === 0) return null;

  const requested = parts.map((p) => decodeURIComponent(p)).join("/");
  const resolved = path.resolve(REPO_ROOT, requested);

  // Containment check — `path.resolve` collapses `..` so this catches
  // both `../etc/passwd` and absolute-path tricks.
  const relative = path.relative(REPO_ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) return null;

  // Extension allowlist.
  const ext = path.extname(resolved).slice(1).toLowerCase();
  if (!ALLOWED_EXTENSIONS.has(ext)) return null;

  try {
    const stats = await stat(resolved);
    if (!stats.isFile()) return null;
    const truncated = stats.size > MAX_BYTES;

    // readFile with `encoding` returns a string; if the file is binary
    // it still tries to decode as UTF-8 and we end up with replacement
    // chars. The extension allowlist already filters obvious binaries.
    const raw = await readFile(resolved, { encoding: "utf8" });
    const content = truncated ? raw.slice(0, MAX_BYTES) : raw;

    return {
      relativePath: relative,
      filename: path.basename(resolved),
      content,
      truncated,
      bytes: stats.size,
    };
  } catch {
    return null;
  }
}

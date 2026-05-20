/**
 * Swift-hint extractor.
 *
 * Scans the studio source for inline annotations and emits a porting
 * checklist grouped by file. Annotations are intentionally lightweight
 * — designers leave breadcrumbs while iterating, the script aggregates
 * them so whoever ports to Swift has a per-surface punch list.
 *
 * Annotation forms (all equivalent):
 *
 *   JSX:        {\/* swift: VStack(spacing: 12) *\/}
 *   TS/TSX:     /\* swift: padding(.horizontal, 16) *\/
 *   line:       // swift: foregroundStyle(scheme.trace)
 *
 * Prefix any annotation with `TODO ` (e.g. `swift: TODO — port not started`)
 * to flag it as unfinished — those land in a separate section.
 *
 * Run from design/studio/:
 *   bun run swift:hints                  # writes PORTING.md
 *   bun run swift:hints --out -          # prints to stdout
 *   bun run swift:hints --format json    # emits JSON instead
 */

import { readdirSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const STUDIO_ROOT = resolve(HERE, "..");
const SCAN_DIRS = ["app", "components", "lib"];
const EXTENSIONS = new Set([".ts", ".tsx"]);
const DEFAULT_OUT = resolve(STUDIO_ROOT, "PORTING.md");

interface Hint {
  file: string; // path relative to studio root, posix slashes
  line: number;
  text: string;
  todo: boolean;
}

// Match both block-comment and line-comment swift hints. JSX block comments
// are just regular block comments wrapped in `{...}`, so the inner pattern
// catches them too.
const BLOCK_RE = /\/\*\s*swift:\s*([\s\S]*?)\s*\*\//g;
const LINE_RE = /\/\/\s*swift:\s*(.*)$/;

function walk(dir: string): string[] {
  const out: string[] = [];
  const entries = readdirSync(dir);
  for (const entry of entries) {
    if (entry === "node_modules" || entry.startsWith(".")) continue;
    const full = resolve(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      out.push(...walk(full));
    } else {
      const dot = entry.lastIndexOf(".");
      const ext = dot >= 0 ? entry.slice(dot) : "";
      if (EXTENSIONS.has(ext)) out.push(full);
    }
  }
  return out;
}

function toPosix(path: string): string {
  return path.split(sep).join("/");
}

function scanFile(path: string): Hint[] {
  const content = readFileSync(path, "utf8");
  const rel = toPosix(relative(STUDIO_ROOT, path));
  const hints: Hint[] = [];

  // Block comments — may span multiple lines. Use offsets to recover line numbers.
  const lineOffsets = computeLineOffsets(content);
  BLOCK_RE.lastIndex = 0;
  let blockMatch: RegExpExecArray | null;
  while ((blockMatch = BLOCK_RE.exec(content)) !== null) {
    const line = lineFromOffset(lineOffsets, blockMatch.index);
    const text = normalizeText(blockMatch[1]);
    hints.push({ file: rel, line, text, todo: isTodo(text) });
  }

  // Line comments — one per line, easy.
  content.split("\n").forEach((rawLine, i) => {
    const m = rawLine.match(LINE_RE);
    if (m) {
      const text = m[1].trim();
      hints.push({ file: rel, line: i + 1, text, todo: isTodo(text) });
    }
  });

  return hints.sort((a, b) => a.line - b.line);
}

function computeLineOffsets(content: string): number[] {
  const offsets = [0];
  for (let i = 0; i < content.length; i++) {
    if (content[i] === "\n") offsets.push(i + 1);
  }
  return offsets;
}

function lineFromOffset(offsets: number[], offset: number): number {
  // Binary search for the largest offset ≤ `offset`.
  let lo = 0;
  let hi = offsets.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >>> 1;
    if (offsets[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}

function normalizeText(s: string): string {
  // Collapse multi-line block bodies into a single line.
  return s.replace(/\s*\n\s*\*?\s*/g, " ").trim();
}

function isTodo(text: string): boolean {
  return /^(TODO|FIXME)\b/i.test(text);
}

function renderMarkdown(hints: Hint[]): string {
  if (hints.length === 0) {
    return [
      "# Studio → Swift porting hints",
      "",
      "_No hints found yet._",
      "",
      "Drop annotations into TSX files to populate this file:",
      "",
      "```tsx",
      "{/* swift: VStack(spacing: 12) */}",
      "{/* swift: TODO — port not started */}",
      "```",
      "",
      "Regenerate via `bun run swift:hints`.",
      "",
    ].join("\n");
  }

  const todos = hints.filter((h) => h.todo);
  const live = hints.filter((h) => !h.todo);

  const sections: string[] = [
    "# Studio → Swift porting hints",
    "",
    `_Generated ${new Date().toISOString()} · ${hints.length} hint${hints.length === 1 ? "" : "s"} across ${countFiles(hints)} file${countFiles(hints) === 1 ? "" : "s"}._`,
    "",
    "Regenerate via `bun run swift:hints` from `design/studio/`.",
    "",
  ];

  if (todos.length > 0) {
    sections.push("## TODO", "");
    sections.push(...renderHintGroup(todos));
    sections.push("");
  }

  sections.push("## Hints by surface", "");
  sections.push(...renderHintGroup(live));

  return sections.join("\n") + "\n";
}

function renderHintGroup(hints: Hint[]): string[] {
  const byFile = new Map<string, Hint[]>();
  for (const h of hints) {
    if (!byFile.has(h.file)) byFile.set(h.file, []);
    byFile.get(h.file)!.push(h);
  }
  const out: string[] = [];
  const fileOrder = [...byFile.keys()].sort();
  for (const file of fileOrder) {
    out.push(`### \`${file}\``);
    out.push("");
    for (const h of byFile.get(file)!) {
      out.push(`- **L${h.line}** — ${h.text}`);
    }
    out.push("");
  }
  return out;
}

function countFiles(hints: Hint[]): number {
  return new Set(hints.map((h) => h.file)).size;
}

function parseArgs(argv: string[]): { out: string | null; format: "md" | "json" } {
  let out: string | null = DEFAULT_OUT;
  let format: "md" | "json" = "md";
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--out") {
      const value = argv[++i];
      if (value === undefined) throw new Error("--out requires a value");
      out = value === "-" ? null : resolve(STUDIO_ROOT, value);
    } else if (arg === "--format") {
      const value = argv[++i];
      if (value !== "md" && value !== "json") throw new Error("--format must be md|json");
      format = value;
    } else {
      throw new Error(`unknown arg: ${arg}`);
    }
  }
  return { out, format };
}

function main(): void {
  const { out, format } = parseArgs(process.argv.slice(2));

  const files: string[] = [];
  for (const dir of SCAN_DIRS) {
    const full = resolve(STUDIO_ROOT, dir);
    try {
      statSync(full);
      files.push(...walk(full));
    } catch {
      // dir missing — skip silently
    }
  }

  const hints = files.flatMap(scanFile);

  const rendered =
    format === "json"
      ? JSON.stringify({ generatedAt: new Date().toISOString(), hints }, null, 2) + "\n"
      : renderMarkdown(hints);

  if (out === null) {
    process.stdout.write(rendered);
  } else {
    writeFileSync(out, rendered);
    console.log(`swift:hints  ${hints.length} hint(s) → ${toPosix(relative(STUDIO_ROOT, out))}`);
  }
}

main();

/**
 * TLK-NNN engineering doc loader.
 *
 * Source of truth lives at `<repo>/docs/specs/tlk-NNN-*.md`. We read
 * those files at request time and parse the conventional header block:
 *
 *   # TLK-NNN — Title
 *
 *   **Status**: Draft | Accepted | Implemented | Deprecated
 *   **Owner**: name | TBD
 *   **Branch context**: optional
 *
 *   ## Summary
 *   …first paragraph…
 *
 * No third-party frontmatter parser — the format is small enough that a
 * tight string parser keeps the dep footprint minimal and the structure
 * visible. If the doc shape drifts, this file is the one place to fix.
 */

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const SPECS_DIR = path.join(process.cwd(), "..", "..", "docs", "specs");

export type TlkStatus =
  | "draft"
  | "accepted"
  | "implemented"
  | "deprecated"
  | "unknown";

export type DocTag = "iOS" | "macOS" | "shared";

export interface EngDocMeta {
  /** Slug used in the URL — `tlk-019`. */
  slug: string;
  /** Numeric portion — `19`. Drives sort order. */
  number: number;
  /** Title without the `TLK-NNN —` prefix. */
  title: string;
  /** Raw status text from the doc; lowercased for the parsed variant. */
  statusRaw: string;
  status: TlkStatus;
  owner: string;
  /** Optional one-line subtitle from a `**Subtitle**: text` header
   *  field. Surfaces in the data sheet between Title and Summary. */
  subtitle: string | null;
  /** Derived platform tag — inferred from title until specs add explicit tags. */
  tag: DocTag;
  /** First paragraph of the `## Summary` section, plain-text-ish. */
  summary: string;
}

export interface HeaderSection {
  /** Uppercase label rendered in the data-sheet grid. */
  label: string;
  /** Markdown body of the section, without the `##` heading line. */
  body: string;
}

export interface EngDoc extends EngDocMeta {
  /** Markdown body with the title, metadata block, and any extracted
   *  header sections removed. */
  body: string;
  /** Sections lifted into the page's data-sheet header. Order is the
   *  configured order (`HEADER_SECTIONS`), not source-doc order. */
  headerSections: HeaderSection[];
}

/** Sections worth promoting into the data-sheet header. Matching is
 *  case-insensitive and lenient on trailing `s` / qualifiers — e.g.
 *  `Goals` and `Decisions required` both match. Order here is the
 *  rendered order in the header. */
const HEADER_SECTION_PATTERNS: Array<{ label: string; match: RegExp }> = [
  { label: "Summary", match: /^summary\s*$/i },
  { label: "Goal", match: /^goals?(?:\s|$)/i },
  { label: "Decision", match: /^decisions?(?:\s|$)/i },
];

const FILENAME_RE = /^tlk-(\d{3})-.*\.md$/;

export async function listEngDocs(): Promise<EngDocMeta[]> {
  const entries = await readdir(SPECS_DIR);
  const tlkFiles = entries.filter((f) => FILENAME_RE.test(f));

  const docs = await Promise.all(
    tlkFiles.map(async (filename) => {
      const raw = await readFile(path.join(SPECS_DIR, filename), "utf8");
      const slug = filename.replace(/\.md$/, "").replace(/^(tlk-\d{3}).*$/, "$1");
      const match = filename.match(FILENAME_RE);
      const number = match ? parseInt(match[1], 10) : 0;
      return parseHeader(raw, slug, number);
    })
  );

  return docs.sort((a, b) => a.number - b.number);
}

export async function getEngDoc(slug: string): Promise<EngDoc | null> {
  const match = slug.match(/^tlk-(\d{3})$/);
  if (!match) return null;
  const number = parseInt(match[1], 10);

  const entries = await readdir(SPECS_DIR);
  const filename = entries.find((f) => f.startsWith(`${slug}-`) && f.endsWith(".md"));
  if (!filename) return null;

  const raw = await readFile(path.join(SPECS_DIR, filename), "utf8");
  const meta = parseHeader(raw, slug, number);
  const stripped = stripTitleLine(raw);
  const { headerSections, rest } = splitOutHeaderSections(stripped);
  return { ...meta, body: rest, headerSections };
}

interface SectionMatch {
  /** Where the `##` heading line starts. */
  start: number;
  /** Where the section body starts (first char after the heading newline). */
  bodyStart: number;
  /** Where the section ends — either the next `##` heading or EOF. */
  end: number;
  /** Label assigned by the pattern table. */
  label: string;
}

function splitOutHeaderSections(input: string): {
  headerSections: HeaderSection[];
  rest: string;
} {
  const headings = findAllH2Headings(input);
  const matched: SectionMatch[] = [];

  for (let i = 0; i < headings.length; i++) {
    const h = headings[i];
    const next = headings[i + 1];
    const label = labelFor(h.text);
    if (!label) continue;
    matched.push({
      start: h.start,
      bodyStart: h.bodyStart,
      end: next ? next.start : input.length,
      label,
    });
  }

  if (matched.length === 0) return { headerSections: [], rest: input };

  // Build the rest of the body by stitching together the spans NOT in
  // any matched section. Walk forward through the matches.
  let rest = "";
  let cursor = 0;
  for (const m of matched) {
    rest += input.slice(cursor, m.start);
    cursor = m.end;
  }
  rest += input.slice(cursor);
  rest = rest.replace(/^\s*\n+/, "").replace(/\n{3,}/g, "\n\n");

  // Re-order matches by the configured pattern order so the data sheet
  // reads Summary → Goal → Decision regardless of how the doc orders them.
  const order = new Map(
    HEADER_SECTION_PATTERNS.map((p, i) => [p.label, i] as const)
  );
  matched.sort(
    (a, b) =>
      (order.get(a.label) ?? Infinity) - (order.get(b.label) ?? Infinity)
  );

  const headerSections: HeaderSection[] = matched.map((m) => ({
    label: m.label,
    body: input.slice(m.bodyStart, m.end).trim(),
  }));

  return { headerSections, rest };
}

interface H2 {
  start: number;
  bodyStart: number;
  text: string;
}

function findAllH2Headings(input: string): H2[] {
  const re = /^##\s+(.+?)\s*$/gm;
  const out: H2[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(input))) {
    const lineEnd = input.indexOf("\n", m.index);
    out.push({
      start: m.index,
      bodyStart: lineEnd === -1 ? input.length : lineEnd + 1,
      text: m[1],
    });
  }
  return out;
}

function labelFor(headingText: string): string | null {
  for (const p of HEADER_SECTION_PATTERNS) {
    if (p.match.test(headingText.trim())) return p.label;
  }
  return null;
}

function parseHeader(raw: string, slug: string, number: number): EngDocMeta {
  const titleMatch = raw.match(/^#\s+TLK-\d{3}\s*[—-]\s*(.+?)\s*$/m);
  const title = titleMatch ? titleMatch[1] : slug;

  const statusRaw = matchField(raw, "Status") ?? "Unknown";
  const owner = matchField(raw, "Owner") ?? "TBD";
  const status = normalizeStatus(statusRaw);
  const subtitle = matchField(raw, "Subtitle");
  const tag = inferTag(title);
  const summary = extractSummary(raw);

  return { slug, number, title, statusRaw, status, owner, subtitle, tag, summary };
}

function inferTag(title: string): DocTag {
  const t = title.toLowerCase();
  if (t.includes("ios") || t.includes("keyboard")) return "iOS";
  if (t.includes("macos")) return "macOS";
  return "shared";
}

function matchField(raw: string, name: string): string | null {
  // Matches `**Name**: value` (lenient on whitespace) on its own line.
  const re = new RegExp(`^\\*\\*${name}\\*\\*\\s*:\\s*(.+?)\\s*$`, "m");
  const m = raw.match(re);
  return m ? m[1] : null;
}

function normalizeStatus(raw: string): TlkStatus {
  const k = raw.trim().toLowerCase();
  if (k.startsWith("draft")) return "draft";
  if (k.startsWith("accepted")) return "accepted";
  if (k.startsWith("implemented") || k.startsWith("shipped")) return "implemented";
  if (k.startsWith("deprecated") || k.startsWith("archived")) return "deprecated";
  return "unknown";
}

function extractSummary(raw: string): string {
  const start = raw.search(/^##\s+Summary\s*$/m);
  if (start < 0) return "";
  // Skip past the heading line.
  const afterHeading = raw.indexOf("\n", start);
  if (afterHeading < 0) return "";
  const rest = raw.slice(afterHeading + 1);

  // Walk paragraphs; first one with prose content wins. Skip empties and
  // lines that are pure markdown noise (lists, tables, code fences).
  const paragraphs = rest.split(/\n{2,}/);
  for (const p of paragraphs) {
    const trimmed = p.trim();
    if (!trimmed) continue;
    if (trimmed.startsWith("##")) break; // next section, no prose found
    if (trimmed.startsWith("```")) continue;
    if (trimmed.startsWith("|")) continue;
    if (/^[-*]\s/.test(trimmed)) continue;
    return collapseWhitespace(trimmed);
  }
  return "";
}

function collapseWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function stripTitleLine(raw: string): string {
  // Drop the leading `# TLK-NNN — Title` heading.
  let out = raw.replace(/^#\s+TLK-\d{3}.*?\n+/, "");
  // Then drop the immediately-following metadata block — consecutive
  // `**Field**: value` lines (Status, Owner, Branch context, …). These
  // are already shown in the page header, so leaving them in the body
  // double-prints. Stop at the first blank line.
  out = out.replace(/^(?:\*\*[^*]+\*\*\s*:.*\n)+\s*\n/, "");
  return out;
}

export function statusPalette(
  status: TlkStatus
): { fg: string; bg: string; label: string } {
  switch (status) {
    case "draft":
      return { fg: "#7A4A0E", bg: "#F5E6CC", label: "DRAFT" };
    case "accepted":
      return { fg: "#1F5A2E", bg: "#E2F0E5", label: "ACCEPTED" };
    case "implemented":
      return { fg: "#1F4A6A", bg: "#DDE9F4", label: "IMPLEMENTED" };
    case "deprecated":
      return { fg: "#8A3030", bg: "#F0DCDC", label: "DEPRECATED" };
    case "unknown":
      return { fg: "#5A554C", bg: "#ECECEB", label: "UNKNOWN" };
  }
}

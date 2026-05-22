/**
 * Studio → Swift token export.
 *
 * Reads the design tokens that live in studio (`lib/schemes.ts`,
 * `lib/themes.ts`) and emits Swift data files so Talkie macOS/iOS
 * consume the same source of truth instead of hand-transcribing hex
 * values from JSX.
 *
 * Outputs:
 *   apps/macos/Talkie/Views/Home/SchemeTokens.swift
 *   apps/ios/Talkie iOS/Resources/StudioThemeMeta.generated.json
 *
 * Run from design/studio/:
 *   bun run tokens:export
 *
 * The macOS file is picked up automatically by xcodegen (Views/ is a
 * directory glob in project.yml). The iOS metadata is emitted as JSON
 * for now since iOS chrome tokens diverge from `themes.ts`; once they
 * align we can switch iOS to a Swift emit too.
 */

import { SCHEMES, type Scheme } from "../lib/schemes";
import { IOS_THEMES, type IOSTheme } from "../lib/themes";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, "../../../");

const MAC_SCHEME_OUT = resolve(
  REPO_ROOT,
  "apps/macos/Talkie/Views/Home/SchemeTokens.swift",
);
const IOS_THEME_OUT = resolve(
  REPO_ROOT,
  "apps/ios/Talkie iOS/Resources/ThemeMeta.generated.json",
);

// ─────────────────────────────────────────────────────────────────────────
// CSS value parsers
// ─────────────────────────────────────────────────────────────────────────

interface RGBA { r: number; g: number; b: number; a: number }
interface GradientStop { hex: string; location: number }

function parseHex(value: string): string {
  const m = value.trim().match(/^#([0-9a-fA-F]{6})$/);
  if (!m) throw new Error(`Expected #RRGGBB, got: ${value}`);
  return m[1].toUpperCase();
}

function parseRGBA(value: string): RGBA {
  const v = value.trim();
  const m = v.match(
    /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$/,
  );
  if (!m) throw new Error(`Expected rgb()/rgba(), got: ${value}`);
  return {
    r: +m[1],
    g: +m[2],
    b: +m[3],
    a: m[4] !== undefined ? +m[4] : 1,
  };
}

function parseLinearGradientStops(value: string): GradientStop[] {
  const v = value.trim();
  const m = v.match(/^linear-gradient\(\s*to\s+bottom\s*,\s*(.+)\)\s*$/);
  if (!m) throw new Error(`Expected 'linear-gradient(to bottom, ...)': ${value}`);
  const parts = m[1].split(/\s*,\s*(?![^()]*\))/);
  return parts.map((part) => {
    const sm = part.trim().match(/^#([0-9a-fA-F]{6})\s+([\d.]+)%$/);
    if (!sm) throw new Error(`Unsupported gradient stop: ${part}`);
    return { hex: sm[1].toUpperCase(), location: +sm[2] / 100 };
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Swift emitters
// ─────────────────────────────────────────────────────────────────────────

function swiftRGBA(rgba: RGBA): string {
  const a = Number(rgba.a.toFixed(4));
  return `RGBAColor(r: ${rgba.r}, g: ${rgba.g}, b: ${rgba.b}, a: ${a})`;
}

function swiftHex(hex: string): string {
  return `"${hex}"`;
}

function swiftStops(stops: GradientStop[], indent: string): string {
  if (stops.length === 0) return "[]";
  const inner = stops
    .map((s) => `${indent}    GradientStop(hex: "${s.hex}", location: ${s.location}),`)
    .join("\n");
  return `[\n${inner}\n${indent}]`;
}

function escapeSwiftString(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function swiftSchemeLiteral(scheme: Scheme, indent: string): string {
  const v = scheme.vars;
  const need = (k: string) => {
    const x = v[k];
    if (x === undefined) throw new Error(`scheme ${scheme.key} missing ${k}`);
    return x;
  };
  const fieldIndent = `${indent}    `;
  const fields: [string, string][] = [
    ["key", `"${scheme.key}"`],
    ["name", `"${escapeSwiftString(scheme.name)}"`],
    ["swatchHex", swiftHex(parseHex(scheme.swatch))],
    ["bgHex", swiftHex(parseHex(scheme.bgHex))],
    ["stripTop", swiftStops(parseLinearGradientStops(need("--scheme-strip-top")), fieldIndent)],
    ["stripBottom", swiftStops(parseLinearGradientStops(need("--scheme-strip-bottom")), fieldIndent)],
    ["graticule", swiftRGBA(parseRGBA(need("--scheme-graticule")))],
    ["inkHex", swiftHex(parseHex(need("--scheme-ink")))],
    ["inkFaintHex", swiftHex(parseHex(need("--scheme-ink-faint")))],
    ["inkSubtleHex", swiftHex(parseHex(need("--scheme-ink-subtle")))],
    ["accentHex", swiftHex(parseHex(need("--scheme-accent")))],
    ["accentGlow", swiftRGBA(parseRGBA(need("--scheme-accent-glow")))],
    ["accentRing", swiftRGBA(parseRGBA(need("--scheme-accent-ring")))],
    ["traceHex", swiftHex(parseHex(need("--scheme-trace")))],
    ["recHex", swiftHex(parseHex(need("--scheme-rec")))],
    ["recGlow", swiftRGBA(parseRGBA(need("--scheme-rec-glow")))],
    ["sparkleHex", swiftHex(parseHex(need("--scheme-sparkle")))],
    ["edge", swiftRGBA(parseRGBA(need("--scheme-edge")))],
    ["edgeStrong", swiftRGBA(parseRGBA(need("--scheme-edge-strong")))],
    ["detailsBg", swiftRGBA(parseRGBA(need("--scheme-details-bg")))],
    ["bezelHighlight", swiftRGBA(parseRGBA(need("--scheme-bezel-highlight")))],
    ["bezelShadow", swiftRGBA(parseRGBA(need("--scheme-bezel-shadow")))],
  ];
  // Swift 5 disallows trailing commas in initializer argument lists, so the
  // last field is emitted without one.
  const body = fields
    .map(([k, val], i) => `${fieldIndent}${k}: ${val}${i === fields.length - 1 ? "" : ","}`)
    .join("\n");
  return `SchemeTokens(\n${body}\n${indent})`;
}

function generateMacSchemesSwift(schemes: Scheme[]): string {
  const entryIndent = "        ";
  const entries = schemes
    .map((s) => `${entryIndent}"${s.key}": ${swiftSchemeLiteral(s, entryIndent)},`)
    .join("\n");

  return `// Auto-generated palette tokens. Do not edit by hand — values are
// regenerated from the design source and manual changes will be lost.

import SwiftUI

public struct GradientStop: Equatable, Sendable {
    public let hex: String
    public let location: Double
}

public struct RGBAColor: Equatable, Sendable {
    public let r: Int
    public let g: Int
    public let b: Int
    public let a: Double

    public var color: Color {
        Color(.sRGB,
              red: Double(r) / 255.0,
              green: Double(g) / 255.0,
              blue: Double(b) / 255.0,
              opacity: a)
    }
}

public struct SchemeTokens: Equatable, Sendable {
    public let key: String
    public let name: String
    public let swatchHex: String
    public let bgHex: String
    public let stripTop: [GradientStop]
    public let stripBottom: [GradientStop]
    public let graticule: RGBAColor
    public let inkHex: String
    public let inkFaintHex: String
    public let inkSubtleHex: String
    public let accentHex: String
    public let accentGlow: RGBAColor
    public let accentRing: RGBAColor
    public let traceHex: String
    public let recHex: String
    public let recGlow: RGBAColor
    public let sparkleHex: String
    public let edge: RGBAColor
    public let edgeStrong: RGBAColor
    public let detailsBg: RGBAColor
    public let bezelHighlight: RGBAColor
    public let bezelShadow: RGBAColor
}

public enum Palette: String, CaseIterable, Sendable {
${schemes.map((s) => `    case ${s.key}`).join("\n")}

    public var tokens: SchemeTokens {
        Self.tokensByKey[rawValue]!
    }

    public static let tokensByKey: [String: SchemeTokens] = [
${entries}
    ]
}
`;
}

// ─────────────────────────────────────────────────────────────────────────
// iOS theme metadata (JSON for now — see file header)
// ─────────────────────────────────────────────────────────────────────────

function serializeThemes(themes: IOSTheme[]): string {
  const payload = {
    themes: themes.map((t) => ({
      key: t.key,
      name: t.name,
      identity: t.identity,
      blurb: t.blurb,
      canvasHex: t.canvasHex,
      accentHex: t.accentHex,
      display: t.display,
      behavior: t.behavior,
      preview: t.preview,
    })),
  };
  return JSON.stringify(payload, null, 2) + "\n";
}

// ─────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────

function writeFile(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  console.log(`  wrote ${path}`);
}

function main(): void {
  console.log("studio → native token export");
  console.log(`  ${SCHEMES.length} schemes, ${IOS_THEMES.length} themes`);

  writeFile(MAC_SCHEME_OUT, generateMacSchemesSwift(SCHEMES));
  writeFile(IOS_THEME_OUT, serializeThemes(IOS_THEMES));

  console.log("done.");
}

main();

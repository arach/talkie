"use client";

/**
 * Shared LED dot-matrix board — the fit engine + the DotMatrix renderer.
 *
 * Extracted from LEDMessenger.tsx so every LED surface in the studio
 * (/led-messenger, /cockpit-grid) writes through the SAME board: one fit
 * engine (greedy word-wrap → pitch-shrink), one DotMatrix, one glyph table
 * (./ledFont). Nothing here animates — the board writes, it never scrolls.
 *
 * The Board is frozen at a content width × height. Callers may pass their own
 * box: the messenger uses the full 366-panel width (BOARD_W/BOARD_H), the
 * cockpit grid passes its narrower message-deck box. Material knobs resize the
 * dots WITHIN the box; they never change the box.
 */

import {
  GLYPH_COLS,
  GLYPH_ROWS,
  LED_PALETTE,
  PLACEHOLDER_ROWS,
  glyphRows,
  hasGlyph,
} from "./ledFont";

// ── Dot palette — amber lit / faint ghost / dim placeholder ──────────────
const DOT = {
  accent: LED_PALETTE.accent, // #FF8800 — a lit dot
  ghost: "rgba(255,136,0,0.065)", // unlit dot — faint amber phosphor
  placeholder: "rgba(255,136,0,0.26)", // unsupported-glyph dot
} as const;

// ── The Board is frozen at true iPhone content width by default. ─────────
export const BOARD_W = 338; // px — dot-matrix content width (366 panel − padding)
export const BOARD_H = 96; // px — dot-matrix content height
export const LINE_GAP_ROWS = 2; // blank matrix rows between wrapped text lines

export type Pitch = "fine" | "medium" | "coarse";
export type Shape = "round" | "square";

/** Base dot diameter per Pitch material (Fit may shrink below this). */
export const PITCH_PX: Record<Pitch, number> = { fine: 2, medium: 3, coarse: 4 };

export interface Material {
  pitch: Pitch;
  shape: Shape;
  bloom: boolean;
  ghost: boolean;
}

export interface Board {
  dotSize: number;
  dotGap: number;
  cols: number;
  rows: number;
  grid: number[][]; // 0 = off · 1 = lit · 2 = placeholder
  lines: string[];
  wrapped: boolean;
  shrunk: boolean;
  overflow: boolean;
}

// ─────────────────────────────────────────────────────────────────────────
//  Fit — wrap + shrink so any message lands inside the frozen Board.
// ─────────────────────────────────────────────────────────────────────────

function dotGapFor(dotSize: number): number {
  return dotSize >= 4 ? 2 : 1;
}

/** How many glyphs fit on one line at a given matrix width (5 cols + 1 gap). */
function charsPerLineFor(cols: number): number {
  return Math.max(1, Math.floor((cols + 1) / (GLYPH_COLS + 1)));
}

/** Greedy word-wrap. Hard-breaks any single word longer than a line. */
function wrapLines(text: string, charsPerLine: number): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  if (words.length === 0) return [""];
  const lines: string[] = [];
  let cur = "";
  for (const raw of words) {
    let word = raw;
    while (word.length > charsPerLine) {
      if (cur) {
        lines.push(cur);
        cur = "";
      }
      lines.push(word.slice(0, charsPerLine));
      word = word.slice(charsPerLine);
    }
    if (!cur) cur = word;
    else if (cur.length + 1 + word.length <= charsPerLine) cur += " " + word;
    else {
      lines.push(cur);
      cur = word;
    }
  }
  if (cur) lines.push(cur);
  return lines;
}

/** Compose the cols×rows dot matrix, centering the text block. */
function buildGrid(lines: string[], cols: number, rows: number): number[][] {
  const grid: number[][] = Array.from({ length: rows }, () =>
    new Array<number>(cols).fill(0)
  );
  const textRows =
    lines.length * GLYPH_ROWS + (lines.length - 1) * LINE_GAP_ROWS;
  const startRow = Math.max(0, Math.floor((rows - textRows) / 2));
  lines.forEach((line, li) => {
    const rowBase = startRow + li * (GLYPH_ROWS + LINE_GAP_ROWS);
    const lineCols = line.length > 0 ? line.length * (GLYPH_COLS + 1) - 1 : 0;
    let col = Math.max(0, Math.floor((cols - lineCols) / 2));
    for (const ch of line) {
      const known = hasGlyph(ch);
      const rowsArr = known ? glyphRows(ch) : PLACEHOLDER_ROWS;
      const value = known ? 1 : 2;
      for (let r = 0; r < GLYPH_ROWS; r++) {
        const rr = rowBase + r;
        if (rr < 0 || rr >= rows) continue;
        const rowStr = rowsArr[r];
        for (let c = 0; c < GLYPH_COLS; c++) {
          if (rowStr[c] === "1") {
            const cc = col + c;
            if (cc >= 0 && cc < cols) grid[rr][cc] = value;
          }
        }
      }
      col += GLYPH_COLS + 1;
    }
  });
  return grid;
}

function boardAt(text: string, dotSize: number, boardW: number, boardH: number) {
  const dotGap = dotGapFor(dotSize);
  const cellPitch = dotSize + dotGap;
  const cols = Math.max(1, Math.floor((boardW + dotGap) / cellPitch));
  const rows = Math.max(1, Math.floor((boardH + dotGap) / cellPitch));
  const lines = wrapLines(text, charsPerLineFor(cols));
  const textRows =
    lines.length * GLYPH_ROWS + (lines.length - 1) * LINE_GAP_ROWS;
  const fits = textRows <= rows;
  return { fits, dotSize, dotGap, cols, rows, lines };
}

/**
 * Fit a message to the Board: try the material's Pitch first, then step the
 * dot size down until the wrapped text fits the fixed content box.
 */
export function computeBoard(
  text: string,
  basePitch: number,
  boardW: number = BOARD_W,
  boardH: number = BOARD_H
): Board {
  const upper = text.toUpperCase();
  for (let dotSize = basePitch; dotSize >= 1; dotSize--) {
    const b = boardAt(upper, dotSize, boardW, boardH);
    if (b.fits || dotSize === 1) {
      return {
        dotSize: b.dotSize,
        dotGap: b.dotGap,
        cols: b.cols,
        rows: b.rows,
        grid: buildGrid(b.lines, b.cols, b.rows),
        lines: b.lines,
        wrapped: b.lines.length > 1,
        shrunk: b.dotSize < basePitch,
        overflow: !b.fits,
      };
    }
  }
  // Unreachable (the dotSize === 1 branch always returns), but keeps TS happy.
  const b = boardAt(upper, 1, boardW, boardH);
  return {
    dotSize: 1,
    dotGap: b.dotGap,
    cols: b.cols,
    rows: b.rows,
    grid: buildGrid(b.lines, b.cols, b.rows),
    lines: b.lines,
    wrapped: b.lines.length > 1,
    shrunk: basePitch > 1,
    overflow: !b.fits,
  };
}

/** A single lit ellipsis glyph marks a truncated single-line readout. */
const ELLIPSIS = "…";

/**
 * Fit a message to a SINGLE-LINE readout strip — no word-wrap, ever.
 *
 * Try the base Pitch first, then step the dot size down until every glyph
 * lands on ONE line. If the message still overflows at the minimum pitch,
 * truncate it and mark the cut with a lit ellipsis (`overflow: true`, so the
 * caller can also fade the right edge). The strip height is frozen: long
 * messages shrink + truncate, they never wrap or grow. Callers that want the
 * wrapping multi-line board keep using `computeBoard` — its output is unchanged.
 */
export function computeLine(
  text: string,
  basePitch: number,
  boardW: number = BOARD_W,
  boardH: number = BOARD_H
): Board {
  const upper = text.toUpperCase();
  for (let dotSize = basePitch; dotSize >= 1; dotSize--) {
    const dotGap = dotGapFor(dotSize);
    const cellPitch = dotSize + dotGap;
    const cols = Math.max(1, Math.floor((boardW + dotGap) / cellPitch));
    // Keep at least one glyph row's worth of matrix rows so buildGrid never
    // clips the 7-row glyphs vertically, whatever the strip height is.
    const rows = Math.max(GLYPH_ROWS, Math.floor((boardH + dotGap) / cellPitch));
    const perLine = charsPerLineFor(cols);
    const fits = upper.length <= perLine;
    if (fits || dotSize === 1) {
      let line = upper;
      const truncated = !fits;
      if (truncated) {
        const keep = Math.max(0, perLine - 1); // leave one cell for the ellipsis
        line = upper.slice(0, keep).replace(/\s+$/, "") + ELLIPSIS;
      }
      return {
        dotSize,
        dotGap,
        cols,
        rows,
        grid: buildGrid([line], cols, rows),
        lines: [line],
        wrapped: false,
        shrunk: dotSize < basePitch,
        overflow: truncated,
      };
    }
  }
  // Unreachable (the dotSize === 1 branch always returns), but keeps TS happy.
  const dotGap = dotGapFor(1);
  const cellPitch = 1 + dotGap;
  const cols = Math.max(1, Math.floor((boardW + dotGap) / cellPitch));
  const rows = Math.max(GLYPH_ROWS, Math.floor((boardH + dotGap) / cellPitch));
  return {
    dotSize: 1,
    dotGap,
    cols,
    rows,
    grid: buildGrid([upper], cols, rows),
    lines: [upper],
    wrapped: false,
    shrunk: basePitch > 1,
    overflow: false,
  };
}

/** Count characters the font can't render (whitespace excluded). */
export function countUnknown(text: string): number {
  let n = 0;
  for (const ch of text) {
    if (/\s/.test(ch)) continue;
    if (!hasGlyph(ch)) n++;
  }
  return n;
}

// ─────────────────────────────────────────────────────────────────────────
//  DotMatrix — dark glass, lit dots, ghost grid. Frozen geometry.
// ─────────────────────────────────────────────────────────────────────────

export function DotMatrix({
  board,
  mat,
  height = BOARD_H,
}: {
  board: Board;
  mat: Material;
  /** content-box height in px — defaults to the messenger's BOARD_H. */
  height?: number;
}) {
  const { grid, cols, dotSize, dotGap } = board;
  const radius =
    mat.shape === "round" ? dotSize : Math.max(1, Math.round(dotSize * 0.18));
  const bloom = mat.bloom
    ? `0 0 ${Math.max(2, dotSize * 1.6)}px rgba(255,136,0,0.75)`
    : "none";
  return (
    <div
      aria-hidden
      style={{
        display: "grid",
        gridTemplateColumns: `repeat(${cols}, ${dotSize}px)`,
        gridAutoRows: `${dotSize}px`,
        gap: dotGap,
        width: "100%",
        height,
        justifyContent: "center",
        alignContent: "center",
      }}
    >
      {grid.map((rowArr, r) =>
        rowArr.map((value, c) => {
          let background: string;
          let boxShadow = "none";
          if (value === 1) {
            background = DOT.accent;
            boxShadow = bloom;
          } else if (value === 2) {
            background = DOT.placeholder; // unsupported glyph — dim
          } else {
            background = mat.ghost ? DOT.ghost : "transparent";
          }
          return (
            <span
              key={`${r}-${c}`}
              style={{
                width: dotSize,
                height: dotSize,
                borderRadius: radius,
                background,
                boxShadow,
              }}
            />
          );
        })
      )}
    </div>
  );
}

/**
 * Generate 1024×1024 SVG masters + 40px/128px thumbs for each t-decoration study.
 * Uses the locked JBM geometry constants.
 * Usage: bun run generate.mjs
 */

import sharp from "sharp";
import { writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";

const BASE = new URL(".", import.meta.url).pathname;
const THUMBS = join(BASE, "thumbs");
await mkdir(THUMBS, { recursive: true });

// Brand palette
const INK = "#F4EFE6";
const CANVAS = "#0E0D0A";
const TAPE_TAN = "#7A6E5C";
const CASSETTE = "#E68A3C";
const HAIRLINE = "#16140e";

// Geometry at size=1024
const S = 1024;
const MONO = "JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace";
const T_CELL_CENTER = 0.31;
const T_STEM_OFFSET = -0.034;
const T_STEM_WIDTH = 0.08;
const T_CROSS_Y = 0.469;
const T_CROSSBAR_LEFT = 0.115;
const T_CROSSBAR_RIGHT = 0.4825;

const anchorX = S * T_CELL_CENTER;
const stemCx = anchorX + S * T_STEM_OFFSET;
const crossY = S * T_CROSS_Y;
const stemW = S * T_STEM_WIDTH;
const crossbarLeft = S * T_CROSSBAR_LEFT;
const crossbarRight = S * T_CROSSBAR_RIGHT;
const baseline = S * 0.86;
const fontSize = S * 0.78;
const viewW = Math.round(S * 0.62);

// Full 1024×1024 icon with canvas bg, centered glyph
function wrapIcon(glyphContent, { bg = CANVAS, defs = "" } = {}) {
  // Center the glyph viewBox (which is viewW×S) inside 1024×1024
  const offsetX = Math.round((S - viewW) / 2);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <defs>
    <style>@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@500');</style>
    ${defs}
  </defs>
  <rect width="${S}" height="${S}" fill="${bg}"/>
  <g transform="translate(${offsetX}, 0)">
    ${glyphContent}
  </g>
</svg>`;
}

function tText(fill = INK, extra = "") {
  return `<text x="${anchorX}" y="${baseline}" text-anchor="middle" font-family="${MONO}" font-weight="500" font-size="${fontSize}" fill="${fill}" ${extra}>t</text>`;
}

// ─── Study SVGs ───

const studies = [
  // QUIET
  {
    name: "stem-dot",
    svg: () => {
      const r = stemW * 0.28;
      const y = crossY + (baseline - crossY) * 0.45;
      return wrapIcon(`${tText()}<circle cx="${stemCx}" cy="${y}" r="${r}" fill="${CASSETTE}"/>`);
    },
  },
  {
    name: "crossbar-slot",
    svg: () => {
      const slotW = stemW * 0.35;
      const slotH = stemW * 1.4;
      const x = stemCx + stemW * 1.8;
      return wrapIcon(
        `${tText(INK, 'mask="url(#slot)"')}`,
        {
          defs: `<mask id="slot"><rect width="100%" height="100%" fill="white"/><rect x="${x - slotW / 2}" y="${crossY - slotH / 2}" width="${slotW}" height="${slotH}" fill="black"/></mask>`,
        }
      );
    },
  },
  {
    name: "stem-foot",
    svg: () => {
      const tickW = stemW * 1.6;
      const tickH = Math.max(2, S * 0.008);
      const y = baseline + S * 0.01;
      return wrapIcon(`${tText()}<rect x="${stemCx - tickW / 2}" y="${y}" width="${tickW}" height="${tickH}" fill="${TAPE_TAN}"/>`);
    },
  },
  {
    name: "cross-hairline",
    svg: () => {
      const len = stemW * 1.8;
      return wrapIcon(`${tText()}<line x1="${stemCx - len}" y1="${crossY + len * 0.6}" x2="${stemCx + len}" y2="${crossY - len * 0.6}" stroke="${TAPE_TAN}" stroke-width="${Math.max(1, S * 0.004)}"/>`);
    },
  },
  {
    name: "ascender-notch",
    svg: () => {
      const w = stemW * 0.5;
      const y = S * 0.155;
      return wrapIcon(
        `${tText(INK, 'mask="url(#notch)"')}`,
        {
          defs: `<mask id="notch"><rect width="100%" height="100%" fill="white"/><rect x="${stemCx - w / 2}" y="${y}" width="${w}" height="${w}" fill="black"/></mask>`,
        }
      );
    },
  },
  {
    name: "crossbar-pin",
    svg: () => {
      const r = stemW * 0.25;
      return wrapIcon(`${tText()}<circle cx="${crossbarRight}" cy="${crossY}" r="${r}" fill="${CASSETTE}"/>`);
    },
  },
  {
    name: "descender-hook-accent",
    svg: () => {
      const w = stemW * 0.4;
      const x = stemCx - stemW * 0.8;
      const y = baseline - stemW * 0.2;
      return wrapIcon(`${tText()}<rect x="${x}" y="${y}" width="${w}" height="${w}" fill="${CASSETTE}" rx="${w * 0.15}"/>`);
    },
  },

  // LOUD
  {
    name: "gradient-fill",
    svg: () =>
      wrapIcon(tText("url(#ge)"), {
        defs: `<linearGradient id="ge" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${CASSETTE}"/><stop offset="100%" stop-color="#6B4422"/></linearGradient>`,
      }),
  },
  {
    name: "glow-halo",
    svg: () => {
      const glowText = `<text x="${anchorX}" y="${baseline}" text-anchor="middle" font-family="${MONO}" font-weight="500" font-size="${fontSize}" fill="none" stroke="${CASSETTE}" stroke-width="3" filter="url(#gl)" opacity="0.7">t</text>`;
      return wrapIcon(`${tText()}${glowText}`, {
        defs: `<filter id="gl" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="8" result="b1"/><feGaussianBlur in="SourceGraphic" stdDeviation="3" result="b2"/><feMerge><feMergeNode in="b1"/><feMergeNode in="b2"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`,
      });
    },
  },
  {
    name: "debossed",
    svg: () =>
      wrapIcon(tText("#B8A88E", 'filter="url(#db)"'), {
        bg: "#C4B49A",
        defs: `<filter id="db" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur in="SourceAlpha" stdDeviation="3" result="bl"/><feOffset dx="2" dy="3" result="off"/><feFlood flood-color="#0E0D0A" flood-opacity="0.5" result="c"/><feComposite in="c" in2="off" operator="in" result="sh"/><feOffset in="SourceAlpha" dx="-1.5" dy="-2" result="off2"/><feGaussianBlur in="off2" stdDeviation="2" result="bl2"/><feFlood flood-color="#F4EFE6" flood-opacity="0.3" result="c2"/><feComposite in="c2" in2="bl2" operator="in" result="hi"/><feMerge><feMergeNode in="sh"/><feMergeNode in="hi"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`,
      }),
  },
  {
    name: "chrome",
    svg: () =>
      wrapIcon(tText("url(#cr)"), {
        defs: `<linearGradient id="cr" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#E8E8E8"/><stop offset="25%" stop-color="#A0A0A0"/><stop offset="50%" stop-color="#D4D4D4"/><stop offset="75%" stop-color="#8A8A8A"/><stop offset="100%" stop-color="#C0C0C0"/></linearGradient>`,
      }),
  },
  {
    name: "tape-spool",
    svg: () => {
      const cx1 = viewW * 0.28;
      const cx2 = viewW * 0.72;
      const cy = S * 0.58;
      const r = S * 0.16;
      const reels = `<g stroke="${TAPE_TAN}" fill="none" opacity="0.18"><circle cx="${cx1}" cy="${cy}" r="${r}" stroke-width="2"/><circle cx="${cx1}" cy="${cy}" r="${r * 0.45}" stroke-width="1.5"/><circle cx="${cx2}" cy="${cy}" r="${r * 0.8}" stroke-width="2"/><circle cx="${cx2}" cy="${cy}" r="${r * 0.35}" stroke-width="1.5"/></g>`;
      return wrapIcon(`${reels}${tText()}`);
    },
  },
  {
    name: "letterpress",
    svg: () =>
      wrapIcon(tText(INK, 'filter="url(#lp)"'), {
        defs: `<filter id="lp" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="4" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="4" xChannelSelector="R" yChannelSelector="G"/></filter>`,
      }),
  },
  {
    name: "lamp",
    svg: () => {
      const r = stemW * 0.32;
      const cy = S * 0.15;
      const lamp = `<circle cx="${stemCx}" cy="${cy}" r="${r * 3}" fill="${CASSETTE}" opacity="0.08"/><circle cx="${stemCx}" cy="${cy}" r="${r * 1.8}" fill="${CASSETTE}" opacity="0.15"/><circle cx="${stemCx}" cy="${cy}" r="${r}" fill="${CASSETTE}"/><circle cx="${stemCx}" cy="${cy}" r="${r * 0.5}" fill="#FCEBD5" opacity="0.8"/>`;
      return wrapIcon(`${tText()}${lamp}`);
    },
  },
];

// Generate all
for (const study of studies) {
  const svgContent = study.svg();
  const svgPath = join(BASE, `${study.name}-1024.svg`);
  await writeFile(svgPath, svgContent);

  // Render to PNG for thumbs
  const pngBuf = await sharp(Buffer.from(svgContent), { density: 144 })
    .resize(1024, 1024)
    .png()
    .toBuffer();

  await Promise.all([
    sharp(pngBuf).resize(40, 40).png().toFile(join(THUMBS, `${study.name}-40.png`)),
    sharp(pngBuf).resize(128, 128).png().toFile(join(THUMBS, `${study.name}-128.png`)),
  ]);

  console.log(`  ✓ ${study.name}`);
}

console.log(`\n✅ ${studies.length} studies generated`);

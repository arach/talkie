/**
 * Batch SVG→PNG converter for Talkie icon explorations.
 * Usage: bun run convert.mjs
 *
 * For each direction folder under 2026-05-12-*, reads master-1024.svg and produces:
 *   - ios-1024.png (no alpha, white bg fallback → uses icon's own bg)
 *   - ios-watch-1024.png (same as ios, separate file)
 *   - macos-squircle-1024.png (with alpha, squircle mask applied)
 *   - favicon-32.png, favicon-512.png
 *   - og-card-1200x630.png (centered on brand bg)
 *   - thumbs/ at 16, 24, 32, 40, 64, 128
 */

import sharp from 'sharp';
import { readdir, readFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';

const BASE = new URL('.', import.meta.url).pathname;
const DIRECTIONS = (await readdir(BASE)).filter(d => d.startsWith('2026-05-12-'));

// macOS squircle mask at 1024x1024 — superellipse approximation
// The icon content sits in ~824x824 centered, but we mask the full 1024
function makeSquircleSVG() {
  // macOS Big Sur+ continuous corner radius ≈ superellipse |x|^5 + |y|^5 = r^5
  // Approximated with cubic beziers for the squircle corners
  const r = 512; // half-size
  const k = 0.18; // corner sharpness (lower = rounder)
  const cx = 512, cy = 512;
  const s = 462; // half-side of squircle

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
    <rect x="${cx-s}" y="${cy-s}" width="${s*2}" height="${s*2}" rx="${s*0.42}" ry="${s*0.42}" fill="white"/>
  </svg>`;
}

const squircleMaskBuffer = Buffer.from(makeSquircleSVG());

async function processDirection(dirName) {
  const dir = join(BASE, dirName);
  const svgPath = join(dir, 'master-1024.svg');

  let svgBuffer;
  try {
    svgBuffer = await readFile(svgPath);
  } catch {
    console.warn(`⚠ Skipping ${dirName}: no master-1024.svg`);
    return;
  }

  console.log(`→ ${dirName}`);

  // Ensure thumbs directory exists
  await mkdir(join(dir, 'thumbs'), { recursive: true });

  // Render SVG at 1024x1024
  const master1024 = await sharp(svgBuffer, { density: 144 })
    .resize(1024, 1024)
    .png()
    .toBuffer();

  // iOS: no alpha, flatten onto the icon's own background
  const ios1024 = await sharp(master1024)
    .flatten({ background: { r: 14, g: 13, b: 10 } }) // canvas fallback
    .png()
    .toBuffer();

  // macOS squircle: apply mask
  const squircleMask = await sharp(squircleMaskBuffer, { density: 144 })
    .resize(1024, 1024)
    .greyscale()
    .png()
    .toBuffer();

  const macosSquircle = await sharp(master1024)
    .composite([{ input: squircleMask, blend: 'dest-in' }])
    .png()
    .toBuffer();

  // OG card: 1200x630, icon centered on canvas background
  const ogIcon = await sharp(master1024).resize(500, 500).png().toBuffer();
  const ogCard = await sharp({
    create: { width: 1200, height: 630, channels: 4, background: { r: 14, g: 13, b: 10, alpha: 1 } }
  })
    .composite([{ input: ogIcon, left: 350, top: 65 }])
    .png()
    .toBuffer();

  // Write main outputs
  await Promise.all([
    sharp(ios1024).toFile(join(dir, 'ios-1024.png')),
    sharp(ios1024).toFile(join(dir, 'ios-watch-1024.png')),
    sharp(macosSquircle).toFile(join(dir, 'macos-squircle-1024.png')),
    sharp(master1024).resize(32, 32).png().toFile(join(dir, 'favicon-32.png')),
    sharp(master1024).resize(512, 512).png().toFile(join(dir, 'favicon-512.png')),
    sharp(ogCard).toFile(join(dir, 'og-card-1200x630.png')),
  ]);

  // Thumbs
  const thumbSizes = [16, 24, 32, 40, 64, 128];
  await Promise.all(
    thumbSizes.map(size =>
      sharp(master1024).resize(size, size).png().toFile(join(dir, 'thumbs', `${size}.png`))
    )
  );

  console.log(`  ✓ ${dirName} — all outputs written`);
}

// Process all directions
for (const dir of DIRECTIONS) {
  await processDirection(dir);
}

console.log(`\n✅ Done — ${DIRECTIONS.length} directions processed`);

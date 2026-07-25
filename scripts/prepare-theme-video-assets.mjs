#!/usr/bin/env bun

import { mkdir, readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
}

function run(command, commandArgs, cwd = ROOT) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, { cwd, stdio: "inherit" });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited ${code}`));
    });
  });
}

const manifestPath = path.resolve(option("manifest"));
const outputRoot = path.resolve(option("output"));
const actionRoot = path.resolve(option("action-root", path.join(ROOT, "../action")));
const skipKeyed = args.includes("--skip-keyed");
const actionScript = path.join(actionRoot, "scripts/chroma-window-video.mjs");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const inputPath = path.resolve(manifest.outputPath);
const rawRoot = path.join(outputRoot, "raw");
const keyedRoot = path.join(outputRoot, "keyed");

await Promise.all([mkdir(rawRoot, { recursive: true }), mkdir(keyedRoot, { recursive: true })]);

for (let index = 0; index < manifest.markers.length; index += 1) {
  const marker = manifest.markers[index];
  const nextMarker = manifest.markers[index + 1];
  const start = marker.atSeconds + 0.9;
  const available = (nextMarker?.atSeconds ?? (marker.atSeconds + marker.holdSeconds)) - start - 0.25;
  const duration = Math.max(3.5, Math.min(5, available));
  const rawPath = path.join(rawRoot, `${marker.id}.mp4`);
  const keyedPath = path.join(keyedRoot, `${marker.id}.chroma.mp4`);
  const metadataPath = path.join(keyedRoot, `${marker.id}.chroma.json`);

  console.log(`[${manifest.theme}] ${marker.id}: ${start.toFixed(3)}s + ${duration.toFixed(3)}s`);
  await run("ffmpeg", [
    "-y",
    "-i", inputPath,
    "-ss", start.toFixed(3),
    "-t", duration.toFixed(3),
    "-vf", "fps=30,format=yuv420p",
    "-an",
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "18",
    "-g", "30",
    "-keyint_min", "30",
    "-sc_threshold", "0",
    "-movflags", "+faststart",
    rawPath,
  ]);

  if (!skipKeyed) {
    await run("bun", [
      actionScript,
      "--input", rawPath,
      "--output", keyedPath,
      "--metadata", metadataPath,
    ], actionRoot);
  }
}

console.log(JSON.stringify({
  theme: manifest.theme,
  screenCount: manifest.markers.length,
  rawRoot,
  keyedRoot,
}, null, 2));

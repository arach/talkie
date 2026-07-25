#!/usr/bin/env bun

import { access, mkdir, rm, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const ACTION_ROOT = path.resolve(process.env.ACTION_ROOT ?? path.join(ROOT, "../action"));
const RUN_HOST = path.join(ACTION_ROOT, "native/engine/scripts/run-app-host.sh");
const BUNDLE_ID = process.env.TALKIE_BUNDLE_ID ?? "to.talkie.app.mac.dev";
const SCHEME = process.env.TALKIE_URL_SCHEME ?? "talkie-dev";

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  if (index === -1) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
};

const theme = option("theme");
if (!theme || !["dark", "light"].includes(theme)) {
  throw new Error("Use --theme dark or --theme light after selecting that theme in Talkie.");
}

const holdScale = Number(option("hold-scale", process.env.TALKIE_CAPTURE_HOLD_SCALE ?? "1"));
if (!Number.isFinite(holdScale) || holdScale <= 0) {
  throw new Error("--hold-scale must be greater than zero");
}

const outputDirectory = path.resolve(
  option("output", path.join(ROOT, "artifacts/talkie-videos/theme-passes", theme)),
);
const outputPath = path.join(outputDirectory, `talkie-${theme}-screen-library.mov`);
const stopPath = `${outputPath}.stop`;
const finishedPath = `${outputPath}.finished`;
const logPath = `${outputPath}.log`;
const manifestPath = path.join(outputDirectory, `talkie-${theme}-screen-library.json`);

const beats = [
  { id: "home", route: "home", holdSeconds: 7 },
  { id: "agent", route: "agent", holdSeconds: 6 },
  { id: "library", route: "library", holdSeconds: 7 },
  { id: "compose", route: "compose", holdSeconds: 8 },
  { id: "captures", route: "screenshots", holdSeconds: 8 },
  { id: "workflows", route: "workflows", holdSeconds: 7 },
  { id: "console", route: "console", holdSeconds: 7 },
  { id: "stats", route: "stats", holdSeconds: 6 },
  { id: "models", route: "models", holdSeconds: 6 },
  { id: "context", route: "context", holdSeconds: 6 },
  { id: "settings", route: "settings/appearance", holdSeconds: 7 },
];

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function exists(filePath) {
  try {
    await access(filePath, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function run(command, commandArgs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(`${command} exited ${code}\n${stderr || stdout}`));
    });
  });
}

await mkdir(outputDirectory, { recursive: true });
await Promise.all([
  rm(outputPath, { force: true }),
  rm(stopPath, { force: true }),
  rm(finishedPath, { force: true }),
  rm(logPath, { force: true }),
]);

const recording = run(RUN_HOST, [
  "record-app-window",
  "--bundle-id", BUNDLE_ID,
  "--output", outputPath,
  "--stop-file", stopPath,
  "--finished-file", finishedPath,
  "--debug-log", logPath,
]);

const startedAt = Date.now();
const markers = [];

try {
  await sleep(2_500);
  for (const beat of beats) {
    const atSeconds = (Date.now() - startedAt) / 1000;
    const url = `${SCHEME}://${beat.route}`;
    console.log(`[${theme}] ${beat.id} → ${url}`);
    await run("open", [url]);
    markers.push({ ...beat, atSeconds, url });
    await sleep(beat.holdSeconds * holdScale * 1_000);
  }
} finally {
  await writeFile(stopPath, "stop\n");
}

await recording;
const finishDeadline = Date.now() + 30_000;
while (!(await exists(finishedPath))) {
  if (Date.now() > finishDeadline) {
    throw new Error(`Timed out waiting for Action marker: ${finishedPath}`);
  }
  await sleep(250);
}

const manifest = {
  schema: "talkie.theme-screen-library/v1",
  theme,
  bundleId: BUNDLE_ID,
  urlScheme: SCHEME,
  outputPath,
  startedAt: new Date(startedAt).toISOString(),
  durationSeconds: (Date.now() - startedAt) / 1000,
  markers,
};

await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify({ outputPath, manifestPath, markerCount: markers.length }, null, 2));

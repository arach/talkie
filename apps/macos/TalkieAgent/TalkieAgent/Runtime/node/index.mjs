#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const runtimeDir = dirname(fileURLToPath(import.meta.url));
const version = readPackageVersion();
let pending = '';
let queue = Promise.resolve();

process.stdin.setEncoding('utf8');

process.stdin.on('data', (chunk) => {
  pending += chunk;
  drainLines();
});

process.stdin.on('end', () => {
  const line = pending.trim();
  pending = '';
  if (line.length > 0) {
    enqueueLine(line);
  }
});

process.stdin.on('error', (error) => {
  console.error(`[TalkieAgentRuntime] stdin error: ${error?.message ?? error}`);
});

function drainLines() {
  let newlineIndex = pending.indexOf('\n');
  while (newlineIndex !== -1) {
    const line = pending.slice(0, newlineIndex).trim();
    pending = pending.slice(newlineIndex + 1);
    if (line.length > 0) {
      enqueueLine(line);
    }
    newlineIndex = pending.indexOf('\n');
  }
}

function enqueueLine(line) {
  queue = queue
    .then(() => handleLine(line))
    .catch((error) => {
      writeResponse({ ok: false, error: error?.message ?? String(error) });
    });
}

async function handleLine(line) {
  let request;
  try {
    request = JSON.parse(line);
  } catch (error) {
    writeResponse({ ok: false, error: `Invalid JSON: ${error.message}` });
    return;
  }

  try {
    switch (request?.op) {
      case 'ping':
        writeResponse({ ok: true, pid: process.pid, version });
        break;
      default:
        writeResponse({ ok: false, error: `Unsupported op: ${String(request?.op ?? '')}` });
        break;
    }
  } catch (error) {
    writeResponse({ ok: false, error: error?.message ?? String(error) });
  }
}

function writeResponse(response) {
  process.stdout.write(`${JSON.stringify(response)}\n`);
}

function readPackageVersion() {
  try {
    const packageJsonPath = join(runtimeDir, 'package.json');
    const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
    return packageJson.version ?? '0.0.0';
  } catch {
    return '0.0.0';
  }
}

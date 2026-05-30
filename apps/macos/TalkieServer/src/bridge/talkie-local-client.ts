import { Buffer } from "node:buffer";
import { createHash, generateKeyPairSync, randomUUID, sign } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const CLIENT_ID = "to.talkie.local-bridge";
const DISPLAY_NAME = "Talkie Local Bridge";
const REQUESTED_CAPABILITIES = [
  "companion.runtimeState",
  "companion.trigger",
  "companion.activateApp",
  "companion.trackpad",
  "companion.pasteImage",
  "terminal.access",
  "desktop.windows.read",
  "desktop.screenshot.read",
  "message.inject",
  "workflow.execute",
];

type LocalClientKeyFile = {
  privateKeyPem: string;
  publicKeyDerBase64: string;
};

let identityCache: LocalClientKeyFile | undefined;
let deniedUntil = 0;

export async function talkieServerFetch(input: string | URL, init: RequestInit = {}): Promise<Response> {
  const signed = signRequest(input, init);
  let response = await fetch(input, signed);

  if (response.status !== 401 && response.status !== 403) {
    return response;
  }

  await requestAccessFor(input);
  response = await fetch(input, signRequest(input, init));
  return response;
}

function signRequest(input: string | URL, init: RequestInit): RequestInit {
  const identity = loadOrCreateIdentity();
  const method = (init.method ?? "GET").toUpperCase();
  const body = bodyBytes(init.body);
  const bodyHash = createHash("sha256").update(body).digest("hex");
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = randomUUID();
  const url = new URL(input.toString());
  const canonical = [
    method,
    `${url.pathname}${url.search}`,
    timestamp,
    nonce,
    bodyHash,
  ].join("\n");

  const signature = sign(
    "sha256",
    Buffer.from(canonical, "utf8"),
    identity.privateKeyPem
  ).toString("base64");

  const headers = new Headers(init.headers);
  headers.set("X-Talkie-Client-ID", CLIENT_ID);
  headers.set("X-Talkie-Timestamp", timestamp);
  headers.set("X-Talkie-Nonce", nonce);
  headers.set("X-Talkie-Body-SHA256", bodyHash);
  headers.set("X-Talkie-Signature", signature);

  return { ...init, method, headers };
}

async function requestAccessFor(input: string | URL): Promise<void> {
  if (Date.now() < deniedUntil) {
    throw new Error("Talkie local bridge access was recently denied");
  }

  const identity = loadOrCreateIdentity();
  const url = new URL(input.toString());
  const response = await fetch(`${url.origin}/local-clients/request-access`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      clientId: CLIENT_ID,
      displayName: DISPLAY_NAME,
      publicKey: identity.publicKeyDerBase64,
      requestedCapabilities: REQUESTED_CAPABILITIES,
    }),
    signal: AbortSignal.timeout(45_000),
  });

  if (!response.ok) {
    deniedUntil = Date.now() + 10 * 60 * 1000;
    const text = await response.text().catch(() => "");
    throw new Error(`Talkie local bridge access failed (${response.status}): ${text}`);
  }

  const payload = await response.json().catch(() => undefined) as { ok?: boolean; message?: string } | undefined;
  if (payload?.ok !== true) {
    deniedUntil = Date.now() + 10 * 60 * 1000;
    throw new Error(payload?.message ?? "Talkie local bridge access was not approved");
  }

  deniedUntil = 0;
}

function loadOrCreateIdentity(): LocalClientKeyFile {
  if (identityCache) {
    return identityCache;
  }

  const file = keyFilePath();
  if (existsSync(file)) {
    identityCache = JSON.parse(readFileSync(file, "utf8")) as LocalClientKeyFile;
    return identityCache;
  }

  const { privateKey, publicKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const identity: LocalClientKeyFile = {
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    publicKeyDerBase64: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
  };

  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(identity, null, 2));
  chmodSync(file, 0o600);
  identityCache = identity;
  return identity;
}

function keyFilePath(): string {
  return path.join(
    os.homedir(),
    "Library",
    "Application Support",
    "Talkie",
    "LocalBridge",
    "talkie-local-bridge-p256.json"
  );
}

function bodyBytes(body: BodyInit | null | undefined): Buffer {
  if (body === undefined || body === null) {
    return Buffer.alloc(0);
  }
  if (typeof body === "string") {
    return Buffer.from(body, "utf8");
  }
  if (body instanceof ArrayBuffer) {
    return Buffer.from(body);
  }
  if (ArrayBuffer.isView(body)) {
    return Buffer.from(body.buffer, body.byteOffset, body.byteLength);
  }
  throw new Error("Unsupported TalkieServer signed request body type");
}

/**
 * Transport Encryption (talkie-bridge v2)
 *
 * Seals authenticated bridge request/response bodies with AES-256-GCM using the
 * per-device key already derived from the ECDH pairing secret
 * (`getDeviceEncryptionKey`, HKDF info "talkie-bridge-encrypt").
 *
 * Negotiation: clients opt in per request with the `X-Enc: 2` header (advertised
 * by `/health` -> `enc: true`). Requests without the header — old clients — are
 * left as plaintext, so this is fully backward compatible.
 *
 * The envelope matches crypto/box.ts and the iOS client:
 *   { "enc": 2, "ciphertext": "<base64( nonce[12] | ciphertext | tag[16] )>" }
 *
 * HMAC auth (auth/hmac.ts) verifies the signature over the *ciphertext* that is
 * transmitted, so decryption here runs only on already-authenticated requests.
 */

import { getDeviceEncryptionKey } from "../devices/registry";
import { sealBytes, openBytes } from "../crypto/box";
import { isExemptPath } from "../auth/hmac";
import { log } from "../log";

const ENC_HEADER = "x-enc";
const ENC_VERSION = "2";

interface Envelope {
  enc: number;
  ciphertext: string;
}

/** Whether a request opted into transport encryption and is eligible (not a bootstrap path). */
export function isEncryptedRequest(request: Request): boolean {
  if (request.headers.get(ENC_HEADER) !== ENC_VERSION) return false;
  const { pathname } = new URL(request.url);
  return !isExemptPath(pathname, request.method);
}

async function deviceKey(request: Request): Promise<CryptoKey | null> {
  const deviceId = request.headers.get("X-Device-ID");
  if (!deviceId) return null;
  try {
    return await getDeviceEncryptionKey(deviceId);
  } catch {
    return null;
  }
}

/**
 * Decrypt an incoming request body. Returns the parsed plaintext value to use as
 * the route `body`, or `undefined` to leave Elysia's default parsing in place.
 */
export async function decryptRequestBody(request: Request): Promise<unknown | undefined> {
  if (!isEncryptedRequest(request)) return undefined;
  if (request.method === "GET" || request.method === "HEAD") return undefined;

  const key = await deviceKey(request);
  if (!key) return undefined;

  // Read a clone so the original stream stays intact for HMAC verification.
  const raw = await request.clone().text();
  if (!raw) return {};

  let envelope: Envelope;
  try {
    envelope = JSON.parse(raw) as Envelope;
  } catch {
    return undefined;
  }
  if (!envelope || typeof envelope.ciphertext !== "string") return undefined;

  try {
    const plaintext = await openBytes(envelope.ciphertext, key);
    const text = new TextDecoder().decode(plaintext);
    return text.length ? JSON.parse(text) : {};
  } catch {
    // Do NOT throw. onParse runs BEFORE the HMAC auth hook, so a thrown 500
    // here would hand an unauthenticated LAN attacker a 500-vs-401 oracle on
    // GCM validity. Return undefined and let the auth layer reject the request
    // with a uniform 401 — a forger without the device key cannot produce a
    // valid signature anyway, so no legitimately-decryptable body is lost.
    log.warn("Transport decrypt failed (deferring to auth layer)");
    return undefined;
  }
}

/**
 * Read a route's JSON body, transparently decrypting an X-Enc:2 envelope first.
 *
 * Many routes parse the body themselves (`await request.json()`) instead of
 * using Elysia's `body` context, to keep the original stream intact for HMAC.
 * But `request.json()` returns the RAW transmitted bytes — which, for an
 * encrypted client, is the `{ enc, ciphertext }` envelope, not the plaintext.
 * Those routes must call this instead so they receive the decrypted body. For a
 * plaintext (old/local) client this is just `request.json()`, so it is fully
 * backward compatible.
 */
export async function readJsonBody(request: Request): Promise<any> {
  const decrypted = await decryptRequestBody(request);
  if (decrypted !== undefined) return decrypted;
  return await request.json();
}

/**
 * For a request that opted into stream encryption (`X-Enc: 2`), return a sealer
 * that wraps one stream frame (e.g. a single SSE `data:` payload) into the v2
 * envelope `{ enc, ciphertext }` — each frame gets its own GCM nonce. Returns
 * `null` for un-opted-in / un-keyed requests so the caller streams plaintext
 * exactly as before (backward compatible).
 */
export async function prepareStreamSealer(
  request: Request
): Promise<((plaintext: string) => Promise<string>) | null> {
  // Dedicated header so this is independent of request-body encryption (X-Enc):
  // the client can ask for sealed response frames without sealing its request.
  if (request.headers.get("x-enc-stream") !== ENC_VERSION) return null;
  const key = await deviceKey(request);
  if (!key) return null;
  return async (plaintext: string): Promise<string> => {
    const ciphertext = await sealBytes(new TextEncoder().encode(plaintext), key);
    const envelope: Envelope = { enc: 2, ciphertext };
    return JSON.stringify(envelope);
  };
}

/**
 * WebSocket variant of the stream sealer. The ws open()/message() handlers do
 * not have a `Request`, so negotiation rides on the upgrade URL query instead of
 * a header: the client appends `encStream=2` and `deviceId=<id>` (both covered
 * by the HMAC signature over path+query, so they are integrity-protected on the
 * authenticated upgrade). Returns a per-frame sealer, or `null` for an un-opted
 * or un-keyed socket so the route streams plaintext exactly as before (old
 * clients are unaffected). Note: sealing to the query deviceId's key is safe —
 * a different paired device that lies about deviceId only seals frames it cannot
 * itself decrypt, so it gains nothing.
 */
export async function prepareWsFrameSealer(
  query: Record<string, string | undefined>
): Promise<((plaintext: string) => Promise<string>) | null> {
  if (query.encStream !== ENC_VERSION) return null;
  const deviceId = query.deviceId;
  if (!deviceId) return null;
  let key: CryptoKey | null;
  try {
    key = await getDeviceEncryptionKey(deviceId);
  } catch {
    key = null;
  }
  if (!key) return null;
  return async (plaintext: string): Promise<string> => {
    const ciphertext = await sealBytes(new TextEncoder().encode(plaintext), key);
    const envelope: Envelope = { enc: 2, ciphertext };
    return JSON.stringify(envelope);
  };
}

/** Serialize a handler response into raw bytes + the status code to preserve. */
async function responseToBytes(
  response: unknown,
  fallbackStatus: number
): Promise<{ bytes: Uint8Array; status: number } | null> {
  if (response instanceof Response) {
    const buf = new Uint8Array(await response.clone().arrayBuffer());
    return { bytes: buf, status: response.status };
  }
  if (typeof response === "string") {
    return { bytes: new TextEncoder().encode(response), status: fallbackStatus };
  }
  if (response === undefined || response === null) {
    return null;
  }
  return { bytes: new TextEncoder().encode(JSON.stringify(response)), status: fallbackStatus };
}

/**
 * Encrypt an outgoing response when the request opted in. Only successful (200)
 * responses are sealed; error bodies (e.g. 401 carrying serverTime) stay plaintext
 * so the client can always read them. Returns a new Response, or `undefined` to
 * leave the response unchanged.
 */
export async function encryptResponse(
  request: Request,
  response: unknown,
  fallbackStatus: number
): Promise<Response | undefined> {
  if (!isEncryptedRequest(request)) return undefined;

  // Never buffer-and-seal a streaming response — that would defeat streaming.
  // SSE/WS streams are sealed per-frame at the route (see prepareStreamSealer).
  if (response instanceof Response) {
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.startsWith("text/event-stream")) return undefined;
  }

  const key = await deviceKey(request);
  if (!key) return undefined;

  const serialized = await responseToBytes(response, fallbackStatus);
  if (!serialized) return undefined;
  if (serialized.status !== 200) return undefined; // never seal error responses

  const ciphertext = await sealBytes(serialized.bytes, key);
  const envelope: Envelope = { enc: 2, ciphertext };
  return new Response(JSON.stringify(envelope), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Enc": ENC_VERSION,
    },
  });
}

# Bridge Transport Encryption (talkie-bridge v2)

Status: implemented, **requires live Mac round-trip test before merge** (cannot be
verified in CI / without a paired Mac running the updated TalkieServer).

## Problem

Bridge traffic between the iPhone and the Mac is HMAC-signed (auth + integrity) but
travels as **plaintext HTTP/WS**. A passive attacker on the LAN (or any hop on the
Tailscale-exempted path) can read CLI command output, screenshots, the live screen
stream, Claude messages, and transcripts. Only the borrowed-credentials payload was
AES-GCM encrypted.

## Design

The ECDH shared secret already derives a dedicated AES-256-GCM key via HKDF
(`info = "talkie-bridge-encrypt"`) on both ends — iOS `SharedSecret.deriveEncryptionKey()`,
server `getDeviceEncryptionKey()`. v2 applies that key to **all non-bootstrap
request and response bodies**, plus WebSocket frames.

### Envelope

```
{ "enc": 2, "ciphertext": "<base64( nonce[12] | AES-GCM ciphertext | tag[16] )>" }
```

Identical byte layout to the existing `crypto/box.ts` / `decryptPayload` format, so the
borrowed-credentials path is unchanged.

### Capability negotiation

- `/health` (plaintext, unauthenticated) advertises `enc: true` and
  `protocol: "talkie-bridge-v2"`.
- The client encrypts a request **only** when `serverSupportsEncryption && encryptionKey != nil`.
- Per request the client sets header `X-Enc: 2` and encrypts the body (if any).
- The server decrypts a request body when `X-Enc: 2` is present and the path is not
  exempt, and **encrypts the response** when the request carried `X-Enc: 2` and the
  response is `200`.

### Backward / forward compatibility (plaintext fallback)

- **Old server (v1), new client:** `/health` has no `enc` flag → client never sets
  `X-Enc` → everything stays plaintext. Works.
- **New server (v2), old client:** client never sends `X-Enc` → server replies plaintext.
  Works.
- No re-pair required; the shared secret is unchanged.

### Exempt (always plaintext) paths

Bootstrap + error surfaces, mirroring `isExemptPath`:
`/health`, `/pair`, `/pair/info`, `/pair/pending`, `/pair/*/approve`, `/pair/*/reject`,
`/devices` (GET), `/extensions/*`. Non-`200` responses (e.g. the `401` carrying
`serverTime` for clock recalibration) are never encrypted so the client can always read them.

### WebSocket frames

`/screen-stream` and `/companion-events` seal each JSON text frame in the same envelope
when the upgrade request carried `X-Enc: 2`.

### Binary endpoints

`/windows/:id/screenshot` returns raw image bytes; under `X-Enc` the bytes are sealed
into the envelope and the client unseals to raw `Data`.

## Test plan (live Mac required)

1. Pair a fresh iPhone build against a Mac running the updated TalkieServer.
2. Confirm `/health` shows `enc: true`; capture traffic (e.g. `tcpdump`/Proxyman) and
   verify request/response bodies are ciphertext, not JSON.
3. Exercise: sessions list, send message, CLI command, screenshot, live screen preview,
   compose, TTS. All must function.
4. Point the new client at an **old** server build → confirm plaintext fallback still works.
5. Point an **old** client at the new server → confirm plaintext fallback still works.

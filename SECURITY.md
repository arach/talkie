# Security Policy

Talkie is primarily a local-first Apple-platform app, but it can expose local bridge and gateway endpoints for the macOS app, paired iOS devices, browser extensions, and workflow tooling. Treat those endpoints as part of the security boundary.

## Supported Surface

For public security reports, focus on code and behavior in this repository:

- macOS and iOS app code
- `apps/macos/TalkieServer/`
- `packages/npm/cli/`, `packages/npm/sdk/`, `packages/npm/companion/`
- workflow and gateway code under `packages/swift/` and `docs/specs/`

Release infrastructure, App Store metadata, website hosting, private credentials, and owner-specific deployment systems are not yet documented as public support surfaces.

## Reporting

Open a GitHub security advisory if the repository supports it. If not, open a private issue or contact the maintainer through the repository owner profile. Do not file public issues with working exploits, tokens, private keys, or user data.

Include:

- Affected component and commit or release
- Reproduction steps
- Expected and actual behavior
- Whether the issue requires local access, LAN access, Tailscale access, or a paired device
- Any logs with secrets removed

## Local Bearer Authentication

TalkieServer generates a local bearer token on startup and writes it to:

```text
~/Library/Application Support/Talkie/Bridge/.config/.local-auth-token
```

The token file is created with `0600` permissions inside app-support directories created with `0700` permissions. Sensitive local routes such as inference, workflow execution, CLI/headless operations, and security event ingestion require `Authorization: Bearer <token>`.

Local development mode binds to `127.0.0.1` and may also expose a Unix socket at `/tmp/talkie-server.sock`, which is chmodded to `0600`.

## Paired Device HMAC

Outside local mode, paired-device requests use HMAC-SHA256 request authentication. Requests include:

- `X-Device-ID`
- `X-Timestamp`
- `X-Nonce`
- `X-Signature`

The signature covers method, path and query, timestamp, nonce, and body hash. The server applies a short timestamp tolerance and nonce replay tracking. Unknown, expired, or unpaired devices must re-pair.

Pairing and health endpoints have limited auth exemptions so devices can discover and establish trust. Treat pairing approval behavior as security-sensitive, especially when enabling LAN mode.

## Tailscale And LAN Modes

Default non-local server mode expects Tailscale and binds to the machine's Tailscale IPv4 address. This keeps paired-device access on the tailnet instead of the general LAN.

Explicit nearby/LAN mode requires:

```bash
bun run src/server.ts --nearby --allow-lan
```

Use LAN mode only on trusted networks. Add `--require-approval` when testing pairing flows that should require Mac-side approval.

## Secret Policy

Do not commit secrets. This includes:

- Provider API keys such as OpenAI, Anthropic, Gemini, and Groq keys
- Auth tokens, bearer tokens, HMAC keys, private keys, or pairing material
- CloudKit, App Store Connect, Fastlane, signing, or notarization credentials
- Local app-support files, logs, or databases that include user content

Provider keys may come from environment variables or local app settings. The macOS app has Keychain-backed credential paths, while TalkieServer can read provider keys from environment or shared local settings. Public docs and examples should use placeholders only.

Service-side secrets should be stored with the local `secret` Keychain helper, not kept in `.env` files. Use `scripts/migrate-service-secrets.sh` to migrate existing ignored service env files into namespaced keys such as `TALKIE_ADMIN_*` and `TALKIE_TO_*`. Use `scripts/dev-talkie-admin-with-secrets.sh` or `scripts/dev-talkie-to-with-secrets.sh` to inject legacy runtime variable names only into the launched subprocess.

If a secret is committed, revoke it immediately, rotate any related credentials, and remove it from history before publishing a public branch.

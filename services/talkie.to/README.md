# talkie.to

This service powers the `talkie.to` domain family for Talkie.

It is active service code, but deployment and production data are maintainer-owned. Public contributors can build and inspect it locally without production credentials.

The go-forward client for this service is the live workflow/control-plane path
used by iPhone and macOS. Older API consumers can keep their existing hosts
until we intentionally cut them over.

Suggested Vercel setup:

- Root Directory: `services/talkie.to`
- Install Command: `bun install`
- Build Command: `bun run build`
- Domains:
  - `talkie.to`
  - `www.talkie.to`
  - `api.talkie.to`

Current responsibilities:

- landing and handoff surface on `talkie.to` / `www.talkie.to`
- app feature flags and authenticated APIs on `api.talkie.to`
- live workflow queue
- Mac executor registration and leasing

Local development with Keychain-backed secrets from the repo root:

```bash
scripts/migrate-service-secrets.sh --apply
scripts/dev-talkie-to-with-secrets.sh
```

The wrapper injects namespaced `TALKIE_TO_*` keys and aliases them to the runtime names expected by the service. Use `.env.example` only as a placeholder reference.

Useful environment variables:

- `TALKIE_LANDING_BASE_URL`
  Usually `https://talkie.to`
- `TALKIE_API_BASE_URL`
  Usually `https://api.talkie.to`
- `TALKIE_IOS_INSTALL_URL`
  iPhone install destination for `/install`
- `TALKIE_MAC_DOWNLOAD_URL`
  Mac DMG destination for `/download`

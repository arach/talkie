# Talkie Admin

Internal admin and report viewer for Talkie service operations. This is a maintainer-facing Nitro app, not part of the core Apple app build.

## Local Development

Install dependencies:

```bash
bun install
```

Copy `.env.example` only for local placeholders. Real values should live in the local Keychain through `secret`, not in committed files. From the repo root:

```bash
scripts/migrate-service-secrets.sh --apply
scripts/dev-talkie-admin-with-secrets.sh
```

The migration script stores namespaced keys such as `TALKIE_ADMIN_API_KEY` and injects legacy runtime names like `API_KEY` only while launching the service.

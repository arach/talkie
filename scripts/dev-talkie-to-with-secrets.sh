#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/services/talkie.to"

keys=(
  TALKIE_TO_BLOB_READ_WRITE_TOKEN
  TALKIE_TO_CLERK_PUBLISHABLE_KEY
  TALKIE_TO_CLERK_SECRET_KEY
)

while IFS= read -r key; do
  case "$key" in
    TALKIE_TO_API_KEY|TALKIE_TO_VERCEL_OIDC_TOKEN|TALKIE_TO_SUPABASE_URL|TALKIE_TO_SUPABASE_ANON_KEY)
      keys+=("$key")
      ;;
  esac
done < <(secret list)

exec secret run "${keys[@]}" -- sh -c '
  export BLOB_READ_WRITE_TOKEN="$TALKIE_TO_BLOB_READ_WRITE_TOKEN"
  export NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="$TALKIE_TO_CLERK_PUBLISHABLE_KEY"
  export CLERK_SECRET_KEY="$TALKIE_TO_CLERK_SECRET_KEY"

  [ -n "${TALKIE_TO_API_KEY:-}" ] && export API_KEY="$TALKIE_TO_API_KEY"
  [ -n "${TALKIE_TO_VERCEL_OIDC_TOKEN:-}" ] && export VERCEL_OIDC_TOKEN="$TALKIE_TO_VERCEL_OIDC_TOKEN"
  [ -n "${TALKIE_TO_SUPABASE_URL:-}" ] && export NEXT_PUBLIC_SUPABASE_URL="$TALKIE_TO_SUPABASE_URL"
  [ -n "${TALKIE_TO_SUPABASE_ANON_KEY:-}" ] && export NEXT_PUBLIC_SUPABASE_ANON_KEY="$TALKIE_TO_SUPABASE_ANON_KEY"

  exec bun run dev
'

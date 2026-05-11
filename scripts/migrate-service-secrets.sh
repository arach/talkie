#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
DELETE_ENV=0

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/migrate-service-secrets.sh [--apply] [--delete-env]

Migrates ignored service .env files into the local `secret` Keychain helper
using Talkie-specific namespaced keys. By default this is a dry run.

  --apply       Store missing namespaced keys with `secret set`.
  --delete-env  After a successful --apply run, delete migrated .env files.

The script refuses to overwrite an existing namespaced key when the stored value
differs from the source .env value. It never prints secret values.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --delete-env) DELETE_ENV=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ "$DELETE_ENV" = 1 ] && [ "$APPLY" != 1 ]; then
  echo "--delete-env requires --apply" >&2
  exit 1
fi

command -v secret >/dev/null 2>&1 || {
  echo "Missing required command: secret" >&2
  exit 1
}

secret_has() {
  secret list | grep -Fxq "$1"
}

dotenv_value() {
  local file="$1"
  local key="$2"
  local line value

  [ -f "$file" ] || return 1

  line="$(
    awk -v wanted="$key" '
      {
        line = $0
        sub(/\r$/, "", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/^export[[:space:]]+/, "", line)
        if (line ~ ("^" wanted "=")) {
          print line
        }
      }
    ' "$file" | tail -n 1
  )"

  [ -n "$line" ] || return 1
  value="${line#*=}"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

env_keys() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/^export[[:space:]]+/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        sub(/=.*/, "", line)
        print line
      }
    }
  ' "$file" | sort -u
}

assert_only_expected_keys() {
  local file="$1"
  shift
  local expected=" $* "
  local key

  [ -f "$file" ] || return 0

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$expected" in
      *" $key "*) ;;
      *)
        echo "Refusing to delete $file: unmapped key $key" >&2
        exit 1
        ;;
    esac
  done < <(env_keys "$file")
}

set_new_from_env() {
  local file="$1"
  local source_key="$2"
  local target_key="$3"
  local value existing

  if ! value="$(dotenv_value "$file" "$source_key")"; then
    return 0
  fi

  if [ -z "$value" ]; then
    echo "skip empty: $source_key from ${file#$ROOT_DIR/}" >&2
    return 0
  fi

  if existing="$(secret get "$target_key" 2>/dev/null)"; then
    if [ "$existing" != "$value" ]; then
      echo "Refusing to overwrite existing key with different value: $target_key" >&2
      exit 1
    fi
    echo "ok existing: $target_key" >&2
    return 0
  fi

  if secret_has "$target_key"; then
    echo "Refusing to continue: $target_key is indexed but not readable" >&2
    exit 1
  fi

  if [ "$APPLY" = 1 ]; then
    printf '%s' "$value" | secret set "$target_key" >/dev/null 2>&1
    echo "stored: $target_key" >&2
  else
    echo "would store: $target_key" >&2
  fi
}

delete_env_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  if [ "$DELETE_ENV" = 1 ]; then
    rm -f "$file"
    echo "deleted: ${file#$ROOT_DIR/}" >&2
  fi
}

ADMIN_ENV="$ROOT_DIR/services/talkie-admin/.env"
ADMIN_LOCAL_ENV="$ROOT_DIR/services/talkie-admin/.env.local"
LEGACY_API_ENV="$ROOT_DIR/services/talkie-api/.env"

set_new_from_env "$ADMIN_ENV" API_KEY TALKIE_ADMIN_API_KEY
set_new_from_env "$ADMIN_ENV" BLOB_READ_WRITE_TOKEN TALKIE_ADMIN_BLOB_READ_WRITE_TOKEN
set_new_from_env "$ADMIN_ENV" VERCEL_OIDC_TOKEN TALKIE_ADMIN_VERCEL_OIDC_TOKEN
set_new_from_env "$ADMIN_ENV" GITHUB_ADMIN_TOKEN TALKIE_ADMIN_GITHUB_ADMIN_TOKEN
set_new_from_env "$ADMIN_ENV" GITHUB_REPO_OWNER TALKIE_ADMIN_GITHUB_REPO_OWNER
set_new_from_env "$ADMIN_ENV" GITHUB_REPO_NAME TALKIE_ADMIN_GITHUB_REPO_NAME
set_new_from_env "$ADMIN_ENV" NEXT_PUBLIC_SUPABASE_URL TALKIE_ADMIN_SUPABASE_URL
set_new_from_env "$ADMIN_ENV" NEXT_PUBLIC_SUPABASE_ANON_KEY TALKIE_ADMIN_SUPABASE_ANON_KEY

set_new_from_env "$ADMIN_LOCAL_ENV" API_KEY TALKIE_ADMIN_LOCAL_API_KEY
set_new_from_env "$ADMIN_LOCAL_ENV" BLOB_READ_WRITE_TOKEN TALKIE_ADMIN_LOCAL_BLOB_READ_WRITE_TOKEN
set_new_from_env "$ADMIN_LOCAL_ENV" VERCEL_OIDC_TOKEN TALKIE_ADMIN_LOCAL_VERCEL_OIDC_TOKEN
set_new_from_env "$ADMIN_LOCAL_ENV" GITHUB_ADMIN_TOKEN TALKIE_ADMIN_LOCAL_GITHUB_ADMIN_TOKEN
set_new_from_env "$ADMIN_LOCAL_ENV" GITHUB_REPO_OWNER TALKIE_ADMIN_LOCAL_GITHUB_REPO_OWNER
set_new_from_env "$ADMIN_LOCAL_ENV" GITHUB_REPO_NAME TALKIE_ADMIN_LOCAL_GITHUB_REPO_NAME
set_new_from_env "$ADMIN_LOCAL_ENV" NEXT_PUBLIC_SUPABASE_URL TALKIE_ADMIN_LOCAL_SUPABASE_URL
set_new_from_env "$ADMIN_LOCAL_ENV" NEXT_PUBLIC_SUPABASE_ANON_KEY TALKIE_ADMIN_LOCAL_SUPABASE_ANON_KEY

# services/talkie-api is no longer a tracked package. Its ignored .env is mapped
# into the active services/talkie.to namespace.
set_new_from_env "$LEGACY_API_ENV" API_KEY TALKIE_TO_API_KEY
set_new_from_env "$LEGACY_API_ENV" BLOB_READ_WRITE_TOKEN TALKIE_TO_BLOB_READ_WRITE_TOKEN
set_new_from_env "$LEGACY_API_ENV" VERCEL_OIDC_TOKEN TALKIE_TO_VERCEL_OIDC_TOKEN
set_new_from_env "$LEGACY_API_ENV" NEXT_PUBLIC_SUPABASE_URL TALKIE_TO_SUPABASE_URL
set_new_from_env "$LEGACY_API_ENV" NEXT_PUBLIC_SUPABASE_ANON_KEY TALKIE_TO_SUPABASE_ANON_KEY
set_new_from_env "$LEGACY_API_ENV" NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY TALKIE_TO_CLERK_PUBLISHABLE_KEY
set_new_from_env "$LEGACY_API_ENV" CLERK_SECRET_KEY TALKIE_TO_CLERK_SECRET_KEY

if [ "$DELETE_ENV" = 1 ]; then
  assert_only_expected_keys "$ADMIN_ENV" \
    API_KEY BLOB_READ_WRITE_TOKEN VERCEL_OIDC_TOKEN GITHUB_ADMIN_TOKEN \
    GITHUB_REPO_OWNER GITHUB_REPO_NAME NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY
  assert_only_expected_keys "$ADMIN_LOCAL_ENV" \
    API_KEY BLOB_READ_WRITE_TOKEN VERCEL_OIDC_TOKEN GITHUB_ADMIN_TOKEN \
    GITHUB_REPO_OWNER GITHUB_REPO_NAME NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY
  assert_only_expected_keys "$LEGACY_API_ENV" \
    API_KEY BLOB_READ_WRITE_TOKEN VERCEL_OIDC_TOKEN NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY CLERK_SECRET_KEY

  delete_env_file "$ADMIN_LOCAL_ENV"
  delete_env_file "$ADMIN_ENV"
  delete_env_file "$LEGACY_API_ENV"
fi

if [ "$APPLY" = 1 ]; then
  echo "secret migration complete" >&2
else
  echo "dry run complete; rerun with --apply to store keys" >&2
fi

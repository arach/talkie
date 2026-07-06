#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${TALKIE_ROOT:-}"
if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
SIBLING_ROOT="${TALKIE_SIBLING_ROOT:-$(cd "$ROOT_DIR/.." && pwd)}"
HUDSON_REF="${HUDSON_REF:-main}"
OPENSCOUT_REF="${OPENSCOUT_REF:-main}"
SSH_KEY_FILES=()

cleanup_ssh_keys() {
    if [ "${#SSH_KEY_FILES[@]}" -eq 0 ]; then
        return
    fi

    for key_file in "${SSH_KEY_FILES[@]}"; do
        rm -f "$key_file"
    done
}
trap cleanup_ssh_keys EXIT

write_ssh_key() {
    local label="$1"
    local key_contents="$2"
    local key_file

    key_file="$(mktemp "${RUNNER_TEMP:-/tmp}/talkie-${label}-key.XXXXXX")"
    printf '%s\n' "$key_contents" > "$key_file"
    chmod 600 "$key_file"
    SSH_KEY_FILES+=("$key_file")
    printf '%s' "$key_file"
}

clone_with_optional_token() {
    local repo="$1"
    local ref="$2"
    local destination="$3"
    local token="$4"

    mkdir -p "$destination"
    git -C "$destination" init --quiet
    git -C "$destination" remote add origin "https://github.com/${repo}.git"

    if [ -n "$token" ]; then
        local auth
        auth="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
        git -C "$destination" \
            -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth}" \
            fetch --depth 1 origin "$ref"
    else
        git -C "$destination" fetch --depth 1 origin "$ref"
    fi

    git -C "$destination" checkout --quiet --detach FETCH_HEAD
}

clone_with_deploy_key() {
    local repo="$1"
    local ref="$2"
    local destination="$3"
    local key_contents="$4"
    local key_file

    key_file="$(write_ssh_key "${repo//\//-}" "$key_contents")"

    mkdir -p "$destination"
    git -C "$destination" init --quiet
    git -C "$destination" remote add origin "git@github.com:${repo}.git"
    GIT_SSH_COMMAND="ssh -i $key_file -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
        git -C "$destination" fetch --depth 1 origin "$ref"
    git -C "$destination" checkout --quiet --detach FETCH_HEAD
}

prepare_checkout() {
    local label="$1"
    local repo="$2"
    local ref="$3"
    local destination="$4"
    local required_path="$5"
    local private_repo="${6:-false}"

    if [ -e "$destination/$required_path" ]; then
        echo "Using existing $label checkout: $destination"
        return
    fi

    if [ -e "$destination" ] && [ -n "$(ls -A "$destination" 2>/dev/null)" ]; then
        echo "Expected $label checkout at $destination, but it is not a usable checkout." >&2
        echo "Missing: $destination/$required_path" >&2
        exit 1
    fi

    local token=""
    local deploy_key=""
    if [ "$private_repo" = "true" ]; then
        deploy_key="${HUDSON_DEPLOY_KEY:-}"
        token="${HUDSON_REPO_TOKEN:-}"
        if [ -z "$deploy_key" ] && [ -z "$token" ] && [ "${CI:-}" = "true" ]; then
            echo "Missing HUDSON_DEPLOY_KEY or HUDSON_REPO_TOKEN for private $repo checkout." >&2
            echo "Create a repository or release-environment secret with read access to $repo." >&2
            exit 1
        fi
        token="${token:-${GH_TOKEN:-}}"
    fi

    echo "Cloning $label ($repo@$ref) into $destination"
    mkdir -p "$(dirname "$destination")"

    if [ -n "$deploy_key" ]; then
        clone_with_deploy_key "$repo" "$ref" "$destination" "$deploy_key"
    elif command -v gh >/dev/null 2>&1 && [ -z "$token" ] && gh auth status >/dev/null 2>&1; then
        gh repo clone "$repo" "$destination" -- --no-checkout
        git -C "$destination" fetch --depth 1 origin "$ref"
        git -C "$destination" checkout --quiet --detach FETCH_HEAD
    else
        clone_with_optional_token "$repo" "$ref" "$destination" "$token"
    fi

    if [ ! -e "$destination/$required_path" ]; then
        echo "$label checkout completed, but $required_path was not found in $destination." >&2
        exit 1
    fi
}

prepare_checkout \
    "Hudson" \
    "arach/hudson" \
    "$HUDSON_REF" \
    "$SIBLING_ROOT/hudson" \
    "Package.swift" \
    true

prepare_checkout \
    "OpenScout native core" \
    "arach/openscout" \
    "$OPENSCOUT_REF" \
    "$SIBLING_ROOT/openscout" \
    "packages/scout-native-core/Package.swift"

echo "Local package checkouts are ready under $SIBLING_ROOT"

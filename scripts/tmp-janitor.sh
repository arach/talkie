#!/bin/bash
set -euo pipefail

mode="dry-run"
max_age_seconds="${TALKIE_JANITOR_MIN_AGE_SECONDS:-$((24 * 60 * 60))}"
cache_root="${TALKIE_JANITOR_CACHE_ROOT:-$HOME/Library/Caches/codex-builds}"
trash_root="${TALKIE_JANITOR_TRASH_ROOT:-$HOME/.Trash}"
legacy_tmp_root="${TALKIE_JANITOR_TMP_ROOT:-/private/tmp}"

usage() {
    echo "Usage: $0 [--dry-run | --delete]"
}

case "${1:---dry-run}" in
    --dry-run)
        ;;
    --delete)
        mode="delete"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

now="$(date +%s)"
removed=0
reclaimed_kib=0

is_talkie_workspace() {
    local workspace="$1"

    case "$workspace" in
        *.xcodeproj|*.xcworkspace)
            ;;
        *)
            return 1
            ;;
    esac

    case "$workspace" in
        */talkie/*|*/talkie-*/*|*/talkie_*/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_under_root() {
    local candidate="$1"
    local root="$2"

    case "$candidate/" in
        "$root"/*/)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prune_candidate() {
    local info_plist="$1"
    local root="$2"
    local candidate workspace modified age size_kib

    candidate="${info_plist%/info.plist}"
    is_under_root "$candidate" "$root" || return 0
    [[ -d "$candidate" && ! -L "$candidate" ]] || return 0

    workspace="$(plutil -extract WorkspacePath raw -o - "$info_plist" 2>/dev/null || true)"
    is_talkie_workspace "$workspace" || return 0

    modified="$(stat -f '%m' "$info_plist" 2>/dev/null || echo "$now")"
    age=$((now - modified))
    (( age >= max_age_seconds )) || return 0

    if lsof +D "$candidate" >/dev/null 2>&1; then
        echo "skip open: $candidate"
        return
    fi

    size_kib="$(du -sk "$candidate" 2>/dev/null | awk '{print $1}' || true)"
    size_kib="${size_kib:-0}"

    if [[ "$mode" == "delete" ]]; then
        rm -rf -- "$candidate"
        echo "removed: $candidate"
        removed=$((removed + 1))
        reclaimed_kib=$((reclaimed_kib + size_kib))
    else
        echo "would remove: $candidate"
    fi
}

scan_root() {
    local root="$1"
    local depth="$2"
    local info_plist

    [[ -d "$root" ]] || return 0
    if ! /bin/ls -A "$root" >/dev/null 2>&1; then
        echo "skip inaccessible: $root" >&2
        return 0
    fi

    while IFS= read -r -d '' info_plist; do
        prune_candidate "$info_plist" "$root"
    done < <(find "$root" -mindepth 2 -maxdepth "$depth" -type f -name info.plist -print0 2>/dev/null)
}

scan_root "$cache_root" 4
scan_root "$trash_root" 4
scan_root "$legacy_tmp_root" 5

if [[ "$mode" == "delete" ]]; then
    echo "removed $removed cache(s), reclaimed approximately $((reclaimed_kib / 1024)) MiB"
else
    echo "dry run complete; pass --delete to remove the listed caches"
fi

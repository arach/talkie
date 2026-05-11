#!/bin/bash
# launchctl-status.sh — Show status of all Talkie launch registrations
# Usage: ./scripts/launchctl-status.sh [--clean]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

CLEAN=false
if [[ "${1:-}" == "--clean" ]]; then
    CLEAN=true
fi

UID_VAL=$(id -u)
STALE=()

echo ""
echo -e "${BOLD}Talkie Launch Registrations${RESET}"
echo "─────────────────────────────────────────────"

while IFS=$'\t' read -r pid status label; do
    pid=$(echo "$pid" | xargs)
    status=$(echo "$status" | xargs)
    label=$(echo "$label" | xargs)

    # Determine state
    if [[ "$pid" == "-" && "$status" == "78" ]]; then
        # Not running, could not find (stale registration or stopped service)
        state="${YELLOW}■ not running${RESET}"
        STALE+=("$label")
    elif [[ "$status" == "-15" || "$status" == "-9" ]]; then
        # Crashed (SIGTERM / SIGKILL)
        state="${RED}✗ crashed (signal $((-status)))${RESET}"
        STALE+=("$label")
    elif [[ "$status" != "0" && "$pid" == "-" ]]; then
        # Error exit, not running
        state="${RED}✗ exited ($status)${RESET}"
        STALE+=("$label")
    elif [[ "$pid" != "-" && "$status" == "0" ]]; then
        # Running normally
        state="${GREEN}● running${RESET} ${DIM}pid $pid${RESET}"
    else
        state="${DIM}? pid=$pid status=$status${RESET}"
    fi

    # Classify: launchd-managed vs app-launched
    if [[ "$label" == application.* ]]; then
        kind="${DIM}(app)${RESET}"
    else
        kind="${DIM}(launchd)${RESET}"
    fi

    printf "  %-45s %s %s\n" "$label" "$state" "$kind"

done < <(launchctl list | grep -i talkie || true)

echo ""

if [[ ${#STALE[@]} -eq 0 ]]; then
    echo -e "${GREEN}No stale registrations.${RESET}"
else
    echo -e "${YELLOW}${#STALE[@]} stale registration(s):${RESET}"
    for label in "${STALE[@]}"; do
        echo -e "  ${DIM}$label${RESET}"
    done
    echo ""

    if $CLEAN; then
        echo -e "${BOLD}Cleaning up...${RESET}"
        for label in "${STALE[@]}"; do
            echo -n "  bootout $label ... "
            if launchctl bootout "gui/$UID_VAL/$label" 2>/dev/null; then
                echo -e "${GREEN}done${RESET}"
            else
                echo -e "${RED}failed${RESET}"
            fi
        done
        echo ""
    else
        echo -e "Run with ${BOLD}--clean${RESET} to bootout stale registrations."
    fi
fi

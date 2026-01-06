#!/bin/bash
#
# TalkieGateway Service Runner
# Called by launchd - runs without TTY
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CCTL="$PROJECT_ROOT/external/containerization/bin/cctl"
KERNEL="$PROJECT_ROOT/external/containerization/bin/vmlinux"
GATEWAY_DIR="$PROJECT_ROOT/macOS/TalkieGateway"

CONTAINER_IP="192.168.64.10/24"
GATEWAY_IP="192.168.64.1"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "TalkieGateway service starting..."
log "CCTL: $CCTL"
log "Kernel: $KERNEL"
log "Gateway: $GATEWAY_DIR"
log "Container IP: ${CONTAINER_IP%/*}"

# Verify dependencies
if [ ! -f "$CCTL" ]; then
    log "ERROR: cctl not found"
    exit 1
fi

if [ ! -f "$KERNEL" ]; then
    log "ERROR: kernel not found"
    exit 1
fi

# Source Swift environment if needed
if [ -f "$HOME/.swiftly/env.sh" ]; then
    source "$HOME/.swiftly/env.sh"
fi

log "Starting container..."

# Run container - use script to provide pseudo-TTY for cctl
script -q /dev/null $CCTL run \
    --kernel "$KERNEL" \
    --id talkie-gateway \
    -i docker.io/oven/bun:1.1-alpine \
    --mount "$GATEWAY_DIR:/app" \
    --cwd /app \
    --ip "$CONTAINER_IP" \
    --gateway "$GATEWAY_IP" \
    --ns "8.8.8.8" \
    -m 512 \
    /bin/sh -c "cd /app && bun install --frozen-lockfile 2>/dev/null; exec bun run src/server.ts"

EXIT_CODE=$?
log "Container exited with code: $EXIT_CODE"
exit $EXIT_CODE

#!/bin/bash
#
# Debug: Interactive shell in container
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CCTL="$PROJECT_ROOT/external/containerization/bin/TalkieGateway"
KERNEL="$PROJECT_ROOT/external/containerization/bin/vmlinux"
GATEWAY_DIR="$PROJECT_ROOT/macOS/TalkieGateway"

CONTAINER_IP="192.168.64.10/24"
GATEWAY_IP="192.168.64.1"

echo "=== Debug Container ==="
echo "Mounting: $GATEWAY_DIR -> /app"
echo "You'll get a shell. Try:"
echo "  ls /app"
echo "  cd /app && bun install"
echo "  bun run src/server.ts"
echo ""

$CCTL run \
    --kernel "$KERNEL" \
    --id talkie-debug \
    -i docker.io/oven/bun:1.1-alpine \
    --mount "$GATEWAY_DIR:/app" \
    --cwd /app \
    --ip "$CONTAINER_IP" \
    --gateway "$GATEWAY_IP" \
    --ns "8.8.8.8" \
    -m 512 \
    /bin/sh

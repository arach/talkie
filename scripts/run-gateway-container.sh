#!/bin/bash
#
# Run TalkieGateway in Apple Container
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CCTL="$PROJECT_ROOT/external/containerization/bin/TalkieGateway"
KERNEL="$PROJECT_ROOT/external/containerization/bin/vmlinux"
GATEWAY_DIR="$PROJECT_ROOT/macOS/TalkieGateway"

echo "=== TalkieGateway Container ==="
echo ""

# Verify setup
if [ ! -f "$CCTL" ]; then
    echo "Error: cctl not found. Run setup-containerization.sh first."
    exit 1
fi

if [ ! -f "$KERNEL" ]; then
    echo "Error: kernel not found. Run setup-containerization.sh first."
    exit 1
fi

echo "Mounting: $GATEWAY_DIR -> /app"
echo "Image: docker.io/oven/bun:1.1-alpine"
echo ""
echo "Starting Gateway on port 8080..."
echo "Press Ctrl+C to stop"
echo ""

# Container gets its own IP on vmnet network
# Default vmnet subnet is typically 192.168.64.0/24
CONTAINER_IP="192.168.64.10/24"
GATEWAY_IP="192.168.64.1"

echo "Container IP: ${CONTAINER_IP%/*}"
echo "After startup, access Gateway at: http://${CONTAINER_IP%/*}:8080"
echo ""

$CCTL run \
    --kernel "$KERNEL" \
    --id talkie-gateway \
    -i docker.io/oven/bun:1.1-alpine \
    --mount "$GATEWAY_DIR:/app" \
    --cwd /app \
    --ip "$CONTAINER_IP" \
    --gateway "$GATEWAY_IP" \
    --ns "8.8.8.8" \
    -m 512 \
    /app/start.sh

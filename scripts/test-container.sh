#!/bin/bash
#
# Test Apple Container with Bun
#
# Run this manually from Terminal to verify containerization works.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CCTL="$PROJECT_ROOT/external/containerization/bin/TalkieGateway"
KERNEL="$PROJECT_ROOT/external/containerization/bin/vmlinux"

echo "=== Testing Apple Container ==="
echo "cctl: $CCTL"
echo "kernel: $KERNEL"
echo ""

# Verify files exist
if [ ! -f "$CCTL" ]; then
    echo "Error: cctl not found. Run setup-containerization.sh first."
    exit 1
fi

if [ ! -f "$KERNEL" ]; then
    echo "Error: kernel not found. Run setup-containerization.sh first."
    exit 1
fi

echo "Running: bun --version in container..."
echo ""

$CCTL run \
    --kernel "$KERNEL" \
    -i docker.io/oven/bun:1.1-alpine \
    bun --version

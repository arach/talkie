#!/bin/sh
#
# TalkieGateway Container Startup
#

set -e

echo "[start.sh] Installing supervisor..."
apk add --no-cache supervisor

echo "[start.sh] Installing npm dependencies..."
cd /app
bun install --frozen-lockfile 2>/dev/null || bun install

echo "[start.sh] Starting supervisord..."
exec supervisord -n -c /app/supervisord.conf

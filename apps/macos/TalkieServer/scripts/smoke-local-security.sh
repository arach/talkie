#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TEST_HOME="$TMP_DIR/home"
PORT="${TALKIE_SMOKE_PORT:-18765}"
SOCKET_PATH="$TMP_DIR/talkie-server.sock"
SERVER_LOG="$TMP_DIR/server.log"
NEARBY_LOG="$TMP_DIR/nearby.log"
SENTINEL="$TMP_DIR/should-not-run"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "smoke-local-security: $*" >&2
  echo "--- server log ---" >&2
  sed -n '1,220p' "$SERVER_LOG" >&2 || true
  echo "--- nearby log ---" >&2
  sed -n '1,120p' "$NEARBY_LOG" >&2 || true
  exit 1
}

status_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@" 2>/dev/null
}

mkdir -p "$TEST_HOME"
cd "$SERVER_DIR"

HOME="$TEST_HOME" \
TALKIE_SERVER_UNIX_SOCKET="$SOCKET_PATH" \
bun run src/server.ts --local --port "$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"

for _ in {1..80}; do
  if [[ "$(status_code "http://127.0.0.1:$PORT/health" || true)" == "200" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "server exited before health check passed"
  fi
  sleep 0.25
done

[[ "$(status_code "http://127.0.0.1:$PORT/health" || true)" == "200" ]] \
  || fail "local health endpoint did not become ready"

grep -q "TalkieServer HTTP at http://127.0.0.1:$PORT" "$SERVER_LOG" \
  || fail "local mode did not report a loopback bind"

TOKEN_FILE="$TEST_HOME/Library/Application Support/Talkie/Bridge/.config/.local-auth-token"
[[ -f "$TOKEN_FILE" ]] || fail "local auth token file was not created"

token_mode="$(stat -f "%Lp" "$TOKEN_FILE" 2>/dev/null || stat -c "%a" "$TOKEN_FILE")"
[[ "$token_mode" == "600" ]] || fail "expected token mode 600, got $token_mode"

[[ -S "$SOCKET_PATH" ]] || fail "Unix socket was not created"
socket_mode="$(stat -f "%Lp" "$SOCKET_PATH" 2>/dev/null || stat -c "%a" "$SOCKET_PATH")"
[[ "$socket_mode" == "600" ]] || fail "expected socket mode 600, got $socket_mode"

evil_origin_status="$(
  status_code -H "Origin: https://evil.example" "http://127.0.0.1:$PORT/health"
)"
[[ "$evil_origin_status" == "403" ]] || fail "expected hostile origin 403, got $evil_origin_status"

unauth_cli_status="$(
  status_code \
    -H "Content-Type: application/json" \
    -d '{"command":"talkie --version"}' \
    "http://127.0.0.1:$PORT/cli"
)"
[[ "$unauth_cli_status" == "401" ]] || fail "expected unauthenticated /cli 401, got $unauth_cli_status"

token="$(cat "$TOKEN_FILE")"
curl -sS \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d "{\"command\":\"talkie --version; touch $SENTINEL\"}" \
  "http://127.0.0.1:$PORT/cli" >/dev/null

[[ ! -e "$SENTINEL" ]] || fail "/cli command created sentinel through a shell separator"

nearby_port="$((PORT + 1))"
HOME="$TMP_DIR/nearby-home" \
TALKIE_SERVER_UNIX_SOCKET="$TMP_DIR/nearby.sock" \
bun run src/server.ts --nearby --port "$nearby_port" >"$NEARBY_LOG" 2>&1 &
nearby_pid="$!"
sleep 2
if kill -0 "$nearby_pid" 2>/dev/null; then
  kill "$nearby_pid" 2>/dev/null || true
  wait "$nearby_pid" 2>/dev/null || true
  fail "nearby mode started without --allow-lan"
fi
wait "$nearby_pid" || nearby_status="$?"
nearby_status="${nearby_status:-0}"
[[ "$nearby_status" != "0" ]] || fail "nearby mode exited successfully without --allow-lan"
grep -q -- "--allow-lan" "$NEARBY_LOG" \
  || fail "nearby refusal did not mention --allow-lan"

echo "TalkieServer local security smoke passed"

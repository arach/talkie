#!/usr/bin/env bash
#
# proc-watchdog.sh — poll a process tree by pattern, terminate if it
# crosses an RSS or process-count threshold. Safety net for running
# things that might run away (e.g. Hudson dev + Next consumer with
# bad config).
#
# Usage:
#   scripts/proc-watchdog.sh <pattern> [opts]
#
# Options:
#   --max-rss-mb N      total RSS (MB) across all matching PIDs (default 3500)
#   --max-procs N       max number of matching processes (default 80)
#   --interval N        poll interval in seconds (default 10)
#   --grace N           seconds between SIGTERM and SIGKILL (default 5)
#   --idle-exit         exit when no matching processes for 30s
#
# Examples:
#   # Watch Hudson + Next dev under talkie/studio while you test
#   scripts/proc-watchdog.sh 'next dev|next-server|tsup|hudsonkit|tailwindcss' --max-rss-mb 3000
#
#   # Custom thresholds
#   scripts/proc-watchdog.sh 'bun.*next' --max-rss-mb 2500 --interval 5
#
# Logs to stderr. Exit codes:
#   0 — exited cleanly (idle-exit) or stopped by user
#   1 — killed processes due to threshold breach
#   2 — argument error

set -uo pipefail

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,28p' "$0" >&2
  [ $# -eq 0 ] && exit 2 || exit 0
fi

PATTERN="$1"
shift

MAX_RSS_MB=3500
MAX_PROCS=80
INTERVAL=10
GRACE=5
IDLE_EXIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --max-rss-mb)  MAX_RSS_MB="$2"; shift 2 ;;
    --max-procs)   MAX_PROCS="$2"; shift 2 ;;
    --interval)    INTERVAL="$2"; shift 2 ;;
    --grace)       GRACE="$2"; shift 2 ;;
    --idle-exit)   IDLE_EXIT=1; shift ;;
    -h|--help)     sed -n '2,28p' "$0" >&2; exit 0 ;;
    *) echo "[watchdog] unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[watchdog %s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

log "pattern=\"$PATTERN\" | max RSS=${MAX_RSS_MB}MB | max procs=${MAX_PROCS} | interval=${INTERVAL}s"

cleanup_running=0
trap 'log "received signal; exiting"; exit 0' INT TERM

idle_ticks=0

while true; do
  pids=$(pgrep -f "$PATTERN" 2>/dev/null | tr '\n' ' ')

  if [ -z "${pids// }" ]; then
    if [ "$IDLE_EXIT" = "1" ]; then
      idle_ticks=$((idle_ticks + 1))
      if [ "$idle_ticks" -ge 3 ]; then
        log "no matching processes for $((idle_ticks * INTERVAL))s — exiting (idle-exit)"
        exit 0
      fi
    fi
    log "no matching processes"
    sleep "$INTERVAL"
    continue
  fi
  idle_ticks=0

  # Aggregate RSS (KB) and proc count
  total_rss_kb=$(ps -o rss= -p $pids 2>/dev/null | awk '{s+=$1} END {print s+0}')
  total_rss_mb=$(( total_rss_kb / 1024 ))
  proc_count=$(echo "$pids" | wc -w | tr -d ' ')

  # Optional CPU% sum (not used as a kill trigger; just visibility)
  total_cpu=$(ps -o %cpu= -p $pids 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s+0}')

  log "procs=$proc_count | RSS=${total_rss_mb}MB | CPU=${total_cpu}%"

  breach=""
  if [ "$total_rss_mb" -gt "$MAX_RSS_MB" ]; then
    breach="RSS ${total_rss_mb}MB > ${MAX_RSS_MB}MB"
  elif [ "$proc_count" -gt "$MAX_PROCS" ]; then
    breach="procs ${proc_count} > ${MAX_PROCS}"
  fi

  if [ -n "$breach" ]; then
    log "!!! BREACH: $breach — sending SIGTERM"
    kill -TERM $pids 2>/dev/null || true
    sleep "$GRACE"
    leftover=$(pgrep -f "$PATTERN" 2>/dev/null | tr '\n' ' ')
    if [ -n "${leftover// }" ]; then
      log "!!! still alive after ${GRACE}s — sending SIGKILL to: $leftover"
      kill -KILL $leftover 2>/dev/null || true
    fi
    log "done — exiting after threshold breach"
    exit 1
  fi

  sleep "$INTERVAL"
done

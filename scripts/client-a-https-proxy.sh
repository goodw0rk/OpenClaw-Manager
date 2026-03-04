#!/usr/bin/env bash
set -euo pipefail

NAME="client-a-https"
CFG="/opt/openclaw/instances/client-a/Caddyfile"
LOG="/opt/openclaw/instances/client-a/logs/caddy-https.log"

usage() {
  cat <<'EOF'
Usage:
  client-a-https-proxy.sh start
  client-a-https-proxy.sh stop
  client-a-https-proxy.sh restart
  client-a-https-proxy.sh status
EOF
}

running() {
  screen -ls 2>/dev/null | grep -q "[.]${NAME}[[:space:]]"
}

start_proxy() {
  if running; then
    echo "HTTPS proxy already running (${NAME})"
    return
  fi
  mkdir -p "$(dirname "$LOG")"
  screen -dmS "${NAME}" bash -lc "exec caddy run --config '${CFG}' --adapter caddyfile >>'${LOG}' 2>&1"
  sleep 1
  if running; then
    echo "Started HTTPS proxy on :19443"
  else
    echo "Failed to start HTTPS proxy. Check ${LOG}" >&2
    exit 1
  fi
}

stop_proxy() {
  if running; then
    screen -S "${NAME}" -X quit || true
    echo "Stopped HTTPS proxy (${NAME})"
  else
    echo "HTTPS proxy is not running"
  fi
}

status_proxy() {
  if running; then
    echo "HTTPS proxy: running (${NAME})"
  else
    echo "HTTPS proxy: stopped"
  fi
}

cmd="${1:-}"
case "$cmd" in
  start) start_proxy ;;
  stop) stop_proxy ;;
  restart) stop_proxy; start_proxy ;;
  status) status_proxy ;;
  -h|--help|"") usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 2 ;;
esac

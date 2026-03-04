#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/openclaw/instances"
DEFAULT_BIND="loopback"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"

usage() {
  cat <<'EOF'
Usage:
  openclaw_client_instance.sh init <client> <port>
  openclaw_client_instance.sh start <client>
  openclaw_client_instance.sh stop <client>
  openclaw_client_instance.sh restart <client>
  openclaw_client_instance.sh status <client>
  openclaw_client_instance.sh health <client>
  openclaw_client_instance.sh list

Notes:
  - Each client is isolated under /opt/openclaw/instances/<client>
  - Main instance on port 18789 is protected; this script refuses to use it
EOF
}

require_tools() {
  command -v "$OPENCLAW_BIN" >/dev/null 2>&1 || {
    echo "openclaw binary not found: $OPENCLAW_BIN" >&2
    exit 1
  }
  command -v curl >/dev/null 2>&1 || {
    echo "'curl' command is required" >&2
    exit 1
  }
  command -v screen >/dev/null 2>&1 || {
    echo "'screen' command is required" >&2
    exit 1
  }
}

sanitize_client() {
  local client="$1"
  if [[ ! "$client" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid client name: $client (allowed: a-z A-Z 0-9 . _ -)" >&2
    exit 2
  fi
}

port_in_use() {
  local port="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 bash -lc ":</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
    return $?
  fi
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

instance_dir() {
  echo "${BASE_DIR}/$1"
}

session_name() {
  echo "openclaw-${1}"
}

screen_session_exists() {
  local name="$1"
  local lines
  lines="$(screen -ls 2>/dev/null | grep "[.]${name}[[:space:]]" || true)"
  [[ -n "$lines" ]] || return 1
  echo "$lines" | grep -viq "dead"
}

load_env() {
  local client="$1"
  local inst_dir
  inst_dir="$(instance_dir "$client")"
  local env_file="${inst_dir}/instance.env"
  if [[ ! -f "$env_file" ]]; then
    echo "Instance not initialized: $client" >&2
    echo "Run: $0 init ${client} <port>" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  source "$env_file"
  OPENCLAW_SESSION_NAME="${OPENCLAW_SESSION_NAME:-$(session_name "$client")}"
}

init_instance() {
  local client="$1"
  local port="$2"
  local inst_dir state_dir log_dir run_dir workspace_dir cfg token env_file

  sanitize_client "$client"
  [[ "$port" =~ ^[0-9]+$ ]] || { echo "Invalid port: $port" >&2; exit 2; }
  if [[ "$port" -eq 18789 ]]; then
    echo "Port 18789 is reserved for the main OpenClaw instance" >&2
    exit 2
  fi
  if port_in_use "$port"; then
    echo "Port ${port} is already in use" >&2
    exit 2
  fi

  inst_dir="$(instance_dir "$client")"
  state_dir="${inst_dir}/state"
  log_dir="${inst_dir}/logs"
  run_dir="${inst_dir}/run"
  workspace_dir="${inst_dir}/workspace"
  cfg="${inst_dir}/openclaw.json"
  token="$(random_token)"
  env_file="${inst_dir}/instance.env"

  mkdir -p "$state_dir" "$log_dir" "$run_dir" "$workspace_dir"
  cat >"$cfg" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "${DEFAULT_BIND}",
    "port": ${port},
    "auth": {
      "mode": "token",
      "token": "${token}"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "agents": {
    "defaults": {
      "workspace": "${workspace_dir}"
    }
  }
}
EOF

  cat >"$env_file" <<EOF
CLIENT_NAME=${client}
OPENCLAW_SESSION_NAME=$(session_name "$client")
OPENCLAW_BIND=${DEFAULT_BIND}
OPENCLAW_GATEWAY_PORT=${port}
OPENCLAW_GATEWAY_TOKEN=${token}
OPENCLAW_STATE_DIR=${state_dir}
OPENCLAW_CONFIG_PATH=${cfg}
OPENCLAW_INSTANCE_DIR=${inst_dir}
OPENCLAW_LOG_PATH=${log_dir}/gateway.out
OPENCLAW_PID_FILE=${run_dir}/gateway.pid
EOF

  chmod 600 "$env_file"
  echo "Initialized instance '${client}' on port ${port}"
  echo "Config: ${env_file}"
}

start_instance() {
  local client="$1"
  load_env "$client"

  if [[ "${OPENCLAW_GATEWAY_PORT}" -eq 18789 ]]; then
    echo "Refusing to start on reserved port 18789" >&2
    exit 2
  fi

  if [[ -f "${OPENCLAW_PID_FILE}" ]]; then
    local existing_pid
    existing_pid="$(cat "${OPENCLAW_PID_FILE}")"
    if kill -0 "${existing_pid}" 2>/dev/null; then
      echo "Instance '${client}' already running (pid ${existing_pid})"
      return
    fi
  fi

  if screen_session_exists "${OPENCLAW_SESSION_NAME}"; then
    echo "Instance '${client}' already running in screen session ${OPENCLAW_SESSION_NAME}"
    return
  fi

  if port_in_use "${OPENCLAW_GATEWAY_PORT}"; then
    echo "Port ${OPENCLAW_GATEWAY_PORT} already in use; cannot start ${client}" >&2
    exit 2
  fi

  screen -dmS "${OPENCLAW_SESSION_NAME}" bash -lc "export OPENCLAW_GATEWAY_TOKEN='${OPENCLAW_GATEWAY_TOKEN}'; export OPENCLAW_STATE_DIR='${OPENCLAW_STATE_DIR}'; export OPENCLAW_CONFIG_PATH='${OPENCLAW_CONFIG_PATH}'; exec '${OPENCLAW_BIN}' gateway run --bind '${OPENCLAW_BIND}' --port '${OPENCLAW_GATEWAY_PORT}' >>'${OPENCLAW_LOG_PATH}' 2>&1"

  for _ in $(seq 1 30); do
    if port_in_use "${OPENCLAW_GATEWAY_PORT}" || curl -sS -m 1 "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/__openclaw__/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if (port_in_use "${OPENCLAW_GATEWAY_PORT}" || curl -sS -m 2 "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/__openclaw__/health" >/dev/null 2>&1) \
    && screen_session_exists "${OPENCLAW_SESSION_NAME}"; then
    local real_pid
    real_pid="$(sed -n 's/.*PID \([0-9]\+\)).*/\1/p' "${OPENCLAW_LOG_PATH}" | tail -n1 || true)"
    if [[ -n "${real_pid}" ]]; then
      echo "${real_pid}" >"${OPENCLAW_PID_FILE}"
    fi
    echo "Started '${client}' on 127.0.0.1:${OPENCLAW_GATEWAY_PORT}"
  else
    echo "Failed to start '${client}'. Check logs: ${OPENCLAW_LOG_PATH}" >&2
    exit 1
  fi
}

stop_instance() {
  local client="$1"
  load_env "$client"
  if [[ ! -f "${OPENCLAW_PID_FILE}" ]]; then
    echo "No pid file for '${client}' (already stopped?)"
    return
  fi
  local pid
  pid="$(cat "${OPENCLAW_PID_FILE}")"
  if screen_session_exists "${OPENCLAW_SESSION_NAME}"; then
    screen -S "${OPENCLAW_SESSION_NAME}" -X quit || true
    sleep 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    pid="$(sed -n 's/.*PID \([0-9]\+\)).*/\1/p' "${OPENCLAW_LOG_PATH}" | tail -n1 || true)"
  fi

  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid"
    fi
    echo "Stopped '${client}' (pid ${pid})"
  else
    echo "Process ${pid} not running"
  fi
  rm -f "${OPENCLAW_PID_FILE}"
}

status_instance() {
  local client="$1"
  load_env "$client"
  local process_state="stopped"
  local socket_listening="no"

  echo "Client: ${client}"
  echo "Port: ${OPENCLAW_GATEWAY_PORT}"
  echo "Bind: ${OPENCLAW_BIND}"
  echo "State: ${OPENCLAW_STATE_DIR}"
  echo "Config: ${OPENCLAW_CONFIG_PATH}"
  echo "Log: ${OPENCLAW_LOG_PATH}"

  if screen_session_exists "${OPENCLAW_SESSION_NAME}"; then
    echo "Screen: running (${OPENCLAW_SESSION_NAME})"
  else
    echo "Screen: not running"
  fi

  if [[ ! -f "${OPENCLAW_PID_FILE}" ]]; then
    local discovered_pid
    discovered_pid="$(sed -n 's/.*PID \([0-9]\+\)).*/\1/p' "${OPENCLAW_LOG_PATH}" | tail -n1 || true)"
    if [[ -n "${discovered_pid}" ]] && kill -0 "${discovered_pid}" 2>/dev/null; then
      echo "${discovered_pid}" >"${OPENCLAW_PID_FILE}"
    fi
  fi

  if [[ -f "${OPENCLAW_PID_FILE}" ]]; then
    local pid
    pid="$(cat "${OPENCLAW_PID_FILE}")"
    if kill -0 "$pid" 2>/dev/null; then
      process_state="running"
      echo "Process: running (pid ${pid})"
    else
      process_state="stale"
      echo "Process: stale pid file (${pid})"
    fi
  else
    echo "Process: stopped"
  fi

  if port_in_use "${OPENCLAW_GATEWAY_PORT}"; then
    socket_listening="yes"
    echo "Socket: listening on ${OPENCLAW_GATEWAY_PORT}"
  else
    echo "Socket: not listening"
  fi

  # Self-heal stale state: clear stale pid file and restart when service is down.
  if [[ "${process_state}" == "stale" && "${socket_listening}" == "no" ]]; then
    echo "Auto-recovery: stale pid with no listener detected; restarting '${client}'..."
    rm -f "${OPENCLAW_PID_FILE}"
    start_instance "${client}" || {
      echo "Auto-recovery failed for '${client}'. Check logs: ${OPENCLAW_LOG_PATH}" >&2
      exit 1
    }
  elif [[ "${process_state}" == "stale" && "${socket_listening}" == "yes" ]]; then
    echo "Auto-recovery: socket is up, so restart skipped (stale pid file only)."
  fi
}

health_instance() {
  local client="$1"
  load_env "$client"
  curl -sS -m 4 -i "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/__openclaw__/health" || {
    echo "Health probe failed for '${client}'" >&2
    exit 1
  }
}

list_instances() {
  mkdir -p "${BASE_DIR}"
  find "${BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec test -f "{}/instance.env" \; -printf '%f\n' | sort
}

main() {
  require_tools
  mkdir -p "${BASE_DIR}"

  local cmd="${1:-}"
  case "$cmd" in
    init)
      [[ $# -eq 3 ]] || { usage; exit 2; }
      init_instance "$2" "$3"
      ;;
    start)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      start_instance "$2"
      ;;
    stop)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      stop_instance "$2"
      ;;
    restart)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      stop_instance "$2"
      start_instance "$2"
      ;;
    status)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      status_instance "$2"
      ;;
    health)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      health_instance "$2"
      ;;
    list)
      [[ $# -eq 1 ]] || { usage; exit 2; }
      list_instances
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"

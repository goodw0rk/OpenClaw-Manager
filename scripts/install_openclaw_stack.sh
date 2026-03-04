#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/openclaw"
MANAGER_PORT="3011"
APP_USER=""
APP_GROUP=""
INIT_CLIENT=""
INIT_PORT=""
START_CLIENT="1"
AUTOSTART_CLIENT="1"
ENABLE_MANAGER="1"
SKIP_APT="0"

usage() {
  cat <<'USAGE'
Usage:
  install_openclaw_stack.sh [options]

Options:
  --user <name>            Linux user to run OpenClaw and manager (default: sudo user)
  --group <name>           Linux group (default: primary group of --user)
  --install-dir <path>     Install path (default: /opt/openclaw)
  --manager-port <port>    Manager HTTP port (default: 3011)
  --client <name>          Initialize first client instance (optional)
  --client-port <port>     Port for --client
  --no-client-start        Do not start client after init
  --no-client-autostart    Do not enable systemd autostart for client
  --no-manager             Do not enable/start openclaw-manager.service
  --skip-apt               Skip apt dependency install
  -h, --help               Show help

Examples:
  sudo ./scripts/install_openclaw_stack.sh --user ubuntu
  sudo ./scripts/install_openclaw_stack.sh --user ubuntu --client bws-bot --client-port 19011
USAGE
}

log() {
  printf "[installer] %s\n" "$*"
}

die() {
  printf "[installer] ERROR: %s\n" "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      APP_USER="${2:-}"
      shift 2
      ;;
    --group)
      APP_GROUP="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --manager-port)
      MANAGER_PORT="${2:-}"
      shift 2
      ;;
    --client)
      INIT_CLIENT="${2:-}"
      shift 2
      ;;
    --client-port)
      INIT_PORT="${2:-}"
      shift 2
      ;;
    --no-client-start)
      START_CLIENT="0"
      shift
      ;;
    --no-client-autostart)
      AUTOSTART_CLIENT="0"
      shift
      ;;
    --no-manager)
      ENABLE_MANAGER="0"
      shift
      ;;
    --skip-apt)
      SKIP_APT="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [[ -z "${APP_USER}" ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    APP_USER="${SUDO_USER}"
  else
    APP_USER="$(whoami)"
  fi
fi

id "${APP_USER}" >/dev/null 2>&1 || die "User does not exist: ${APP_USER}"

if [[ -z "${APP_GROUP}" ]]; then
  APP_GROUP="$(id -gn "${APP_USER}")"
fi

if ! [[ "${MANAGER_PORT}" =~ ^[0-9]+$ ]]; then
  die "--manager-port must be numeric"
fi

if [[ -n "${INIT_CLIENT}" ]] && [[ -z "${INIT_PORT}" ]]; then
  die "--client-port is required when --client is provided"
fi

if [[ -z "${INIT_CLIENT}" ]] && [[ -n "${INIT_PORT}" ]]; then
  die "--client is required when --client-port is provided"
fi

if [[ -n "${INIT_CLIENT}" ]] && ! [[ "${INIT_CLIENT}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  die "Invalid --client name: ${INIT_CLIENT}"
fi

if [[ -n "${INIT_PORT}" ]] && ! [[ "${INIT_PORT}" =~ ^[0-9]+$ ]]; then
  die "--client-port must be numeric"
fi

if [[ "${INIT_PORT}" == "18789" ]]; then
  die "Port 18789 is reserved"
fi

if [[ "$EUID" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

APP_HOME="$(getent passwd "${APP_USER}" | cut -d: -f6)"
[[ -n "${APP_HOME}" ]] || die "Could not determine home directory for ${APP_USER}"

OPENCLAW_BIN="${APP_HOME}/.npm-global/bin/openclaw"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

install_dependencies() {
  if [[ "${SKIP_APT}" == "1" ]]; then
    log "Skipping apt dependency install (--skip-apt)."
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "This installer currently supports apt-based Linux distributions."
  log "Installing OS dependencies via apt..."
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    npm \
    nodejs \
    python3 \
    python3-pip \
    python3-venv \
    rsync \
    screen
}

install_openclaw_binary() {
  log "Installing OpenClaw npm package for user ${APP_USER}..."
  "${SUDO[@]}" -u "${APP_USER}" mkdir -p "${APP_HOME}/.npm-global"
  "${SUDO[@]}" -u "${APP_USER}" npm config set prefix "${APP_HOME}/.npm-global"
  "${SUDO[@]}" -u "${APP_USER}" npm install -g openclaw

  [[ -x "${OPENCLAW_BIN}" ]] || die "OpenClaw binary not found after npm install: ${OPENCLAW_BIN}"

  log "Linking /usr/local/bin/openclaw -> ${OPENCLAW_BIN}"
  "${SUDO[@]}" ln -sf "${OPENCLAW_BIN}" /usr/local/bin/openclaw

  cat <<PATHFILE | "${SUDO[@]}" tee /etc/profile.d/openclaw-path.sh >/dev/null
export PATH="${APP_HOME}/.npm-global/bin:\$PATH"
PATHFILE
}

deploy_repo() {
  log "Deploying files into ${INSTALL_DIR}..."
  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}"

  if [[ "${SOURCE_DIR}" != "${INSTALL_DIR}" ]]; then
    "${SUDO[@]}" rsync -a \
      --exclude '.git' \
      --exclude 'instances' \
      --exclude 'manager/manager.log' \
      "${SOURCE_DIR}/" "${INSTALL_DIR}/"
  fi

  "${SUDO[@]}" mkdir -p "${INSTALL_DIR}/instances"
  "${SUDO[@]}" chown -R "${APP_USER}:${APP_GROUP}" "${INSTALL_DIR}"
  "${SUDO[@]}" chmod +x "${INSTALL_DIR}/scripts/"*
}

render_client_template() {
  local src="${INSTALL_DIR}/systemd/openclaw-client@.service"
  local dst="/etc/systemd/system/openclaw-client@.service"

  [[ -f "${src}" ]] || die "Missing template file: ${src}"

  sed \
    -e "s|__OPENCLAW_USER__|${APP_USER}|g" \
    -e "s|__OPENCLAW_GROUP__|${APP_GROUP}|g" \
    -e "s|__OPENCLAW_BIN__|${OPENCLAW_BIN}|g" \
    "${src}" | "${SUDO[@]}" tee "${dst}" >/dev/null
}

install_manager_service() {
  log "Installing manager Python environment..."
  "${SUDO[@]}" -u "${APP_USER}" python3 -m venv "${INSTALL_DIR}/manager/.venv"
  "${SUDO[@]}" -u "${APP_USER}" "${INSTALL_DIR}/manager/.venv/bin/pip" install --upgrade pip >/dev/null
  "${SUDO[@]}" -u "${APP_USER}" "${INSTALL_DIR}/manager/.venv/bin/pip" install -r "${INSTALL_DIR}/manager/requirements.txt" >/dev/null

  log "Installing systemd service: openclaw-manager.service"
  cat <<SERVICE | "${SUDO[@]}" tee /etc/systemd/system/openclaw-manager.service >/dev/null
[Unit]
Description=OpenClaw Web Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${INSTALL_DIR}/manager
Environment=HOST=0.0.0.0
Environment=PORT=${MANAGER_PORT}
ExecStart=${INSTALL_DIR}/manager/.venv/bin/python ${INSTALL_DIR}/manager/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE
}

init_client_instance_if_requested() {
  if [[ -z "${INIT_CLIENT}" ]]; then
    return
  fi

  local env_path="${INSTALL_DIR}/instances/${INIT_CLIENT}/instance.env"
  if [[ -f "${env_path}" ]]; then
    log "Client ${INIT_CLIENT} already exists; skipping init."
  else
    log "Initializing client ${INIT_CLIENT} on port ${INIT_PORT}..."
    "${SUDO[@]}" -u "${APP_USER}" env OPENCLAW_BIN="${OPENCLAW_BIN}" \
      "${INSTALL_DIR}/scripts/openclaw_client_instance.sh" init "${INIT_CLIENT}" "${INIT_PORT}"
  fi

  if [[ "${START_CLIENT}" == "1" ]]; then
    log "Starting client ${INIT_CLIENT}..."
    "${SUDO[@]}" -u "${APP_USER}" env OPENCLAW_BIN="${OPENCLAW_BIN}" \
      "${INSTALL_DIR}/scripts/openclaw_client_instance.sh" start "${INIT_CLIENT}" || true
  fi

  if [[ "${AUTOSTART_CLIENT}" == "1" ]]; then
    log "Enabling autostart for client ${INIT_CLIENT}..."
    "${SUDO[@]}" systemctl enable --now "openclaw-client@${INIT_CLIENT}.service"
  fi
}

install_dependencies
install_openclaw_binary
deploy_repo
render_client_template
install_manager_service

"${SUDO[@]}" systemctl daemon-reload

if [[ "${ENABLE_MANAGER}" == "1" ]]; then
  log "Enabling and starting openclaw-manager.service..."
  "${SUDO[@]}" systemctl enable --now openclaw-manager.service
else
  log "Manager service installed but not started (--no-manager)."
fi

init_client_instance_if_requested

log "Install complete."
log "Manager URL: http://127.0.0.1:${MANAGER_PORT}"
log "Client template command: ${INSTALL_DIR}/scripts/oc-client <client> status --json"

if [[ -n "${INIT_CLIENT}" ]]; then
  log "Client status command: ${INSTALL_DIR}/scripts/openclaw_client_instance.sh status ${INIT_CLIENT}"
fi

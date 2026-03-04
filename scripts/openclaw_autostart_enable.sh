#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <instance-name>" >&2
  echo "Example: $0 bws-bot" >&2
  exit 2
fi

INSTANCE="$1"
if [[ ! "$INSTANCE" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Invalid instance name: $INSTANCE" >&2
  echo "Allowed: letters, numbers, dot, underscore, dash" >&2
  exit 2
fi

UNIT_TEMPLATE_SRC="/opt/openclaw/systemd/openclaw-client@.service"
UNIT_TEMPLATE_DST="/etc/systemd/system/openclaw-client@.service"
INSTANCE_ENV="/opt/openclaw/instances/${INSTANCE}/instance.env"
UNIT_NAME="openclaw-client@${INSTANCE}.service"
OPENCLAW_USER="${OPENCLAW_USER:-${SUDO_USER:-$USER}}"
OPENCLAW_GROUP="${OPENCLAW_GROUP:-$(id -gn "${OPENCLAW_USER}")}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || true)}"

if [[ -z "${OPENCLAW_BIN}" ]]; then
  OPENCLAW_BIN="/home/${OPENCLAW_USER}/.npm-global/bin/openclaw"
fi

if [[ ! -f "$INSTANCE_ENV" ]]; then
  echo "Instance not found or not initialized: $INSTANCE" >&2
  echo "Expected: $INSTANCE_ENV" >&2
  exit 1
fi

if [[ ! -f "$UNIT_TEMPLATE_SRC" ]]; then
  echo "Missing template file: $UNIT_TEMPLATE_SRC" >&2
  exit 1
fi

sed \
  -e "s|__OPENCLAW_USER__|${OPENCLAW_USER}|g" \
  -e "s|__OPENCLAW_GROUP__|${OPENCLAW_GROUP}|g" \
  -e "s|__OPENCLAW_BIN__|${OPENCLAW_BIN}|g" \
  "$UNIT_TEMPLATE_SRC" | sudo tee "$UNIT_TEMPLATE_DST" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now "$UNIT_NAME"

echo
sudo systemctl status "$UNIT_NAME" --no-pager

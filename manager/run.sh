#!/usr/bin/env bash
set -euo pipefail

cd /opt/openclaw/manager

export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-3011}"

exec python3 app.py

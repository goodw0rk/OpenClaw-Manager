#!/usr/bin/env bash
set -euo pipefail

REPO_URL=""
REF="main"
WORKDIR="/tmp/openclaw-bootstrap"
KEEP_WORKDIR="0"

usage() {
  cat <<'USAGE'
Usage:
  bootstrap.sh --repo <git-repo-url> [options] -- [install.sh options]

Bootstrap options:
  --repo <url>            Git repository URL (required)
  --ref <branch|tag|sha>  Git ref to checkout (default: main)
  --workdir <path>        Temp working directory (default: /tmp/openclaw-bootstrap)
  --keep-workdir          Keep workdir after install
  -h, --help              Show help

Any args after `--` are forwarded to `install.sh`.

Example:
  curl -fsSL <raw-bootstrap-url> | sudo bash -s -- \
    --repo https://github.com/your-org/openclaw.git \
    --ref main -- \
    --user ubuntu --client bws-bot --client-port 19011
USAGE
}

log() {
  printf "[bootstrap] %s\n" "$*"
}

die() {
  printf "[bootstrap] ERROR: %s\n" "$*" >&2
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

FORWARD_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --keep-workdir)
      KEEP_WORKDIR="1"
      shift
      ;;
    --)
      shift
      FORWARD_ARGS=("$@")
      break
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

[[ -n "${REPO_URL}" ]] || die "--repo is required"

if [[ "$EUID" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

if command -v apt-get >/dev/null 2>&1; then
  log "Ensuring bootstrap dependencies are installed (git, ca-certificates, curl)..."
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y git ca-certificates curl
fi

cleanup() {
  if [[ "${KEEP_WORKDIR}" == "1" ]]; then
    log "Keeping workdir: ${WORKDIR}"
    return
  fi
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

log "Preparing workdir: ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

REPO_DIR="${WORKDIR}/repo"
log "Cloning ${REPO_URL} (ref: ${REF})"
git clone --depth 1 --branch "${REF}" "${REPO_URL}" "${REPO_DIR}" 2>/dev/null || {
  log "Shallow branch clone failed; falling back to full clone + checkout"
  git clone "${REPO_URL}" "${REPO_DIR}"
  git -C "${REPO_DIR}" checkout "${REF}"
}

INSTALL_SCRIPT="${REPO_DIR}/install.sh"
[[ -x "${INSTALL_SCRIPT}" ]] || die "install.sh not found or not executable in repo root"

log "Running installer..."
if [[ ${#FORWARD_ARGS[@]} -eq 0 ]]; then
  log "No install args forwarded. Example: -- --user ubuntu --client bws-bot --client-port 19011"
fi

"${INSTALL_SCRIPT}" "${FORWARD_ARGS[@]}"

log "Bootstrap completed successfully."

# OpenClaw Server Installer

This repo now includes an idempotent installer for new servers.

## New Server Bootstrap (Recommended)

From a fresh Ubuntu/Debian host:

```bash
sudo apt-get update && sudo apt-get install -y git
sudo mkdir -p /opt
sudo git clone <your-openclaw-repo-url> /opt/openclaw
cd /opt/openclaw
sudo ./install.sh --user <linux-user> --client bws-bot --client-port 19011
```

If you are not using git, copy this folder to `/opt/openclaw` (scp/rsync/tar), then run:

```bash
cd /opt/openclaw
sudo ./install.sh --user <linux-user> --client bws-bot --client-port 19011
```

## Single-Line Auto Installer

If this repository is already on GitHub/GitLab, users can run a single command:

```bash
curl -fsSL <raw-bootstrap-url> | sudo bash -s -- \
  --repo <git-repo-url> \
  --ref main -- \
  --user <linux-user> --client bws-bot --client-port 19011
```

GitHub example:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/bootstrap.sh | sudo bash -s -- \
  --repo https://github.com/<org>/<repo>.git \
  --ref main -- \
  --user ubuntu --client bws-bot --client-port 19011
```

This uses [`bootstrap.sh`](/opt/openclaw/bootstrap.sh), which:
- installs bootstrap dependencies (`git`, `curl`, `ca-certificates`) if needed
- clones your repo at the selected ref
- runs `install.sh` with forwarded installer options

## Quick Start

Run from this repo:

```bash
sudo ./install.sh --user <linux-user>
```

Example with first client bootstrap:

```bash
sudo ./install.sh --user ubuntu --client bws-bot --client-port 19011
```

## What It Installs

- OS dependencies (`curl`, `git`, `jq`, `screen`, `nodejs`, `npm`, `python3`, `python3-venv`, etc.)
- OpenClaw CLI via npm for the target user
- `/usr/local/bin/openclaw` symlink
- OpenClaw manager Python virtualenv and systemd unit (`openclaw-manager.service`)
- Rendered systemd template for clients (`openclaw-client@.service`) with your target user/group/bin
- Optional first client instance init/start/autostart

## Options

```bash
sudo ./install.sh --help
```

Main options:

- `--user <name>`: required in practice for predictable ownership
- `--group <name>`: optional, defaults to user's primary group
- `--manager-port <port>`: default `3011`
- `--client <name> --client-port <port>`: create first client
- `--no-manager`: install manager service but do not enable/start it
- `--no-client-start`: do not start initial client after init
- `--no-client-autostart`: do not enable `openclaw-client@<name>.service`
- `--skip-apt`: skip apt dependency installation

## Verify

```bash
systemctl status openclaw-manager.service --no-pager
curl -I http://127.0.0.1:3011/

/opt/openclaw/scripts/openclaw_client_instance.sh list
/opt/openclaw/scripts/openclaw_client_instance.sh status <client>
```

## Notes

- Installer currently targets apt-based Linux hosts.
- It keeps existing `/opt/openclaw/instances` data.

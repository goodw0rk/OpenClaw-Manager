# OpenClaw Manager (Multi-Client)

Production-friendly OpenClaw stack for running isolated client instances on one server, with:

- Per-client gateway isolation (`/opt/openclaw/instances/<client>`)
- Web manager dashboard (default `:3011`)
- Systemd autostart for clients
- One-line bootstrap installer for new servers

## Quick Install (One Line)

```bash
curl -fsSL https://raw.githubusercontent.com/goodw0rk/OpenClaw-Manager/main/bootstrap.sh | sudo bash -s -- \
  --repo https://github.com/goodw0rk/OpenClaw-Manager.git \
  --ref main -- \
  --user ubuntu --client bws-bot --client-port 19011
```

Replace `--user ubuntu` with your Linux username.

## What Gets Installed

- OpenClaw CLI via npm
- `/usr/local/bin/openclaw` symlink
- Manager service: `openclaw-manager.service`
- Client template service: `openclaw-client@.service`
- Optional first client init/start/autostart

## Main URLs

- Manager UI: `http://<server-ip>:3011`
- Client canvas: `http://<server-ip>:<client-port>/__openclaw__/canvas/`

## Common Commands

```bash
# Manager service
sudo systemctl status openclaw-manager.service --no-pager

# List clients
/opt/openclaw/scripts/openclaw_client_instance.sh list

# Status / health for a client
/opt/openclaw/scripts/openclaw_client_instance.sh status bws-bot
/opt/openclaw/scripts/openclaw_client_instance.sh health bws-bot

# Client-scoped OpenClaw CLI
/opt/openclaw/scripts/oc-client bws-bot status --json
/opt/openclaw/scripts/oc-client bws-bot devices list --json
```
## Screenshot
  <p align="center">
    <img src="./docs/Screenshot 2026-03-04 at 14.09.59.png" alt="Manager Dashboard"
  width="900" />
  </p>
  
## Docs

- Installer guide: [`INSTALLER.md`](./INSTALLER.md)
- Multi-client notes: [`CLIENTS.md`](./CLIENTS.md)
- Manager details: [`manager/README.md`](./manager/README.md)

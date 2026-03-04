# OpenClaw Multi-Client Setup (Isolated)

This repo now uses `scripts/openclaw_client_instance.sh` to run separate OpenClaw gateways for each client without touching the main instance on `127.0.0.1:18789`.

## Rules

- Never use port `18789` for client instances.
- Each client instance has isolated files under `/opt/openclaw/instances/<client>`.
- Each client uses its own token, config, state, logs, and PID file.
- Each client default workspace is isolated at `/opt/openclaw/instances/<client>/workspace` (`agents.defaults.workspace`).
- Default bind mode is `loopback` to avoid exposing client gateways publicly.
- Runtime uses detached `screen` sessions (`openclaw-<client>`) for durable background execution.

## Quick Start

Current clients:

- `bws-bot` on `19011`
- `client-b` on `19012`

Initialize clients with unique ports:

```bash
/opt/openclaw/scripts/openclaw_client_instance.sh init bws-bot 19011
/opt/openclaw/scripts/openclaw_client_instance.sh init client-b 19012
```

Start and verify:

```bash
/opt/openclaw/scripts/openclaw_client_instance.sh start bws-bot
/opt/openclaw/scripts/openclaw_client_instance.sh status bws-bot
/opt/openclaw/scripts/openclaw_client_instance.sh health bws-bot
```

Stop:

```bash
/opt/openclaw/scripts/openclaw_client_instance.sh stop bws-bot
```

## Global vs Client Terminals

Use separate wrappers to avoid mixing env across terminals:

```bash
# Global/default OpenClaw context
/opt/openclaw/scripts/oc-global status --json
```

```bash
# Client-scoped OpenClaw context
/opt/openclaw/scripts/oc-client bws-bot status --json
/opt/openclaw/scripts/oc-client bws-bot devices list --json
```

## Add New Client

```bash
/opt/openclaw/scripts/openclaw_client_instance.sh init client-c 19013
/opt/openclaw/scripts/openclaw_client_instance.sh start client-c
```

## Logs and Paths

- Base: `/opt/openclaw/instances`
- Per-client env: `/opt/openclaw/instances/<client>/instance.env`
- Per-client logs: `/opt/openclaw/instances/<client>/logs/gateway.out`
- Per-client state: `/opt/openclaw/instances/<client>/state`
- Per-client workspace: `/opt/openclaw/instances/<client>/workspace`

## Workspace Migration (Existing Clients)

If an older client still uses shared workspace paths, patch it:

```bash
client=bws-bot
ws="/opt/openclaw/instances/${client}/workspace"
mkdir -p "$ws"
jq --arg ws "$ws" '.agents = (.agents // {}) | .agents.defaults = (.agents.defaults // {}) | .agents.defaults.workspace = $ws' \
  "/opt/openclaw/instances/${client}/openclaw.json" > "/tmp/${client}.json" && \
  mv "/tmp/${client}.json" "/opt/openclaw/instances/${client}/openclaw.json"
/opt/openclaw/scripts/openclaw_client_instance.sh restart "$client"
```

## Rename a Client

Rename an existing client safely:

```bash
/opt/openclaw/scripts/openclaw_client_instance.sh stop <old-name>
mv /opt/openclaw/instances/<old-name> /opt/openclaw/instances/<new-name>
sed -i 's#/opt/openclaw/instances/<old-name>#/opt/openclaw/instances/<new-name>#g' /opt/openclaw/instances/<new-name>/instance.env
sed -i 's/^CLIENT_NAME=.*/CLIENT_NAME=<new-name>/' /opt/openclaw/instances/<new-name>/instance.env
sed -i 's/^OPENCLAW_SESSION_NAME=.*/OPENCLAW_SESSION_NAME=openclaw-<new-name>/' /opt/openclaw/instances/<new-name>/instance.env
/opt/openclaw/scripts/openclaw_client_instance.sh start <new-name>
```

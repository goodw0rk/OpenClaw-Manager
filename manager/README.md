# OpenClaw Manager (Python + Tailwind)

This dashboard manages OpenClaw clients under `/opt/openclaw` only.

## Features

- List all clients from `/opt/openclaw/instances`
- Start, stop, restart, health-check clients
- Create new client instances (init + optional autostart)
- View per-client gateway logs

## Run

```bash
cd /opt/openclaw/manager
python3 -m pip install -r requirements.txt
./run.sh
```

Default URL:

- `http://127.0.0.1:3011`

## Notes

- Uses `/opt/openclaw/scripts/openclaw_client_instance.sh` for all client operations.
- Does not modify `/home/bws/.openclaw` or port `18789`.

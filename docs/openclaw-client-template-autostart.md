# Reusable systemd template for OpenClaw client instances

This template lets you auto-start any instance under `/opt/openclaw/instances/<name>`.

Template file in this repo:
- `/opt/openclaw/systemd/openclaw-client@.service`

## 1) Install template into systemd

```bash
sudo cp /opt/openclaw/systemd/openclaw-client@.service /etc/systemd/system/openclaw-client@.service
sudo systemctl daemon-reload
```

## 2) Enable/start any instance

Replace `<instance>` with your instance name (example: `bws-bot`).

```bash
sudo systemctl enable --now openclaw-client@<instance>.service
```

Example:

```bash
sudo systemctl enable --now openclaw-client@bws-bot.service
```

## 3) Verify

```bash
sudo systemctl status openclaw-client@bws-bot.service --no-pager
/opt/openclaw/scripts/openclaw_client_instance.sh status bws-bot
/opt/openclaw/scripts/openclaw_client_instance.sh health bws-bot
```

Expected:
- unit status: `active (exited)`
- instance status: socket listening on configured port
- health endpoint returns HTTP `200`

## Daily operations

```bash
sudo systemctl restart openclaw-client@bws-bot.service
sudo systemctl stop openclaw-client@bws-bot.service
sudo systemctl start openclaw-client@bws-bot.service
```

## Disable autostart for one instance

```bash
sudo systemctl disable --now openclaw-client@bws-bot.service
```

## Remove template entirely

```bash
sudo systemctl disable --now openclaw-client@bws-bot.service
sudo rm -f /etc/systemd/system/openclaw-client@.service
sudo systemctl daemon-reload
```

# Auto-start bws-bot on reboot (systemd)

This sets up `bws-bot` to start automatically whenever the machine boots.

## 1) Create the service unit

```bash
sudo tee /etc/systemd/system/openclaw-bws-bot.service >/dev/null <<'UNIT'
[Unit]
Description=OpenClaw bws-bot instance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=bws
Group=bws
Environment=OPENCLAW_BIN=/home/bws/.npm-global/bin/openclaw
ExecStart=/usr/bin/bash -lc '/opt/openclaw/scripts/openclaw_client_instance.sh start bws-bot'
ExecStop=/usr/bin/bash -lc '/opt/openclaw/scripts/openclaw_client_instance.sh stop bws-bot'
ExecReload=/usr/bin/bash -lc '/opt/openclaw/scripts/openclaw_client_instance.sh restart bws-bot'
TimeoutStartSec=90
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT
```

## 2) Enable and start it now

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-bws-bot.service
```

## 3) Verify

```bash
sudo systemctl status openclaw-bws-bot.service --no-pager
/opt/openclaw/scripts/openclaw_client_instance.sh status bws-bot
/opt/openclaw/scripts/openclaw_client_instance.sh health bws-bot
```

Expected:
- service is `active (exited)` (this is normal for `Type=oneshot`)
- `status` shows socket on port `19011`
- `health` returns HTTP `200`

## Useful operations

```bash
sudo systemctl restart openclaw-bws-bot.service
sudo systemctl stop openclaw-bws-bot.service
sudo systemctl start openclaw-bws-bot.service
```

## Remove autostart

```bash
sudo systemctl disable --now openclaw-bws-bot.service
sudo rm -f /etc/systemd/system/openclaw-bws-bot.service
sudo systemctl daemon-reload
```

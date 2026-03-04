#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
from pathlib import Path
from typing import Dict, List, Set, Tuple

from flask import Flask, jsonify, render_template, request

ROOT = Path("/opt/openclaw")
INSTANCES_DIR = ROOT / "instances"
MANAGER_SCRIPT = ROOT / "scripts" / "openclaw_client_instance.sh"
OPENCLAW_BIN = os.getenv("OPENCLAW_BIN", "openclaw")

app = Flask(__name__)

ALLOWED_MANAGER_COMMANDS: Dict[str, int] = {
    "list": 0,
    "start": 1,
    "stop": 1,
    "restart": 1,
    "status": 1,
    "health": 1,
    "init": 2,
}


def run_cmd(args: List[str], timeout: int = 20) -> Tuple[int, str, str]:
    proc = subprocess.run(
        args,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def parse_status_output(text: str) -> Dict[str, str]:
    status: Dict[str, str] = {}
    for line in text.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            status[k.strip().lower().replace(" ", "_")] = v.strip()
    return status


def valid_client_name(name: str) -> bool:
    return bool(re.fullmatch(r"[a-zA-Z0-9._-]+", name))


def list_client_names() -> List[str]:
    code, out, _ = run_cmd([str(MANAGER_SCRIPT), "list"])
    if code != 0:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def collect_client(client: str) -> Dict[str, object]:
    code, out, err = run_cmd([str(MANAGER_SCRIPT), "status", client])
    status = parse_status_output(out)
    status["client"] = client
    status["ok"] = code == 0
    if code != 0:
        status["error"] = err or out or "status command failed"
    status["ws_url"] = f"ws://127.0.0.1:{status.get('port', 'unknown')}"
    status["dashboard_url"] = f"http://127.0.0.1:{status.get('port', 'unknown')}/"
    return status


def parse_manager_command(raw_command: str) -> Tuple[List[str], str | None]:
    raw = raw_command.strip()
    if not raw:
        raise ValueError("command is required")
    if len(raw) > 200:
        raise ValueError("command is too long")

    try:
        tokens = shlex.split(raw)
    except ValueError:
        raise ValueError("invalid command syntax")

    if not tokens:
        raise ValueError("command is required")

    first = tokens[0]
    if first in {
        str(MANAGER_SCRIPT),
        MANAGER_SCRIPT.name,
        f"./{MANAGER_SCRIPT.name}",
    }:
        tokens = tokens[1:]
        if not tokens:
            raise ValueError("missing command after script name")

    cmd = tokens[0].lower()
    args = tokens[1:]
    expected_args = ALLOWED_MANAGER_COMMANDS.get(cmd)
    if expected_args is None:
        allowed = ", ".join(sorted(ALLOWED_MANAGER_COMMANDS.keys()))
        raise ValueError(f"unsupported command: {cmd}. allowed: {allowed}")
    if len(args) != expected_args:
        raise ValueError(f"{cmd} expects {expected_args} argument(s)")

    if cmd in {"start", "stop", "restart", "status", "health", "init"}:
        client = args[0]
        if not valid_client_name(client):
            raise ValueError("invalid client name")
    if cmd == "init":
        port = args[1]
        if not port.isdigit():
            raise ValueError("port must be numeric")
        if int(port) == 18789:
            raise ValueError("port 18789 is reserved")

    return [str(MANAGER_SCRIPT), cmd, *args], args[0] if args else None


def is_safe_token(token: str) -> bool:
    return bool(re.fullmatch(r"[a-zA-Z0-9._:/=@+,\-*~]+", token))


def parse_options(
    args: List[str], allowed_flags: Set[str], allowed_kv: Set[str]
) -> List[str]:
    positionals: List[str] = []
    i = 0
    while i < len(args):
        token = args[i]
        if not is_safe_token(token):
            raise ValueError(f"unsafe token: {token}")

        if token in allowed_flags:
            i += 1
            continue
        if token in allowed_kv:
            if i + 1 >= len(args):
                raise ValueError(f"missing value for {token}")
            value = args[i + 1]
            if not is_safe_token(value):
                raise ValueError(f"unsafe value for {token}")
            i += 2
            continue
        if token.startswith("--"):
            raise ValueError(f"unsupported option: {token}")

        positionals.append(token)
        i += 1
    return positionals


def parse_openclaw_command(raw_command: str) -> List[str]:
    raw = raw_command.strip()
    if not raw:
        raise ValueError("command is required")
    if len(raw) > 300:
        raise ValueError("command is too long")

    try:
        tokens = shlex.split(raw)
    except ValueError:
        raise ValueError("invalid command syntax")
    if not tokens:
        raise ValueError("command is required")

    if tokens[0] == OPENCLAW_BIN:
        tokens = tokens[1:]
    if not tokens:
        raise ValueError("missing openclaw subcommand")
    for token in tokens:
        if not is_safe_token(token):
            raise ValueError(f"unsafe token: {token}")

    top = tokens[0]
    rest = tokens[1:]

    if top == "models":
        if not rest:
            raise ValueError("models subcommand is required")
        sub = rest[0]
        sub_args = rest[1:]
        if sub == "list":
            positionals = parse_options(
                sub_args,
                allowed_flags={"--json", "--plain", "--all", "--local"},
                allowed_kv={"--provider"},
            )
            if positionals:
                raise ValueError("models list does not accept positional arguments")
        elif sub == "status":
            positionals = parse_options(
                sub_args,
                allowed_flags={"--json", "--plain"},
                allowed_kv=set(),
            )
            if positionals:
                raise ValueError("models status does not accept positional arguments")
        else:
            raise ValueError("allowed models commands: list, status")

    elif top == "devices":
        if not rest:
            raise ValueError("devices subcommand is required")
        sub = rest[0]
        sub_args = rest[1:]
        common_flags = {"--json"}
        common_kv = {"--timeout", "--token", "--url", "--password"}
        if sub == "list":
            positionals = parse_options(sub_args, common_flags, common_kv)
            if positionals:
                raise ValueError("devices list does not accept positional arguments")
        elif sub in {"approve", "reject"}:
            positionals = parse_options(sub_args, common_flags, common_kv)
            if len(positionals) != 1:
                raise ValueError(f"devices {sub} expects 1 request id")
        elif sub in {"revoke", "rotate"}:
            positionals = parse_options(
                sub_args,
                common_flags,
                common_kv | {"--device", "--role", "--scope"},
            )
            if positionals:
                raise ValueError(f"devices {sub} does not accept positional arguments")
        else:
            raise ValueError("allowed devices commands: list, approve, reject, revoke, rotate")

    elif top == "approvals":
        if not rest:
            raise ValueError("approvals subcommand is required")
        sub = rest[0]
        sub_args = rest[1:]
        if sub == "get":
            positionals = parse_options(
                sub_args,
                {"--json", "--gateway"},
                {"--node", "--timeout", "--token", "--url"},
            )
            if positionals:
                raise ValueError("approvals get does not accept positional arguments")
        elif sub == "allowlist":
            if not sub_args:
                raise ValueError("allowlist action is required (add/remove)")
            action = sub_args[0]
            action_args = sub_args[1:]
            if action not in {"add", "remove"}:
                raise ValueError("allowed allowlist actions: add, remove")
            positionals = parse_options(
                action_args,
                {"--json", "--gateway"},
                {"--agent", "--node", "--timeout", "--token", "--url"},
            )
            if len(positionals) != 1:
                raise ValueError(f"approvals allowlist {action} expects 1 pattern")
        else:
            raise ValueError("allowed approvals commands: get, allowlist")

    elif top == "status":
        positionals = parse_options(
            rest,
            {"--json", "--all", "--deep", "--usage", "--verbose", "--debug"},
            {"--timeout"},
        )
        if positionals:
            raise ValueError("status does not accept positional arguments")

    elif top == "health":
        positionals = parse_options(rest, {"--json"}, set())
        if positionals:
            raise ValueError("health does not accept positional arguments")
    else:
        raise ValueError("allowed top-level commands: models, devices, approvals, status, health")

    return [OPENCLAW_BIN, *tokens]


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/clients")
def api_clients():
    names = list_client_names()
    clients = [collect_client(name) for name in names]
    return jsonify({"ok": True, "count": len(clients), "clients": clients})


@app.post("/api/clients")
def api_create_client():
    payload = request.get_json(silent=True) or {}
    client = str(payload.get("client", "")).strip()
    port = str(payload.get("port", "")).strip()
    autostart = bool(payload.get("autostart", True))

    if not client or not valid_client_name(client):
        return jsonify({"ok": False, "error": "invalid client name"}), 400
    if not port.isdigit():
        return jsonify({"ok": False, "error": "port must be numeric"}), 400
    if int(port) == 18789:
        return jsonify({"ok": False, "error": "port 18789 is reserved"}), 400

    code, out, err = run_cmd([str(MANAGER_SCRIPT), "init", client, port])
    if code != 0:
        return jsonify({"ok": False, "error": err or out or "init failed"}), 400

    action_result = out
    if autostart:
        scode, sout, serr = run_cmd([str(MANAGER_SCRIPT), "start", client], timeout=35)
        if scode != 0:
            return (
                jsonify(
                    {
                        "ok": False,
                        "error": serr or sout or "start failed",
                        "init_output": out,
                    }
                ),
                400,
            )
        action_result = f"{out}\n{sout}".strip()

    return jsonify({"ok": True, "message": action_result, "client": collect_client(client)})


@app.post("/api/clients/<client>/action")
def api_client_action(client: str):
    if not valid_client_name(client):
        return jsonify({"ok": False, "error": "invalid client name"}), 400

    payload = request.get_json(silent=True) or {}
    action = str(payload.get("action", "")).strip().lower()
    if action not in {"start", "stop", "restart", "status", "health"}:
        return jsonify({"ok": False, "error": "invalid action"}), 400

    code, out, err = run_cmd([str(MANAGER_SCRIPT), action, client], timeout=35)
    if code != 0:
        return jsonify({"ok": False, "error": err or out or f"{action} failed"}), 400

    return jsonify(
        {
            "ok": True,
            "action": action,
            "output": out,
            "client": collect_client(client),
        }
    )


@app.post("/api/command")
def api_command():
    payload = request.get_json(silent=True) or {}
    raw_command = str(payload.get("command", "")).strip()

    try:
        args, client = parse_manager_command(raw_command)
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400

    code, out, err = run_cmd(args, timeout=40)
    if code != 0:
        return jsonify({"ok": False, "error": err or out or "command failed"}), 400

    result: Dict[str, object] = {"ok": True, "command": " ".join(args[1:]), "output": out}
    if client:
        result["client"] = collect_client(client)
    return jsonify(result)


@app.post("/api/openclaw/command")
def api_openclaw_command():
    payload = request.get_json(silent=True) or {}
    raw_command = str(payload.get("command", "")).strip()

    try:
        args = parse_openclaw_command(raw_command)
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400

    code, out, err = run_cmd(args, timeout=45)
    if code != 0:
        return jsonify({"ok": False, "error": err or out or "command failed"}), 400

    return jsonify({"ok": True, "command": " ".join(args), "output": out})


@app.get("/api/clients/<client>/logs")
def api_client_logs(client: str):
    if not valid_client_name(client):
        return jsonify({"ok": False, "error": "invalid client name"}), 400

    lines_str = request.args.get("lines", "100")
    if not lines_str.isdigit():
        return jsonify({"ok": False, "error": "lines must be numeric"}), 400
    lines = min(max(int(lines_str), 10), 500)

    log_path = INSTANCES_DIR / client / "logs" / "gateway.out"
    if not log_path.exists():
        return jsonify({"ok": False, "error": f"log not found: {log_path}"}), 404

    code, out, err = run_cmd(["tail", "-n", str(lines), str(log_path)])
    if code != 0:
        return jsonify({"ok": False, "error": err or "failed to read log"}), 500

    return jsonify({"ok": True, "client": client, "log_path": str(log_path), "log": out})


@app.get("/api/health")
def api_health():
    code, out, err = run_cmd(["python3", "--version"])
    return jsonify(
        {
            "ok": True,
            "manager": "openclaw-manager",
            "python": out if code == 0 else None,
            "instances_dir": str(INSTANCES_DIR),
            "script_exists": MANAGER_SCRIPT.exists(),
            "script_path": str(MANAGER_SCRIPT),
            "script_error": None if code == 0 else err,
        }
    )


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "3011"))
    app.run(host=host, port=port, debug=False)

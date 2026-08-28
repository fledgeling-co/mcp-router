#!/usr/bin/env python3
"""A minimal stdio MCP server, written for the effect-witness pass.

It exists so the router has a real child to spawn that reaches no network and
holds no credential. It answers `initialize` and `tools/list` and nothing else.
"""
import json, sys, os, pathlib

pathlib.Path(os.environ.get("WITNESS_PIDFILE", "/tmp/mcp-witness-home/child.pid")).write_text(
    f"{os.getpid()} {os.getppid()}\n")

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid, method = msg.get("id"), msg.get("method")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "witness-fixture", "version": "1.0.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"name": "echo", "description": "Returns its input.",
             "inputSchema": {"type": "object",
                             "properties": {"text": {"type": "string"}},
                             "required": ["text"]}}]}})
    elif method == "tools/call":
        args = (msg.get("params") or {}).get("arguments") or {}
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "content": [{"type": "text", "text": args.get("text", "")}]}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid,
              "error": {"code": -32601, "message": f"no method {method}"}})

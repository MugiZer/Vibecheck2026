"""Roblox Studio MCP calls from WSL, for the dress step (ticket 24) and the decor subagent (ticket 25).

Talks MCP JSON-RPC over stdio to ~/.local/bin/roblox-studio-mcp (Roblox's mcp.bat on Windows),
one launcher process per call. Copied from .scratch/roblox-pivot/tools/mcp_call.py, which is not in git."""
import json, queue, subprocess, threading

LAUNCHER = "/home/rigged/.local/bin/roblox-studio-mcp"


def call(tool, args=None, timeout=30):
    """Call one Studio MCP tool and return the JSON-RPC reply (a dict with "result" or "error").
    Tries twice; raises RuntimeError when the launcher sends nothing for `timeout` seconds both times
    (Studio busy with a dialog or a place switch made it hang once)."""
    for _ in range(2):
        try:
            return _call_once(tool, args, timeout)
        except queue.Empty:
            pass
    raise RuntimeError("Studio did not answer: is it open in Edit mode with no dialog showing?")


def _call_once(tool, args, timeout):
    p = subprocess.Popen([LAUNCHER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True)
    q = queue.Queue()
    threading.Thread(target=lambda: [q.put(l) for l in p.stdout], daemon=True).start()
    def send(m):
        p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
    def wait(i):
        while True:
            try:
                m = json.loads(q.get(timeout=timeout))
            except ValueError:
                continue
            if m.get("id") == i:
                return m
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "rigged", "version": "0"}}})
        wait(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": args or {}}})
        return wait(2)
    finally:
        p.kill()


def studio_id():
    """The id of the open Studio instance whose name contains RiggedArcade, or None."""
    for part in call("list_roblox_studios").get("result", {}).get("content", []):
        try:
            studios = json.loads(part.get("text", "")).get("studios", [])
        except (ValueError, AttributeError):
            continue
        for s in studios:
            if isinstance(s, dict) and "RiggedArcade" in str(s.get("name", "")):
                return s.get("id")
    return None

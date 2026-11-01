"""The only Python that talks to the decor gate (`.lake/build/bin/decor-gate`).

The gate's decisions are proved in Lean (`app/decor/Decor/Gate.lean`,
`Specs/DecorSpec/`). This module runs the program with a list of arguments
(no shell) and a timeout, and answers no on any failure. It never parses a
tree itself: Python's `json` accepts NaN.
"""

import json
import subprocess
import sys
from pathlib import Path

GATE = Path(__file__).resolve().parent.parent / ".lake/build/bin/decor-gate"
KINDS = ("prop", "npc")
WHERES = ("wall", "corner", "watcher")
MAX_PICKS = 6
NO = {"ok": False, "nodes": 0}


def _run(args, data, timeout):
    """Run the gate. Returns (exit code, stdout bytes), or None if it cannot run."""
    if not GATE.exists():
        print("decor-gate is not built: run `lake build decor-gate`", file=sys.stderr)
        return None
    try:
        p = subprocess.run([str(GATE), *args], input=data, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.returncode, p.stdout


def check_tree(kind, data):
    """Ask the gate about one model tree (raw JSON bytes). {"ok": bool, "nodes": int}."""
    if kind not in KINDS or not isinstance(data, bytes):
        return dict(NO)
    r = _run([kind], data, timeout=10)
    if r is None or r[0] != 0:
        return dict(NO)
    try:
        reply = json.loads(r[1])  # the gate's own one-line reply, not the tree
    except ValueError:
        return dict(NO)
    if not isinstance(reply, dict) or reply.get("ok") is not True or type(reply.get("nodes")) is not int:
        return dict(NO)
    return {"ok": True, "nodes": reply["nodes"]}


def valid_id(asset_id):
    """True only when the gate accepts the asset id (1 to 19 digits)."""
    if not isinstance(asset_id, str) or len(asset_id) > 32:
        return False
    r = _run(["id", asset_id], b"", timeout=5)
    return r is not None and r[0] == 0


def clean_picks(raw):
    """Keep at most 6 good decor picks from an untrusted list."""
    if not isinstance(raw, list):
        return []
    out = []
    for pick in raw:
        if len(out) == MAX_PICKS:
            break
        if not isinstance(pick, dict) or pick.get("kind") not in KINDS or pick.get("where") not in WHERES:
            continue
        if not valid_id(pick.get("id")):
            continue
        clean = {"id": pick["id"], "kind": pick["kind"], "where": pick["where"]}
        if isinstance(pick.get("name"), str):
            clean["name"] = pick["name"][:80]  # for people to read; never goes into Luau or HTML
        out.append(clean)
    return out

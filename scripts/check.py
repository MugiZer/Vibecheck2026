"""Acceptance checks: every way a wrong game could get published must fail.

Run on Linux from the repo root with the server running (make run):
    python3 scripts/check.py
Each check prints PASS or FAIL; the exit code is the number of failures.
"""

from http.client import HTTPConnection
import json
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import verify  # noqa: E402

ROOT = verify.ROOT
failures = 0


def check(name, ok, detail=""):
    global failures
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail and not ok else ""))


def example(title):
    for m in verify.published():
        if m["example"] and m["presentation"]["title"] == title:
            d = Path(m["dir"])
            return m, (d / "UserSpec.lean").read_text(), (d / "Solution.lean").read_text()
    raise SystemExit(f"example {title!r} not found; run make examples")


def judged(name, spec, variant, solution, tag):
    ok, diag, _ = verify.judge(name, spec, variant, solution, verify.BUILD / "check" / tag, log=lambda m: None)
    return ok, diag


def http(method, path, body=b"", headers=None):
    c = HTTPConnection("127.0.0.1", int(os.environ.get("PORT", "8642")), timeout=60)
    c.request(method, path, body=body, headers=headers or {})
    r = c.getresponse()
    return r.status, json.loads(r.read() or b"{}")


vault, vault_spec, vault_proof = example("The Museum Vault")
orchard, _, _ = example("Owl Orchard")
v = vault["variant"]

# --- the judge -----------------------------------------------------------
ok, _ = judged("maze", vault_spec, v, vault_proof, "good")
check("judge accepts a shipped example's proof", ok)

header = vault_proof[:vault_proof.index("theorem accepted")]
statement = vault_proof[:vault_proof.index(":=\n")]
ok, diag = judged("maze", vault_spec, v, statement + ":= sorry\n", "sorry")
check("judge rejects a proof that builds but uses sorry", not ok and "sorryAx" in diag, diag[:200])

forged = vault_proof.replace("(R := [", "(R := [1, ", 1)
ok, diag = judged("maze", vault_spec, v, forged, "forged-cert")
check("judge rejects a forged certificate", not ok, diag[:200])

weaker = header + "theorem accepted : Maze.WellFormed Candidate.variant := by decide +kernel\n"
ok, diag = judged("maze", vault_spec, v, weaker, "weaker")
check("judge rejects a weaker statement that builds", not ok and "do not match" in diag, diag[:200])

cheat = vault_proof.replace("import UserSpec\n", "def UserSpec.requirement (_ : Maze.Variant) : Prop := True\n", 1)
ok, diag = judged("maze", vault_spec, v, cheat, "redefine")
check("judge rejects a proof that redefines the requirement", not ok, diag[:200])

axiom = statement.replace("theorem accepted", "axiom cheat : False\n\ntheorem accepted", 1) + ":= cheat.elim\n"
ok, diag = judged("maze", vault_spec, v, axiom, "axiom")
check("judge rejects a proof that adds its own axiom", not ok and "comparator rejected" in diag, diag[:200])

native = vault_proof.replace("by decide +kernel", "by native_decide", 1)
ok, diag = judged("maze", vault_spec, v, native, "native")
check("judge rejects native_decide", not ok and "comparator rejected" in diag, diag[:200])

ok, diag = judged("maze", vault_spec, orchard["variant"], vault_proof, "other-level")
check("judge rejects a proof checked against a different level", not ok, diag[:200])

# --- what renderers draw from: the runtime's drawing op -----------------------
status, body = http("GET", f"/api/artifacts/{vault['id']}")
guards_by_turn = (body.get("drawing") or {}).get("guardsByTurn") or []
vault_reveal = body.get("reveal") or {}
check("The Museum Vault's drawing has one list of guard cells per turn of the Show why cycle",
      status == 200 and len(guards_by_turn) == vault_reveal.get("cycle") == len(vault_reveal.get("cellsByTurn") or []),
      f"{status}: {len(guards_by_turn)} turns drawn, cycle {vault_reveal.get('cycle')}, "
      f"{len(vault_reveal.get('cellsByTurn') or [])} turns of cells")


def drawn_as_played(state):
    """The drawing's guard cells for this state's turn are the runtime's own state.guards."""
    t = state.get("turn")
    return isinstance(t, int) and 0 <= t < len(guards_by_turn) and guards_by_turn[t] == state.get("guards")


status, body = http("POST", "/api/sessions", json.dumps({"artifactId": vault["id"]}).encode())
sid, state = body.get("sessionId"), body.get("state") or {}
turns = [state.get("turn")]
agree = status == 200 and state.get("turn") == 0 and drawn_as_played(state)
for seq in range(len(guards_by_turn)):  # stay once per turn of the cycle, ending back on turn 0
    status, body = http("POST", f"/api/sessions/{sid}/act", json.dumps({"seq": seq, "action": "stay"}).encode())
    state = body.get("state") or {}
    if status != 200 or state.get("status") != "playing":
        break
    turns.append(state["turn"])
    agree = agree and drawn_as_played(state)
check("the drawing's guard cells equal the runtime's state.guards on every turn played",
      agree and len(turns) > 1, f"turns {turns}")

keyhole, _, _ = example("The Keyhole")
status, body = http("GET", f"/api/artifacts/{keyhole['id']}")
drawing = body.get("drawing") or {}
check("The Keyhole's drawing: 64 units per cell, and every flight starts at [96, 32]",
      status == 200 and drawing.get("cellSize") == 64 and drawing.get("launchPoint") == [96, 32], f"{status} {drawing}")

# --- identities and freshness ---------------------------------------------
check("the runtime prints exactly the judged level for every published level",
      all(verify.sha(verify.runtime(m["template"], "lean", m["variant"])) == m["candidateHash"] for m in verify.published()))

stale_dir = verify.ARTIFACTS / "stale-check"
shutil.rmtree(stale_dir, ignore_errors=True)
shutil.copytree(vault["dir"], stale_dir)
man = json.loads((stale_dir / "manifest.json").read_text())
man.update(id="stale-check", templateHash="0" * 64)
(stale_dir / "manifest.json").write_text(json.dumps(man))
status, body = http("POST", "/api/sessions", json.dumps({"artifactId": "stale-check"}).encode())
check("server refuses to play a level checked against an older template", status == 409, f"{status} {body}")
shutil.rmtree(stale_dir)

status, body = http("POST", "/api/sessions", json.dumps({"artifactId": vault["id"]}).encode())
sid = body.get("sessionId")
s1, _ = http("POST", f"/api/sessions/{sid}/act", json.dumps({"seq": 0, "action": "down"}).encode())
s2, _ = http("POST", f"/api/sessions/{sid}/act", json.dumps({"seq": 0, "action": "down"}).encode())
check("a retried move with a stale sequence number is not applied twice", s1 == 200 and s2 == 409, f"{s1} {s2}")
s3, _ = http("POST", f"/api/sessions/{sid}/act", json.dumps({"seq": 1, "action": "teleport"}).encode())
check("the runtime refuses a move the rules do not have", s3 == 400, str(s3))

# --- uploads through the real HTTP endpoint ----------------------------------
uploads = verify.BUILD / "data" / "uploads"
before = set(p.name for p in uploads.iterdir()) if uploads.exists() else set()
spec = b"import Maze.Spec\ndef UserSpec.requirement (v : Maze.Variant) : Prop := Maze.Winnable v\n"
status, body = http("POST", "/api/upload", spec, {"X-File-Name": "../../../../tmp/evil.lean", "Content-Length": str(len(spec))})
up = body.get("uploadId", "")
check("a traversal file name is stored under uploads/<random id>/UserSpec.lean",
      status == 200 and (uploads / up / "UserSpec.lean").read_bytes() == spec and not Path("/tmp/evil.lean").exists())
status, body = http("POST", "/api/upload", b"x" * 65536, {"X-File-Name": "/etc/passwd", "Content-Length": "65536"})
check("an upload of exactly the limit (64 KiB) is accepted", status == 200, str(status))
status, body = http("POST", "/api/upload", b"x" * 65537, {"X-File-Name": "big.lean", "Content-Length": "65537"})
check("an upload one byte over the limit is rejected", status == 413, str(status))
after = set(p.name for p in uploads.iterdir())
check("a rejected upload leaves nothing behind", len(after - before) == 2, f"{len(after - before)} new uploads")

print(f"\n{failures} failure(s)")
sys.exit(failures)

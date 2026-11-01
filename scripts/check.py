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
import server  # noqa: E402  (for MAZE_CAPTIONS; importing it starts nothing)
import decor_gate  # noqa: E402

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

# --- Show why: the painted cells are checked by Lean each time a level opens ---
status, body = http("GET", f"/api/artifacts/{vault['id']}")
rv = body.get("reveal") or {}
lean_check = rv.get("check") or {}
check("Show why's painted cells pass the runtime's checkRegions, with the coordinator's passing caption",
      status == 200 and lean_check.get("passes") is True
      and (lean_check.get("caption") or "").startswith(server.MAZE_CAPTIONS["passed"]), f"{status} {lean_check}")
check("Show why's caption starts with \"Until a guard catches you\" (without it the caption is false)",
      (lean_check.get("caption") or "").startswith("Until a guard catches you"), str(lean_check.get("caption")))
check("the level reply has no matchesProof and no regionCells",
      status == 200 and "matchesProof" not in rv and "regionCells" not in rv, str(sorted(rv)))
cells = vault["reveal"]["cellsByTurn"]
bad = [[c for c in cells[0] if c != v["start"]]] + cells[1:]
try:
    refused, err = verify.runtime("maze", "check", v, cellsByTurn=bad)["passes"] is False, ""
except Exception as e:  # an old binary answers "unknown op check": print FAIL, not a traceback
    refused, err = False, str(e)
bad_dir = verify.ARTIFACTS / "bad-cells-check"  # the vault with the damaged cells, opened through the coordinator
bad_dir.mkdir(parents=True, exist_ok=True)
try:  # never leave the fake level in the list, even if the request fails
    (bad_dir / "manifest.json").write_text(json.dumps({**vault, "id": bad_dir.name, "reveal": {**vault["reveal"], "cellsByTurn": bad}}))
    status, body = http("GET", f"/api/artifacts/{bad_dir.name}")
finally:
    shutil.rmtree(bad_dir)
bad_check = (body.get("reveal") or {}).get("check") or {}
check("the runtime's check refuses the painted cells without the start cell, and the coordinator shows its failed caption",
      refused and bad_check.get("passes") is False and bad_check.get("caption") == server.MAZE_CAPTIONS["failed"],
      f"{err} {status} {bad_check}")

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

# --- the Roblox place: the endpoints it calls, and its art ------------------------
marker = "check-" + os.urandom(6).hex()
status, _ = http("POST", "/api/roblox/log", json.dumps({"lines": [f"[check] {marker}"]}).encode())
log = verify.BUILD / "roblox.log"
check("a line posted to /api/roblox/log lands in build/roblox.log",
      status == 200 and log.exists() and marker in log.read_text(), str(status))
status, _ = http("POST", "/api/roblox/log", json.dumps({"lines": "x"}).encode())
status2, _ = http("POST", "/api/roblox/log", json.dumps({"lines": [1]}).encode())
check("the log endpoint refuses lines that are not a list of strings", status == status2 == 400, f"{status} {status2}")
status, body = http("GET", "/api/status")
check("/api/status has the fields the Roblox place reads",
      status == 200 and body.get("templates") == ["maze"] and all(
          isinstance(body.get(k, {}).get("ok"), bool) and isinstance(body.get(k, {}).get("why"), str)
          for k in ("verifier", "model")), f"{status} {body}")
status, body = http("GET", "/api/artifacts")
check("every level in /api/artifacts has the fields the Roblox level list reads",
      status == 200 and isinstance(body, list) and all(
          {"id", "title", "template", "current", "example", "label"} <= item.keys() for item in body), f"{status} {body}")
status, body = http("GET", f"/api/artifacts/{vault['id']}")
check("The Museum Vault's detail has the fields the Roblox claim panel reads",
      status == 200 and all(body.get(k) for k in ("claim", "scope", "variant", "reveal"))
      and (body.get("presentation") or {}).get("title"), f"{status} {sorted(body)}")
status, _ = http("POST", "/api/sessions", json.dumps({"artifactId": "nope"}).encode())
check("starting a session on a level that does not exist gives 404", status == 404, str(status))
status, _ = http("POST", "/api/sessions/nope/act", json.dumps({"seq": 0, "action": "up"}).encode())
check("a move in a session that does not exist gives 404", status == 404, str(status))
# Rojo also makes scripts from .rbxm, .luau and .json files, and only XML can be searched for scripts.
scripted = [str(f.relative_to(ROOT)) for f in (ROOT / "roblox" / "art").rglob("*") if not f.is_dir() and (
            f.suffix != ".rbxmx" or any(f'class="{c}"' in f.read_text(errors="replace")
                                        for c in ("Script", "LocalScript", "ModuleScript")))]
check("roblox/art holds only .rbxmx files, none with a script", not scripted, ", ".join(scripted))

# Decor gate (ticket 23): runs .lake/build/bin/decor-gate directly; no server needed.
def tree(cls, name="x", size=(0, 0, 0), off=(0, 0, 0), part=False, children=()):
    """One instance with every field the gate reads. `part=True` gives safe part values."""
    turn = ([1000, 0, 0], [0, 1000, 0], [0, 0, 1000]) if part else ([0, 0, 0],) * 3
    return {"name": name, "cls": cls, "anchored": part, "canCollide": False, "canTouch": False,
            "canQuery": False, "size": list(size), "off": list(off), "alongX": turn[0], "alongY": turn[1],
            "alongZ": turn[2], "displayDistance": "", "healthDisplay": "", "children": list(children)}


bookshelf = tree("Model", "Bookshelf", children=[
    tree("MeshPart", "Shelf", (35, 55, 12), part=True),
    tree("Part", "Books", (30, 10, 8), (0, 15, 0), part=True, children=[tree("Decal", "Spines")])])
raw = json.dumps(bookshelf).encode()
answer = decor_gate.check_tree("prop", raw)
check("decor gate: a bookshelf prop is accepted with 4 instances", answer == {"ok": True, "nodes": 4}, str(answer))
deep = tree("ModuleScript", "Module")
for _ in range(6):
    deep = tree("Model", "Box", children=[deep])
answer = decor_gate.check_tree("prop", json.dumps(deep).encode())
check("decor gate: a ModuleScript six Models deep is rejected", answer["ok"] is False, str(answer))
answer = decor_gate.check_tree("prop", json.dumps(tree("Model", "Tool", children=[tree("Script", "Handle")])).encode())
check("decor gate: a Script named Handle is rejected", answer["ok"] is False, str(answer))
fraction = raw.replace(b"[35, ", b"[35.5, ", 1)
missing = raw.replace(b'"canQuery": false, ', b"", 1)
answers = [decor_gate.check_tree("prop", fraction), decor_gate.check_tree("prop", missing)]
check("decor gate: a fraction or a missing field is rejected",
      fraction != raw and missing != raw and all(a["ok"] is False for a in answers), str(answers))
bad_id = '1"; game:Destroy()--'
check("decor gate: a code-shaped asset id is refused, a digits-only id is accepted",
      decor_gate.valid_id(bad_id) is False and decor_gate.valid_id("9333354309") is True)
picks = [{"id": str(9333354300 + i), "kind": "prop", "where": "wall", "name": f"Pick {i}"} for i in range(8)]
picks[1]["id"] = bad_id
picks[3]["kind"] = "script"
kept = decor_gate.clean_picks(picks)
check("decor gate: clean_picks keeps 6 good picks and drops the bad id and the script kind",
      len(kept) == 6 and all(p["id"] != bad_id and p["kind"] in ("prop", "npc") for p in kept), str(kept))

# --- the dress step: only checked values go into its Luau text ----------------------
try:
    import dress  # noqa: E402  (imports app/decor_gate.py, ticket 23)
    try:
        dress.luau_value('x"; game:Destroy()--')
        refused = False
    except ValueError:
        refused = True
    passed = dress.luau_value("9333354309") == "9333354309"
    detail = "" if refused else "the code-shaped text was accepted"
except Exception as e:  # print FAIL, not a traceback
    refused, passed, detail = False, False, repr(e)
check("luau_value refuses 'x\"; game:Destroy()--' and returns \"9333354309\" unchanged", refused and passed, detail)

print(f"\n{failures} failure(s)")
sys.exit(failures)

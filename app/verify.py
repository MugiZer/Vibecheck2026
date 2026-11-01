"""The judge: freeze a candidate, build the trusted challenge, and accept only
what `lake comparator` accepts. Nothing the agent says can publish a level."""

import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
ARTIFACTS = ROOT / "artifacts"
ELAN = Path(os.environ.get("ELAN_HOME", Path.home() / ".elan"))
LAKE = str(ELAN / "bin" / "lake")
AXIOMS = ["propext", "Quot.sound", "Classical.choice"]

TEMPLATES = {
    "maze": {"lib": "Maze", "src": ROOT / "templates" / "maze", "exe": ROOT / ".lake/build/bin/maze"},
    "sling": {"lib": "Sling", "src": ROOT / "templates" / "sling", "exe": ROOT / ".lake/build/bin/sling"},
}

ATTEMPT_LAKEFILE = """name = "attempt"
defaultTargets = ["{lib}"]

[[lean_lib]]
name = "{lib}"

[[lean_lib]]
name = "UserSpec"

[[lean_lib]]
name = "Candidate"

[[lean_lib]]
name = "Challenge"

[[lean_lib]]
name = "Solution"
"""

CHALLENGE = """import {lib}
import Candidate
import UserSpec

/-- The claim the judge checks: this exact level is well formed, playable, and
meets the uploaded requirement. Written by the coordinator, never by the agent. -/
theorem accepted :
    {lib}.WellFormed Candidate.variant ∧ {lib}.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant := sorry
"""

INTAKE = """import UserSpec

example : {lib}.Variant → Prop := UserSpec.requirement
"""


def sha(data):
    if isinstance(data, str):
        data = data.encode()
    return hashlib.sha256(data).hexdigest()


def template_sources(name):
    t = TEMPLATES[name]
    lib = t["lib"]
    files = [t["src"] / f"{lib}.lean"] + sorted((t["src"] / lib).rglob("*.lean"))
    return [(f.relative_to(t["src"]).as_posix(), f.read_bytes()) for f in files]


def template_hash(name):
    h = hashlib.sha256((ROOT / "lean-toolchain").read_bytes())
    for rel, data in template_sources(name):
        h.update(rel.encode() + b"\0" + data + b"\0")
    return h.hexdigest()


def run(cmd, cwd, timeout, sandbox=False):
    """Run a command, optionally inside a bubblewrap sandbox with no network,
    no credentials, and write access only to `cwd`."""
    if sandbox:
        cwd = Path(cwd).resolve()
        ro = []
        for p in ["/usr", "/etc", "/lib", "/lib64", "/bin", "/sbin"]:
            if Path(p).is_symlink():
                ro += ["--symlink", os.readlink(p), p]
            elif Path(p).exists():
                ro += ["--ro-bind", p, p]
        cmd = ["bwrap", "--unshare-all", "--die-with-parent", "--new-session",
               *ro, "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
               "--ro-bind", str(ELAN), str(ELAN), "--bind", str(cwd), str(cwd),
               "--chdir", str(cwd), "--clearenv",
               "--setenv", "PATH", f"{ELAN}/bin:/usr/bin:/bin", "--setenv", "HOME", "/tmp",
               "--setenv", "ELAN_HOME", str(ELAN), *cmd]
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return 124, out + f"\n[timed out after {timeout}s]"


def verifier_ready():
    """Live generation needs Linux with bubblewrap and the pinned Lean."""
    if shutil.which("bwrap") is None:
        return False, "bubblewrap (bwrap) is not installed; the proof sandbox needs Linux"
    if not Path(LAKE).exists():
        return False, "Lean is not installed; run make install"
    code, out = run(["true"], BUILD if BUILD.exists() else ROOT, 20, sandbox=True)
    if code != 0:
        return False, "the bubblewrap sandbox does not start here: " + out.strip()[:200]
    return True, "ready"


def workspace(name):
    """A prebuilt Lean project holding the template, cached per template
    revision. Attempts copy it, so they never share a writable build dir."""
    lib = TEMPLATES[name]["lib"]
    ws = BUILD / f"ws-{name}-{template_hash(name)[:16]}"
    if (ws / ".ready").exists():
        return ws
    tmp = ws.with_name(ws.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    shutil.copy(ROOT / "lean-toolchain", tmp)
    (tmp / "lakefile.toml").write_text(ATTEMPT_LAKEFILE.format(lib=lib))
    for rel, data in template_sources(name):
        (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp / rel).write_bytes(data)
    code, out = run([LAKE, "build", lib], tmp, 900)
    if code != 0:
        raise RuntimeError(f"template {name} does not build:\n{out[-3000:]}")
    (tmp / ".ready").write_text(template_hash(name))
    shutil.rmtree(ws, ignore_errors=True)
    tmp.rename(ws)
    return ws


def fresh_copy(name, dest):
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(workspace(name), dest, symlinks=True)
    return Path(dest)


def check_upload(name, spec_text, scratch):
    """Build an uploaded requirement in the sandbox and check its type."""
    lib = TEMPLATES[name]["lib"]
    ws = fresh_copy(name, scratch)
    (ws / "UserSpec.lean").write_text(spec_text)
    (ws / "IntakeCheck.lean").write_text(INTAKE.format(lib=lib))
    code, out = run([LAKE, "build", "UserSpec"], ws, 300, sandbox=True)
    if code == 0:
        code, out2 = run([LAKE, "env", "lean", "IntakeCheck.lean"], ws, 120, sandbox=True)
        out += out2
    shutil.rmtree(ws, ignore_errors=True)
    if code != 0:
        return False, out[-4000:]
    return True, ""


def runtime(name, op, variant, **extra):
    """Ask the template's game process (the real runtime) about a level."""
    exe = TEMPLATES[name]["exe"]
    req = json.dumps({"op": op, "variant": variant, **extra})
    p = subprocess.run([str(exe), "serve"], input=req + "\n", capture_output=True, text=True, timeout=120)
    reply = json.loads(p.stdout.strip().splitlines()[0])
    if not reply["ok"]:
        raise ValueError(reply["error"])
    return reply["result"]


def judge(name, spec_text, variant, solution_text, attempt_dir, log=print):
    """Check one candidate. Returns (accepted, diagnostics, files)."""
    lib = TEMPLATES[name]["lib"]
    attempt_dir = Path(attempt_dir)
    try:
        candidate = runtime(name, "lean", variant)
    except ValueError as e:
        return False, f"The level data was rejected before proof checking: {e}", {}
    files = {
        "UserSpec.lean": spec_text,
        "Candidate.lean": candidate,
        "Challenge.lean": CHALLENGE.format(lib=lib),
        "Solution.lean": solution_text,
        "comparator.json": json.dumps({"challenge_module": "Challenge", "solution_module": "Solution",
                                       "theorem_names": ["accepted"], "permitted_axioms": AXIOMS}, indent=2),
    }

    # 1. Diagnostics: build the proposed proof in a sandboxed scratch copy.
    log("building the proposed proof")
    diag = fresh_copy(name, attempt_dir / "diagnostics")
    for f, text in files.items():
        (diag / f).write_text(text)
    t0 = time.time()
    code, out = run([LAKE, "build", "Solution"], diag, 600, sandbox=True)
    if code != 0:
        return False, "Lean rejected Solution.lean:\n" + trim_build_log(out), files

    # 2. Judgement in a fresh copy where the proposal was never compiled.
    log(f"proof builds ({time.time() - t0:.0f}s); running lake comparator")
    judge_dir = fresh_copy(name, attempt_dir / "judge")
    for f, text in files.items():
        (judge_dir / f).write_text(text)
    code, out = run([LAKE, "comparator"], judge_dir, 900)
    files["comparator.log"] = out
    if code != 0 or "Your solution is okay!" not in out:
        return False, "lake comparator rejected the proof:\n" + out[-3000:], files
    log("lake comparator accepted the proof")
    return True, "", files


def trim_build_log(out):
    lines = [l for l in out.splitlines() if not l.startswith("trace:") and "Note: This linter" not in l]
    return "\n".join(lines)[-6000:]


def publish(name, variant, presentation, files, meta, base=ARTIFACTS):
    """Write an immutable, self-contained artifact: the level, the theorem,
    the proof, the judge's log, and their hashes. Returns its id."""
    request_hash = sha(files["UserSpec.lean"])
    variant_hash = sha(json.dumps(variant, sort_keys=True))
    t_hash = template_hash(name)
    art_id = sha(t_hash + request_hash + variant_hash + sha(files["Solution.lean"]))[:12]
    dest = base / art_id
    if dest.exists():
        return art_id
    tmp = base / (art_id + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    lib = TEMPLATES[name]["lib"]
    shutil.copy(ROOT / "lean-toolchain", tmp)
    (tmp / "lakefile.toml").write_text(ATTEMPT_LAKEFILE.format(lib=lib))
    for rel, data in template_sources(name):
        (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp / rel).write_bytes(data)
    for f, text in files.items():
        (tmp / f).write_text(text)
    manifest = {
        "id": art_id, "template": name, "templateHash": t_hash, "requestHash": request_hash,
        "variantHash": variant_hash, "candidateHash": sha(files["Candidate.lean"]),
        "solutionHash": sha(files["Solution.lean"]), "permittedAxioms": AXIOMS,
        "variant": variant, "presentation": presentation, "created": int(time.time()), **meta,
    }
    (tmp / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    tmp.rename(dest)
    return art_id


def published():
    """Every published level: shipped examples first, then generated ones."""
    out = []
    for base, example in ((ROOT / "examples", True), (ARTIFACTS, False)):
        for m in sorted(base.glob("*/manifest.json")) if base.exists() else []:
            man = json.loads(m.read_text())
            out.append({**man, "dir": str(m.parent), "example": example})
    return out

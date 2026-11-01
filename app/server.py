"""The coordinator: serves the browser UI, streams uploads through the Lean
upload gate, runs generation jobs, and plays published levels through the
template's Lean runtime. Python standard library only; the Claude Agent SDK is
imported lazily by agent.py when a job starts."""

import json
import os
import secrets
import subprocess
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import verify

ROOT = verify.ROOT
WEB = ROOT / "app" / "web"
DATA = verify.BUILD / "data"
EXAMPLES = ROOT / "examples"
SAMPLES = ROOT / "samples"
GATE = ROOT / ".lake/build/bin/upload-gate"
ROBLOX_LOG = verify.BUILD / "roblox.log"  # the Roblox place's Output, for agents that cannot see Studio
UPLOAD_LIMIT = 64 * 1024
MIME = {".html": "text/html", ".js": "text/javascript", ".css": "text/css",
        ".png": "image/png", ".json": "application/json", ".svg": "image/svg+xml",
        ".woff2": "font/woff2", ".txt": "text/plain"}

# The maze Show why caption, written only here; every renderer shows reveal.check.caption.
MAZE_CAPTIONS = {
    "passed": ("Lean ran checkRegions on exactly these cells, and it passed. The checked theorem "
               "maze_regions_sound says that when this check passes, no sequence of moves wins. "
               "The exit never glows."),
    "failed": "Lean's check did not pass on these cells, so they show nothing.",
    "unchecked": "Lean has not checked these cells, so they show nothing.",
}

sessions = {}
session_lock = threading.Lock()  # a move's seq check and its update happen together
jobs = {}
job_lock = threading.Lock()  # one generation job at a time
runtimes = {}
runtime_locks = {}


def runtime(template, op, variant, **extra):
    """Ask the template's long-running Lean game process. Requests are
    stateless: the full move list is replayed with the proved `run`."""
    lock = runtime_locks.setdefault(template, threading.Lock())
    with lock:
        for _ in range(2):  # requests are stateless, so one retry on a fresh process is safe
            proc = runtimes.get(template)
            if proc is None or proc.poll() is not None:
                proc = subprocess.Popen([str(verify.TEMPLATES[template]["exe"]), "serve"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
                runtimes[template] = proc
            try:
                proc.stdin.write(json.dumps({"op": op, "variant": variant, **extra}) + "\n")
                proc.stdin.flush()
                line = proc.stdout.readline()
            except BrokenPipeError:
                line = ""
            if line:
                break
            proc.kill()  # the process died mid-request
            runtimes.pop(template, None)
        else:
            raise RuntimeError(f"the {template} game process stopped twice in a row")
        reply = json.loads(line)
    if not reply["ok"]:
        raise ValueError(reply["error"])
    return reply["result"]


def artifacts():
    """Published levels by id, marked stale if their template has changed."""
    found = {}
    for man in verify.published():
        man["current"] = man["templateHash"] == verify.template_hash(man["template"])
        found[man["id"]] = man
    return found


def summary(man):
    keys = ["id", "template", "label", "claim", "scope", "example", "current", "created", "brief"]
    out = {k: man.get(k) for k in keys}
    out["title"] = man["presentation"].get("title", man["id"])
    return out


def model_status():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return False, "no ANTHROPIC_API_KEY in the environment"
    try:
        import claude_agent_sdk  # noqa: F401
    except ImportError:
        return False, "claude-agent-sdk is not installed (make install)"
    return True, "ready"


def samples():
    out = []
    for f in sorted(SAMPLES.glob("*/*.lean")):
        out.append({"template": f.parent.name, "name": f.stem, "text": f.read_text()})
    return out


class Job:
    def __init__(self, template, spec_text, spec_label, brief):
        self.id = secrets.token_hex(6)
        self.template, self.spec_text, self.spec_label, self.brief = template, spec_text, spec_label, brief
        self.state = "received"
        self.events = []
        self.artifact = None
        self.cancelled = threading.Event()
        self.created = time.time()

    def emit(self, text, state=None):
        if state:
            self.state = state
        self.events.append({"t": round(time.time() - self.created, 1), "state": self.state, "text": text})

    def view(self):
        return {"id": self.id, "state": self.state, "events": self.events[-60:],
                "artifact": self.artifact, "template": self.template, "brief": self.brief}


def run_job(job):
    with job_lock:
        try:
            ok, why = verify.verifier_ready()
            if not ok:
                return job.emit(why, "verifier_unavailable")
            mok, mwhy = model_status()
            if not mok:
                return job.emit(mwhy, "model_unavailable")
            job.emit("checking the uploaded requirement in the sandbox", "checking_upload")
            ok, out = verify.check_upload(job.template, job.spec_text, verify.BUILD / "jobs" / job.id / "intake")
            if not ok:
                return job.emit("the requirement does not build:\n" + out, "invalid_upload")
            if job.cancelled.is_set():
                return job.emit("cancelled", "cancelled")
            import agent
            agent.generate(job, runtime)
        except Exception as e:
            traceback.print_exc()
            job.emit(f"internal error: {e}", "failed")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n > 1 << 20:
            raise ValueError("request too large")
        req = json.loads(self.rfile.read(n) or b"{}")
        if not isinstance(req, dict):
            raise ValueError("expected a JSON object")
        return req

    def do_GET(self):
        path = urlparse(self.path).path
        try:
            if path == "/":
                return self.send(200, (WEB / "index.html").read_bytes(), "text/html")
            if path.startswith("/static/"):
                f = (WEB / path[len("/static/"):]).resolve()
                if WEB.resolve() not in f.parents or not f.is_file():
                    return self.send(404, {"error": "not found"})
                return self.send(200, f.read_bytes(), MIME.get(f.suffix, "application/octet-stream"))
            if path == "/api/status":
                v_ok, v_why = verify.verifier_ready()
                m_ok, m_why = model_status()
                return self.send(200, {"verifier": {"ok": v_ok, "why": v_why},
                                       "model": {"ok": m_ok, "why": m_why},
                                       "templates": list(verify.TEMPLATES)})
            if path == "/api/samples":
                return self.send(200, samples())
            if path == "/api/artifacts":
                arts = sorted(artifacts().values(), key=lambda m: (not m["example"], m["created"]))
                return self.send(200, [summary(m) for m in arts])
            if path.startswith("/api/artifacts/"):
                man = artifacts().get(path.rsplit("/", 1)[1])
                if not man:
                    return self.send(404, {"error": "no such level"})
                d = Path(man["dir"])
                files = {f: (d / f).read_text() for f in
                         ["UserSpec.lean", "Candidate.lean", "Challenge.lean", "Solution.lean",
                          "comparator.json", "comparator.log"] if (d / f).exists()}
                rv = man.get("reveal") or {}
                rv.pop("matchesProof", None)  # the old Python substring test; no renderer may read it
                rv.pop("regionCells", None)
                if man["template"] == "maze" and rv.get("cellsByTurn"):
                    try:
                        check = runtime("maze", "check", man["variant"], cellsByTurn=rv["cellsByTurn"])
                    except Exception as e:  # an old or stopped runtime must not stop the level from opening
                        check = {"passes": False, "error": str(e)}
                    check["caption"] = MAZE_CAPTIONS["unchecked" if "error" in check else
                                                     "passed" if check["passes"] else "failed"]
                    rv["check"] = check
                return self.send(200, {**{k: v for k, v in man.items() if k != "dir"}, "files": files})
            if path.startswith("/api/jobs/"):
                job = jobs.get(path.rsplit("/", 1)[1])
                return self.send(200, job.view()) if job else self.send(404, {"error": "no such job"})
            return self.send(404, {"error": "not found"})
        except Exception as e:
            traceback.print_exc()
            return self.send(500, {"error": str(e)})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            if path == "/api/upload":
                return self.upload()
            if path == "/api/generate":
                req = self.body()
                template = req.get("template")
                if template not in verify.TEMPLATES:
                    return self.send(400, {"error": "unknown template"})
                if req.get("uploadId"):
                    up = req["uploadId"]
                    if not (len(up) == 32 and all(c in "0123456789abcdef" for c in up)):
                        return self.send(400, {"error": "bad upload id"})
                    spec_file = DATA / "uploads" / up / "UserSpec.lean"
                    if not spec_file.is_file():
                        return self.send(404, {"error": "no such upload"})
                    spec_text, label = spec_file.read_text(errors="replace"), None
                else:
                    match = [s for s in samples() if s["template"] == template and s["name"] == req.get("sample")]
                    if not match:
                        return self.send(400, {"error": "choose a sample requirement or upload one"})
                    spec_text, label = match[0]["text"], match[0]["name"]
                brief = str(req.get("brief", ""))[:2000]
                job = Job(template, spec_text, label, brief)
                jobs[job.id] = job
                job.emit("job received")
                threading.Thread(target=run_job, args=(job,), daemon=True).start()
                return self.send(200, {"jobId": job.id})
            if path.startswith("/api/jobs/") and path.endswith("/cancel"):
                job = jobs.get(path.split("/")[3])
                if job:
                    job.cancelled.set()
                    job.emit("cancel requested")
                return self.send(200, {"ok": True})
            if path == "/api/sessions":
                return self.start_session(self.body())
            if path.startswith("/api/sessions/") and path.endswith("/act"):
                with session_lock:
                    return self.act(path.split("/")[3], self.body())
            if path == "/api/roblox/log":
                lines = self.body().get("lines")
                if not isinstance(lines, list) or not all(isinstance(line, str) for line in lines):
                    return self.send(400, {"error": "lines must be a list of strings"})
                ROBLOX_LOG.parent.mkdir(parents=True, exist_ok=True)
                stamp = time.strftime("%H:%M:%S")
                # shortcut: build/roblox.log is never rotated, rotate it when the file gets large
                with ROBLOX_LOG.open("a") as f:
                    f.writelines(f"{stamp} {line[:2000]}\n" for line in lines[:200])
                return self.send(200, {"ok": True})
            return self.send(404, {"error": "not found"})
        except ValueError as e:  # bad JSON, bad Content-Length, oversized body
            self.close_connection = True  # the body may be unread
            return self.send(400, {"error": str(e)})
        except Exception as e:
            traceback.print_exc()
            return self.send(500, {"error": str(e)})

    def upload(self):
        """Stream the body through the Lean upload gate in bounded chunks. The
        gate decides the path and enforces the limit; we never buffer the
        whole body."""
        length = int(self.headers.get("Content-Length", "-1"))
        if length < 0:
            return self.send(411, {"error": "Content-Length required"})
        name = self.headers.get("X-File-Name", "upload.lean")[:200]
        DATA.mkdir(parents=True, exist_ok=True)
        gate = subprocess.Popen([str(GATE), str(UPLOAD_LIMIT), name], cwd=DATA,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        remaining = length
        try:
            while remaining > 0:
                chunk = self.rfile.read(min(65536, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                gate.stdin.write(chunk)
        except BrokenPipeError:
            pass
        try:
            gate.stdin.close()
        except BrokenPipeError:
            pass
        result = json.loads(gate.stdout.read() or b'{"ok": false, "error": "gate failed"}')
        gate.wait()
        if remaining > 0:
            self.close_connection = True  # unread body: drop the connection
        if not result["ok"]:
            return self.send(413, {"error": result["error"]})
        return self.send(200, {"uploadId": result["id"], "limit": UPLOAD_LIMIT})

    def start_session(self, req):
        man = artifacts().get(req.get("artifactId", ""))
        if not man:
            return self.send(404, {"error": "no such level"})
        if not man["current"]:
            return self.send(409, {"error": "this level was checked against an older template; it cannot be played with the current runtime"})
        # The runtime must load exactly the level the judge checked.
        if verify.sha(runtime(man["template"], "lean", man["variant"])) != man["candidateHash"]:
            return self.send(409, {"error": "the runtime's level does not match the checked level"})
        sid = secrets.token_hex(8)
        sessions[sid] = {"artifact": man["id"], "template": man["template"], "variant": man["variant"],
                         "moves": [], "seq": 0}
        state = runtime(man["template"], "replay", man["variant"], moves=[])
        return self.send(200, {"sessionId": sid, "seq": 0, "state": state})

    def act(self, sid, req):
        s = sessions.get(sid)
        if not s:
            return self.send(404, {"error": "no such session"})
        if req.get("seq") != s["seq"]:
            return self.send(409, {"error": "stale move", "seq": s["seq"]})
        action = req.get("action")
        if action == "reset":
            moves = []
        else:
            moves = s["moves"] + [action]
        try:
            state = runtime(s["template"], "replay", s["variant"], moves=moves)
        except ValueError as e:
            return self.send(400, {"error": str(e)})
        s["moves"], s["seq"] = moves, s["seq"] + 1
        return self.send(200, {"seq": s["seq"], "state": state, "moves": len(moves)})


def main():
    port = int(os.environ.get("PORT", "8642"))
    v_ok, v_why = verify.verifier_ready()
    m_ok, m_why = model_status()
    print(f"Rigged Arcade on http://127.0.0.1:{port}")
    print(f"  examples: {len(artifacts())} published levels")
    print(f"  live generation: {'ready' if v_ok and m_ok else 'unavailable'}"
          f" (verifier: {v_why}; model: {m_why})")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()

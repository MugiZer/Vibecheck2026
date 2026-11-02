"""Write app/web/security.html: the upload security theorems, their specs, the code they are about,
and the proofs, copied from the Lean files. Open it at /static/security.html. Regenerate after any
change to those files: python3 scripts/security_page.py"""
import html
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    ("The code the upload gate runs", "app/upload/Upload/Store.lean",
     "The gate is a compiled Lean program. It calls destination and admit on every upload."),
    ("Spec: an upload cannot choose where it is stored", "Specs/UploadSpec/Destination.lean", ""),
    ("Spec: an upload cannot be larger than the limit", "Specs/UploadSpec/Limit.lean", ""),
    ("The proofs, with good and bad examples", "Specs/UploadSpec/Proofs.lean",
     "Lean's kernel checks every proof and every example. A false example would stop the build."),
]
rows = [l.split("|")[1:3] for l in (ROOT / "README.md").read_text().splitlines() if l.startswith("| `upload_")]
commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
esc = html.escape

table = "".join(f"<tr><td><code>{esc(n.strip().strip('`'))}</code></td><td>{esc(w.strip())}</td></tr>" for n, w in rows)
sections = "".join(
    f"<h2>{esc(title)}</h2><p class=path>{esc(rel)}</p>" + (f"<p>{esc(note)}</p>" if note else "")
    + f"<pre>{esc((ROOT / rel).read_text())}</pre>" for title, rel, note in FILES)

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Upload security, proved in Lean</title>
<link rel="stylesheet" href="/static/style.css">
<style>
  main {{ max-width: 980px; margin: 0 auto; padding: 32px 20px 64px; }}
  table {{ border-collapse: collapse; width: 100%; background: var(--sheet); }}
  td {{ border: 1px solid var(--line); padding: 8px 10px; vertical-align: top; }}
  pre {{ background: var(--sheet); border: 1px solid var(--line); padding: 14px; overflow-x: auto;
        font: 13px/1.5 var(--mono); }}
  .path {{ color: var(--soft); font-family: var(--mono); margin: -8px 0 8px; }}
</style></head>
<body><main>
<h1>Upload security, proved in Lean</h1>
<p>Five theorems about the upload gate. <code>make verify</code> checks each one with
<code>lake comparator</code> against the statements in <code>Verification/Challenge.lean</code>,
and allows no axioms beyond Lean's standard three.</p>
<table>{table}</table>
<p><strong>Not proved:</strong> the gate's file-system calls and read loop, the Python HTTP
handler, and the sandbox that runs uploaded Lean. <code>make check</code> tests these through the
real endpoints, for example an upload named <code>../../../../tmp/evil.lean</code> and an upload one
byte over the limit.</p>
{sections}
<p class=path>Copied from the files above at commit {esc(commit)} by scripts/security_page.py.</p>
</main></body></html>
"""
(ROOT / "app" / "web" / "security.html").write_text(page)
print("wrote app/web/security.html")

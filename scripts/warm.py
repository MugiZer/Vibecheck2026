"""Warm up before a live demo: one upload check and one full judge run on a shipped example level,
so Lean, the template, and the comparator are in memory. Publishes nothing. The first Lean run after
the machine sits idle is about 15 s slower. Run it a minute before going on stage: make warm"""
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import verify  # noqa: E402

man = next(m for m in verify.published() if m["example"])
d, scratch = Path(man["dir"]), verify.BUILD / "warm"
spec = (d / "UserSpec.lean").read_text()
t = time.time()
ok_upload, _ = verify.check_upload(man["template"], spec, scratch / "intake")
print(f"upload check: {'ok' if ok_upload else 'FAILED'} ({time.time() - t:.0f}s)")
t = time.time()
ok, diag, _ = verify.judge(man["template"], spec, man["variant"], (d / "Solution.lean").read_text(), scratch / "judge",
                           log=lambda m: print("  " + m))
shutil.rmtree(scratch, ignore_errors=True)
print(f"judge: {'accepted' if ok else 'REJECTED: ' + diag[-500:]} ({time.time() - t:.0f}s)")
sys.exit(0 if ok and ok_upload else 1)

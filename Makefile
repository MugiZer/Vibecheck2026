# Rigged Arcade
#   make install    get Lean if needed, build the games and every proof, set up Python
#   make run        start the app on http://127.0.0.1:8642 (examples play without any keys)
#   make verify     run lake comparator on the template, upload, and decor theorems (Linux)
#   make check      acceptance checks against the judge, runtime, and uploads (server running)
#   make examples   rebuild the shipped example levels through the judge (Linux)

PORT ?= 8642
export PORT
export PATH := $(HOME)/.elan/bin:$(PATH)
PY = $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)

.PHONY: install run verify check examples clean

install:
	@command -v lake >/dev/null 2>&1 || { echo "Installing Lean with elan..."; \
	  curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none; }
	lake build
	@[ -x .venv/bin/python ] || uv venv -q .venv 2>/dev/null || python3 -m venv .venv 2>/dev/null || true
	@[ -x .venv/bin/python ] && { uv pip install -q --python .venv/bin/python claude-agent-sdk 2>/dev/null || \
	  .venv/bin/python -m pip install -q claude-agent-sdk; } || \
	  echo "Note: claude-agent-sdk is not installed, so live generation is off. The examples still play."

run:
	@lake build maze sling upload-gate >/dev/null
	@$(PY) app/server.py

verify:
	lake build
	lake env lean Verification/Audit.lean
	lake comparator --config Verification/comparator.json

check:
	$(PY) scripts/check.py

examples:
	$(PY) scripts/make_examples.py

clean:
	rm -rf build artifacts
	lake clean

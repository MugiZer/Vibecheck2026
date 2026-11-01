# Rigged Arcade
#   make install    get Lean if needed, build the games and every proof, set up Python
#   make run        start the app on http://127.0.0.1:8642 (examples play without any keys)
#   make verify     run lake comparator on the template, upload, and decor theorems (Linux)
#   make check      acceptance checks against the judge, runtime, and uploads (server running)
#   make examples   rebuild the shipped example levels through the judge (Linux)
#   make roblox     build the Roblox place build/RiggedArcade.rbxlx (gets Rojo and selene into .tools/)
#   make roblox-serve  live-sync roblox/ into the place open in Studio (never the art)

PORT ?= 8642
export PORT
export PATH := $(HOME)/.elan/bin:$(PATH)
PY = $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
ROBLOX_URL ?= http://127.0.0.1:$(PORT)

.PHONY: install run verify check examples clean roblox roblox-serve roblox-prep

install:
	@command -v lake >/dev/null 2>&1 || { echo "Installing Lean with elan..."; \
	  curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none; }
	lake build
	@[ -x .venv/bin/python ] || uv venv -q .venv 2>/dev/null || python3 -m venv .venv 2>/dev/null || true
	@[ -x .venv/bin/python ] && { uv pip install -q --python .venv/bin/python claude-agent-sdk 2>/dev/null || \
	  .venv/bin/python -m pip install -q claude-agent-sdk; } || \
	  echo "Note: claude-agent-sdk is not installed, so live generation is off. The examples still play."

run:
	@lake build maze upload-gate >/dev/null
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

# Pinned Roblox tools. A download is unzipped or used only if it matches GitHub's SHA-256 digest:
# the plugin runs in Studio with plugin rights, and the binaries run next to ANTHROPIC_API_KEY.
ROJO_ZIP = https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip
ROJO_ZIP_SHA = 00feb4fa0829a1dd72b49df2639da519a352bfe13cadcd83969e2ba2bb5693c4
SELENE_ZIP = https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip
SELENE_ZIP_SHA = d3773393578580074386e69337d35b7acddfbaa9fc38964c07fa3e28436ade9b
ROJO_PLUGIN = https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/Rojo.rbxm
ROJO_PLUGIN_SHA = 50a8d83db87deab4d65fd6100eb74396de232355b1ae89c641035d02c49db6f4
# $(call fetch,url,file,sha256): download url to file; stop, and delete file, if that fails or the hash differs
fetch = curl -sSfL -o $(2) $(1) || { rm -f $(2); echo "download failed: $(1)"; exit 1; }; \
  echo "$(3)  $(2)" | sha256sum -c || { rm -f $(2); echo "wrong SHA-256, not used: $(1)"; exit 1; }

# Tools, the coordinator URL file, and the lint: shared by roblox and roblox-serve.
roblox-prep:
	@mkdir -p .tools
	@[ "$$(.tools/rojo --version 2>/dev/null)" = "Rojo 7.7.1" ] || \
	  { $(call fetch,$(ROJO_ZIP),.tools/rojo.zip,$(ROJO_ZIP_SHA)); $(PY) -m zipfile -e .tools/rojo.zip .tools; }
	@[ "$$(.tools/selene --version 2>/dev/null)" = "selene 0.32.0" ] || \
	  { $(call fetch,$(SELENE_ZIP),.tools/selene.zip,$(SELENE_ZIP_SHA)); $(PY) -m zipfile -e .tools/selene.zip .tools; }
	@[ -f .tools/Rojo.rbxm ] || \
	  { $(call fetch,$(ROJO_PLUGIN),.tools/Rojo.rbxm.part,$(ROJO_PLUGIN_SHA)); mv .tools/Rojo.rbxm.part .tools/Rojo.rbxm; }
	@chmod +x .tools/rojo .tools/selene
	printf '%s' '$(ROBLOX_URL)' > roblox/CoordinatorUrl.txt
	cd roblox && ../.tools/selene src

# Rojo also makes scripts from .rbxm, .luau and .json files, and only XML can be searched for scripts.
roblox: roblox-prep
	@mkdir -p roblox/art/models roblox/art/materials build
	@! find roblox/art ! -type d ! -name '*.rbxmx' | grep . || { echo 'roblox/art holds files that are not .rbxmx: only XML models can be checked for scripts'; exit 1; }
	@! grep -rlE 'class="(Script|LocalScript|ModuleScript)"' roblox/art || { echo 'roblox/art holds scripts: strip them (ticket 06)'; exit 1; }
	.tools/rojo build roblox -o build/RiggedArcade.rbxlx

roblox-serve: roblox-prep
	.tools/rojo serve roblox/serve.project.json

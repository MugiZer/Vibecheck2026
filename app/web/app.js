// Backrooms page. The browser only draws and sends moves: every game state
// shown here comes from the Lean runtime through the coordinator.
const $ = (id) => document.getElementById(id);
const api = async (path, opts = {}) => {
  const r = await fetch(path, { headers: { "Content-Type": "application/json" }, ...opts });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(body.error || r.statusText), { status: r.status, body });
  return body;
};

const ui = { art: null, session: null, seq: 0, state: null, busy: false, reveal: null,
  samples: [], upload: null, levels: [], tab: "Mechanics", job: null };
const canvas = $("board");
const ctx = canvas.getContext("2d");
const KIND = { unwinnable: ["rigged", "rigged"], winnable: ["fair", "fair"], "exactly-one": ["one way out", "fair"] };

// ---------- Lean text ----------
const LEAN_WORDS = /\b(theorem|lemma|def|abbrev|structure|inductive|where|import|open|namespace|section|end|by|fun|let|have|show|example|instance|match|with|if|then|else|deriving|decide|native_decide|sorry|Prop|Type)\b/;
const LEAN = new RegExp(String.raw`(\/-[\s\S]*?-\/)|(--[^\n]*)|("(?:[^"\\]|\\.)*")|` + LEAN_WORDS.source, "g");
function leanHtml(text) {
  let out = "", last = 0, m;
  LEAN.lastIndex = 0;
  while ((m = LEAN.exec(text))) {
    out += esc(text.slice(last, m.index));
    const cls = m[1] || m[2] ? "c" : m[3] ? "s" : "k";
    out += `<span class="${cls}">${esc(m[0])}</span>`;
    last = m.index + m[0].length;
  }
  return out + esc(text.slice(last));
}
function showCode(el, text) { el.innerHTML = leanHtml(text || ""); el.scrollTop = 0; }

// ---------- spec pane ----------
// The spec pane shows the spec the next "Generate" will use: the open level's
// own spec, a sample, or an uploaded file.
function fillSpecPick() {
  const opts = [];
  if (ui.art && ui.art.files["UserSpec.lean"]) opts.push(["level", "This level's spec"]);
  if (ui.upload) opts.push(["upload", ui.upload.name]);
  for (const s of ui.samples) opts.push([`sample:${s.name}`, `Sample: ${s.name}`]);
  const pick = $("spec-pick"), keep = pick.value;
  pick.innerHTML = opts.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join("");
  if (opts.some(([v]) => v === keep)) pick.value = keep;
  showSpec();
}
function specText() {
  const v = $("spec-pick").value;
  if (v === "level") return ui.art.files["UserSpec.lean"];
  if (v === "upload") return ui.upload.text;
  const s = ui.samples.find((x) => `sample:${x.name}` === v);
  return s ? s.text : "";
}
function showSpec() { showCode($("spec-body"), specText()); }
$("spec-pick").onchange = showSpec;

$("upload").onchange = async () => {
  const f = $("upload").files[0];
  if (!f) return;
  ui.upload = { name: f.name, text: await f.text() };
  fillSpecPick();
  $("spec-pick").value = "upload";
  showSpec();
  $("upload").value = "";
};

// ---------- Lean tabs ----------
const TABS = [
  ["Mechanics", "Candidate.lean", "The level itself: board, walls, exit and watcher loops, printed by the Lean game runtime."],
  ["Theorem", "Challenge.lean", "The statement Lean checks. The coordinator writes it from the spec."],
  ["Proof", "Solution.lean", "Written by the model. Trusted only because Lean accepts it."],
  ["Check", "comparator.log", "Output of lake comparator: the proof matches the theorem and uses no extra axioms."],
];
function buildTabs() {
  const bar = $("tabs");
  const names = TABS.map((t) => t[0]).concat(ui.job ? ["Progress"] : []);
  bar.innerHTML = names.map((n) => `<button role="tab" aria-selected="${n === ui.tab}">${n}</button>`).join("");
  bar.querySelectorAll("button").forEach((b) => (b.onclick = () => { ui.tab = b.textContent; buildTabs(); }));
  showTab();
}
function showTab() {
  if (ui.tab === "Progress" && ui.job) {
    $("tab-note").textContent = "The model proposes a level and a proof; only Lean can publish it.";
    $("lean-body").textContent = ui.job.events.map((e) => `${String(e.t).padStart(4)}s  ${e.text}`).join("\n");
    $("lean-body").scrollTop = 1e9;
    return;
  }
  const t = TABS.find((x) => x[0] === ui.tab) || TABS[0];
  $("tab-note").textContent = t[2];
  showCode($("lean-body"), (ui.art && ui.art.files[t[1]]) || "(not in this level)");
}

// ---------- levels ----------
async function loadLevels(selectId) {
  const arts = (await api("/api/artifacts")).filter((a) => a.template === "maze");
  ui.levels = arts;
  $("level").innerHTML = arts.map((a, i) => {
    const k = KIND[a.label] || ["custom"];
    return `<option value="${a.id}">Backrooms ${i + 1} · ${k[0]}${a.example ? " · example" : ""}</option>`;
  }).join("");
  const pick = selectId || (ui.art && ui.art.id) || (arts[0] && arts[0].id);
  if (pick) await openLevel(pick);
}
$("level").onchange = () => openLevel($("level").value);

async function openLevel(id) {
  stopReveal();
  const art = await api(`/api/artifacts/${id}`);
  ui.art = art;
  $("level").value = id;
  const k = KIND[art.label] || ["custom", ""];
  $("kind").textContent = k[0];
  $("kind").className = `tag ${k[1] || ""}`;
  $("claim").hidden = false;
  $("claim-text").textContent = art.claim;
  $("claim-scope").textContent = art.scope;
  $("claim-who").textContent = art.example ? "Prepared example, checked by lake comparator" : `Made by ${art.generatedBy || "a model"}, checked by lake comparator`;
  $("reveal").hidden = !art.reveal;
  $("reveal-note").hidden = true;
  fillSpecPick();
  $("spec-pick").value = "level";
  showSpec();
  if (ui.tab === "Progress" && !ui.job) ui.tab = "Mechanics";
  buildTabs();
  try {
    const s = await api("/api/sessions", { method: "POST", body: JSON.stringify({ artifactId: id }) });
    ui.session = s.sessionId; ui.seq = s.seq; ui.state = s.state;
    $("overlay").hidden = true;
    $("moves").textContent = "";
    $("status-text").textContent = "";
    render();
  } catch (e) {
    ui.session = null;
    showOverlay("Cannot play this level", e.message);
  }
}

// The Roblox place polls the coordinator and opens whatever level was sent last.
$("to-roblox").onclick = async () => {
  if (!ui.art) return;
  try {
    await api("/api/roblox/play", { method: "POST", body: JSON.stringify({ artifactId: ui.art.id }) });
    $("roblox-note").textContent = "Sent. It opens in Roblox in a second.";
  } catch (e) { $("roblox-note").textContent = e.message; }
  setTimeout(() => { $("roblox-note").textContent = ""; }, 4000);
};

// ---------- play ----------
const DIRS = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", w: "up", s: "down", a: "left", d: "right", " ": "stay" };

async function act(action) {
  if (!ui.session || ui.busy || !ui.art) return;
  if (action !== "reset" && ui.state && ui.state.status !== "playing") return;
  stopReveal();
  ui.busy = true;
  try {
    const r = await api(`/api/sessions/${ui.session}/act`, { method: "POST", body: JSON.stringify({ seq: ui.seq, action }) });
    ui.seq = r.seq; ui.state = r.state;
    $("moves").textContent = r.moves ? `${r.moves} move${r.moves === 1 ? "" : "s"}` : "";
    const st = r.state.status;
    if (st === "caught") showOverlay("Caught", "Press R to try again.", "caught");
    else if (st === "escaped") showOverlay("You got out", "This level was fair.", "out");
    else $("overlay").hidden = true;
    render();
  } catch (e) {
    if (e.status === 409 && e.body && e.body.seq !== undefined) ui.seq = e.body.seq;
    $("status-text").textContent = e.message;
  } finally { ui.busy = false; }
}

function showOverlay(title, sub, cls = "") {
  const o = $("overlay");
  o.className = `overlay ${cls}`;
  o.innerHTML = `<div>${esc(title)}<small>${esc(sub || "")}</small></div>`;
  o.hidden = false;
}

function render() { if (ui.art) drawMaze(); }

const INK = { floor: "#fbfbfa", wall: "#2f3437", grid: "rgba(0,0,0,.06)", player: "#1f2326",
  guard: "#9f2f2d", exitBg: "#edf3ec", exit: "#346538", gem: "#956400", glow: "rgba(52,101,56,.20)" };

function drawMaze(revealTurn) {
  const v = ui.art.variant, st = ui.state;
  const size = Math.floor(Math.min(640 / v.width, 480 / v.height));
  canvas.width = size * v.width; canvas.height = size * v.height;
  const walls = new Set(v.walls);
  const xy = (c) => [(c % v.width) * size, Math.floor(c / v.width) * size];
  const mid = (c) => { const [x, y] = xy(c); return [x + size / 2, y + size / 2]; };
  ctx.fillStyle = INK.floor; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.strokeStyle = INK.grid; ctx.lineWidth = 1;
  for (let c = 0; c < v.width * v.height; c++) {
    const [x, y] = xy(c);
    if (walls.has(c)) { ctx.fillStyle = INK.wall; ctx.fillRect(x, y, size, size); }
    else ctx.strokeRect(x + .5, y + .5, size - 1, size - 1);
  }
  const guardsByTurn = (ui.art.drawing || {}).guardsByTurn || [];  // from the Lean runtime; none if it is missing
  let guards = st ? st.guards : guardsByTurn[0] || [];
  let next = st ? st.guardsNext : [];
  if (revealTurn !== undefined) {
    if (ui.art.reveal.check && ui.art.reveal.check.passes) {
      ctx.fillStyle = INK.glow;
      for (const c of ui.art.reveal.cellsByTurn[revealTurn] || []) { const [x, y] = xy(c); ctx.fillRect(x + 1, y + 1, size - 2, size - 2); }
    }
    guards = guardsByTurn[revealTurn] || [];
    next = [];
  }
  const dot = (c, r, fill, stroke) => {
    const [x, y] = mid(c);
    ctx.beginPath(); ctx.arc(x, y, size * r, 0, Math.PI * 2);
    if (fill) { ctx.fillStyle = fill; ctx.fill(); }
    if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 2; ctx.stroke(); }
  };
  // The exit: a door frame. In Show why it gets a red frame: the caption says the exit never glows.
  const [ex, ey] = xy(v.exit);
  ctx.fillStyle = revealTurn === undefined ? INK.exitBg : INK.floor;
  ctx.fillRect(ex + 2, ey + 2, size - 4, size - 4);
  ctx.strokeStyle = revealTurn === undefined ? INK.exit : INK.guard; ctx.lineWidth = 2;
  ctx.strokeRect(ex + 3, ey + 3, size - 6, size - 6);
  v.gems.forEach((g, i) => { if (!(st && st.collected[i])) dot(g, .14, INK.gem); });
  next.forEach((c) => dot(c, .3, null, "rgba(159,47,45,.35)"));
  guards.forEach((c) => dot(c, .3, INK.guard));
  if (revealTurn === undefined) dot(st ? st.pos : v.start, .28, INK.player);
}

// ---------- Show why ----------
function stopReveal() { if (ui.reveal) { clearInterval(ui.reveal); ui.reveal = null; $("reveal").textContent = "Show why"; render(); } }

$("reveal").onclick = () => {
  const art = ui.art;
  if (!art || !art.reveal) return;
  if (ui.reveal) return stopReveal();
  const note = $("reveal-note");
  note.hidden = false;
  const rv = art.reveal;
  if (rv.check) {
    let t = 0;
    note.textContent = rv.check.caption;
    $("reveal").textContent = "Stop";
    const tick = () => { drawMaze(t); t = (t + 1) % rv.cycle; };
    tick();
    ui.reveal = setInterval(tick, 700);
  } else if (rv.winningMoves) {
    note.textContent = `A way out in ${rv.winningMoves.length} moves, replayed by the Lean runtime. Lean's kernel replayed the same moves to prove the level can be won.`;
    replay(rv.winningMoves);
  }
};

async function replay(moves) {
  await act("reset");
  $("reveal").textContent = "Stop";
  let i = 0;
  ui.reveal = setInterval(async () => {
    if (i >= moves.length) return stopReveal();
    const m = moves[i++];
    const saved = ui.reveal; ui.reveal = null;  // let act() run
    await act(m);
    ui.reveal = saved;
  }, 260);
}

document.addEventListener("keydown", (e) => {
  if (["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return;
  if (e.key === "r" || e.key === "R") { $("overlay").hidden = true; act("reset"); return; }
  const m = DIRS[e.key];
  if (m) { e.preventDefault(); act(m); }
});

// ---------- making levels ----------
async function loadStatus() {
  const s = await api("/api/status");
  const live = s.verifier.ok && s.model.ok;
  $("generate").disabled = !live;
  $("gen-note").className = live ? "note" : "note bad";
  $("gen-note").textContent = live ? "" : `Generation is off: ${!s.verifier.ok ? s.verifier.why : s.model.why}. The levels below still play.`;
  ui.samples = (await api("/api/samples")).filter((x) => x.template === "maze");
}

$("make").onsubmit = async (e) => {
  e.preventDefault();
  const req = { template: "maze", brief: $("brief").value };
  // A "-- watcher: <name>" line in the spec picks the watchers' look. Lean ignores comments, so it
  // is not part of what is proved; it only joins the brief, which the dress step reads.
  const look = /^--\s*watcher:\s*(.+)$/im.exec(specText());
  if (look && !/watcher:/i.test(req.brief)) req.brief = `${req.brief.trim()}${req.brief.trim() ? "; " : ""}watcher: ${look[1].trim()}`;
  const pick = $("spec-pick").value;
  $("generate").disabled = true;
  $("gen-note").className = "note";
  try {
    if (pick.startsWith("sample:")) req.sample = pick.slice(7);
    else {  // the level's own spec or a file: both go through the upload gate first
      const name = pick === "upload" ? ui.upload.name : "UserSpec.lean";
      const r = await fetch("/api/upload", { method: "POST", headers: { "X-File-Name": name }, body: specText() });
      const body = await r.json();
      if (!r.ok) throw new Error(`upload rejected: ${body.error}`);
      req.uploadId = body.uploadId;
    }
    const { jobId } = await api("/api/generate", { method: "POST", body: JSON.stringify(req) });
    ui.job = { events: [] };
    ui.tab = "Progress";
    buildTabs();
    $("gen-note").textContent = "Generating. Usually one to three minutes.";
    pollJob(jobId);
  } catch (err) {
    $("gen-note").className = "note bad";
    $("gen-note").textContent = err.message;
    $("generate").disabled = false;
  }
};

const TERMINAL = ["accepted", "invalid_upload", "budget_exhausted", "verifier_unavailable", "model_unavailable", "cancelled", "failed"];
async function pollJob(id) {
  let job;
  try { job = await api(`/api/jobs/${id}`); } catch (e) { setTimeout(() => pollJob(id), 1500); return; }
  ui.job = job;
  if (ui.tab === "Progress") showTab();
  if (!TERMINAL.includes(job.state)) { setTimeout(() => pollJob(id), 1000); return; }
  $("generate").disabled = false;
  if (job.artifact) {
    $("gen-note").textContent = "Lean accepted the level. It is open on the right.";
    ui.tab = "Mechanics";
    await loadLevels(job.artifact);
  } else {
    $("gen-note").className = "note bad";
    $("gen-note").textContent = `No level published (${job.state.replace(/_/g, " ")}). See Progress.`;
  }
}

function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]); }

loadStatus().then(() => loadLevels()).catch((e) => showOverlay("Server unavailable", e.message));

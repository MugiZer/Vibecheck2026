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
$("safety-open").onclick = () => $("safety").showModal();
$("safety").onclick = (e) => { if (e.target === $("safety")) $("safety").close(); };  // click outside closes

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
  const arts = await api("/api/artifacts");
  ui.levels = arts;
  $("level").innerHTML = arts.map((a, i) => {
    const k = KIND[a.label] || ["custom"];
    return `<option value="${a.id}">${esc(a.title)} · ${k[0]}${a.example ? " · example" : ""}</option>`;
  }).join("");
  const pick = selectId || (ui.art && ui.art.id) || (arts[0] && arts[0].id);
  $("level").classList.toggle("is-off", !arts.length);
  $("to-roblox").classList.toggle("is-off", !arts.length);
  if (pick) await openLevel(pick);
  else { $("kind").textContent = ""; $("tab-note").textContent = "No level yet. Upload a spec and press Generate level."; }
}
$("level").onchange = () => openLevel($("level").value);

async function openLevel(id) {
  const art = await api(`/api/artifacts/${id}`);
  ui.art = art;
  $("level").value = id;
  const k = KIND[art.label] || ["custom", ""];
  $("kind").textContent = k[0];
  $("kind").className = `tag ${k[1] || ""}`;
  fillSpecPick();
  $("spec-pick").value = "level";
  showSpec();
  if (ui.tab === "Progress" && !ui.job) ui.tab = "Mechanics";
  buildTabs();
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
  // The watchers' looks come from the spec's Lean list `UserSpec.watcherLooks` (one per watcher, in order).
  const looks = /def\s+UserSpec\.watcherLooks[^:]*:\s*List String\s*:=\s*\[([^\]]*)\]/.exec(specText());
  if (looks && !/watcher:/i.test(req.brief)) {
    const names = [...looks[1].matchAll(/"([^"]*)"/g)].map((m) => m[1].trim()).filter(Boolean);
    if (names.length) req.brief = `${req.brief.trim()}${req.brief.trim() ? "; " : ""}watcher: ${names.join(", ")}`;
  }
  for (const key of ["watcher", "decor", "floor"]) {  // "-- watcher:", "-- decor:" and "-- floor:" lines in the spec
    const line = new RegExp(`^--\\s*${key}:\\s*(.+)$`, "im").exec(specText());
    if (line && !new RegExp(`${key}:`, "i").test(req.brief)) req.brief = `${req.brief.trim()}${req.brief.trim() ? "; " : ""}${key}: ${line[1].trim()}`;
  }
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

loadStatus().then(() => loadLevels()).catch((e) => { $("gen-note").textContent = `Server unavailable: ${e.message}`; });

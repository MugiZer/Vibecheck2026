// Slingshot renderer. Flights come from the Lean runtime (Sling.flight); the
// browser only animates the positions it is given and never simulates physics.
(() => {
  const atlas = new Image();
  atlas.src = "/static/assets/aliens/level.png";
  let frames = {};
  fetch("/static/assets/aliens/frames.json").then((r) => r.json()).then((f) => { frames = f; window.Sling.draw(); });
  atlas.onload = () => window.Sling.draw();

  const S = { art: null, state: null, anim: null, shown: null, trails: null };
  const CELL = 64;  // Lean units per cell
  const OUTCOME = { hitTarget: "Hit! The target is down.", hitBlock: "Blocked.", hitGround: "Hit the ground.",
                    leftWorld: "Flew out of the world.", tooLong: "Still flying after 160 ticks: a miss." };

  function geom() {
    const v = S.art.variant;
    const cell = Math.floor(Math.min(720 / v.width, 460 / v.height));
    const ground = Math.round(cell * 0.7);
    canvas.width = v.width * cell; canvas.height = v.height * cell + ground;
    const px = (x) => (x / CELL) * cell;
    const py = (y) => v.height * cell - (y / CELL) * cell;
    const cellXY = (c) => [(c % v.width) * cell, (v.height - 1 - Math.floor(c / v.width)) * cell];
    return { v, cell, ground, px, py, cellXY };
  }

  function sprite(name, x, y, w, h, fallback) {
    const f = frames[name];
    if (f && atlas.complete && atlas.naturalWidth) ctx.drawImage(atlas, f.x, f.y, f.w, f.h, x, y, w, h);
    else { ctx.fillStyle = fallback || "#888"; ctx.fillRect(x, y, w, h); }
  }

  function draw() {
    if (!S.art) return;
    const { v, cell, ground, px, py, cellXY } = geom();
    const p = S.art.presentation;
    const sky = ctx.createLinearGradient(0, 0, 0, canvas.height);
    sky.addColorStop(0, p.sky || "#8fd3ff"); sky.addColorStop(1, "#ffffff");
    ctx.fillStyle = sky; ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (let x = 0; x < canvas.width; x += ground) sprite(p.ground || "grass", x, v.height * cell, ground, ground, "#5b8c3a");
    for (const b of v.blocks) { const [x, y] = cellXY(b); sprite(`${p.material || "wood"}_square_pristine_1x1`, x, y, cell, cell, "#a0703c"); }
    const [tx, ty] = cellXY(v.target);
    if (!(S.state && S.state.status === "won")) sprite(`${p.target || "alienGreen"}_round`, tx + cell * .08, ty + cell * .08, cell * .84, cell * .84, "#3c3");
    const [lx, ly] = cellXY(v.launch);
    sprite("slingshot", lx + cell * .3, ly - cell * .55, cell * .42, cell * 1.55, "#6b4a2b");
    // aim indicator: direction only, never a predicted path
    const a = currentAngle();
    if (a !== null && !S.anim) {
      const r = (a * 10) * Math.PI / 180, cx = lx + cell / 2, cy = ly + cell / 2;
      ctx.strokeStyle = "rgba(0,0,0,.45)"; ctx.lineWidth = 3; ctx.setLineDash([6, 6]);
      ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(r) * cell * 1.6, cy - Math.sin(r) * cell * 1.6); ctx.stroke();
      ctx.setLineDash([]);
    }
    if (S.trails) for (const f of S.trails) path(f.path, f.outcome === "hitTarget" ? "rgba(30,170,90,.95)" : "rgba(200,40,60,.55)", f.outcome === "hitTarget" ? 4 : 1.5, px, py, v);
    if (S.shown) {
      path(S.shown.path.slice(0, S.shown.i + 1), "rgba(255,255,255,.85)", 2.5, px, py, v, true);
      const pt = S.shown.path[Math.min(S.shown.i, S.shown.path.length - 1)];
      if (pt) sprite(`${p.projectile || "alienPink"}_round`, px(pt[0]) - cell * .3, py(pt[1]) - cell * .3, cell * .6, cell * .6, "#f6c");
    }
  }

  function path(pts, color, width, px, py, v, dotted) {
    const [lx, ly] = [(v.launch % v.width) * CELL + CELL / 2, Math.floor(v.launch / v.width) * CELL + CELL / 2];
    ctx.strokeStyle = color; ctx.lineWidth = width; if (dotted) ctx.setLineDash([2, 5]);
    ctx.beginPath(); ctx.moveTo(px(lx), py(ly));
    for (const [x, y] of pts) ctx.lineTo(px(x), py(y));
    ctx.stroke(); ctx.setLineDash([]);
  }

  function currentAngle() { const v = S.art && S.art.variant; return v ? v.angles[+$("angle").value] : null; }
  function currentPower() { const v = S.art && S.art.variant; return v ? v.powers[+$("power").value] : null; }
  function syncLabels() {
    if (!S.art) return;
    $("angle-out").textContent = `${currentAngle() * 10}°`;
    $("power-out").textContent = currentPower();
    draw();
  }

  async function launch() {
    if (!ui.session || S.anim || ui.busy) return;
    S.trails = null; stopReveal();
    ui.busy = true;
    try {
      const r = await api(`/api/sessions/${ui.session}/act`, { method: "POST", body: JSON.stringify({ seq: ui.seq, action: `${currentAngle()}:${currentPower()}` }) });
      ui.seq = r.seq; ui.state = S.state = r.state;
      const f = r.state.last;
      S.shown = { path: f.path, i: 0 };
      $("sling-status").textContent = "";
      S.anim = setInterval(() => {
        S.shown.i += 1; draw();
        if (S.shown.i >= f.path.length) {
          clearInterval(S.anim); S.anim = null;
          $("sling-status").textContent = `${f.angle * 10}°, power ${f.power}: ${OUTCOME[f.outcome]}`;
          if (r.state.status === "won") showOverlay("Target down!", "This level was fair.");
          draw();
        }
      }, 33);
    } catch (e) { $("sling-status").textContent = e.message; }
    finally { ui.busy = false; }
  }

  window.Sling = {
    open(art, state) {
      S.art = art; S.state = state; S.shown = null; S.trails = null;
      const v = art.variant;
      $("angle").max = v.angles.length - 1; $("angle").value = Math.floor(v.angles.length / 2);
      $("power").max = v.powers.length - 1; $("power").value = v.powers.length - 1;
      $("sling-status").textContent = `${v.angles.length * v.powers.length} possible shots`;
      syncLabels();
    },
    draw,
    reveal(note) {
      const rv = S.art.reveal || {};
      const flights = rv.flights || [];
      const wins = flights.filter((f) => f.outcome === "hitTarget").length;
      S.trails = flights; S.shown = null; draw();
      note.textContent = `Every shot this slingshot allows (${flights.length} of them), flown by the Lean runtime. ` +
        (wins === 0 ? "Not one reaches the target. " : `${wins} reach${wins === 1 ? "es" : ""} the target (green). `) +
        "Lean's kernel flew the same shots under the same rules to prove it.";
    },
  };
  $("angle").oninput = syncLabels;
  $("power").oninput = syncLabels;
  $("fire").onclick = launch;
  document.addEventListener("keydown", (e) => {
    if (!S.art || !ui.art || ui.art.template !== "sling" || ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return;
    if (e.key === " " || e.key === "Enter") { e.preventDefault(); launch(); }
  });
})();

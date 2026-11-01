# Rigged Arcade

**Every level ships with a proof. Some are fair. Some are rigged. Lean knows which.**

Pick what you want to be true about a maze ("impossible, but looks
winnable", "can be won", or your own Lean statement), and describe it in a
sentence. An AI model (Claude by default) designs the level. Lean checks a
proof about the exact level you then play. Try to beat a rigged level, then
press **Show why**: in the game lights the cells that pass Lean's region
check, turn by turn; until a guard catches you, you are always on a lit
cell, and the exit is never lit.

The game is a turn-based maze: reach the exit (after any gems), and dodge
guards that walk fixed loops. You move one cell (or wait), then every guard
steps.

```sh
make install && make run      # then open http://127.0.0.1:8642
```

`make install` gets Lean through [elan](https://github.com/leanprover/elan)
if needed, builds the game and every proof, and installs the Claude Agent
SDK into `.venv`. The shipped levels play without any keys or network.
Live generation also needs Linux with `bubblewrap` (the proof sandbox) and
`ANTHROPIC_API_KEY`; the page shows whether both are ready. On Windows, run
it inside WSL.

The maze also plays inside Roblox Studio as a first-person Backrooms-style
game (see "Play it in Roblox Studio" below). The web page stays the main way
to run it.

To let Codex design levels instead (`gpt-6.1-sol`, `ultrafast` speed when your
login offers it): `uv pip install --python .venv/bin/python openai-codex`, log in
once with `.venv/lib/python3.12/site-packages/codex_cli_bin/bin/codex login`, then
`RIGGED_BACKEND=codex make run`.

## How it works

```
Roblox place ─┐   (server Script, HttpService)
browser ──HTTP┴─> coordinator (app/server.py, Python stdlib)
                    ├─ upload gate (Lean exe): stores and size-limits uploads
                    ├─ game runtime (Lean exe: maze): every move
                    ├─ agent (app/agent.py, Claude Agent SDK) ─ tools ─┐
                    │      try_level: runtime checks + search hints    │
                    │      submit:    send level + proof to the judge  │
                    └─ judge (app/verify.py): sandboxed build, then lake comparator
                           only an accepted proof publishes a level → artifacts/
```

1. The uploaded requirement (one Lean file defining
   `UserSpec.requirement : <Game>.Variant → Prop`) streams through the Lean
   upload gate and is built in a `bwrap` sandbox with no network.
2. Claude drafts a level and calls `try_level`, which runs the game's own Lean
   runtime: data checks, a search, and proof hints. It then calls `submit` with
   the level and a `Solution.lean`.
3. The coordinator prints the level as `Candidate.lean` (using the runtime),
   writes the challenge
   `WellFormed Candidate.variant ∧ Playable Candidate.variant ∧ UserSpec.requirement Candidate.variant`
   itself, builds the proposed proof in a sandboxed copy for diagnostics, and
   then runs `lake comparator` in a fresh copy where the proof was never
   compiled. A rejection goes back to Claude with Lean's messages. Nothing
   Claude says can publish a level.
4. An accepted level is published as a self-contained Lean project
   (`artifacts/<id>/`, or `examples/<id>/` for shipped levels) with the
   level, requirement, challenge, proof, judge log, and their hashes. You can
   `cd` into one and run `lake comparator` yourself.
5. Before play, the coordinator asks the runtime to print the level it loaded
   and refuses to start unless it matches the judged `Candidate.lean` byte for
   byte, and refuses levels judged against an older template.

## Play it in Roblox Studio

The same levels play in Roblox Studio as a first-person Backrooms game. You
need Roblox Studio on Windows and this repo in WSL. The place lists the maze
levels (the newest level made from each requirement) and shows each level's
claim. You walk the maze, and every step is a reply from the Lean runtime: the
place only draws it. **Show why** is a button on the play screen. On a rigged
level the lights go out, the camera rises, and the checked cells glow one
guard turn at a time. The watchers stand where the runtime puts them on that
turn (`drawing.guardsByTurn`). The caption is the one the coordinator sends
(`reveal.check.caption`), shown as it is. On a fair level, Show why replays a
winning route.

1. In WSL: `make run`. This starts the coordinator on `http://127.0.0.1:8642`;
   the place calls it.
2. In WSL: `make roblox`. It builds `build/RiggedArcade.rbxlx` with Rojo 7.7.1
   and checks the Luau with selene. The first run downloads both, and the Rojo
   plugin, into `.tools/` (each checked against a pinned SHA-256). The
   coordinator address is one value: `make roblox ROBLOX_URL=http://...`.
3. On Windows, open that file in Roblox Studio: File > Open from File >
   `\\wsl$\<your distro>\<path to the repo>\build\RiggedArcade.rbxlx`. Do not
   save the place: `make roblox` builds it again.
4. Optional, live sync while you edit `roblox/`: run `make roblox-serve`, copy
   `.tools/Rojo.rbxm` to `%LOCALAPPDATA%\Roblox\Plugins\` (restart Studio if it
   was open), then Plugins > Rojo > Connect (`localhost`, port `34872`).
5. Optional, art and decor: with the place open in Edit mode, run `make dress`
   (below). Studio must then stay open, because the art lives only in the open
   place.
6. Press **Play** (F5). Keys: W step, A/D turn, S turn around, Space wait,
   R restart, M map. The place's server script calls the coordinator, and
   the place's Output goes to `build/roblox.log`.

**Play in Roblox.** While the place is playing, the web page's **Play in
Roblox** button opens that level in the place and starts it, as a click on the
level and Play would. The place asks the coordinator for the last level sent
(`GET /api/roblox/play`) once a second.

**Art and decor (`make dress`).** Run it with Studio in Edit mode, before Play.
It needs the decor gate built (`make install` does that) and Roblox's Studio
MCP, a program that lets scripts control Studio. `app/studio.py` starts it
through a small script that runs Roblox's `mcp.bat` (not in the repo; its path
is `LAUNCHER` in `app/studio.py`). The decor gate is the Lean program that
decides which Creator Store models may enter the scene; "What is proved" lists
its theorems. `make dress` empties and refills the folder
`ServerStorage.DressPool` in the open place with:

- the art kit: a ceiling light and a watcher;
- each maze level's decor props, from the level's `decor.json` or found by
  searching the Creator Store with words from its brief or title;
- three surfaces (wall, floor, ceiling) from the Backrooms Material Pack, once
  you set their numbers at the top of `app/dress.py`.

From each model it deletes every script and every other class the gate does not
allow, asks the gate, and keeps the model only if the gate says yes. A last
sweep destroys the whole pool if anything not allowed is left (`python3
app/dress.py --check` runs just that sweep). It refuses to run during Play.
Without the pool, the place uses plain built-in materials, lights and
watchers. Decor props stand against walls and in corners, away from the start,
the exit, the gems, and every cell a watcher walks on.

**Watcher looks.** Each watcher gets the first of these that works:

1. The level's own decor watcher (found by `make dress`).
2. A cached look that the level's brief names. Write `watcher: <name>` in the
   "Describe the place" field on the web page, or a comment line
   `-- watcher: <name>` in your Lean requirement (Lean ignores it, so it is not
   part of what is proved). The place looks for a model with that name, in
   lower case, in `ServerStorage.DressPool.Looks`.
3. The art watcher, `ServerStorage.DressPool.Art.Watcher`.
4. A plain dark shape.

`make dress` does not fill `Looks`, and it empties the pool first, so add
cached looks by hand afterwards. Our demo place has three (`subaru natsuki`,
`bernie sanders`, `jon snow`), and its art watcher is Subaru Natsuki. The scene
uses a model only if it carries `checkedNodes` (the number of instances the
decor gate checked) and a fresh clone still has that many.

Check by hand after a change:

- Play shows "Coordinator ready", and the level list shows the maze levels,
  the same ones as the web page.
- A level shows its claim, and Play starts it.
- In a rigged maze a watcher catches you. R restarts. M switches the map view.
- Show why glows the checked cells under the coordinator's caption. On a fair
  level it replays the route to "You escaped!".

## Why the proofs are about the game you play

The rules are executable Lean, and the same functions are what the game runs.

- Maze: each move you make is replayed with `Maze.run`, the function the
  theorems are about. The browser holds no rules; it draws the state the
  runtime returns.

Neither renderer decides a move, a win, or a level: not the browser, and not
the Roblox place. Each draws the state the runtime returns. The cells Show why
lights come with the level, and the runtime checks exactly those cells with
`checkRegions` each time a level opens. The guard positions for each Show why
turn come from the runtime (`drawing`) each time a level opens.

## What is proved

Repository theorems, judged by `lake comparator` (see `Verification/`):

| Theorem | In plain words |
|---|---|
| `maze_regions_sound` | For every maze and every certificate: if the certificate passes `checkRegions`, no list of moves of any length wins. |
| `maze_isOpen_iff` | The fast bit test for open cells means "on the board and not a wall". |
| `maze_never_leaves_regions` | For every maze and every list of painted cells (one list per turn of the guards' cycle): if the lists pass `checkRegions`, then after any moves, while the game is on, you stand on a painted cell of the current turn. Show why paints lists like these; each time a level opens, the runtime runs `checkRegions` on the lists it paints. |
| `upload_ignores_client_name` | The file name a client sends never changes where its upload is stored. |
| `upload_fixed_shape` | Every stored path is `uploads/<32 lowercase hex digits>/UserSpec.lean`, so it cannot leave `uploads/`. |
| `upload_never_over_limit` | The bytes the gate lets through never add up to more than the limit, for any chunking. |
| `upload_accepted_iff_within_limit` | An upload is accepted exactly when it fits: the limit is accepted, one byte more is rejected. |
| `upload_accepted_writes_everything` | An accepted upload is written in full, in order. |
| `decor_only_allowed_classes` | In an accepted model, every instance at every level has a class from the allowlist. |
| `decor_no_bad_classes` | An accepted model holds none of 59 classes from the threat list: no script, explosion, seat, spawn, prompt, text, sound, light, effect or special mesh. |
| `decor_top_is_model` | The top instance of an accepted model is a Model. |
| `decor_parts_are_inert` | Every part in an accepted model is anchored, with collisions, touch events and queries off. |
| `decor_parts_stay_in_box` | Every part in an accepted model is inside the slot box. |
| `decor_humanoids_show_nothing` | Every Humanoid in an accepted model shows no name and no health bar. |
| `decor_within_limits` | An accepted model has at most 500 instances and at most 8 levels. |
| `decor_ignores_names` | Two models that differ only in names get the same answer. |
| `decor_accepts_safe_decor` | Every model that meets the rules is accepted, so the gate is not "always no". |
| `decor_smaller_stays_accepted` | Deleting instances from an accepted model keeps it accepted. `Clone()` deletes instances that are not `Archivable`. |
| `decor_id_is_digits_only` | An accepted asset id has 1 to 19 characters, all digits 0–9. So it has no quote, bracket or line break. |

`make dress` runs the decor gate on each model it puts into the Roblox place.
What these proofs do not cover is listed under "What is trusted".

Per published level, one theorem `accepted` about that exact level:

- **Maze, rigged**: `Maze.Unwinnable` (no move list of any length wins) and
  `Maze.Playable`: without the guards, a route collects every gem and reaches
  the exit, and the first move is safe. The proof is a certificate (one set of
  cells per turn of the guards' cycle) checked by the kernel with bit
  arithmetic, plus `maze_regions_sound`.
- **Maze, fair**: `Maze.Winnable`, with a winning move list replayed by the kernel.

Each spec file comes with concrete examples that meet its hypotheses and
examples of bad behaviour it rejects (`Specs/UploadSpec/Proofs.lean`), and
`make verify` lists the definitions each main theorem depends on, which is
the surface to review: `templates/maze/Maze/Game.lean` and `Spec.lean`,
`app/upload/Upload/Store.lean`,
`Specs/UploadSpec/`.

## What is trusted

- **Lean's kernel** and the axioms `propext`, `Quot.sound`, `Classical.choice`.
  No `sorry`, no `native_decide`, no new axioms (`make check` confirms the judge
  rejects each).
- **The definitions in the statements.** A theorem means only what they say:
  for example "caught" means a guard lands on your cell or you swap cells.
- **The Lean compiler, while you play.** The running game is compiled code of
  the proved functions. The kernel checked the theorems about those functions.
- **Not proved:** the JSON adapters, the Python coordinator, HTTP, the browser
  drawing, the Roblox place (next bullets), and the upload gate's
  file-system calls and read loop (which calls
  the proved `Upload.admit` before writing each chunk of at most 64 KiB).
  The runtime's compiled `checkRegions` checks Show why's glowing cells each
  time a level is opened. The caption beside them comes from the coordinator
  (`reveal.check.caption`).
  `make check` tests these through the real endpoints. The `bwrap` sandbox and
  the operating system are trusted to isolate uploaded Lean, which can run code
  while it compiles.
- **The Roblox place is an untrusted renderer**, like the browser: it decides
  no move, win, or level. Not proved: Roblox Studio, the place's Luau scripts,
  `HttpService`, and the localhost path from Windows to the coordinator in WSL.
  In-game text does not go through Roblox's `TextService` filter, because the
  place runs only in Studio and is not published.
- **The decor gate** (`app/decor/`, proved in `Specs/DecorSpec/`) decides
  whether a Creator Store model may go into the scene. The proofs cover that
  decision. Not proved: that the Luau in `app/dress.py` reports a model's tree
  truthfully (sizes, positions, turns; a model reported with all sizes zero
  would pass the box rule); that the scene uses the model the gate checked (it
  only compares the number of instances with the model's `checkedNodes`; the
  cached watcher looks, added by hand, are trusted to have passed the gate);
  the JSON reader in `decor-gate`; Roblox's `ClassName`; and what a picture on a
  model shows (the gate cannot see pixels).
- **Models and art also rely on** the Studio MCP (it inserts the models we ask
  for and runs our Luau as written), Roblox Studio itself, and the Creator
  Store. The MaterialVariants (the wall, floor and ceiling surfaces) are not
  models, so the gate does not check them: the dress step keeps only instances
  whose class is exactly `MaterialVariant` and removes their children.
- **Decor is visual only.** Every decor part is anchored, with collisions,
  touch events and queries off. Decor never changes a move, a win, or where a
  watcher stands; the runtime decides those.
- **Search and the agent are not trusted.** They only propose; the kernel and
  `lake comparator` decide.
- **Codex and the OpenAI model are not trusted either**, the same as Claude.

Not claimed: that a level is fun, looks fair, or that a human cannot react fast
enough. Those are playtesting questions. A label like "rigged" appears only for
the reviewed sample requirements; an uploaded requirement is shown as "checked
against your uploaded requirement", with its text.

## Limits

- The maze certificate ignores gems, so a rigged maze must cut off the exit
  itself. Search failing to find a win is never presented as a proof.
- The maze is turn-based by design; the proof covers that model, not real-time play.
- One generation job at a time, with a time and cost budget. Running out of
  budget is reported as such; it is not a proof that a request is impossible.
- Levels are designed by Opus 5.5 in fast mode by default.
  Fast mode costs twice as much, so `RIGGED_BUDGET_USD=3` buys about half the work;
  raise it if jobs run out of budget.
- The judge needs Linux (`lake comparator` sandboxes with `bwrap`).
- The Roblox place is a Studio-only demo: one player, not published. Its art
  pool is lost each time Studio closes the place, so run `make dress` again
  before the next Play.

## Commands

```sh
make install       # Lean, the game, all proofs, Python env
make run           # the app on :8642
make verify        # axioms + trusted definitions per theorem, then lake comparator on Verification/
make check         # acceptance checks against the judge, runtime, and upload endpoint (server running)
make examples      # rebuild the shipped levels through the judge
make roblox        # build the Roblox place build/RiggedArcade.rbxlx (gets Rojo and selene into .tools/)
make roblox-serve  # live-sync roblox/ into the place open in Studio (never the art)
make dress         # fill the place open in Studio with the art kit and each level's decor (Edit mode, before Play)
```

## Layout

```
templates/maze/      Maze/Game.lean (rules) · Spec.lean · Cert.lean (certificate + soundness) · runtime · GUIDE.md
app/upload/          Upload/Store.lean (storage decision, size limit) · UploadGate.lean (the gate)
Specs/UploadSpec/    readable upload specs and their proofs
app/decor/           Decor/Gate.lean (the decor gate, proved) · DecorGate.lean (its program)
Specs/DecorSpec/     readable decor specs and their proofs
Verification/        repository challenge, solution, audit
app/                 server.py · verify.py (judge) · agent.py · templates.py · web/
                     dress.py (make dress) · studio.py (Studio MCP) · decor_gate.py
samples/             reviewed sample requirements per game
examples/            shipped levels, each a self-contained judged Lean project
scripts/             make_examples.py · check.py
roblox/              Rojo project for the Roblox place (renderer only)
```

## Art credits

All art comes from the Roblox Creator Store and is used inside Roblox Studio
only. No model file is stored in the repo (`roblox/art/` is git-ignored),
because Roblox content may be used on Roblox only. `make dress` inserts models
into the open place by id.

- Art kit, inserted by `make dress`: Roof Light (12737467199) by
  SillyGoofyDumb, backrooms monster (10699449494) by mihopb1, and Yasu's
  Backrooms Material Pack (89043606186394) by mvyasu.
- Watcher looks in our demo place: Subaru Natsuki (122480168835819) by O_Kar,
  "annoying robot with bernie sanders face" (1192620519) by Arsaw (kept under
  the name `bernie sanders`), and Jon Snow (934805927) by Aethanius.
- Decor props: Creator Store models picked per level, from its `decor.json` or
  searched for among free models from verified creators. The dress step does
  not record which model it took, so props are not credited one by one.
- Sounds, Roblox audio used by id and never stored: light hum 9112823813
  (Light Bulb Buzz 2, ProSoundEffects), room tone 9125446564 (Command Room Tone
  Deep Air Conditioning Hum, ProSoundEffects), drone 1843770413 (Low Drone 42,
  APMOfficial), and light switch click 9120484192 (Wall Light Switch 2,
  ProSoundEffects).

Built for the Vibecheck hackathon. Plan and reasoning: `ARCHITECTURE.md`,
`UPLOAD_SECURITY.md`, `RULES.md`.

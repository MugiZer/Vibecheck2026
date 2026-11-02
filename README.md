# Rigged Arcade

**Every level ships with a proof. Some are fair. Some are rigged. Lean knows which.**

Pick what you want to be true about a maze ("impossible, but looks
winnable", "can be won", or your own Lean statement), and describe it in a
sentence. Claude designs the level. Lean checks a proof about the exact
level you then play. Try to beat a rigged level, then press **Show why**: in
the game lights the cells that pass Lean's region check, turn by turn;
until a guard catches you, you are always on a lit cell, and the exit is
never lit.

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

## How it works

```
browser ──HTTP──> coordinator (app/server.py, Python stdlib)
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

## Why the proofs are about the game you play

The rules are executable Lean, and the same functions are what the game runs.

- Maze: the game process reads the move names with `MazeRuntime.replayMoves`,
  and `maze_runtime_replays_with_run` proves that it then answers with
  `Maze.run` of those moves, the function the other theorems are about. It
  refuses any other name. The browser holds no rules; it draws the state the
  runtime returns.

## What is proved

Repository theorems, judged by `lake comparator` (see `Verification/`):

| Theorem | In plain words |
|---|---|
| `maze_regions_sound` | For every maze and every certificate: if the certificate passes `checkRegions`, no list of moves of any length wins. |
| `maze_isOpen_iff` | The fast bit test for open cells means "on the board and not a wall". |
| `maze_never_leaves_regions` | For every maze and every list of painted cells (one list per turn of the guards' cycle): if the lists pass `checkRegions`, then after any moves, while the game is on, you stand on a painted cell of the current turn. Show why paints lists like these; each time a level opens, the runtime runs `checkRegions` on the lists it paints. |
| `maze_runtime_replays_with_run` | The maze game process accepts a list of move names exactly when every name is a move, and then it answers with `Maze.run` of those moves. It refuses any other name. |
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

The decor gate is proved and judged here, but the Roblox place does not use it yet.

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
`templates/maze/MazeRuntime/Replay.lean`, `app/upload/Upload/Store.lean`,
`Specs/UploadSpec/`.

## What is trusted

- **Lean's kernel** and the axioms `propext`, `Quot.sound`, `Classical.choice`.
  No `sorry`, no `native_decide`, no new axioms (`make check` confirms the judge
  rejects each).
- **The definitions in the statements.** A theorem means only what they say:
  for example "caught" means a guard lands on your cell or you swap cells.
- **The Lean compiler, while you play.** The running game is compiled code of
  the proved functions. The kernel checked the theorems about those functions.
- **Not proved:** the JSON adapters; the line in the maze process that passes
  the request's names to `replayMoves`; the Python coordinator, HTTP, the
  browser drawing, and the upload gate's file-system calls and read loop (which
  calls the proved `Upload.admit` before writing each chunk of at most 64 KiB).
  The runtime's compiled `checkRegions` checks Show why's glowing cells each
  time a level is opened. The caption beside them comes from the coordinator
  (`reveal.check.caption`).
  `make check` tests these through the real endpoints. The `bwrap` sandbox and
  the operating system are trusted to isolate uploaded Lean, which can run code
  while it compiles.
- **Search and the agent are not trusted.** They only propose; the kernel and
  `lake comparator` decide.

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

## Commands

```sh
make install    # Lean, the game, all proofs, Python env
make run        # the app on :8642
make verify     # axioms + trusted definitions per theorem, then lake comparator on Verification/
make check      # acceptance checks against the judge, runtime, and upload endpoint (server running)
make examples   # rebuild the shipped levels through the judge
```

## Layout

```
templates/maze/      Maze/Game.lean (rules) · Spec.lean · Cert.lean (certificate + soundness) · runtime · GUIDE.md
app/upload/          Upload/Store.lean (storage decision, size limit) · UploadGate.lean (the gate)
Specs/UploadSpec/    readable upload specs and their proofs
Verification/        repository challenge, solution, audit
app/                 server.py · verify.py (judge) · agent.py · templates.py · web/
samples/             reviewed sample requirements per game
examples/            shipped levels, each a self-contained judged Lean project
scripts/             make_examples.py · check.py
```

Built for the Vibecheck hackathon. Plan and reasoning: `ARCHITECTURE.md`,
`UPLOAD_SECURITY.md`, `RULES.md`.

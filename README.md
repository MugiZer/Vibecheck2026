# blox

blox is about making games with rules you can prove. You bring an idea for a
world and decide what has to be true inside it. An agent works on the level
and its proof, and Lean checks that the result follows the rules you asked for.

In a horror game, you can make "no way out" something you actually prove.
Give the player a safe start, space to move, and an exit they can see, then
prove that no sequence of moves will ever get them there. Or make a room
they can escape, with a route to back it up.

> **Come find me and I'll show you live.** Right now, I'm the only person who
> can run the complete walkthrough, because the tools and Studio assets are
> configured on my machine. You can inspect the code and play the browser
> examples from this repo, but you won't see the whole experience that way.
> Bring an idea for a room, or someone ridiculous you want chasing you.

## What we're making right now

We start from one Backrooms-style maze template and make variations of it.
The movement rules and proof tools stay fixed. The agent changes the layout,
the exit, the watchers' patrol routes, and the look of the room to fit a new
requirement and creative brief.

You walk through yellow office corridors in Roblox, under humming lights,
with watchers somewhere between you and the exit. Everything advances one
turn at a time, even in the first-person view. Some rooms are escapable;
others are deliberately impossible under those same rules.

A brief can be as odd as:

> Give me three watchers: Subaru Natsuki, Bernie Sanders and Jon Snow.
> Put burgers on the floor. Make escape impossible, but give me a safe
> start and at least one way to survive six moves.

The watcher names and burgers guide the art. The Lean requirement handles
the watcher count, safe start, six survivable moves, and impossible escape.
Keeping the game template fixed gives us room to try these combinations
while checking each new layout against its own requirements.

## See why you couldn't escape

Press **Show why** in an impossible room. The lights go out, the camera rises,
and the checked regions of the maze glow, one watcher turn at a time. As long
as you're still playing, you can only be on a glowing tile for that turn.
The exit never glows.

Those regions come from the level's certificate, which the runtime checks
when the room opens. In an escapable room, Show why replays a winning route.
You can try the room yourself, then see the explanation in the space you've
just been walking through.

## How a room gets made

1. You provide a creative brief and a Lean file defining
   `UserSpec.requirement : Maze.Variant → Prop`. The brief describes the room;
   the Lean file says exactly what must hold.
2. The agent proposes a variation of the maze template. It tries the level
   against the Lean runtime, gets feedback, and writes a proof for that
   particular level.
3. The judge builds the submission in a Linux sandbox and runs
   `lake comparator` against a challenge written by the coordinator. The
   proof must establish that the maze is well formed, meets the template's
   playability conditions, and satisfies your requirement.
4. Only an accepted level enters the local collection. It includes the
   requirement, level, proof, judge log, and hashes. You can open it in the
   browser or the connected Roblox Studio place.

The same Lean rules used in the proof drive play. The browser and Roblox
send moves to the coordinator and draw the state returned by the Lean
runtime. Before a session starts, the coordinator checks that the loaded
level matches the judged candidate and uses the current template.

Agents also use Roblox Studio's MCP connection to prepare the scene. In
Studio's Edit mode, they can find Creator Store models, strip scripts, and
check the reported model trees with the Lean decor gate before adding them.
The artwork gives each room its character; movement and escape still follow
the checked maze rules.

Generation runs one job at a time, with time and cost limits. A request can
run out of budget or fail to produce an accepted level. A failed search does
not prove that the request is impossible.

## What Lean checks

The proofs cover the game rules and specific decisions in the upload and
asset gates. The statements and their definitions are available in the repo.

| Part | What is checked | Where to read it |
| --- | --- | --- |
| Each accepted room | The level is well formed, has a route to the exit with watchers removed, offers a safe first step to another cell, and satisfies the uploaded requirement. An unwinnable requirement rules out every winning move list, of any length. A winnable requirement supplies a winning route. | [Maze specs](templates/maze/Maze/Spec.lean), [sample requirements](samples/maze/), [shipped proofs](examples/) |
| Gameplay and Show why | Recognized move names replay through `Maze.run`. The region checker is sound: if a certificate passes, escape is impossible, and a player still in the game stays inside the checked region for the current turn. | [Replay](templates/maze/MazeRuntime/Replay.lean), [certificate checker](templates/maze/Maze/Cert.lean) |
| Upload decisions | Client filenames do not affect the destination. Paths have the fixed shape `uploads/<32 lowercase hex digits>/UserSpec.lean`. The byte limit is exact for any chunking, and accepted uploads pass every chunk through in order. The app uses a 64 KiB limit. | [Upload specs and proofs](Specs/UploadSpec/), [upload implementation](app/upload/) |
| Decor decisions | An accepted model tree uses allowed classes, stays within size and depth limits, and has inert parts inside the slot box. The gate also checks asset IDs. | [Decor specs and proofs](Specs/DecorSpec/), [decor implementation](app/decor/) |

The repository's theorem list is in
[Verification/Challenge.lean](Verification/Challenge.lean). `make verify`
prints the axioms and definitions behind the main statements, then runs
Comparator. The judge rejects `sorry`, `native_decide`, and added axioms.

<details>
<summary>The Lean requirement for the three-watcher room</summary>

The comment lines guide the visual brief. The proposition below them is what
the generated room must prove.

```lean
import Maze.Spec

-- watcher: Subaru Natsuki, Bernie Sanders, Jon Snow
-- floor: burger every tile
-- decor: office chair, filing cabinet, water cooler

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Unwinnable v ∧
  v.guards.length = 3 ∧
  v.gems = [] ∧
  (∀ route ∈ v.guards, Maze.nextToOrSame v v.start (Maze.guardAt route 0) = false) ∧
  ∃ moves : List Maze.Move, moves.length = 6 ∧ (Maze.run v moves).status = .playing
```

</details>

### What is trusted

The proof means what its definitions say. Here, being caught means a watcher
lands on your cell or you swap cells with one. The maze is turn based; the
claims concern those rules. Appearance, fun, character likenesses, and human
reaction time are outside those claims. For an uploaded requirement, the app
shows the requirement itself; it reserves the familiar room labels for the
reviewed samples.

- Lean's kernel and the standard axioms `propext`, `Quot.sound`, and
  `Classical.choice` are trusted. During play, the Lean compiler is also
  trusted to execute the proved functions correctly.
- The Python coordinator, JSON adapters, HTTP, filesystem operations, upload
  read loop, and the call that hands move names to the runtime are outside
  the proofs. The operating system and `bubblewrap` provide isolation while
  uploaded Lean compiles. `make check` exercises the real endpoints and
  checks that the judge rejects invalid submissions.
- The browser, Roblox Studio, Luau scripts, `HttpService`, and the Windows/WSL
  connection draw and transport the game state. They are not formally
  verified. Show why's caption comes from the coordinator; the runtime
  checks the regions used for the display.
- The decor gate checks the model tree reported to it. It trusts the Studio
  tooling to report that tree accurately and use the checked asset. The
  scene compares instance counts when cloning a model; that is not a proof
  of asset identity. Manually cached watcher looks are trusted to have been
  checked. The gate cannot inspect an image or prove that a model resembles
  its name. Material variants use a separate class-and-children filter.
  Roblox, its Creator Store, and the Studio MCP connection remain trusted.
- The generation agent and its search results supply candidates. Acceptance
  depends on the proof check. Decoration is visual only and does not change
  a move, a win, or a watcher's position.

The impossibility certificate ignores gems, so it must establish that the
exit itself is unreachable. See [UPLOAD_SECURITY.md](UPLOAD_SECURITY.md) for
the upload boundary in more detail.

## Running the parts yourself

There is a fair amount to install for the full setup. The browser examples
are the easiest part to run locally. The live walkthrough also needs Roblox
Studio, the generation tools, and the local connection between them.

| What you want to run | What you need |
| --- | --- |
| Browser and shipped rooms | Linux or WSL, `make`, `curl`, Python 3, and Lean. `make install` installs Lean through elan if needed and builds the game with the pinned toolchain. |
| New room generation | `bubblewrap`, a Python environment with the Claude Agent SDK, and `ANTHROPIC_API_KEY`. `make install` attempts to set up the environment through `uv` or Python's `venv` and pip. |
| Roblox view | Roblox Studio on Windows, with the coordinator running in WSL. `make roblox` downloads the pinned Rojo and selene tools and the Rojo plugin into `.tools/`, checking their SHA-256 hashes. |
| Creator Store art and dressing | Roblox's Studio MCP, a configured local launcher, access to the assets, and Studio open in Edit mode. The launcher script is not included in the repo; its path is `LAUNCHER` in [app/studio.py](app/studio.py). |

Start the browser app:

```sh
make install && make run
```

Open [http://127.0.0.1:8642](http://127.0.0.1:8642). The shipped rooms play
without a model key or `bubblewrap`. Making new rooms needs the generation
setup above.

To use Codex for generation instead, install `openai-codex` in `.venv`, log in
with its `codex login`, and start the server with `RIGGED_BACKEND=codex make run`.

### Opening the Roblox place

With the coordinator running, use another WSL terminal:

```sh
make roblox
```

Open `build/RiggedArcade.rbxlx` in Roblox Studio on Windows using **File > Open
from File**. Windows can reach it at
`\\wsl$\<your distro>\<path to the repo>\build\RiggedArcade.rbxlx`.
If the coordinator needs another address, build with
`make roblox ROBLOX_URL=http://...`.

For art and props, configure the Studio MCP launcher, then run `make dress`
while Studio is in Edit mode. On the first run, it prints the available
materials. Set `WALL`, `FLOOR`, and `CEILING` in [app/dress.py](app/dress.py)
to the wallpaper, carpet, and ceiling numbers from that list, then run
`make dress` again.

Each run refills `ServerStorage.DressPool`. Cached character looks need to
be added afterwards; `make dress` does not populate `DressPool.Looks`.
Those assets live in the open Studio session and need preparing again when
the place closes. A fresh build uses the built-in materials and shapes until
that setup is done.

Press **Play** (F5). Use W to step, A/D to turn, S to turn around, Space to
wait, R to restart, and M for the map. While Studio is playing, **Play in
Roblox** in the browser sends the selected room to the open place.

The place currently runs in Studio with one player. It is not a published
Roblox experience, and its in-game text does not pass through `TextService`.
That local Studio session, including its prepared artwork, is what I'll
show you in person.

### Useful commands

| Command | Purpose |
| --- | --- |
| `make install` | Set up Lean, build the game and proofs, and attempt to install the generation SDK. |
| `make run` | Start the coordinator and browser app on port 8642. |
| `make verify` | Audit axioms and trusted definitions, then run Comparator on `Verification/`. |
| `make check` | Check the judge, runtime, and upload endpoints with the server running. |
| `make examples` | Rebuild the shipped rooms through the judge. |
| `make roblox` | Build `build/RiggedArcade.rbxlx`. |
| `make roblox-serve` | Sync source changes into Studio through Rojo; art is separate. |
| `make dress` | Prepare the open place's art and props in Edit mode. |

For live source sync, copy `.tools/Rojo.rbxm` into
`%LOCALAPPDATA%\Roblox\Plugins\`, restart Studio, run `make roblox-serve`,
and connect through **Plugins > Rojo** on `localhost:34872`.

## Reading the code

- [templates/maze/](templates/maze/) contains the game rules, specs,
  certificate checker, runtime, and [level design guide](templates/maze/GUIDE.md).
- [app/agent.py](app/agent.py), [app/verify.py](app/verify.py), and
  [app/server.py](app/server.py) handle generation, judging, and play.
- [Verification/](Verification/) contains the repository's proof challenge,
  solution, examples, and audits.
- [samples/maze/](samples/maze/) contains reviewed requirements;
  [examples/](examples/) contains complete judged rooms. Each room is a
  self-contained Lean project where you can run `lake comparator`.
- [roblox/](roblox/) contains the Roblox renderer.

Built for the Vibecheck hackathon. [RULES.md](RULES.md) describes the judging
criteria, and [CLAUDE.md](CLAUDE.md) records the verification guidelines.
[ARCHITECTURE.md](ARCHITECTURE.md) preserves the design history; the current
implementation is the maze workflow described here.

## Art credits

The artwork comes from the Roblox Creator Store and is used inside Roblox
Studio. Model files are not committed to this repo. `make dress` inserts
models into the open place by ID.

- Art kit: Roof Light (12737467199) by SillyGoofyDumb, backrooms monster
  (10699449494) by mihopb1, and Yasu's Backrooms Material Pack
  (89043606186394) by mvyasu.
- Watcher looks in my prepared place: Subaru Natsuki (122480168835819) by
  O_Kar, "annoying robot with bernie sanders face" (1192620519) by Arsaw,
  and Jon Snow (934805927) by Aethanius.
- Other props come from Creator Store searches or each level's `decor.json`.
  The dressing step does not currently record individual prop credits.
- Audio, used by ID: Light Bulb Buzz 2 (9112823813), Command Room Tone Deep
  Air Conditioning Hum (9125446564), and Wall Light Switch 2 (9120484192) by
  ProSoundEffects; Low Drone 42 (1843770413) by APMOfficial.

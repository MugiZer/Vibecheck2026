import Maze.Spec

/-! Demo spec 2 for the Backrooms: a way out exists, but it is a long, tight run.

* some list of moves gets you out, and Lean replays that exact list on the
  game's own rules to prove it;
* exactly four watchers patrol it, all four Subaru Natsuki (`UserSpec.watcherLooks`),
  and none of them starts on or next to you;
* the exit is at least 12 steps from the start (rows plus columns);
* the maze is at least 12 wide and 10 high;
* there are no gems: the only goal is the exit.

The game also always checks `Maze.Playable`: with the watchers removed there is
a clear way out, and your first move is safe. -/

-- decor: filing cabinet, water cooler
-- floor: burger every tile
-- (Props along the walls and a burger on every tile. Lean ignores these
--  comments; the decor gate proves only that each model is safe.)

/-- The watchers' looks, one per watcher, in patrol order. The game reads this
list and dresses watcher i in look i (models from Roblox's Creator Store). -/
def UserSpec.watcherLooks : List String :=
  ["Subaru Natsuki", "Subaru Natsuki", "Subaru Natsuki", "Subaru Natsuki"]

/-- One look per watcher (as many watchers as looks), and every look is
Subaru Natsuki: four watchers, all Subaru Natsuki. -/
abbrev UserSpec.FourSubarus (v : Maze.Variant) : Prop :=
  v.guards.length = UserSpec.watcherLooks.length ∧
  UserSpec.watcherLooks.length = 4 ∧
  ∀ look ∈ UserSpec.watcherLooks, look = "Subaru Natsuki"

/-- No watcher starts on your start cell or on a cell next to it. -/
abbrev UserSpec.SafeSpawn (v : Maze.Variant) : Prop :=
  ∀ route ∈ v.guards, Maze.nextToOrSame v (Maze.guardAt route 0) v.start = false

/-- The exit is at least 12 steps from the start: column distance plus row distance. -/
abbrev UserSpec.ExitFarAway (v : Maze.Variant) : Prop :=
  let sx := v.start % v.width
  let sy := v.start / v.width
  let ex := v.exit % v.width
  let ey := v.exit / v.width
  12 ≤ (sx - ex) + (ex - sx) + (sy - ey) + (ey - sy)

/-- The maze is at least 12 cells wide and 10 cells high. -/
abbrev UserSpec.BigMaze (v : Maze.Variant) : Prop :=
  12 ≤ v.width ∧ 10 ≤ v.height

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Winnable v ∧ v.gems = [] ∧ UserSpec.FourSubarus v ∧
  UserSpec.SafeSpawn v ∧ UserSpec.ExitFarAway v ∧ UserSpec.BigMaze v

/-! ## Checks on the spec itself

Lean proves the whole requirement except `Maze.Playable` on a small hand-made
room, and proves that broken rooms fail it. The judge proves the full
requirement for each generated level. -/

/-- A 12 by 10 open room: start top left, exit 12 steps away, four watchers
pacing near the bottom. -/
def UserSpec.sampleRoom : Maze.Variant :=
  { width := 12, height := 10, walls := [], start := 0, exit := 23, gems := [],
    guards := [[96, 97], [99, 100], [102, 103], [105, 106]] }

theorem UserSpec.sampleRoom_meets_requirement : UserSpec.requirement UserSpec.sampleRoom :=
  ⟨⟨[.right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .down],
     by decide⟩,
   by decide, by decide, by decide, by decide, by decide⟩

/-- Three watchers is rejected: the spec asks for four. -/
theorem UserSpec.three_watchers_rejected :
    ¬ UserSpec.FourSubarus { UserSpec.sampleRoom with guards := [[96, 97], [99, 100], [102, 103]] } := by
  decide

/-- An exit 11 steps away is rejected. -/
theorem UserSpec.exit_too_close_rejected :
    ¬ UserSpec.ExitFarAway { UserSpec.sampleRoom with exit := 11 } := by
  decide

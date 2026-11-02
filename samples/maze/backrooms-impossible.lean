import Maze.Spec

/-! Demo spec for the Backrooms.

Nobody can get out of this maze, but it is a real, fair-looking place to play:

* no list of moves, of any length, reaches the exit without a watcher catching you;
* exactly three watchers patrol it, one of each look in `UserSpec.watcherLooks`
  (Subaru Natsuki, Bernie Sanders, Jon Snow), and none starts on or next to you;
* you can stay alive for at least 8 turns, so you never die right off spawn;
* the exit is at least 8 steps from the start (rows plus columns);
* the maze is at least 10 wide and 8 high;
* there are no gems: the only goal is the exit.

The game also always checks `Maze.Playable`: with the watchers removed there is
a clear way out, and your first move is safe. -/

-- decor: office chair, filing cabinet, water cooler
-- floor: burger every tile
-- (Props along the walls and a burger on every tile. Lean ignores these
--  comments; the decor gate proves only that each model is safe.)

/-- The watchers' looks, one per watcher, in patrol order: watcher 1 wears the
first look, watcher 2 the second, watcher 3 the third. The game reads this list
and dresses watcher i in look i (models from Roblox's Creator Store). -/
def UserSpec.watcherLooks : List String := ["Subaru Natsuki", "Bernie Sanders", "Jon Snow"]

/-- One watcher of each look: as many watchers as looks, and no look twice. -/
abbrev UserSpec.OneWatcherPerLook (v : Maze.Variant) : Prop :=
  v.guards.length = UserSpec.watcherLooks.length ∧ UserSpec.watcherLooks.Nodup

/-- No watcher starts on your start cell or on a cell next to it. -/
abbrev UserSpec.SafeSpawn (v : Maze.Variant) : Prop :=
  ∀ route ∈ v.guards, Maze.nextToOrSame v (Maze.guardAt route 0) v.start = false

/-- Some way of playing keeps you alive for 8 turns. -/
def UserSpec.SurvivesEightTurns (v : Maze.Variant) : Prop :=
  ∃ moves : List Maze.Move, moves.length = 8 ∧ (Maze.run v moves).status = .playing

/-- The exit is at least 8 steps from the start: column distance plus row distance. -/
abbrev UserSpec.ExitFarAway (v : Maze.Variant) : Prop :=
  let sx := v.start % v.width
  let sy := v.start / v.width
  let ex := v.exit % v.width
  let ey := v.exit / v.width
  8 ≤ (sx - ex) + (ex - sx) + (sy - ey) + (ey - sy)

/-- The maze is at least 10 cells wide and 8 cells high. -/
abbrev UserSpec.BigMaze (v : Maze.Variant) : Prop :=
  10 ≤ v.width ∧ 8 ≤ v.height

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Unwinnable v ∧ v.gems = [] ∧ UserSpec.OneWatcherPerLook v ∧
  UserSpec.SafeSpawn v ∧ UserSpec.SurvivesEightTurns v ∧
  UserSpec.ExitFarAway v ∧ UserSpec.BigMaze v

/-! ## Checks on the spec itself

Lean proves each rule on a small hand-made room, so the rules can all be met,
and proves that broken rooms fail them. The full requirement (including
"impossible to win") is proved for each generated level by the judge. -/

/-- A 10 by 8 open room: start in one corner, exit in the far corner, three
watchers pacing far from the start. -/
def UserSpec.sampleRoom : Maze.Variant :=
  { width := 10, height := 8, walls := [], start := 0, exit := 77, gems := [],
    guards := [[55, 56], [57, 58], [65, 66]] }

theorem UserSpec.sampleRoom_meets_rules :
    UserSpec.OneWatcherPerLook UserSpec.sampleRoom ∧ UserSpec.SafeSpawn UserSpec.sampleRoom ∧
    UserSpec.ExitFarAway UserSpec.sampleRoom ∧ UserSpec.BigMaze UserSpec.sampleRoom := by
  decide

theorem UserSpec.sampleRoom_survives : UserSpec.SurvivesEightTurns UserSpec.sampleRoom :=
  ⟨[.stay, .stay, .stay, .stay, .stay, .stay, .stay, .stay], by decide⟩

/-- Two watchers for three looks is rejected. -/
theorem UserSpec.two_watchers_rejected :
    ¬ UserSpec.OneWatcherPerLook { UserSpec.sampleRoom with guards := [[55, 56], [57, 58]] } := by
  decide

/-- A watcher starting next to you is rejected. -/
theorem UserSpec.watcher_next_to_start_rejected :
    ¬ UserSpec.SafeSpawn { UserSpec.sampleRoom with guards := [[1, 2], [57, 58], [65, 66]] } := by
  decide

/-- An exit next to the start is rejected. -/
theorem UserSpec.exit_next_to_start_rejected :
    ¬ UserSpec.ExitFarAway { UserSpec.sampleRoom with exit := 1 } := by
  decide

import Maze.Spec

/-! Demo spec 3 for the Backrooms: a real maze, not a room with one guarded door.

Nobody can get out of this maze, and it is a real maze to explore:

* no list of moves, of any length, reaches the exit without a watcher catching you;
* exactly three watchers patrol it, one of each look in `UserSpec.watcherLooks`
  (Subaru Natsuki, Bernie Sanders, Jon Snow), and none starts on or next to you;
* you can stay alive for at least 8 turns, so you never die right off spawn;
* the exit is at least 8 steps from the start (rows plus columns);
* the maze is at least 10 wide and 8 high;
* it is a maze, not a room: no 2 by 2 block of open floor anywhere, so every
  hallway is one tile wide, and at least a quarter of the tiles are walls;
* every watcher really patrols: its loop visits at least 4 steps, so no watcher
  just stands in a doorway;
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

/-- No open rooms: no 2 by 2 block of four open tiles anywhere, so every hallway
is one tile wide. -/
abbrev UserSpec.NoOpenRooms (v : Maze.Variant) : Prop :=
  ∀ c ∈ List.range v.cells, c % v.width + 1 < v.width → c + v.width + 1 < v.cells →
    ¬ (v.isOpen c = true ∧ v.isOpen (c + 1) = true ∧
       v.isOpen (c + v.width) = true ∧ v.isOpen (c + v.width + 1) = true)

/-- At least a quarter of the tiles are walls. -/
abbrev UserSpec.EnoughWalls (v : Maze.Variant) : Prop :=
  v.cells ≤ 4 * v.walls.length

/-- Every watcher really patrols: each loop has at least 4 steps. -/
abbrev UserSpec.WatchersPatrol (v : Maze.Variant) : Prop :=
  ∀ route ∈ v.guards, 4 ≤ route.length

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Unwinnable v ∧ v.gems = [] ∧ UserSpec.OneWatcherPerLook v ∧
  UserSpec.SafeSpawn v ∧ UserSpec.SurvivesEightTurns v ∧
  UserSpec.ExitFarAway v ∧ UserSpec.BigMaze v ∧
  UserSpec.NoOpenRooms v ∧ UserSpec.EnoughWalls v ∧ UserSpec.WatchersPatrol v

/-! ## Checks on the spec itself

Lean proves each rule on a small hand-made maze, so the rules can all be met,
and proves that broken mazes fail them. The full requirement (including
"impossible to win") is proved for each generated level by the judge. -/

/-- A 10 by 8 grid of pillars (a wall wherever both coordinates are odd): no open
2 by 2 block, a quarter walls, three watchers pacing 4-step loops far from the start. -/
def UserSpec.sampleMaze : Maze.Variant :=
  { width := 10, height := 8, start := 0, exit := 76, gems := [],
    walls := (List.range 80).filter (fun c => c % 2 = 1 ∧ (c / 10) % 2 = 1),
    guards := [[40, 41, 42, 41], [44, 45, 46, 45], [60, 61, 62, 61]] }

theorem UserSpec.sampleMaze_meets_rules :
    UserSpec.OneWatcherPerLook UserSpec.sampleMaze ∧ UserSpec.SafeSpawn UserSpec.sampleMaze ∧
    UserSpec.ExitFarAway UserSpec.sampleMaze ∧ UserSpec.BigMaze UserSpec.sampleMaze ∧
    UserSpec.NoOpenRooms UserSpec.sampleMaze ∧ UserSpec.EnoughWalls UserSpec.sampleMaze ∧
    UserSpec.WatchersPatrol UserSpec.sampleMaze := by
  decide

theorem UserSpec.sampleMaze_survives : UserSpec.SurvivesEightTurns UserSpec.sampleMaze :=
  ⟨[.stay, .stay, .stay, .stay, .stay, .stay, .stay, .stay], by decide⟩

/-- One big open room (no walls) is rejected: it has open 2 by 2 blocks. -/
theorem UserSpec.open_room_rejected :
    ¬ UserSpec.NoOpenRooms { UserSpec.sampleMaze with walls := [] } := by
  decide

/-- A watcher bouncing between two tiles (standing in a doorway) is rejected. -/
theorem UserSpec.doorway_guard_rejected :
    ¬ UserSpec.WatchersPatrol { UserSpec.sampleMaze with guards := [[40, 41], [44, 45, 46, 45], [60, 61, 62, 61]] } := by
  decide

/-- A watcher starting next to you is rejected. -/
theorem UserSpec.watcher_next_to_start_rejected :
    ¬ UserSpec.SafeSpawn { UserSpec.sampleMaze with guards := [[1, 2, 3, 2], [44, 45, 46, 45], [60, 61, 62, 61]] } := by
  decide

import Maze.Spec

/-! Sample requirement: nobody can win this level, and there is no hiding
place. Every open cell lies on some watcher's loop, so a player who stands
still anywhere is caught within one loop. `Maze.Playable` is always checked
too, so the level still looks winnable. -/

/-- Every open cell is on the route of at least one guard. -/
abbrev UserSpec.NoHidingPlace (v : Maze.Variant) : Prop :=
  ∀ c ∈ List.range v.cells, v.isOpen c = true → ∃ route ∈ v.guards, c ∈ route

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Unwinnable v ∧ UserSpec.NoHidingPlace v

-- The Museum Vault (a shipped rigged level) has hiding places, for example its start.
#guard !decide (UserSpec.NoHidingPlace
  { width := 11, height := 9,
    walls := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15, 21, 22, 24, 26, 28, 29, 30, 32, 33, 35, 39,
      41, 43, 44, 46, 47, 48, 49, 50, 52, 54, 55, 63, 65, 66, 67, 68, 69, 70, 72, 73, 74, 76, 77,
      87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98],
    start := 12, exit := 78, gems := [40, 56],
    guards := [[71, 82], [64, 75], [56, 57, 58, 59, 60, 59, 58, 57]] })

-- A corridor of three cells, swept end to end by one guard: no hiding place.
#guard decide (UserSpec.NoHidingPlace
  { width := 3, height := 1, walls := [], start := 0, exit := 2, gems := [],
    guards := [[0, 1, 2, 1]] })

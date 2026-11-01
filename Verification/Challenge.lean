import Maze
import UploadSpec.Destination
import UploadSpec.Limit

/-!
# The repository's main theorems (trusted statements)

`lake comparator --config Verification/comparator.json` checks that
`Verification/Solution.lean` proves exactly these statements with only the
standard axioms. Each published level has its own challenge as well, written by
the coordinator.
-/

/-- Maze: a region certificate that passes `checkRegions` proves the level
cannot be won, for every level and every certificate. -/
theorem maze_regions_sound (v : Maze.Variant) (R : List Nat)
    (h : Maze.checkRegions v R = true) : Maze.Unwinnable v := sorry

/-- Maze: the fast bit test for open cells means "on the board and not a wall". -/
theorem maze_isOpen_iff (v : Maze.Variant) (c : Nat) :
    v.isOpen c = true ↔ c < v.cells ∧ c ∉ v.walls := sorry

/-- Upload: the client's file name never changes where an upload is stored. -/
theorem upload_ignores_client_name : UploadSpec.IgnoresClientName := sorry

/-- Upload: every stored path is `uploads/<32 hex digits>/UserSpec.lean`. -/
theorem upload_fixed_shape : UploadSpec.FixedShape := sorry

/-- Upload: the bytes the gate writes never add up to more than the limit. -/
theorem upload_never_over_limit : UploadSpec.NeverOverLimit := sorry

/-- Upload: an upload is accepted exactly when it fits in the limit. -/
theorem upload_accepted_iff_within_limit : UploadSpec.AcceptedIffWithinLimit := sorry

/-- Upload: an accepted upload is written in full. -/
theorem upload_accepted_writes_everything : UploadSpec.AcceptedWritesEverything := sorry

/-- Maze: Show why paints one list of cells for each turn of the guards' cycle.
If those lists pass `checkRegions`, then after any list of moves, while the game
is still on, the player stands on a cell of the list for the current turn. -/
theorem maze_never_leaves_regions (v : Maze.Variant) (cells : List (List Nat))
    (h : Maze.checkRegions v (cells.map Maze.maskOfList) = true)
    (moves : List Maze.Move) (hplay : (Maze.run v moves).status = .playing) :
    (Maze.run v moves).pos ∈ cells.getD (Maze.run v moves).turn [] := sorry

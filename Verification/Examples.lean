import Verification.Solution

namespace Examples

/-! ### The Museum Vault, a shipped rigged level -/

/-- The Museum Vault (`examples/4f87aa1149ef`), copied from its `Candidate.lean`. -/
def vault : Maze.Variant := { width := 11, height := 9, walls := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15, 21, 22, 24, 26, 28, 29, 30, 32, 33, 35, 39, 41, 43, 44, 46, 47, 48, 49, 50, 52, 54, 55, 63, 65, 66, 67, 68, 69, 70, 72, 73, 74, 76, 77, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98], start := 12, exit := 78, gems := [40, 56], guards := [[71, 82], [64, 75], [56, 57, 58, 59, 60, 59, 58, 57]] }

/-- What Show why paints for The Museum Vault: its manifest's `reveal.cellsByTurn`,
one list for each of the 8 turns of the guards' cycle. -/
def vaultCells : List (List Nat) := [[12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 64], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 57], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 57, 58, 64], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 57, 58, 59], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 57, 58, 64], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 57], [12, 13, 14, 16, 17, 18, 19, 20, 23, 25, 27, 31, 34, 36, 37, 38, 42, 45, 53, 56, 64]]

/-- Six moves after which the game is still on: turn 6, cell 57. -/
def walk : List Maze.Move := [.up, .down, .down, .down, .down, .right]

/-- Six moves after which a guard catches you: turn 6, cell 58. -/
def caughtWalk : List Maze.Move := [.down, .down, .down, .down, .right, .right]

-- Every hypothesis holds on a shipped level.
example : Maze.checkRegions vault (vaultCells.map Maze.maskOfList) = true := by decide
example : (Maze.run vault walk).status = .playing := by decide
example : (Maze.run vault walk).pos ∈ vaultCells.getD (Maze.run vault walk).turn [] :=
  maze_never_leaves_regions vault vaultCells (by decide) walk (by decide)

-- The list must be the current turn's: after `walk` you stand on cell 57 on turn 6,
-- and the list for turn 7 does not have it.
example : (Maze.run vault walk).pos ∉
    vaultCells.getD (((Maze.run vault walk).turn + 1) % vault.cycle) [] := by decide

-- Once you are caught, the claim no longer holds: after `caughtWalk` a guard
-- catches you on cell 58, and the list for turn 6 does not have it.
example : (Maze.run vault caughtWalk).status = .caught ∧
    (Maze.run vault caughtWalk).pos ∉ vaultCells.getD (Maze.run vault caughtWalk).turn [] := by decide

/-! ### `tiny`, a small made-up level (not playable: its exit is walled off) -/

/-- A 3 by 3 maze with no guards. Walls on cells 5 and 7 shut the exit (cell 8) off.
```
S . .
. . #
. # E
```
-/
def tiny : Maze.Variant :=
  { width := 3, height := 3, walls := [5, 7], start := 0, exit := 8, gems := [], guards := [] }

/-- What Show why paints for `tiny`: one turn (no guards), every open cell but the exit. -/
def tinyCells : List (List Nat) := [[0, 1, 2, 3, 4, 6]]

-- Every hypothesis holds on a small input.
example : (Maze.run tiny [.right, .down]).pos ∈ tinyCells.getD (Maze.run tiny [.right, .down]).turn [] :=
  maze_never_leaves_regions tiny tinyCells (by decide) [.right, .down] (by decide)

-- The check refuses painted cells that leave out a cell you can reach (cell 4) ...
example : Maze.checkRegions tiny ([[0, 1, 2, 3, 6]].map Maze.maskOfList) = false := by decide
-- ... and painted cells that include the exit.
example : Maze.checkRegions tiny ([[0, 1, 2, 3, 4, 6, 8]].map Maze.maskOfList) = false := by decide

/-! ## `maze_runtime_replays_with_run` -/

-- A concrete input: two real move names are accepted and played with `Maze.run`.
example : MazeRuntime.replayMoves tiny ["right", "down"] = .ok (Maze.run tiny [.right, .down]) :=
  (maze_runtime_replays_with_run tiny ["right", "down"] _).mpr ⟨[.right, .down], rfl, rfl⟩
-- The spec refuses a name that is not a move ...
example : ¬ ∃ moves : List Maze.Move, ["teleport"].map MazeRuntime.Move.ofString? = moves.map some := by
  rintro ⟨moves, h⟩
  cases moves <;> simp [MazeRuntime.Move.ofString?] at h
-- ... and a process that ignored the move (answered "right" with the start state).
example : ¬ ∃ moves : List Maze.Move,
    ["right"].map MazeRuntime.Move.ofString? = moves.map some ∧ Maze.start tiny = Maze.run tiny moves := by
  rintro ⟨moves, h1, h2⟩
  match moves, h1 with
  | [m], h1 =>
    simp [MazeRuntime.Move.ofString?] at h1
    subst h1
    revert h2; decide
-- What it buys: on a level proved unwinnable, no reply the process gives is a win.
example (v : Maze.Variant) (hv : Maze.Unwinnable v) (names : List String) (s : Maze.State)
    (h : MazeRuntime.replayMoves v names = .ok s) : s.status ≠ .escaped := by
  obtain ⟨moves, -, rfl⟩ := (maze_runtime_replays_with_run v names s).mp h
  exact fun hw => hv ⟨moves, hw⟩
-- The hypothesis `Maze.Unwinnable v` holds on a concrete level.
example : Maze.Unwinnable tiny :=
  maze_regions_sound tiny (tinyCells.map Maze.maskOfList) (by decide)

end Examples

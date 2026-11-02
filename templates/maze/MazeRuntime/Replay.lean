import Maze

/-!
# Reading move names and replaying them (runtime, no JSON)

The game process answers every `replay` request with `replayMoves`. This
module does not import `Lean`, so `Verification/` can state theorems about it.
-/

namespace MazeRuntime
open Maze

/-- A move from the name a renderer sends. Any other name is not a move. -/
def Move.ofString? : String → Option Move
  | "up" => some .up
  | "down" => some .down
  | "left" => some .left
  | "right" => some .right
  | "stay" => some .stay
  | _ => none

/-- Read one move name, or refuse it. -/
def readMove (n : String) : Except String Move :=
  match Move.ofString? n with
  | some m => pure m
  | none => throw s!"unknown move {n}"

/-- Read the move names and play them from the start with `Maze.run`.
Fails on the first name that is not a move. -/
def replayMoves (v : Variant) (names : List String) : Except String State := do
  let moves ← names.mapM readMove
  return run v moves

end MazeRuntime

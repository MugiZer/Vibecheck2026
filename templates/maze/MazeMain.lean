import MazeRuntime.Json

/-!
# The maze game process

`maze serve` answers one JSON request per line on stdin:

* `{"op":"replay","variant":V,"moves":["up",...]}` plays the moves from the
  start with `Maze.run`, the function the proofs are about, and returns the
  state.
* `{"op":"solve","variant":V}` searches for evidence (untrusted).
* `{"op":"drawing","variant":V}` returns each guard's cell on every turn.
* `{"op":"lean","variant":V}` prints the `Candidate` module for the level.
* `{"op":"check","variant":V,"cellsByTurn":[[...],...]}` runs `Maze.checkRegions`
  on the cells Show why paints and returns `{"passes":true|false}`.

`maze lean FILE` and `maze solve FILE` do the same for a JSON file.
-/

open Lean Maze MazeRuntime

def parseVariant (j : Json) : Except String Variant := fromJson? j

def handle (req : Json) : Except String Json := do
  let op ← req.getObjValAs? String "op"
  let v ← parseVariant (← req.getObjVal? "variant")
  match op with
  | "replay" =>
    let names ← req.getObjValAs? (List String) "moves"
    return stateJson v (← replayMoves v names)
  | "solve" => return solveJson v
  | "drawing" => return drawingJson v
  | "lean" =>
    if (problems v).isEmpty then return toJson (candidateModule v)
    else throw s!"level is not well formed: {problems v}"
  | "check" => return checkJson v (← req.getObjValAs? (List (List Nat)) "cellsByTurn")
  | _ => throw s!"unknown op {op}"

def serve : IO Unit := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    let reply := match Json.parse line >>= handle with
      | .ok j => Json.mkObj [("ok", true), ("result", j)]
      | .error e => Json.mkObj [("ok", false), ("error", toJson e)]
    stdout.putStrLn reply.compress
    stdout.flush

def main (args : List String) : IO UInt32 := do
  match args with
  | ["serve"] => serve; return 0
  | [op, path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= parseVariant with
    | .error e => IO.eprintln e; return 1
    | .ok v =>
      match handle (Json.mkObj [("op", toJson op), ("variant", toJson v)]) with
      | .ok (.str s) => IO.print s; return 0
      | .ok j => IO.println j.pretty; return 0
      | .error e => IO.eprintln e; return 1
  | _ => IO.eprintln "usage: maze serve | maze (lean|solve) VARIANT.json"; return 2

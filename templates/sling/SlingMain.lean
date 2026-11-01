import SlingRuntime.Json

/-!
# The slingshot game process

`sling serve` answers one JSON request per line on stdin:

* `{"op":"replay","variant":V,"moves":["3:5",...]}` flies each launch with
  `Sling.flight`, the function the proofs are about, and returns the last
  flight. A shot the level does not allow is refused, so play stays inside
  `Sling.shots`, the set the proofs cover.
* `{"op":"solve","variant":V}` reports every shot's outcome (untrusted search).
* `{"op":"drawing","variant":V}` returns where flights start and the cell size.
* `{"op":"lean","variant":V}` prints the `Candidate` module for the level.
-/

open Lean Sling SlingRuntime

def handle (req : Json) : Except String Json := do
  let op ← req.getObjValAs? String "op"
  let v : Variant ← fromJson? (← req.getObjVal? "variant")
  match op with
  | "replay" =>
    let names ← req.getObjValAs? (List String) "moves"
    let launched ← names.mapM fun n => match Shot.ofString? n with
      | some s => if shots v |>.contains s then pure s else throw s!"this level does not allow the shot {n}"
      | none => throw s!"bad shot {n}"
    return stateJson v launched
  | "solve" => return solveJson v
  | "drawing" => return drawingJson v
  | "lean" =>
    if (problems v).isEmpty then return toJson (candidateModule v)
    else throw s!"level is not well formed: {problems v}"
  | _ => throw s!"unknown op {op}"

def main (args : List String) : IO UInt32 := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  if args != ["serve"] then
    IO.eprintln "usage: sling serve"
    return 2
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    let reply := match Json.parse line >>= handle with
      | .ok j => Json.mkObj [("ok", true), ("result", j)]
      | .error e => Json.mkObj [("ok", false), ("error", toJson e)]
    stdout.putStrLn reply.compress
    stdout.flush
  return 0

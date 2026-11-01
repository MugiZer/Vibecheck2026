import Lean.Data.Json
import MazeRuntime.Search

/-!
# JSON for the maze runtime (untrusted adapter)

Converts levels and states to and from JSON, and prints a level as Lean source.
The printed source is what the judge checks; the coordinator compares it with
what this runtime prints for the level it plays, so both are the same level.
-/

namespace MazeRuntime
open Lean Maze

deriving instance FromJson, ToJson for Maze.Variant

def Move.ofString? : String → Option Move
  | "up" => some .up
  | "down" => some .down
  | "left" => some .left
  | "right" => some .right
  | "stay" => some .stay
  | _ => none

def Move.name : Move → String
  | .up => "up"
  | .down => "down"
  | .left => "left"
  | .right => "right"
  | .stay => "stay"

def Status.name : Status → String
  | .playing => "playing"
  | .caught => "caught"
  | .escaped => "escaped"

/-- A list of moves as Lean source, e.g. `[.up, .left]`. -/
def movesLean (ms : List Move) : String :=
  "[" ++ ", ".intercalate (ms.map fun m => "." ++ Move.name m) ++ "]"

/-- The level as Lean source: the body of `Candidate.variant`. -/
def variantLean (v : Variant) : String :=
  s!"\{ width := {v.width}, height := {v.height},\n    walls := {v.walls},\n    start := {v.start}, exit := {v.exit}, gems := {v.gems},\n    guards := {v.guards} }"

/-- The board as text, one row per line: `#` wall, `S` start, `E` exit, `G` gem. -/
def picture (v : Variant) : String := Id.run do
  let mut out := ""
  for y in [0:v.height] do
    for x in [0:v.width] do
      let c := y * v.width + x
      out := out.push <|
        if c == v.start then 'S' else if c == v.exit then 'E'
        else if v.gems.contains c then 'G' else if v.isOpen c then '.' else '#'
    out := out.push '\n'
  return out

/-- The `Candidate` module the judge imports. Generated; never edit by hand. -/
def candidateModule (v : Variant) : String :=
  "import Maze.Game\n\n/-! The level under test. Generated from validated data; do not edit.\n\n```\n" ++
    picture v ++ "```\n-/\n\ndef Candidate.variant : Maze.Variant :=\n  " ++ variantLean v ++ "\n"

/-- Plain-language problems that stop `WellFormed` from holding. -/
def problems (v : Variant) : List String := Id.run do
  let mut ps : List String := []
  if !(3 ≤ v.width && v.width ≤ 16 && 3 ≤ v.height && v.height ≤ 16) then
    ps := ps ++ ["the board must be 3 to 16 cells wide and high"]
  if !(v.walls.all (· < v.cells)) then ps := ps ++ ["a wall is off the board"]
  if !v.isOpen v.start then ps := ps ++ ["the start must be an open cell"]
  if !v.isOpen v.exit then ps := ps ++ ["the exit must be an open cell"]
  if v.start == v.exit then ps := ps ++ ["the start and exit must differ"]
  if v.gems.length > 4 then ps := ps ++ ["at most 4 gems"]
  if !(v.gems.all v.isOpen) then ps := ps ++ ["every gem must be on an open cell"]
  if v.gems.eraseDups.length != v.gems.length then ps := ps ++ ["two gems share a cell"]
  if v.gems.contains v.start then ps := ps ++ ["no gem on the start cell"]
  if v.guards.length > 4 then ps := ps ++ ["at most 4 guards"]
  if v.cycle > 24 then ps := ps ++ [s!"the guards' routes repeat together every {v.cycle} turns; keep it at most 24 (use route lengths like 2, 4, 6, 8, 12)"]
  for (route, k) in v.guards.zipIdx do
    if route.isEmpty || route.length > 12 then ps := ps ++ [s!"guard {k}: route must have 1 to 12 cells"]
    if !(route.all v.isOpen) then ps := ps ++ [s!"guard {k}: every route cell must be open"]
    for i in [0:route.length] do
      let a := route.getD i 0
      let b := route.getD ((i + 1) % route.length) 0
      if !nextToOrSame v a b then
        ps := ps ++ [s!"guard {k}: route step {i} jumps from cell {a} to {b}; guards move one cell at a time, and the route loops back to its first cell"]
    if guardAt route 0 == v.start then ps := ps ++ [s!"guard {k} starts on the player's start cell"]
  return ps

def stateJson (v : Variant) (s : State) : Json :=
  Json.mkObj [
    ("pos", toJson s.pos), ("turn", toJson s.turn), ("status", toJson (Status.name s.status)),
    ("collected", toJson ((List.range v.gems.length).map fun i => s.gems.testBit i)),
    ("guards", toJson (v.guards.map fun r => guardAt r s.turn)),
    ("guardsNext", toJson (v.guards.map fun r => guardAt r (s.turn + 1)))]

/-- Everything the agent or the reveal needs to know about a level. -/
def solveJson (v : Variant) : Json := Id.run do
  let ps := problems v
  let R := regions v
  let exitInRegions := R.any (·.testBit v.exit)
  let win := findWin v
  let route := findWin (withoutGuards v)
  let first := Move.all.find? fun m =>
    (step v (start v) m).status == .playing && (step v (start v) m).pos != v.start
  let verdict :=
    if win.isSome then "winnable" else if !exitInRegions then "unwinnable" else "unresolved"
  let hints : List (String × Json) :=
    [("wellFormed", toJson "by decide +kernel")] ++
    (match route, first with
      | some r, some m => [("playable", toJson s!"⟨⟨{movesLean r}, by decide +kernel⟩, ⟨.{Move.name m}, by decide +kernel⟩⟩")]
      | _, _ => []) ++
    (match win with
      | some w => [("winnable", toJson s!"⟨{movesLean w}, by decide +kernel⟩")]
      | none => []) ++
    (if exitInRegions then [] else
      [("unwinnable", toJson s!"Maze.unwinnable_of_checkRegions (R := {R}) (by decide +kernel)")])
  return Json.mkObj [
    ("wellFormed", toJson ps.isEmpty), ("problems", toJson ps),
    ("verdict", toJson verdict),
    ("winningMoves", toJson (win.map (·.map Move.name))),
    ("routeWithoutGuards", toJson (route.map (·.map Move.name))),
    ("safeFirstMove", toJson (first.map Move.name)),
    ("regions", if exitInRegions then Json.null else toJson R),
    ("regionCells", if exitInRegions then Json.null else toJson (regionCells v R)),
    ("cycle", toJson v.cycle),
    ("leanHints", Json.mkObj hints)]

/-- Run `Maze.checkRegions`, the check `maze_regions_sound` is about, on the
cells Show why paints (one list of cells per turn of the guards' cycle). -/
def checkJson (v : Variant) (cells : List (List Nat)) : Json :=
  Json.mkObj [("passes", toJson (checkRegions v (cells.map maskOfList)))]

end MazeRuntime

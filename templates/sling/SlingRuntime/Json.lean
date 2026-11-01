import Lean.Data.Json
import Sling

/-!
# JSON for the slingshot runtime (untrusted adapter)

Converts levels and flights to and from JSON and prints a level as Lean
source. The coordinator compares that source with the module the judge
checked, so the game plays the checked level.
-/

namespace SlingRuntime
open Lean Sling

deriving instance FromJson, ToJson for Sling.Variant

def Outcome.name : Outcome → String
  | .hitTarget => "hitTarget"
  | .hitBlock => "hitBlock"
  | .hitGround => "hitGround"
  | .leftWorld => "leftWorld"
  | .tooLong => "tooLong"

/-- A shot written as `"angle:power"`, with the angle index (not degrees). -/
def Shot.ofString? (s : String) : Option Shot :=
  match s.splitOn ":" with
  | [a, p] => do pure ⟨← a.toNat?, ← p.toNat?⟩
  | _ => none

def variantLean (v : Variant) : String :=
  s!"\{ width := {v.width}, height := {v.height},\n    blocks := {v.blocks},\n    target := {v.target}, launch := {v.launch},\n    angles := {v.angles}, powers := {v.powers} }"

/-- The world as text, top row first: `#` block, `T` target, `S` slingshot. -/
def picture (v : Variant) : String := Id.run do
  let mut out := ""
  for r in [0:v.height] do
    let y := v.height - 1 - r
    for x in [0:v.width] do
      let c := y * v.width + x
      out := out.push <|
        if c == v.target then 'T' else if c == v.launch then 'S'
        else if v.blocks.contains c then '#' else '.'
    out := out.push '\n'
  return out

def candidateModule (v : Variant) : String :=
  "import Sling.Game\n\n/-! The level under test. Generated from validated data; do not edit.\n\n```\n" ++
    picture v ++ "```\n-/\n\ndef Candidate.variant : Sling.Variant :=\n  " ++ variantLean v ++ "\n"

def problems (v : Variant) : List String := Id.run do
  let cells := v.width * v.height
  let mut ps : List String := []
  if !(4 ≤ v.width && v.width ≤ 24 && 3 ≤ v.height && v.height ≤ 14) then
    ps := ps ++ ["the world must be 4 to 24 cells wide and 3 to 14 high"]
  if !(v.launch < cells) then ps := ps ++ ["the slingshot is off the board"]
  if !(v.target < cells) then ps := ps ++ ["the target is off the board"]
  if v.launch == v.target then ps := ps ++ ["the slingshot and target share a cell"]
  if !(v.blocks.all fun b => b < cells && b != v.launch && b != v.target) then
    ps := ps ++ ["a block is off the board or on the slingshot or target"]
  if v.angles.isEmpty || v.angles.eraseDups.length != v.angles.length || !(v.angles.all (· < directions.length)) then
    ps := ps ++ ["angles must be distinct multiples of 10 degrees from 0 to 80"]
  if v.powers.isEmpty || v.powers.eraseDups.length != v.powers.length || !(v.powers.all fun p => 1 ≤ p && p ≤ 6) then
    ps := ps ++ ["powers must be distinct numbers from 1 to 6"]
  return ps

def flightJson (v : Variant) (s : Shot) : Json :=
  let (o, path) := flight v s
  Json.mkObj [("angle", toJson s.angle), ("power", toJson s.power), ("outcome", toJson (Outcome.name o)),
    ("path", toJson (path.map fun (x, y) => [x, y]))]

def stateJson (v : Variant) (launched : List Shot) : Json :=
  let won := launched.any (hits v)
  Json.mkObj [("launches", toJson launched.length), ("status", toJson (if won then "won" else "playing")),
    ("last", match launched.getLast? with | some s => flightJson v s | none => Json.null)]

/-- Where every flight starts (`launchStone`; the start does not depend on the
shot), and how many units make one cell. -/
def drawingJson (v : Variant) : Json :=
  let s := launchStone v ⟨0, 0⟩
  Json.mkObj [("launchPoint", toJson [s.x, s.y]), ("cellSize", toJson cellSize)]

def solveJson (v : Variant) : Json :=
  let ps := problems v
  let all := shots v
  let winners := all.filter (hits v)
  let open_ := (shots (withoutBlocks v)).filter (hits (withoutBlocks v))
  let verdict := if winners.isEmpty then "unwinnable" else "winnable"
  Json.mkObj [
    ("wellFormed", toJson ps.isEmpty), ("problems", toJson ps), ("verdict", toJson verdict),
    ("shotCount", toJson all.length),
    ("winningShots", toJson (winners.map fun s => s!"{s.angle * 10} degrees, power {s.power}")),
    ("winningShotCount", toJson winners.length),
    ("playable", toJson (!open_.isEmpty)),
    ("hitsWithoutBlocks", toJson (open_.map fun s => s!"{s.angle * 10} degrees, power {s.power}")),
    ("outcomes", toJson (all.map fun s => s!"{s.angle * 10} degrees, power {s.power}: {Outcome.name (outcome v s)}")),
    ("flights", toJson (all.map (flightJson v))),
    ("leanHints", Json.mkObj [
      ("wellFormed", toJson "by decide +kernel"), ("playable", toJson "by decide +kernel"),
      ("unwinnable", toJson "by decide +kernel"), ("winnable", toJson "by decide +kernel"),
      ("exactlyOneWinningShot", toJson "by decide +kernel")])]

end SlingRuntime

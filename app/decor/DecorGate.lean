import Lean.Data.Json
import Decor.Gate

/-!
# The decor gate program (untrusted adapter around proved decisions)

`decor-gate prop` or `decor-gate npc` reads one model tree as JSON from stdin
(at most 1 MiB), runs `Decor.accept` with `Decor.propLimits` or
`Decor.npcLimits`, and prints `{"ok": true, "nodes": N}` (exit 0) or
`{"ok": false, "nodes": N}` (exit 1). Input it cannot read gives
`{"ok": false, "error": "..."}` (exit 2).

`decor-gate id ID` prints `{"ok": true}` (exit 0) when `Decor.validAssetId`
accepts ID, else `{"ok": false}` (exit 1).

The reader is strict: a missing field, a wrong type, a fraction or a negative
number is an error. It never fills in a default. Extra fields are ignored.

Not proved here: this reader, and that the JSON describes the real model.
-/

open Lean Decor

/-- The most input read from stdin. -/
def maxBytes : Nat := 1024 * 1024

/-- The most nested brackets the reader accepts. A tree of `depth` levels uses
about `2 * depth + 1`, so every tree within `maxDepth` (8) fits; deeper input
is refused before parsing, so the parser's recursion stays small. -/
def maxNesting : Nat := 40

/-- The deepest bracket nesting in `b`, outside strings. -/
def nesting (b : ByteArray) : Nat := Id.run do
  let mut depth := 0
  let mut most := 0
  let mut inStr := false
  let mut esc := false
  for i in [0:b.size] do
    let c := b.get! i
    if inStr then
      if esc then esc := false
      else if c == 92 then esc := true      -- backslash
      else if c == 34 then inStr := false   -- quote
    else if c == 34 then inStr := true
    else if c == 91 || c == 123 then        -- [ {
      depth := depth + 1
      most := max most depth
    else if c == 93 || c == 125 then        -- ] }
      depth := depth - 1
  return most

partial def readAll (s : IO.FS.Stream) (acc : ByteArray) : IO (Option ByteArray) := do
  if acc.size > maxBytes then return none
  let chunk ← s.read 65536
  if chunk.isEmpty then return some acc
  readAll s (acc ++ chunk)

def field (j : Json) (k : String) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!"missing field {k}"

/-- A whole number of at least zero. `35.5`, `35.0`, `-1` are errors. -/
def natOf (k : String) (j : Json) : Except String Nat := do
  let some n := (j.getNum?).toOption | throw s!"{k} is not a number"
  if n.exponent != 0 then throw s!"{k} is not a whole number"
  if n.mantissa < 0 then throw s!"{k} is negative"
  return n.mantissa.toNat

def boolOf (j : Json) (k : String) : Except String Bool := do
  let some b := ((← field j k).getBool?).toOption | throw s!"{k} is not true or false"
  return b

def strOf (j : Json) (k : String) : Except String String := do
  let some s := ((← field j k).getStr?).toOption | throw s!"{k} is not a string"
  return s

def xyzOf (j : Json) (k : String) : Except String Xyz := do
  let some a := ((← field j k).getArr?).toOption | throw s!"{k} is not a list"
  let #[x, y, z] := a | throw s!"{k} does not have 3 numbers"
  return ⟨← natOf k x, ← natOf k y, ← natOf k z⟩

def nodeOf (j : Json) : Except String Node := do
  return { name := ← strOf j "name", cls := ← strOf j "cls",
           anchored := ← boolOf j "anchored", canCollide := ← boolOf j "canCollide",
           canTouch := ← boolOf j "canTouch", canQuery := ← boolOf j "canQuery",
           size := ← xyzOf j "size", off := ← xyzOf j "off",
           alongX := ← xyzOf j "alongX", alongY := ← xyzOf j "alongY", alongZ := ← xyzOf j "alongZ",
           displayDistance := ← strOf j "displayDistance", healthDisplay := ← strOf j "healthDisplay" }

/-- One instance and its children. `fuel` bounds the recursion; `maxNesting`
already bounds the input, so it never runs out on input that got this far. -/
def instOf : Nat → Json → Except String Inst
  | 0, _ => throw "tree too deep"
  | fuel + 1, j => do
    let some cs := ((← field j "children").getArr?).toOption | throw "children is not a list"
    return .mk (← nodeOf j) (← cs.toList.mapM (instOf fuel))

def say (line : String) (code : UInt32) : IO UInt32 := do
  IO.println line
  return code

def refuse (why : String) : IO UInt32 :=
  say s!"\{\"ok\": false, \"error\": {(Json.str why).compress}}" 2

def checkTree (lim : Limits) : IO UInt32 := do
  let some bytes ← readAll (← IO.getStdin) .empty | refuse "input is larger than 1 MiB"
  if nesting bytes > maxNesting then return ← refuse "input is nested too deep"
  let some text := String.fromUTF8? bytes | refuse "input is not UTF-8"
  match Json.parse text >>= instOf maxNesting with
  | .error why => refuse why
  | .ok t =>
    let ok := accept lim t
    say s!"\{\"ok\": {ok}, \"nodes\": {count t}}" (if ok then 0 else 1)

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prop"] => checkTree propLimits
  | ["npc"] => checkTree npcLimits
  | ["id", id] => if validAssetId id then say "{\"ok\": true}" 0 else say "{\"ok\": false}" 1
  | _ => say "usage: decor-gate prop|npc < tree.json, or decor-gate id ID" 2

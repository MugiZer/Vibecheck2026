import Maze
import Std.Data.HashMap

/-!
# Search for evidence (untrusted)

Nothing here is trusted. A winning list of moves is replayed by the kernel
with `run`, and a region certificate is checked with `checkRegions`.
-/

namespace MazeRuntime
open Maze

/-- Breadth-first search over full game states for a winning list of moves.
Returns `none` if no win was found within `limit` states. -/
def findWin (v : Variant) (limit : Nat := 300000) : Option (List Move) := Id.run do
  let s0 := start v
  let mut parent : Std.HashMap State (State × Move) := {}
  parent := parent.insert s0 (s0, .stay)
  let mut order : Array State := #[s0]
  let mut i := 0
  let mut goal : Option State := none
  while i < order.size && goal.isNone && order.size < limit do
    let s := order[i]!
    i := i + 1
    for m in Move.all do
      let s' := step v s m
      unless parent.contains s' do
        parent := parent.insert s' (s, m)
        order := order.push s'
        if s'.status == .escaped && goal.isNone then goal := some s'
  let some g := goal | return none
  let mut path : List Move := []
  let mut cur := g
  for _ in [0:order.size] do
    if cur == s0 then break
    let (p, m) := parent.getD cur (s0, .stay)
    path := m :: path
    cur := p
  return some path

/-- For each turn of the guards' cycle, the bit set of cells a player can stand
on, found by breadth-first search over (cell, turn) and ignoring gems. If the
exit is in none of them, this is a certificate for `checkRegions`. -/
def regions (v : Variant) : List Nat := Id.run do
  let n := v.cycle
  let mut R : Array Nat := Array.replicate n 0
  R := R.set! 0 (2 ^ v.start)
  let mut queue : Array (Nat × Nat) := #[(v.start, 0)]
  let mut i := 0
  while i < queue.size do
    let (c, t) := queue[i]!
    i := i + 1
    for m in Move.all do
      let d := moveTo v c m
      if !caughtBy v t c d then
        let t' := (t + 1) % n
        if !(R[t']!.testBit d) then
          R := R.set! t' (R[t']! ||| 2 ^ d)
          queue := queue.push (d, t')
  return R.toList

/-- The cells that appear in any of the region sets. -/
def regionCells (v : Variant) (R : List Nat) : List Nat :=
  (List.range v.cells).filter fun c => R.any (·.testBit c)

end MazeRuntime

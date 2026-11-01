/-!
# Maze rules

A turn-based maze. On each turn the player makes one move, then every guard
takes one step along its own loop. The player wins by picking up every gem and
then standing on the exit. The player is caught if a guard lands on the
player's cell, or if the player and a guard walk through each other.

The playable game runs these functions. The proofs are about these functions.
-/

namespace Maze

/-- One player move. `stay` waits for one turn. -/
inductive Move where
  | up | down | left | right | stay
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- Every move, in a fixed order. -/
def Move.all : List Move := [.up, .down, .left, .right, .stay]

/-- A level.

Cells are numbered row by row from the top left: the cell in column `x` and
row `y` is `y * width + x`. -/
structure Variant where
  width : Nat
  height : Nat
  /-- Cells the player and guards cannot enter. -/
  walls : List Nat
  start : Nat
  exit : Nat
  /-- The player must pick up all of these before the exit opens. -/
  gems : List Nat
  /-- Each guard walks its route in a loop, one cell per turn, starting at
  the first cell. -/
  guards : List (List Nat)
  deriving Repr, DecidableEq, Inhabited

/-- A number with bit `c` set for every cell `c` in the list. Lean's kernel
tests a bit much faster than it searches a list. -/
def maskOfList (cells : List Nat) : Nat := cells.foldr (fun c acc => 2 ^ c ||| acc) 0

namespace Variant

/-- The number of cells on the board. -/
def cells (v : Variant) : Nat := v.width * v.height

/-- A cell is open when it is on the board and is not a wall.
`Maze.isOpen_iff` restates this without bits. -/
def isOpen (v : Variant) (c : Nat) : Bool := c < v.cells && !(maskOfList v.walls).testBit c

/-- After this many turns, every guard is back at the start of its route. -/
def cycle (v : Variant) : Nat :=
  v.guards.foldl (fun acc route => Nat.lcm acc (max route.length 1)) 1

/-- The gem bits when every gem has been picked up. -/
def allGems (v : Variant) : Nat := 2 ^ v.gems.length - 1

end Variant

/-- Where a guard with this route stands on a given turn. -/
def guardAt (route : List Nat) (turn : Nat) : Nat :=
  route.getD (turn % route.length) 0

/-- How a game stands. -/
inductive Status where
  | playing | caught | escaped
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- Everything that changes during a game. -/
structure State where
  pos : Nat
  /-- The turn number, counted from 0 and wrapping at `Variant.cycle`. -/
  turn : Nat
  /-- Bit `i` is set once gem `i` has been picked up. -/
  gems : Nat
  status : Status
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- The state at the start of a game. -/
def start (v : Variant) : State :=
  { pos := v.start, turn := 0, gems := 0, status := .playing }

/-- The cell next to `c` in the direction of the move, if it is on the board. -/
def neighbor (v : Variant) (c : Nat) : Move → Option Nat
  | .up => if c / v.width = 0 then none else some (c - v.width)
  | .down => if c / v.width + 1 < v.height then some (c + v.width) else none
  | .left => if c % v.width = 0 then none else some (c - 1)
  | .right => if c % v.width + 1 < v.width then some (c + 1) else none
  | .stay => some c

/-- Where a move takes the player: the next cell if it is open, else nowhere. -/
def moveTo (v : Variant) (c : Nat) (m : Move) : Nat :=
  match neighbor v c m with
  | some d => if v.isOpen d then d else c
  | none => c

/-- Set the bit of every gem that lies on cell `c`. Gem `i` owns bit `i`. -/
def collectFrom (c : Nat) : List Nat → Nat → Nat → Nat
  | [], _, bits => bits
  | g :: rest, i, bits => collectFrom c rest (i + 1) (if g = c then bits ||| 2 ^ i else bits)

/-- Pick up the gem on cell `c`, if there is one. -/
def collect (v : Variant) (c : Nat) (bits : Nat) : Nat := collectFrom c v.gems 0 bits

/-- True if some guard catches a player who moves from `src` to `dst` on this
turn: the guard steps onto `dst`, or the guard and the player swap cells. -/
def caughtBy (v : Variant) (turn src dst : Nat) : Bool :=
  v.guards.any fun route =>
    let now := guardAt route turn
    let next := guardAt route (turn + 1)
    next == dst || (now == dst && next == src)

/-- One turn: the player moves, then every guard takes one step.
A finished game does not change. -/
def step (v : Variant) (s : State) (m : Move) : State :=
  if s.status != .playing then s else
  let dst := moveTo v s.pos m
  let turn := (s.turn + 1) % v.cycle
  if caughtBy v s.turn s.pos dst then
    { pos := dst, turn, gems := s.gems, status := .caught }
  else
    let gems := collect v dst s.gems
    let status := if dst == v.exit && gems == v.allGems then .escaped else .playing
    { pos := dst, turn, gems, status }

/-- Play a list of moves from the start. -/
def run (v : Variant) (moves : List Move) : State :=
  moves.foldl (step v) (start v)

end Maze

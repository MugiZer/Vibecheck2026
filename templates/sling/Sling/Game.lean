/-!
# Slingshot rules

A side-view physics game. The player picks a launch angle and a power from the
level's allowed choices, and a stone flies from the slingshot. Each tick the
stone moves by its velocity, then gravity pulls its upward speed down. The
flight ends when the stone enters a block, the target, the ground, or leaves
the world. The player wins by hitting the target.

Positions are whole numbers of units; a cell is 64 units wide and high. A
stone never moves more than 48 units per tick in either direction (falling
speed is capped there), so it cannot skip over a whole cell.
The playable game runs these functions. The proofs are about these functions.
-/

namespace Sling

/-- Units per cell, in both directions. -/
def cellSize : Nat := 64

/-- How much upward speed the stone loses each tick. -/
def gravity : Int := 2

/-- The fastest a stone can fall, in units per tick. -/
def maxFall : Int := 48

/-- The longest flight, in ticks. A stone still flying after this is a miss. -/
def maxTicks : Nat := 160

/-- Launch directions, one per allowed angle: angle `i` is `10 * i` degrees
above the ground. Each pair is about `8 * (cos, sin)` of the angle. -/
def directions : List (Nat × Nat) :=
  [(8, 0), (8, 1), (8, 3), (7, 4), (6, 5), (5, 6), (4, 7), (3, 8), (1, 8)]

/-- A level. Cells are numbered row by row from the bottom left: column `x`,
row `y` is `y * width + x`, and row 0 sits on the ground. -/
structure Variant where
  width : Nat
  height : Nat
  /-- Cells the stone cannot pass. -/
  blocks : List Nat
  /-- The cell to hit. -/
  target : Nat
  /-- The cell the slingshot is in. The stone starts at its center. -/
  launch : Nat
  /-- Allowed angles, as indices into `directions`. -/
  angles : List Nat
  /-- Allowed powers. Speed is direction times power, so powers are 1 to 6. -/
  powers : List Nat
  deriving Repr, DecidableEq, Inhabited

/-- One launch: an angle index and a power. -/
structure Shot where
  angle : Nat
  power : Nat
  deriving Repr, DecidableEq, Inhabited

/-- Every shot the level allows: each allowed angle with each allowed power. -/
def shots (v : Variant) : List Shot :=
  v.angles.flatMap fun a => v.powers.map fun p => ⟨a, p⟩

/-- How a flight ends. -/
inductive Outcome where
  | hitTarget | hitBlock | hitGround | leftWorld | tooLong
  deriving Repr, DecidableEq, Inhabited

/-- A number with bit `c` set for every cell `c` in the list. -/
def maskOfList (cells : List Nat) : Nat := cells.foldr (fun c acc => 2 ^ c ||| acc) 0

/-- The stone mid-flight. -/
structure Stone where
  x : Int
  y : Int
  vx : Int
  vy : Int
  deriving Repr, DecidableEq, Inhabited

/-- The stone at launch. -/
def launchStone (v : Variant) (s : Shot) : Stone :=
  let (dx, dy) := directions.getD s.angle (0, 0)
  { x := ((v.launch % v.width) * cellSize + cellSize / 2 : Nat),
    y := ((v.launch / v.width) * cellSize + cellSize / 2 : Nat),
    vx := (dx * s.power : Nat), vy := (dy * s.power : Nat) }

/-- What, if anything, ends the flight at this position. `blockBits` has a bit
per block cell. -/
def contact (v : Variant) (blockBits : Nat) (x y : Int) : Option Outcome :=
  if y < 0 then some .hitGround
  else if x < 0 || x ≥ (v.width * cellSize : Nat) || y ≥ (v.height * cellSize : Nat) then some .leftWorld
  else
    let c := (y.toNat / cellSize) * v.width + x.toNat / cellSize
    if c == v.target then some .hitTarget
    else if blockBits.testBit c then some .hitBlock
    else none

/-- Fly for at most `fuel` more ticks. Returns the outcome and the positions
the stone passed through, in order. -/
def flyFrom (v : Variant) (blockBits : Nat) : Nat → Stone → Outcome × List (Int × Int)
  | 0, _ => (.tooLong, [])
  | fuel + 1, st =>
    let x := st.x + st.vx
    let y := st.y + st.vy
    match contact v blockBits x y with
    | some o => (o, [(x, y)])
    | none =>
      let r := flyFrom v blockBits fuel { x, y, vx := st.vx, vy := max (st.vy - gravity) (-maxFall) }
      (r.1, (x, y) :: r.2)

/-- The whole flight of a shot. -/
def flight (v : Variant) (s : Shot) : Outcome × List (Int × Int) :=
  flyFrom v (maskOfList v.blocks) maxTicks (launchStone v s)

/-- How a shot ends. -/
def outcome (v : Variant) (s : Shot) : Outcome := (flight v s).1

/-- The shot hits the target. -/
def hits (v : Variant) (s : Shot) : Bool := outcome v s == .hitTarget

end Sling

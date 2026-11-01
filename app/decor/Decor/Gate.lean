/-!
# Decor gate: may a fetched model go into the scene?

The place deletes every class that is not on the allowlist from a Creator
Store model, and sets its parts to safe values. Then it sends the model's tree
to the coordinator as JSON, and the coordinator runs `accept`. The proofs in
`Specs/DecorSpec` are about these exact functions.

The place asks the gate at two times:
- In Edit mode, right after it strips a model in `ServerStorage`. It deletes
  every rejected model before anyone presses Play. This matters because a
  Script with `RunContext = Server` runs even in `ServerStorage`.
- In Play, about the copy it will show: clone with no parent, send that clone,
  and on yes, write the clone's JSON again, compare it with what it sent, and
  then parent that same clone.

The decision never reads a name. Names come from the model's creator and can
say anything, for example a Script named "Handle".

Not proved here: that the place reports every instance (the children of every
class, not only of Models), with its exact `ClassName` and its real property
values, and that it obeys the answer.
-/

namespace Decor

/-- Three whole numbers, one for each axis: x, y and z. -/
structure Xyz where
  x : Nat
  y : Nat
  z : Nat
  deriving DecidableEq, Repr

/-- One instance of the model, without its children. The part fields matter
only for part classes, and the display fields only for a Humanoid. For other
classes the place sends `false`, zero and `""`. All lengths are in tenths of a
stud, rounded up. -/
structure Node where
  /-- The instance's name. The gate never reads it. -/
  name : String
  /-- The exact `ClassName`, for example `"Part"`. -/
  cls : String
  /-- The part cannot move. -/
  anchored : Bool
  /-- Players and other parts bump into the part. -/
  canCollide : Bool
  /-- The part fires touch events. -/
  canTouch : Bool
  /-- Ray casts and other spatial queries see the part. -/
  canQuery : Bool
  /-- The part's size. `⟨40, 20, 10⟩` is 4 by 2 by 1 studs. -/
  size : Xyz
  /-- How far the part's center is from the model's pivot on each axis of the
  pivot. No sign: 3 studs left and 3 studs right are both `30`. -/
  off : Xyz
  /-- How much each side of the part points along the pivot's x axis, in
  thousandths. `alongX.y` is for the part's y side. A part that is not turned
  has `alongX = ⟨1000, 0, 0⟩`. -/
  alongX : Xyz
  /-- The same for the pivot's y axis. Not turned: `⟨0, 1000, 0⟩`. -/
  alongY : Xyz
  /-- The same for the pivot's z axis. Not turned: `⟨0, 0, 1000⟩`. -/
  alongZ : Xyz
  /-- For a Humanoid: the name of its `DisplayDistanceType`, for example `"None"`. -/
  displayDistance : String
  /-- For a Humanoid: the name of its `HealthDisplayType`, for example `"AlwaysOff"`. -/
  healthDisplay : String
  deriving DecidableEq, Repr

/-- A model's tree: one instance and its children. -/
inductive Inst where
  | mk (node : Node) (children : List Inst)

/-- The top instance of a tree. -/
def Inst.node : Inst → Node
  | .mk n _ => n

/-- Limits on one model. -/
structure Limits where
  /-- The most instances in the whole tree, the top one included. -/
  maxNodes : Nat
  /-- The most levels in the tree. A model with no children has 1 level. -/
  maxDepth : Nat
  /-- Half the size of the slot box on each axis, in tenths of a stud. The box's
  center is the model's pivot. Every part must stay inside it. -/
  half : Xyz

/-- Limits for a prop: 500 instances, 8 levels, a slot box of 4 by 6 by 4 studs.
Its x and z are equal, so a quarter turn of the model keeps the same box. -/
def propLimits : Limits := { maxNodes := 500, maxDepth := 8, half := ⟨20, 30, 20⟩ }

/-- Limits for an NPC look: as for a prop, with a slot box of 6 by 8 by 6 studs. -/
def npcLimits : Limits := { maxNodes := 500, maxDepth := 8, half := ⟨30, 40, 30⟩ }

/-- Part classes. Each part must be anchored, have collisions, touch events and
queries off, and stay inside the slot box. `SpawnLocation`, `Seat` and
`VehicleSeat` are parts too, but they are not on this list. -/
def partClasses : List String :=
  ["Part", "MeshPart", "WedgePart", "CornerWedgePart", "UnionOperation"]

/-- Classes that group parts (`Model`, `Folder`), color their faces (`Decal`,
`Texture`, `SurfaceAppearance`), or join them (`Attachment` and the joints,
which do nothing when every part is anchored). -/
def lookClasses : List String :=
  ["Model", "Folder", "Decal", "Texture", "SurfaceAppearance",
   "Attachment", "Weld", "WeldConstraint", "Motor6D"]

/-- Classes for an NPC's look. A Humanoid must have its display off, because
it would show the model's name, which can say anything. -/
def npcClasses : List String :=
  ["Humanoid", "BodyColors", "Shirt", "Pants", "ShirtGraphic", "Accessory"]

/-- Every class the gate allows. All other classes are rejected: scripts,
remotes, sounds, GUIs, text, lights, effects, special meshes, explosions,
tools, seats, spawns, click detectors, prompts, values. -/
def allowedClasses : List String := partClasses ++ lookClasses ++ npcClasses

/-- How wide a part is along one axis of the pivot, given how much each of its
sides points along that axis (`a`). In tenths of a stud, times 1000. -/
def width (size a : Xyz) : Nat := size.x * a.x + size.y * a.y + size.z * a.z

/-- The part stays inside the slot box on one axis: its center is `o` from the
pivot, and half its width `w` fits in what is left of `h`. -/
def fits (o w h : Nat) : Bool := 2000 * o + w ≤ 2000 * h

/-- The part checks: anchored; collisions, touch events and queries off; and
inside the slot box on all three axes. -/
def partOk (lim : Limits) (n : Node) : Bool :=
  n.anchored && !n.canCollide && !n.canTouch && !n.canQuery &&
  fits n.off.x (width n.size n.alongX) lim.half.x &&
  fits n.off.y (width n.size n.alongY) lim.half.y &&
  fits n.off.z (width n.size n.alongZ) lim.half.z

/-- The checks on one instance alone. Its name is not read. -/
def nodeOk (lim : Limits) (n : Node) : Bool :=
  allowedClasses.contains n.cls &&
  (!partClasses.contains n.cls || partOk lim n) &&
  (n.cls != "Humanoid" || (n.displayDistance == "None" && n.healthDisplay == "AlwaysOff"))

mutual
/-- The number of instances in a tree, the top one included. -/
def count : Inst → Nat
  | .mk _ cs => 1 + countAll cs

/-- The number of instances in a list of trees. -/
def countAll : List Inst → Nat
  | [] => 0
  | c :: cs => count c + countAll cs
end

mutual
/-- The number of levels in a tree. A tree with no children has 1 level. -/
def depth : Inst → Nat
  | .mk _ cs => 1 + depthAll cs

/-- The most levels of any tree in a list, or 0 for an empty list. -/
def depthAll : List Inst → Nat
  | [] => 0
  | c :: cs => max (depth c) (depthAll cs)
end

mutual
/-- Every instance in the tree passes `nodeOk`. -/
def allOk (lim : Limits) : Inst → Bool
  | .mk n cs => nodeOk lim n && allOkAll lim cs

/-- Every instance in every tree of the list passes `nodeOk`. -/
def allOkAll (lim : Limits) : List Inst → Bool
  | [] => true
  | c :: cs => allOk lim c && allOkAll lim cs
end

/-- The decor gate. Yes only if the top instance is a Model, the tree is within
the node and depth limits, and every instance passes `nodeOk`. -/
def accept (lim : Limits) (t : Inst) : Bool :=
  t.node.cls == "Model" && count t ≤ lim.maxNodes && depth t ≤ lim.maxDepth && allOk lim t

/-- An asset id that the coordinator may put into Luau code: 1 to 19
characters, each a digit from `0` to `9`. -/
def validAssetId (id : String) : Bool :=
  1 ≤ id.toList.length && id.toList.length ≤ 19 && id.toList.all fun c => '0' ≤ c && c ≤ '9'

end Decor

import Decor.Gate

/-!
# Spec: what an accepted model can hold

A third-party model goes into a place where HTTP is on. These statements say
what the decor gate lets through. They are about `Decor.accept` and
`Decor.validAssetId`, the functions the coordinator runs.

The class lists and the box rule are written out again here, and not taken
from the gate. So an edit to the gate's lists cannot change what a theorem
says: it breaks a proof instead.
-/

namespace DecorSpec
open Decor

/-- Every class an accepted model may hold. -/
def okClasses : List String :=
  ["Part", "MeshPart", "WedgePart", "CornerWedgePart", "UnionOperation",
   "Model", "Folder", "Decal", "Texture", "SurfaceAppearance",
   "Attachment", "Weld", "WeldConstraint", "Motor6D",
   "Humanoid", "BodyColors", "Shirt", "Pants", "ShirtGraphic", "Accessory"]

/-- The classes that get the part rules. -/
def solidClasses : List String :=
  ["Part", "MeshPart", "WedgePart", "CornerWedgePart", "UnionOperation"]

/-- Classes from the threat list that must never get in: code, things that act
with no script, text, sound, light and effects, and shapes that can draw
outside their part. -/
def badClasses : List String :=
  ["Script", "LocalScript", "ModuleScript", "Actor", "ProceduralModel", "PackageLink",
   "Explosion", "SpawnLocation", "Seat", "VehicleSeat", "Tool", "HopperBin", "Flag", "FlagStand",
   "Platform", "SkateboardPlatform", "TrussPart", "ForceField", "TouchTransmitter",
   "ClickDetector", "DragDetector", "ProximityPrompt", "Dialog", "DialogChoice",
   "RemoteEvent", "RemoteFunction", "LinearVelocity", "AlignPosition", "VectorForce",
   "BodyVelocity", "BodyPosition", "RocketPropulsion",
   "BillboardGui", "SurfaceGui", "TextLabel", "TextBox", "TextButton", "ImageLabel", "VideoFrame",
   "Sound", "AudioPlayer", "ParticleEmitter", "Fire", "Smoke", "Sparkles", "Beam", "Trail",
   "PointLight", "SpotLight", "SurfaceLight", "Highlight", "SelectionBox", "BoxHandleAdornment",
   "Sky", "Atmosphere", "SpecialMesh", "BlockMesh", "CylinderMesh", "Bone"]

/-- `NodeAt t d n`: `n` is an instance in tree `t`, `d` levels down. The top
instance is at level 1, its children at level 2, and so on. -/
inductive NodeAt : Inst → Nat → Node → Prop
  | top (n : Node) (cs : List Inst) : NodeAt (.mk n cs) 1 n
  | inChild (n : Node) (cs : List Inst) (c : Inst) (d : Nat) (m : Node) :
      c ∈ cs → NodeAt c d m → NodeAt (.mk n cs) (d + 1) m

/-- How wide part `n` is along one axis of the pivot, where `a` says how much
each side of the part points along that axis. In tenths of a stud, times 1000. -/
def widthAlong (n : Node) (a : Xyz) : Nat := n.size.x * a.x + n.size.y * a.y + n.size.z * a.z

/-- Part `n` is inside the slot box: on each axis, its distance from the pivot
plus half its width is at most half the box. (Both sides are times 2000.) -/
def InBox (lim : Limits) (n : Node) : Prop :=
  2000 * n.off.x + widthAlong n n.alongX ≤ 2000 * lim.half.x ∧
  2000 * n.off.y + widthAlong n n.alongY ≤ 2000 * lim.half.y ∧
  2000 * n.off.z + widthAlong n n.alongZ ≤ 2000 * lim.half.z

/-- A safe instance: its class is on the allowlist; a part is anchored, has
collisions, touch events and queries off, and is inside the slot box; a
Humanoid shows no name and no health bar. -/
def SafeNode (lim : Limits) (n : Node) : Prop :=
  n.cls ∈ okClasses ∧
  (n.cls ∈ solidClasses →
    n.anchored = true ∧ n.canCollide = false ∧ n.canTouch = false ∧ n.canQuery = false ∧
    InBox lim n) ∧
  (n.cls = "Humanoid" → n.displayDistance = "None" ∧ n.healthDisplay = "AlwaysOff")

/-- Safe decor: the top instance is a Model, the tree has at most `maxNodes`
instances, and every instance is at most `maxDepth` levels down and is safe. -/
def SafeDecor (lim : Limits) (t : Inst) : Prop :=
  (∀ n, NodeAt t 1 n → n.cls = "Model") ∧ count t ≤ lim.maxNodes ∧
  ∀ n d, NodeAt t d n → d ≤ lim.maxDepth ∧ SafeNode lim n

mutual
/-- The same tree with every name replaced by the empty name. -/
def eraseNames : Inst → Inst
  | .mk n cs => .mk { n with name := "" } (eraseNamesAll cs)

/-- `eraseNames` on every tree of a list. -/
def eraseNamesAll : List Inst → List Inst
  | [] => []
  | c :: cs => eraseNames c :: eraseNamesAll cs
end

/-- (a) In an accepted model, every instance at every level has a class from
the allowlist. -/
def OnlyAllowedClasses : Prop :=
  ∀ (lim : Limits) (t : Inst) (d : Nat) (n : Node),
    accept lim t = true → NodeAt t d n → n.cls ∈ okClasses

/-- (a) An accepted model holds no class from the threat list, at any level: no
script, no explosion, no seat or spawn, no prompt, no text, no sound, no light. -/
def NoBadClasses : Prop :=
  ∀ (lim : Limits) (t : Inst) (d : Nat) (n : Node),
    accept lim t = true → NodeAt t d n → n.cls ∉ badClasses

/-- (a) The top instance of an accepted model is a Model. -/
def TopIsModel : Prop :=
  ∀ (lim : Limits) (t : Inst) (n : Node), accept lim t = true → NodeAt t 1 n → n.cls = "Model"

/-- (b) In an accepted model, every part is anchored and has collisions, touch
events and queries off. -/
def PartsAreInert : Prop :=
  ∀ (lim : Limits) (t : Inst) (d : Nat) (n : Node),
    accept lim t = true → NodeAt t d n → n.cls ∈ solidClasses →
      n.anchored = true ∧ n.canCollide = false ∧ n.canTouch = false ∧ n.canQuery = false

/-- (b) In an accepted model, every part is inside the slot box. -/
def PartsStayInBox : Prop :=
  ∀ (lim : Limits) (t : Inst) (d : Nat) (n : Node),
    accept lim t = true → NodeAt t d n → n.cls ∈ solidClasses → InBox lim n

/-- (b) In an accepted model, every Humanoid shows no name and no health bar. -/
def HumanoidsShowNothing : Prop :=
  ∀ (lim : Limits) (t : Inst) (d : Nat) (n : Node),
    accept lim t = true → NodeAt t d n → n.cls = "Humanoid" →
      n.displayDistance = "None" ∧ n.healthDisplay = "AlwaysOff"

/-- (c) An accepted model has at most `maxNodes` instances, and no instance is
more than `maxDepth` levels down. -/
def WithinLimits : Prop :=
  ∀ (lim : Limits) (t : Inst), accept lim t = true →
    count t ≤ lim.maxNodes ∧ ∀ (d : Nat) (n : Node), NodeAt t d n → d ≤ lim.maxDepth

/-- (d) Names do not count: two models that differ only in names get the same
answer. -/
def IgnoresNames : Prop :=
  ∀ (lim : Limits) (a b : Inst), eraseNames a = eraseNames b → accept lim a = accept lim b

/-- (e) The gate is not empty: every safe model is accepted. -/
def AcceptsSafeDecor : Prop :=
  ∀ (lim : Limits) (t : Inst), SafeDecor lim t → accept lim t = true

/-- (f) Deleting instances from an accepted model keeps it accepted. `small` is
`big` with instances deleted when it has no more instances than `big`, and each
of its instances is also in `big` at the same level. `Clone()` does this when
it drops instances that are not `Archivable`. -/
def SmallerStaysAccepted : Prop :=
  ∀ (lim : Limits) (big small : Inst), accept lim big = true → count small ≤ count big →
    (∀ d n, NodeAt small d n → NodeAt big d n) → accept lim small = true

/-- (g) An asset id the gate accepts has 1 to 19 characters, each a digit from
`0` to `9`. So it holds no quote, no bracket and no line break, and it cannot
end or change the Luau code it is put into. -/
def IdIsDigitsOnly : Prop :=
  ∀ id : String, validAssetId id = true →
    1 ≤ id.toList.length ∧ id.toList.length ≤ 19 ∧
    ∀ c ∈ id.toList, '0' ≤ c ∧ c ≤ '9' ∧ c ≠ '"' ∧ c ≠ '\'' ∧ c ≠ ']' ∧ c ≠ '\n'

end DecorSpec

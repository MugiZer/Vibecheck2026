import Sling.Game

/-!
# What a slingshot level must satisfy

Stated with the rules in `Sling.Game`, the same functions the game runs. The
level's controls are exactly `shots v`: the game offers no other angle or
power, so a statement about every shot in `shots v` covers every way to play.
-/

namespace Sling

/-- Some allowed shot hits the target. -/
def Winnable (v : Variant) : Prop := ∃ s ∈ shots v, hits v s = true

/-- No allowed shot hits the target. -/
def Unwinnable (v : Variant) : Prop := ¬ Winnable v

/-- Exactly one allowed shot hits the target. -/
def ExactlyOneWinningShot (v : Variant) : Prop := (shots v).countP (hits v) = 1

/-- The same level with every block taken away. -/
def withoutBlocks (v : Variant) : Variant := { v with blocks := [] }

/-- The level can be built and played: a sensible size, the slingshot and the
target are distinct cells on the board, blocks are on the board, and the
controls are valid. -/
def WellFormed (v : Variant) : Prop :=
  4 ≤ v.width ∧ v.width ≤ 24 ∧ 3 ≤ v.height ∧ v.height ≤ 14 ∧
  v.launch < v.width * v.height ∧ v.target < v.width * v.height ∧ v.launch ≠ v.target ∧
  (∀ b ∈ v.blocks, b < v.width * v.height ∧ b ≠ v.launch ∧ b ≠ v.target) ∧
  v.angles ≠ [] ∧ v.angles.Nodup ∧ (∀ a ∈ v.angles, a < directions.length) ∧
  v.powers ≠ [] ∧ v.powers.Nodup ∧ (∀ p ∈ v.powers, 1 ≤ p ∧ p ≤ 6)

/-- The smallest amount of play every level must offer: with the blocks taken
away, some allowed shot would hit the target. So the target is in range; only
the blocks can stand in the way. A playable level can still be impossible. -/
def Playable (v : Variant) : Prop := Winnable (withoutBlocks v)

instance (v : Variant) : Decidable (WellFormed v) := by unfold WellFormed; infer_instance
instance (v : Variant) : Decidable (Winnable v) := by unfold Winnable; infer_instance
instance (v : Variant) : Decidable (Unwinnable v) := by unfold Unwinnable; infer_instance
instance (v : Variant) : Decidable (Playable v) := by unfold Playable; infer_instance
instance (v : Variant) : Decidable (ExactlyOneWinningShot v) := by unfold ExactlyOneWinningShot; infer_instance

end Sling

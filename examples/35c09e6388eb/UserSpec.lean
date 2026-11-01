import Sling.Spec

/-! Sample requirement: no allowed shot hits the target, even though the
slingshot offers at least 5 angles and 4 powers. `Sling.Playable` is always
checked too, so with the blocks taken away some shot would hit. -/

def UserSpec.requirement (v : Sling.Variant) : Prop :=
  Sling.Unwinnable v ∧ 5 ≤ v.angles.length ∧ 4 ≤ v.powers.length

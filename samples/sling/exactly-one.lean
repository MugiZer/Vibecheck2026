import Sling.Spec

/-! Sample requirement: a fair but tight puzzle. Exactly one of the allowed
shots hits the target, and the slingshot offers at least 5 angles and 4 powers
to choose from. -/

def UserSpec.requirement (v : Sling.Variant) : Prop :=
  Sling.ExactlyOneWinningShot v ∧ 5 ≤ v.angles.length ∧ 4 ≤ v.powers.length

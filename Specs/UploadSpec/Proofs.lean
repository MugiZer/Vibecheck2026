import UploadSpec.Destination
import UploadSpec.Limit

/-! Proofs of the upload specs, with examples that meet every hypothesis and
examples of bad behaviour the specs rule out. -/

namespace UploadSpec
open Upload

theorem ignoresClientName : IgnoresClientName := fun _ _ _ => rfl

theorem fixedShape : FixedShape := by
  intro id name path h
  simp only [destination] at h
  split at h
  · rename_i hv
    cases h
    simp only [validId, Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at hv
    refine ⟨by simp [storedName, String.append_assoc], hv.1, fun c hc => ?_⟩
    have hd := hv.2 c hc
    simp only [isHexDigit, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hd
    refine ⟨?_, ?_, hd⟩ <;> rintro rfl <;> simp at hd
  · cases h

theorem gate_written_le : ∀ (limit used : Nat) (chunks : List Nat), used ≤ limit →
    used + total (gate limit chunks used).1 ≤ limit
  | _, used, [], h => by simpa [gate, total] using h
  | limit, used, c :: cs, h => by
    by_cases hle : used + c ≤ limit
    · have ih := gate_written_le limit (used + c) cs hle
      simp only [gate, admit, hle, ite_true, total, List.foldr_cons] at ih ⊢
      omega
    · simp [gate, admit, hle, total, h]

theorem neverOverLimit : NeverOverLimit := fun limit chunks => by
  simpa using gate_written_le limit 0 chunks (Nat.zero_le _)

theorem gate_accepts_iff : ∀ (limit used : Nat) (chunks : List Nat), used ≤ limit →
    ((gate limit chunks used).2 = true ↔ used + total chunks ≤ limit)
  | _, used, [], h => by simpa [gate, total] using h
  | limit, used, c :: cs, _ => by
    by_cases hle : used + c ≤ limit
    · have ih := gate_accepts_iff limit (used + c) cs hle
      simp only [gate, admit, hle, ite_true, total, List.foldr_cons] at ih ⊢
      rw [ih]
      omega
    · simp only [gate, admit, hle, ite_false, total, List.foldr_cons, Bool.false_eq_true, false_iff]
      omega

theorem acceptedIffWithinLimit : AcceptedIffWithinLimit := fun limit chunks => by
  simpa using gate_accepts_iff limit 0 chunks (Nat.zero_le _)

theorem gate_accepted_all : ∀ (limit used : Nat) (chunks : List Nat),
    (gate limit chunks used).2 = true → (gate limit chunks used).1 = chunks
  | _, _, [], _ => rfl
  | limit, used, c :: cs, h => by
    by_cases hle : used + c ≤ limit
    · simp only [gate, admit, hle, ite_true] at h ⊢
      exact congrArg (c :: ·) (gate_accepted_all limit (used + c) cs h)
    · simp [gate, admit, hle] at h

theorem acceptedWritesEverything : AcceptedWritesEverything := fun limit chunks =>
  gate_accepted_all limit 0 chunks

/-! ## Examples -/

/-- A real id: traversal and absolute file names land in the same place as a plain one. -/
example : destination "0123456789abcdef0123456789abcdef" "../UserSpec.lean" =
    destination "0123456789abcdef0123456789abcdef" "spec.lean" := ignoresClientName _ _ _
example : destination "0123456789abcdef0123456789abcdef" "/etc/passwd" =
    some "uploads/0123456789abcdef0123456789abcdef/UserSpec.lean" := by decide
/-- Ids that are not 32 lowercase hex digits are refused. -/
example : destination "../../../../../../../../etc/passwd" "x" = none := by decide
example : destination "0123456789ABCDEF0123456789ABCDEF" "x" = none := by decide
example : destination "0123456789abcdef0123456789abcde/" "x" = none := by decide

/-- Limit 10: exactly 10 bytes is accepted, in any chunking. -/
example : gate 10 [4, 6] 0 = ([4, 6], true) := by decide
example : gate 10 [10] 0 = ([10], true) := by decide
/-- One byte over is rejected, and a chunk that crosses the limit is never written. -/
example : gate 10 [11] 0 = ([], false) := by decide
example : gate 10 [4, 7] 0 = ([4], false) := by decide
example : (gate 10 [4, 7] 0).2 = false := by decide
/-- The spec rejects a gate that would write a chunk crossing the limit. -/
example : ¬ (total [4, 7] ≤ 10) := by decide

end UploadSpec

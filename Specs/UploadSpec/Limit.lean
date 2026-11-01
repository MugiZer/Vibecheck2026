import Upload.Store

/-!
# Spec: an upload cannot be larger than the limit

The gate reads an upload in chunks and asks `Upload.admit` about each chunk
before writing it. These statements are about `Upload.gate`, which feeds a list
of chunk sizes through `admit` in the same way.
-/

namespace UploadSpec

/-- The total of a list of chunk sizes. -/
def total (chunks : List Nat) : Nat := chunks.foldr (· + ·) 0

/-- The bytes the gate lets through never add up to more than the limit, for
any sequence of chunks. -/
def NeverOverLimit : Prop :=
  ∀ (limit : Nat) (chunks : List Nat), total (Upload.gate limit chunks 0).1 ≤ limit

/-- An upload is accepted exactly when its total size is at most the limit. A
file of exactly the limit is accepted; one byte more is rejected. -/
def AcceptedIffWithinLimit : Prop :=
  ∀ (limit : Nat) (chunks : List Nat),
    (Upload.gate limit chunks 0).2 = true ↔ total chunks ≤ limit

/-- When an upload is accepted, every chunk is written, in order. -/
def AcceptedWritesEverything : Prop :=
  ∀ (limit : Nat) (chunks : List Nat),
    (Upload.gate limit chunks 0).2 = true → (Upload.gate limit chunks 0).1 = chunks

end UploadSpec

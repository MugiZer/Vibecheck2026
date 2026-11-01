import Upload.Store

/-!
# Spec: an upload cannot choose where it is stored

The client sends a file name. That name must have no effect on where the file
is written, and every path the server writes to must have one fixed shape.
-/

namespace UploadSpec

/-- Changing the file name the client sends never changes the destination. -/
def IgnoresClientName : Prop :=
  ∀ (id nameA nameB : String), Upload.destination id nameA = Upload.destination id nameB

/-- Every destination the server accepts is `uploads/<id>/UserSpec.lean`, where
`id` is 32 lowercase hexadecimal digits. Such an id holds no `/` and no `.`,
so the path has exactly three parts and cannot climb out of `uploads/`. -/
def FixedShape : Prop :=
  ∀ (id name path : String), Upload.destination id name = some path →
    path = "uploads/" ++ id ++ "/" ++ "UserSpec.lean" ∧
    id.toList.length = 32 ∧
    ∀ c ∈ id.toList, c ≠ '/' ∧ c ≠ '.' ∧ (('0' ≤ c ∧ c ≤ '9') ∨ ('a' ≤ c ∧ c ≤ 'f'))

end UploadSpec

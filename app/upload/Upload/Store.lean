/-!
# Upload storage decisions

The upload gate uses these two functions on the real upload path. The proofs
in `Specs/UploadSpec` are about these exact functions.
-/

namespace Upload

/-- A lowercase hexadecimal digit: `0`-`9` or `a`-`f`. -/
def isHexDigit (c : Char) : Bool := ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- A server-made upload id: exactly 32 lowercase hexadecimal digits. -/
def validId (id : String) : Bool := id.toList.length == 32 && id.toList.all isHexDigit

/-- The one file name every upload is stored under. -/
def storedName : String := "UserSpec.lean"

/-- Where an upload is stored: `uploads/<id>/UserSpec.lean`. The file name the
client sent is ignored on purpose, so it cannot choose the path. -/
def destination (id : String) (_clientName : String) : Option String :=
  if validId id then some ("uploads/" ++ id ++ "/" ++ storedName) else none

/-- What to do with the next chunk of an upload, given the bytes already
accepted: keep it and return the new total, or reject the whole upload. -/
def admit (limit used size : Nat) : Option Nat :=
  if used + size ≤ limit then some (used + size) else none

/-- Feed an upload's chunk sizes through `admit`, as the gate does. Returns the
chunks it lets the gate write, and whether the whole upload was accepted. -/
def gate (limit : Nat) : List Nat → Nat → List Nat × Bool
  | [], _ => ([], true)
  | c :: cs, used =>
    match admit limit used c with
    | some used' => let r := gate limit cs used'; (c :: r.1, r.2)
    | none => ([], false)

end Upload

import Upload.Store

/-!
# The upload gate (trusted adapter around proved decisions)

`upload-gate LIMIT CLIENT_NAME` reads one upload from stdin and stores it under
the current directory. It makes a random id, asks `Upload.destination` where to
store the file (the client name is passed in and ignored), and asks
`Upload.admit` about every chunk before writing it. A rejected upload is
deleted. Prints one JSON line.

Not proved here: the file system calls, and that this loop matches
`Upload.gate`. It reads at most 64 KiB per chunk and writes a chunk only after
`admit` returns `some`.
-/

open Upload

def hexOf (bytes : ByteArray) : String :=
  let digit (n : Nat) : Char := "0123456789abcdef".toList.getD n '0'
  String.ofList (bytes.toList.flatMap fun b => [digit (b.toNat / 16), digit (b.toNat % 16)])

partial def pump (input : IO.FS.Stream) (out : IO.FS.Handle) (limit used : Nat) : IO Bool := do
  let chunk ← input.read 65536
  if chunk.isEmpty then return true
  match admit limit used chunk.size with
  | some used' => out.write chunk; pump input out limit used'
  | none => return false

def reply (ok : Bool) (field value : String) : IO UInt32 := do
  IO.println s!"\{\"ok\": {ok}, \"{field}\": \"{value}\"}"
  return if ok then 0 else 1

def main (args : List String) : IO UInt32 := do
  let [limitText, clientName] := args | reply false "error" "usage: upload-gate LIMIT CLIENT_NAME"
  let some limit := limitText.toNat? | reply false "error" "bad limit"
  let id := hexOf (← IO.getRandomBytes 16)
  let some path := destination id clientName | reply false "error" "bad id"
  IO.FS.createDirAll "uploads"
  -- Creating the directory fails if the id is already taken.
  try IO.FS.createDir s!"uploads/{id}" catch _ => return ← reply false "error" "id collision"
  -- `writeNew` refuses to open a file that already exists.
  let out ← IO.FS.Handle.mk path .writeNew
  let ok ← pump (← IO.getStdin) out limit 0
  out.flush
  if ok then reply true "id" id
  else
    IO.FS.removeFile path
    IO.FS.removeDir s!"uploads/{id}"
    reply false "error" s!"upload is larger than {limit} bytes"

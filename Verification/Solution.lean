import Maze
import UploadSpec.Proofs

/-! Proofs of the statements in `Verification/Challenge.lean`. -/

theorem maze_regions_sound (v : Maze.Variant) (R : List Nat)
    (h : Maze.checkRegions v R = true) : Maze.Unwinnable v :=
  Maze.unwinnable_of_checkRegions h

theorem maze_isOpen_iff (v : Maze.Variant) (c : Nat) :
    v.isOpen c = true ↔ c < v.cells ∧ c ∉ v.walls :=
  Maze.isOpen_iff v c

theorem upload_ignores_client_name : UploadSpec.IgnoresClientName :=
  UploadSpec.ignoresClientName

theorem upload_fixed_shape : UploadSpec.FixedShape := UploadSpec.fixedShape

theorem upload_never_over_limit : UploadSpec.NeverOverLimit := UploadSpec.neverOverLimit

theorem upload_accepted_iff_within_limit : UploadSpec.AcceptedIffWithinLimit :=
  UploadSpec.acceptedIffWithinLimit

theorem upload_accepted_writes_everything : UploadSpec.AcceptedWritesEverything :=
  UploadSpec.acceptedWritesEverything

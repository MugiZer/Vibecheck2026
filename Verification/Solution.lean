import Maze
import UploadSpec.Proofs
import DecorSpec.Proofs

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

theorem decor_only_allowed_classes : DecorSpec.OnlyAllowedClasses := DecorSpec.onlyAllowedClasses

theorem decor_no_bad_classes : DecorSpec.NoBadClasses := DecorSpec.noBadClasses

theorem decor_top_is_model : DecorSpec.TopIsModel := DecorSpec.topIsModel

theorem decor_parts_are_inert : DecorSpec.PartsAreInert := DecorSpec.partsAreInert

theorem decor_parts_stay_in_box : DecorSpec.PartsStayInBox := DecorSpec.partsStayInBox

theorem decor_humanoids_show_nothing : DecorSpec.HumanoidsShowNothing := DecorSpec.humanoidsShowNothing

theorem decor_within_limits : DecorSpec.WithinLimits := DecorSpec.withinLimits

theorem decor_ignores_names : DecorSpec.IgnoresNames := DecorSpec.ignoresNames

theorem decor_accepts_safe_decor : DecorSpec.AcceptsSafeDecor := DecorSpec.acceptsSafeDecor

theorem decor_smaller_stays_accepted : DecorSpec.SmallerStaysAccepted := DecorSpec.smallerStaysAccepted

theorem decor_id_is_digits_only : DecorSpec.IdIsDigitsOnly := DecorSpec.idIsDigitsOnly

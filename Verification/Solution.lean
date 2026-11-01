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

/-- Maze: Show why paints one list of cells for each turn of the guards' cycle.
If those lists pass `checkRegions`, then after any list of moves, while the game
is still on, the player stands on a cell of the list for the current turn. -/
theorem maze_never_leaves_regions (v : Maze.Variant) (cells : List (List Nat))
    (h : Maze.checkRegions v (cells.map Maze.maskOfList) = true)
    (moves : List Maze.Move) (hplay : (Maze.run v moves).status = .playing) :
    (Maze.run v moves).pos ∈ cells.getD (Maze.run v moves).turn [] := by
  have hstart : Maze.Inside v (cells.map Maze.maskOfList) (Maze.start v) := by
    have h' := h
    simp only [Maze.checkRegions, Bool.and_eq_true, decide_eq_true_eq] at h'
    obtain ⟨⟨⟨hcyc, hlt⟩, hbit⟩, -⟩ := h'
    exact ⟨by simp [Maze.start], fun _ => ⟨hlt, hcyc, hbit⟩⟩
  have hin := (Maze.inside_foldl h moves _ hstart).2 hplay
  have key : ∀ t, (cells.map Maze.maskOfList).getD t 0 = Maze.maskOfList (cells.getD t []) := by
    intro t
    simp only [List.getD_eq_getElem?_getD, List.getElem?_map]
    cases cells[t]? <;> rfl
  have hbit := hin.2.2
  rw [key, Maze.testBit_maskOfList] at hbit
  exact hbit

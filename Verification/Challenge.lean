import Maze
import MazeRuntime.Replay
import UploadSpec.Destination
import UploadSpec.Limit
import DecorSpec.Safe

/-!
# The repository's main theorems (trusted statements)

`lake comparator --config Verification/comparator.json` checks that
`Verification/Solution.lean` proves exactly these statements with only the
standard axioms. Each published level has its own challenge as well, written by
the coordinator.
-/

/-- Maze: a region certificate that passes `checkRegions` proves the level
cannot be won, for every level and every certificate. -/
theorem maze_regions_sound (v : Maze.Variant) (R : List Nat)
    (h : Maze.checkRegions v R = true) : Maze.Unwinnable v := sorry

/-- Maze: the fast bit test for open cells means "on the board and not a wall". -/
theorem maze_isOpen_iff (v : Maze.Variant) (c : Nat) :
    v.isOpen c = true ↔ c < v.cells ∧ c ∉ v.walls := sorry

/-- Upload: the client's file name never changes where an upload is stored. -/
theorem upload_ignores_client_name : UploadSpec.IgnoresClientName := sorry

/-- Upload: every stored path is `uploads/<32 hex digits>/UserSpec.lean`. -/
theorem upload_fixed_shape : UploadSpec.FixedShape := sorry

/-- Upload: the bytes the gate writes never add up to more than the limit. -/
theorem upload_never_over_limit : UploadSpec.NeverOverLimit := sorry

/-- Upload: an upload is accepted exactly when it fits in the limit. -/
theorem upload_accepted_iff_within_limit : UploadSpec.AcceptedIffWithinLimit := sorry

/-- Upload: an accepted upload is written in full. -/
theorem upload_accepted_writes_everything : UploadSpec.AcceptedWritesEverything := sorry

/-- Decor: In an accepted model, every instance at every level has a class from the allowlist. -/
theorem decor_only_allowed_classes : DecorSpec.OnlyAllowedClasses := sorry

/-- Decor: An accepted model holds none of 59 classes from the threat list: no script, explosion, seat, spawn, prompt, text, sound, light, effect or special mesh. -/
theorem decor_no_bad_classes : DecorSpec.NoBadClasses := sorry

/-- Decor: The top instance of an accepted model is a Model. -/
theorem decor_top_is_model : DecorSpec.TopIsModel := sorry

/-- Decor: Every part in an accepted model is anchored, with collisions, touch events and queries off. -/
theorem decor_parts_are_inert : DecorSpec.PartsAreInert := sorry

/-- Decor: Every part in an accepted model is inside the slot box. -/
theorem decor_parts_stay_in_box : DecorSpec.PartsStayInBox := sorry

/-- Decor: Every Humanoid in an accepted model shows no name and no health bar. -/
theorem decor_humanoids_show_nothing : DecorSpec.HumanoidsShowNothing := sorry

/-- Decor: An accepted model has at most 500 instances and at most 8 levels. -/
theorem decor_within_limits : DecorSpec.WithinLimits := sorry

/-- Decor: Two models that differ only in names get the same answer. -/
theorem decor_ignores_names : DecorSpec.IgnoresNames := sorry

/-- Decor: Every model that meets the rules is accepted, so the gate is not "always no". -/
theorem decor_accepts_safe_decor : DecorSpec.AcceptsSafeDecor := sorry

/-- Decor: Deleting instances from an accepted model keeps it accepted. `Clone()` deletes instances that are not `Archivable`. -/
theorem decor_smaller_stays_accepted : DecorSpec.SmallerStaysAccepted := sorry

/-- Decor: An accepted asset id has 1 to 19 characters, all digits 0–9. So it has no quote, bracket or line break. -/
theorem decor_id_is_digits_only : DecorSpec.IdIsDigitsOnly := sorry

/-- Maze: Show why paints one list of cells for each turn of the guards' cycle.
If those lists pass `checkRegions`, then after any list of moves, while the game
is still on, the player stands on a cell of the list for the current turn. -/
theorem maze_never_leaves_regions (v : Maze.Variant) (cells : List (List Nat))
    (h : Maze.checkRegions v (cells.map Maze.maskOfList) = true)
    (moves : List Maze.Move) (hplay : (Maze.run v moves).status = .playing) :
    (Maze.run v moves).pos ∈ cells.getD (Maze.run v moves).turn [] := sorry

/-- Maze: when the game process replays a list of move names, it accepts the
list exactly when every name is a move, and then it returns the state that
`Maze.run` gives for those moves, in that order. A list with any other name is
refused. -/
theorem maze_runtime_replays_with_run (v : Maze.Variant) (names : List String) (s : Maze.State) :
    MazeRuntime.replayMoves v names = .ok s ↔
      ∃ moves : List Maze.Move,
        names.map MazeRuntime.Move.ofString? = moves.map some ∧ s = Maze.run v moves := sorry

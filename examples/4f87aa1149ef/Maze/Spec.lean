import Maze.Game

/-!
# What a maze level must satisfy

These are the predicates the judge checks for every published maze level.
Each one is stated with the rules in `Maze.Game`, the same functions the game
runs.
-/

namespace Maze

/-- Some list of moves wins the level. -/
def Winnable (v : Variant) : Prop :=
  ∃ moves : List Move, (run v moves).status = .escaped

/-- No list of moves, of any length, wins the level. -/
def Unwinnable (v : Variant) : Prop := ¬ Winnable v

/-- The same level with every guard taken away. -/
def withoutGuards (v : Variant) : Variant := { v with guards := [] }

/-- Two cells are the same cell or side by side. -/
def nextToOrSame (v : Variant) (a b : Nat) : Bool :=
  Move.all.any fun m => neighbor v a m == some b

/-- The level can be built and played: the board is a sensible size, every
named cell is open, gems are distinct, and guards walk (one step at a time)
instead of jumping. -/
def WellFormed (v : Variant) : Prop :=
  3 ≤ v.width ∧ v.width ≤ 16 ∧ 3 ≤ v.height ∧ v.height ≤ 16 ∧
  (∀ w ∈ v.walls, w < v.cells) ∧
  v.isOpen v.start ∧ v.isOpen v.exit ∧ v.start ≠ v.exit ∧
  v.gems.length ≤ 4 ∧ v.gems.Nodup ∧ (∀ g ∈ v.gems, v.isOpen g) ∧ v.start ∉ v.gems ∧
  v.guards.length ≤ 4 ∧ v.cycle ≤ 24 ∧
  (∀ route ∈ v.guards, route ≠ [] ∧ route.length ≤ 12 ∧ (∀ c ∈ route, v.isOpen c) ∧
    (∀ i < route.length,
      nextToOrSame v (route.getD i 0) (route.getD ((i + 1) % route.length) 0)) ∧
    guardAt route 0 ≠ v.start)

/-- The smallest amount of play every level must offer: with the guards taken
away the level could be won, and the player has a first move that goes to a new
cell without being caught. A playable level can still be impossible to win. -/
def Playable (v : Variant) : Prop :=
  Winnable (withoutGuards v) ∧
  ∃ m : Move, (step v (start v) m).status = .playing ∧ (step v (start v) m).pos ≠ v.start

instance (v : Variant) : Decidable (WellFormed v) := by unfold WellFormed; infer_instance

end Maze

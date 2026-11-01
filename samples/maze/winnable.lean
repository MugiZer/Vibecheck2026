import Maze.Spec

/-! Sample requirement: a fair level. Some list of moves wins, and there are
at least two gems and two guards. -/

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Winnable v ∧ 2 ≤ v.gems.length ∧ 2 ≤ v.guards.length

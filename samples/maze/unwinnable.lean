import Maze.Spec

/-! Sample requirement: a level nobody can win, guarded by at least two guards.
`Maze.Playable` is always checked too, so the level still looks winnable: with
the guards removed there is a route that collects every gem and reaches the
exit. -/

def UserSpec.requirement (v : Maze.Variant) : Prop :=
  Maze.Unwinnable v ∧ 2 ≤ v.guards.length

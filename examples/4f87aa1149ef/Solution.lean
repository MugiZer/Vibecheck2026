import Maze
import Candidate
import UserSpec

theorem accepted :
    Maze.WellFormed Candidate.variant ∧ Maze.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, ⟨⟨[.down, .down, .down, .down, .right, .right, .right, .right, .right, .right, .up, .up, .down, .down, .left, .left, .down, .down, .left, .left, .left, .left], by decide +kernel⟩, ⟨.down, by decide +kernel⟩⟩,
    ⟨Maze.unwinnable_of_checkRegions (R := [9047282215251968, 18527848949962731520, 225220064329035776, 18960194514190299136, 1089911192784171008, 18960194514190299136, 225220064329035776, 18527848949962731520]) (by decide +kernel), by decide⟩⟩

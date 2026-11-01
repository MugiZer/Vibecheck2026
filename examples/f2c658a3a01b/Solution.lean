import Maze
import Candidate
import UserSpec

theorem accepted :
    Maze.WellFormed Candidate.variant ∧ Maze.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, ⟨⟨[.down, .down, .down, .down, .up, .up, .right, .right, .right, .right, .up, .up, .right, .right, .down, .down, .down, .down], by decide +kernel⟩, ⟨.down, by decide +kernel⟩⟩,
    ⟨⟨[.up, .up, .up, .down, .down, .down, .down, .right, .right, .up, .up, .right, .right, .up, .up, .right, .right, .down, .down, .down, .down], by decide +kernel⟩, by decide, by decide⟩⟩

import Maze
import Candidate
import UserSpec

theorem accepted :
    Maze.WellFormed Candidate.variant ∧ Maze.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, ⟨⟨[.down, .down, .down, .down, .right, .right, .up, .up, .down, .down, .right, .right, .right, .right, .right, .right, .up, .up, .right, .right, .up, .up, .down, .down, .down, .down, .left, .left, .down, .down, .left], by decide +kernel⟩, ⟨.down, by decide +kernel⟩⟩,
    ⟨Maze.unwinnable_of_checkRegions (R := [150758368920512839008256, 164564374688604901246222336, 149872925204974780530688, 154891197244256791731617792, 146331150342822546620416, 164555520251449520661446656, 132164050894213610979328, 9813015340776986299056128, 146331150342822546620416, 164562603801173825129267200, 149872925204974780530688, 154892968131687867848572928]) (by decide +kernel), by decide⟩⟩

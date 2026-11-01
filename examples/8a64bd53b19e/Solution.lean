import Sling
import Candidate
import UserSpec

theorem accepted :
    Sling.WellFormed Candidate.variant ∧ Sling.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, by decide +kernel,
    ⟨by decide +kernel, by decide, by decide⟩⟩

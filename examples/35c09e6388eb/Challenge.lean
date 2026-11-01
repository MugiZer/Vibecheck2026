import Sling
import Candidate
import UserSpec

/-- The claim the judge checks: this exact level is well formed, playable, and
meets the uploaded requirement. Written by the coordinator, never by the agent. -/
theorem accepted :
    Sling.WellFormed Candidate.variant ∧ Sling.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant := sorry

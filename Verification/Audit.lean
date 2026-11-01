import Verification.Solution
import Verification.SpecSurface

/-! `make verify` prints, for each main theorem, the axioms it uses and the
project definitions its statement depends on (the trusted surface to review). -/

#audit_axioms maze_regions_sound
#audit_axioms maze_isOpen_iff
#audit_axioms upload_ignores_client_name
#audit_axioms upload_fixed_shape
#audit_axioms upload_never_over_limit
#audit_axioms upload_accepted_iff_within_limit
#audit_axioms upload_accepted_writes_everything

#spec_surface maze_regions_sound
#spec_surface upload_fixed_shape
#spec_surface upload_never_over_limit
#spec_surface upload_accepted_iff_within_limit

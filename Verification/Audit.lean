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
#audit_axioms decor_only_allowed_classes
#audit_axioms decor_no_bad_classes
#audit_axioms decor_top_is_model
#audit_axioms decor_parts_are_inert
#audit_axioms decor_parts_stay_in_box
#audit_axioms decor_humanoids_show_nothing
#audit_axioms decor_within_limits
#audit_axioms decor_ignores_names
#audit_axioms decor_accepts_safe_decor
#audit_axioms decor_smaller_stays_accepted
#audit_axioms decor_id_is_digits_only

#spec_surface maze_regions_sound
#spec_surface upload_fixed_shape
#spec_surface upload_never_over_limit
#spec_surface upload_accepted_iff_within_limit
#spec_surface decor_only_allowed_classes
#spec_surface decor_parts_stay_in_box
#spec_surface decor_id_is_digits_only

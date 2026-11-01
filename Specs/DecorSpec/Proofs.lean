import DecorSpec.Safe

/-! Proofs of the decor specs, accepted examples that meet every hypothesis,
and rejected examples of bad models. -/

namespace DecorSpec
open Decor

/-! ## The gate's lists are the spec's lists

If someone edits a list in the gate, these stop building. -/

theorem allowedClasses_eq : allowedClasses = okClasses := rfl
theorem partClasses_eq : partClasses = solidClasses := rfl

theorem ok_not_bad : ∀ c ∈ okClasses, c ∉ badClasses := by decide

section
variable {lim : Limits}

/-! ## One instance: `nodeOk` is `SafeNode` -/

theorem nodeOk_iff (n : Node) : nodeOk lim n = true ↔ SafeNode lim n := by
  simp only [nodeOk, partOk, fits, SafeNode, InBox, allowedClasses_eq,
    partClasses_eq, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', ← Bool.not_eq_true,
    List.contains_iff_mem, bne_iff_ne, beq_iff_eq, ne_eq, decide_eq_true_eq,
    Decidable.imp_iff_not_or, and_assoc]
  -- `width` (gate) and `widthAlong` (spec) are the same sum.
  exact Iff.rfl

/-! ## Accepted means safe -/

theorem nodeAt_one {t : Inst} {n : Node} (h : NodeAt t 1 n) : n = t.node := by
  cases h with
  | top => rfl
  | inChild _ _ _ _ _ _ hm => cases hm

theorem allOkAll_mem {cs : List Inst} {c : Inst} (h : allOkAll lim cs = true) (hc : c ∈ cs) :
    allOk lim c = true := by
  induction cs with
  | nil => cases hc
  | cons c' cs ih =>
    simp only [allOkAll, Bool.and_eq_true] at h
    rcases List.mem_cons.mp hc with rfl | hc
    · exact h.1
    · exact ih h.2 hc

theorem nodeOk_of_allOk {t : Inst} {d : Nat} {n : Node} (hn : NodeAt t d n) :
    allOk lim t = true → nodeOk lim n = true := by
  induction hn with
  | top n cs => intro h; simp only [allOk, Bool.and_eq_true] at h; exact h.1
  | inChild n cs c d m hc _ ih =>
    intro h; simp only [allOk, Bool.and_eq_true] at h; exact ih (allOkAll_mem h.2 hc)

theorem depthAll_mem {cs : List Inst} {c : Inst} (hc : c ∈ cs) : depth c ≤ depthAll cs := by
  induction cs with
  | nil => cases hc
  | cons c' cs ih =>
    simp only [depthAll]
    rcases List.mem_cons.mp hc with rfl | hc
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih hc) (Nat.le_max_right _ _)

theorem le_depth {t : Inst} {d : Nat} {n : Node} (hn : NodeAt t d n) : d ≤ depth t := by
  induction hn with
  | top n cs => simp only [depth]; omega
  | inChild n cs c d m hc _ ih => have := depthAll_mem hc; simp only [depth]; omega

theorem safe_of_accept {t : Inst} (h : accept lim t = true) : SafeDecor lim t := by
  simp only [accept, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  obtain ⟨⟨⟨hm, hc⟩, hd⟩, ho⟩ := h
  exact ⟨fun n hn => nodeAt_one hn ▸ hm, hc,
    fun n d hn => ⟨Nat.le_trans (le_depth hn) hd, (nodeOk_iff n).mp (nodeOk_of_allOk hn ho)⟩⟩

/-! ## Safe means accepted -/

mutual
theorem allOk_of_forall : ∀ (t : Inst),
    (∀ n d, NodeAt t d n → nodeOk lim n = true) → allOk lim t = true
  | .mk n cs, h => by
    simp only [allOk, Bool.and_eq_true]
    exact ⟨h n 1 (.top n cs),
      allOkAll_of_forall cs fun c hc m d hm => h m (d + 1) (.inChild n cs c d m hc hm)⟩

theorem allOkAll_of_forall : ∀ (cs : List Inst),
    (∀ c ∈ cs, ∀ m d, NodeAt c d m → nodeOk lim m = true) → allOkAll lim cs = true
  | [], _ => rfl
  | c :: cs, h => by
    simp only [allOkAll, Bool.and_eq_true]
    exact ⟨allOk_of_forall c (h c (by simp)),
      allOkAll_of_forall cs fun c' hc' => h c' (by simp [hc'])⟩
end

mutual
theorem depth_le_of_forall : ∀ (t : Inst) (k : Nat),
    (∀ n d, NodeAt t d n → d ≤ k) → depth t ≤ k
  | .mk n cs, k, h => by
    have h1 := h n 1 (.top n cs)
    have h2 := depthAll_le_of_forall cs (k - 1) fun c hc m d hm => by
      have := h m (d + 1) (.inChild n cs c d m hc hm); omega
    simp only [depth]; omega

theorem depthAll_le_of_forall : ∀ (cs : List Inst) (k : Nat),
    (∀ c ∈ cs, ∀ m d, NodeAt c d m → d ≤ k) → depthAll cs ≤ k
  | [], _, _ => Nat.zero_le _
  | c :: cs, k, h => by
    simp only [depthAll]
    exact Nat.max_le.mpr ⟨depth_le_of_forall c k (h c (by simp)),
      depthAll_le_of_forall cs k fun c' hc' => h c' (by simp [hc'])⟩
end

theorem accept_of_safe {t : Inst} (h : SafeDecor lim t) : accept lim t = true := by
  obtain ⟨hm, hc, hs⟩ := h
  simp only [accept, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq]
  refine ⟨⟨⟨hm _ (by cases t; exact .top _ _), hc⟩,
    depth_le_of_forall t _ fun n d hn => (hs n d hn).1⟩,
    allOk_of_forall t fun n d hn => (nodeOk_iff n).mpr (hs n d hn).2⟩

/-! ## Names do not count -/

mutual
theorem count_eraseNames : ∀ t, count (eraseNames t) = count t
  | .mk _ cs => by simp only [eraseNames, count, countAll_eraseNames cs]

theorem countAll_eraseNames : ∀ cs, countAll (eraseNamesAll cs) = countAll cs
  | [] => rfl
  | c :: cs => by simp only [eraseNamesAll, countAll, count_eraseNames c, countAll_eraseNames cs]
end

mutual
theorem depth_eraseNames : ∀ t, depth (eraseNames t) = depth t
  | .mk _ cs => by simp only [eraseNames, depth, depthAll_eraseNames cs]

theorem depthAll_eraseNames : ∀ cs, depthAll (eraseNamesAll cs) = depthAll cs
  | [] => rfl
  | c :: cs => by simp only [eraseNamesAll, depthAll, depth_eraseNames c, depthAll_eraseNames cs]
end

mutual
theorem allOk_eraseNames : ∀ t, allOk lim (eraseNames t) = allOk lim t
  | .mk n cs => by
    simp only [eraseNames, allOk, allOkAll_eraseNames cs]
    rfl

theorem allOkAll_eraseNames : ∀ cs, allOkAll lim (eraseNamesAll cs) = allOkAll lim cs
  | [] => rfl
  | c :: cs => by
    simp only [eraseNamesAll, allOkAll, allOk_eraseNames c, allOkAll_eraseNames cs]
end

theorem accept_eraseNames (t : Inst) : accept lim (eraseNames t) = accept lim t := by
  have hm : (eraseNames t).node.cls = t.node.cls := by cases t; rfl
  simp only [accept, hm, count_eraseNames, depth_eraseNames, allOk_eraseNames]

end

/-! ## The specs -/

theorem onlyAllowedClasses : OnlyAllowedClasses := fun _ _ d n h hn =>
  ((safe_of_accept h).2.2 n d hn).2.1

theorem noBadClasses : NoBadClasses := fun lim t d n h hn =>
  ok_not_bad n.cls (onlyAllowedClasses lim t d n h hn)

theorem topIsModel : TopIsModel := fun _ _ n h hn => (safe_of_accept h).1 n hn

theorem partsAreInert : PartsAreInert := fun _ _ d n h hn hp => by
  obtain ⟨a, b, c, e, _⟩ := ((safe_of_accept h).2.2 n d hn).2.2.1 hp
  exact ⟨a, b, c, e⟩

theorem partsStayInBox : PartsStayInBox := fun _ _ d n h hn hp =>
  (((safe_of_accept h).2.2 n d hn).2.2.1 hp).2.2.2.2

theorem humanoidsShowNothing : HumanoidsShowNothing := fun _ _ d n h hn hh =>
  ((safe_of_accept h).2.2 n d hn).2.2.2 hh

theorem withinLimits : WithinLimits := fun _ _ h =>
  ⟨(safe_of_accept h).2.1, fun d n hn => ((safe_of_accept h).2.2 n d hn).1⟩

theorem ignoresNames : IgnoresNames := fun lim a b h => by
  rw [← accept_eraseNames (lim := lim) a, h, accept_eraseNames]

theorem acceptsSafeDecor : AcceptsSafeDecor := fun _ _ h => accept_of_safe h

theorem smallerStaysAccepted : SmallerStaysAccepted := fun _ _ _ h hc hsub =>
  have hs := safe_of_accept h
  accept_of_safe ⟨fun n hn => hs.1 n (hsub 1 n hn), Nat.le_trans hc hs.2.1,
    fun n d hn => hs.2.2 n d (hsub d n hn)⟩

theorem idIsDigitsOnly : IdIsDigitsOnly := by
  intro id h
  simp only [validAssetId, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨h1, h2, fun c hc => ?_⟩
  have hd := h3 c hc
  refine ⟨hd.1, hd.2, ?_, ?_, ?_, ?_⟩ <;> rintro rfl <;> exact absurd hd (by decide)

/-! ## Examples -/

/-- Not turned: each side points along its own axis. -/
def straightX : Xyz := ⟨1000, 0, 0⟩
def straightY : Xyz := ⟨0, 1000, 0⟩
def straightZ : Xyz := ⟨0, 0, 1000⟩

/-- A part with the safe values the place sets, not turned. -/
def safePart (cls name : String) (size off : Xyz) : Node :=
  { name, cls, anchored := true, canCollide := false, canTouch := false, canQuery := false,
    size, off, alongX := straightX, alongY := straightY, alongZ := straightZ,
    displayDistance := "", healthDisplay := "" }

/-- An instance that is not a part. Its part fields are not read. -/
def plain (cls name : String) : Node :=
  { name, cls, anchored := false, canCollide := false, canTouch := false, canQuery := false,
    size := ⟨0, 0, 0⟩, off := ⟨0, 0, 0⟩, alongX := ⟨0, 0, 0⟩, alongY := ⟨0, 0, 0⟩,
    alongZ := ⟨0, 0, 0⟩, displayDistance := "", healthDisplay := "" }

/-- A Model that holds a safe base part and one more child. -/
def modelWith (child : Inst) : Inst :=
  .mk (plain "Model" "Thing") [.mk (safePart "Part" "Base" ⟨20, 2, 20⟩ ⟨0, 0, 0⟩) [], child]

/-- The shelf of the bookshelf below: 3.5 by 5.5 by 1.2 studs. -/
def shelf : Node := safePart "MeshPart" "Shelf" ⟨35, 55, 12⟩ ⟨0, 0, 0⟩

/-- A bookshelf: Model > MeshPart, and Part > Decal. -/
def bookshelf : Inst :=
  .mk (plain "Model" "Bookshelf")
    [.mk shelf [],
     .mk (safePart "Part" "Books" ⟨30, 10, 8⟩ ⟨0, 15, 0⟩) [.mk (plain "Decal" "Spines") []]]

example : accept propLimits bookshelf = true := by decide
/-- Every hypothesis of (e) holds for a real model. -/
example : SafeDecor propLimits bookshelf := safe_of_accept (by decide)

/-- `k` nested Models around a tree. -/
def nested : Nat → Inst → Inst
  | 0, t => t
  | k + 1, t => .mk (plain "Model" "Box") [nested k t]

/-- The bookshelf inside two more Models: Room > Corner > Bookshelf > Shelf. -/
def corner : Inst := .mk (plain "Model" "Corner") [bookshelf]
def room : Inst := .mk (plain "Model" "Room") [corner]

/-- (b) on a part 4 levels down: every hypothesis holds, so the shelf is anchored. -/
example : shelf.anchored = true :=
  (partsAreInert propLimits room 4 shelf (by decide)
    (.inChild _ _ corner 3 shelf (by simp) (.inChild _ _ bookshelf 2 shelf (by simp)
      (.inChild _ _ (.mk shelf []) 1 shelf (by simp) (.top _ _))))
    (by decide)).1

/-- A board 0.4 by 6 by 4 studs fits the prop box standing up. Turned a quarter
turn, so that its 6-stud side points along x, it is wider than the 4-stud box. -/
def board : Node := safePart "Part" "Board" ⟨4, 60, 40⟩ ⟨0, 0, 0⟩
example : accept propLimits (modelWith (.mk board [])) = true := by decide
example : accept propLimits
    (modelWith (.mk { board with alongX := ⟨0, 1000, 0⟩, alongY := ⟨1000, 0, 0⟩ } [])) = false := by
  decide

/-- A part whose center is 3 studs from the pivot sticks out of the prop box. -/
example : accept propLimits (modelWith (.mk (safePart "Part" "Far" ⟨10, 10, 10⟩ ⟨30, 0, 0⟩) [])) =
    false := by decide

/-- An NPC look: a Humanoid with its display off is accepted; with its name or
its health bar shown, rejected. -/
def npc (displayDistance healthDisplay : String) : Inst :=
  .mk (plain "Model" "Guard")
    [.mk (safePart "Part" "Head" ⟨20, 10, 10⟩ ⟨0, 30, 0⟩) [],
     .mk { plain "Humanoid" "Humanoid" with displayDistance, healthDisplay } []]

example : accept npcLimits (npc "None" "AlwaysOff") = true := by decide
example : accept npcLimits (npc "Viewer" "AlwaysOff") = false := by decide
example : accept npcLimits (npc "None" "DisplayWhenDamaged") = false := by decide

/-- (d) A Weld named "Script" and a Weld named "Handle" get the same answer: yes. -/
example : accept propLimits (modelWith (.mk (plain "Weld" "Script") [])) =
    accept propLimits (modelWith (.mk (plain "Weld" "Handle") [])) :=
  ignoresNames _ _ _ rfl
example : accept propLimits (modelWith (.mk (plain "Weld" "Script") [])) = true := by decide

/-- A ModuleScript 6 levels deep. The depth is within the limit, so the class
is what rejects it. -/
def deepModuleScript : Inst := nested 5 (.mk (plain "ModuleScript" "Config") [])

example : depth deepModuleScript = 6 := by decide
example : accept propLimits deepModuleScript = false := by decide
/-- The spec itself rules out this whole tree. -/
example : ¬ SafeDecor propLimits deepModuleScript := fun h =>
  absurd (accept_of_safe h) (by decide)

/-- A Script named "Handle", next to a part. -/
example : accept propLimits (modelWith (.mk (plain "Script" "Handle") [])) = false := by decide
/-- An Explosion. -/
example : accept propLimits (modelWith (.mk (plain "Explosion" "Boom") [])) = false := by decide
/-- A SpecialMesh can draw far from its part, so it is rejected. -/
example : accept propLimits (modelWith (.mk (plain "SpecialMesh" "Mesh") [])) = false := by decide
/-- A SpawnLocation and a Seat are rejected even with the safe part values. -/
example : accept propLimits
    (modelWith (.mk (safePart "SpawnLocation" "Pad" ⟨10, 2, 10⟩ ⟨0, 0, 0⟩) [])) = false := by decide
example : accept propLimits
    (modelWith (.mk (safePart "Seat" "Chair" ⟨10, 2, 10⟩ ⟨0, 0, 0⟩) [])) = false := by decide
/-- An unanchored part. -/
example : accept propLimits (modelWith
    (.mk { safePart "Part" "Loose" ⟨10, 10, 10⟩ ⟨0, 0, 0⟩ with anchored := false } [])) = false := by
  decide
/-- A part with touch events on. -/
example : accept propLimits (modelWith
    (.mk { safePart "Part" "Trap" ⟨10, 10, 10⟩ ⟨0, 0, 0⟩ with canTouch := true } [])) = false := by
  decide
/-- A BillboardGui on a part: it can show any text. -/
example : accept propLimits (modelWith (.mk (safePart "Part" "Sign" ⟨10, 10, 1⟩ ⟨0, 0, 0⟩)
    [.mk (plain "BillboardGui" "Tag") []])) = false := by decide
/-- The top instance must be a Model: a lone Humanoid, a Decal or a Folder is rejected. -/
example : accept propLimits (.mk (plain "Humanoid" "H") []) = false := by decide
example : accept propLimits (.mk (plain "Decal" "D") []) = false := by decide
example : accept propLimits (.mk (plain "Folder" "F") [.mk board []]) = false := by decide

/-- A model with 5000 instances: too big to check in the kernel, so `#guard`. -/
def pile : Inst :=
  .mk (plain "Model" "Pile")
    (List.replicate 4999 (.mk (safePart "Part" "Brick" ⟨10, 10, 10⟩ ⟨0, 0, 0⟩) []))

#guard count pile == 5000
#guard accept propLimits pile == false

/-- The spec itself rules out bad instances. -/
example : ¬ SafeNode propLimits (plain "Script" "Handle") := by unfold SafeNode InBox; decide
example : ¬ SafeNode propLimits
    { safePart "Part" "Trap" ⟨1, 1, 1⟩ ⟨0, 0, 0⟩ with canTouch := true } := by
  unfold SafeNode InBox; decide
example : ¬ SafeNode propLimits (plain "Humanoid" "Humanoid") := by unfold SafeNode InBox; decide

/-- Asset ids: digits are accepted; anything that could break out of Luau code
is rejected. -/
example : validAssetId "9333354309" = true := by decide
example : validAssetId "" = false := by decide
example : validAssetId "12345678901234567890" = false := by decide
example : validAssetId "1\") os.exit() --" = false := by decide
example : validAssetId "123]]" = false := by decide
example : validAssetId "123\n" = false := by decide

end DecorSpec

import Maze.Spec

/-!
# Checking that a level cannot be won

A certificate gives, for each turn of the guards' cycle, a set of cells: the
places a player might stand on that turn. The checker confirms by computation:

1. The player starts inside the set for turn 0.
2. From any cell in the set for turn `t`, every move either gets the player
   caught or lands inside the set for the next turn.
3. The exit is in none of the sets.

Then no list of moves reaches the exit, so no list of moves wins.
`unwinnable_of_checkRegions` proves this once, for every level and every
certificate. A failed check proves nothing: it does not mean the level can be
won.

The sets are stored as bits of a number, so the kernel moves all players in a
set with a few arithmetic operations instead of one cell at a time. Gems are
ignored, because they never change where anyone can move.
-/

namespace Maze

/-! ## Bit sets -/

/-- `allBelow n f` is true when `f i` is true for every `i < n`. -/
def allBelow : Nat → (Nat → Bool) → Bool
  | 0, _ => true
  | n + 1, f => allBelow n f && f n

theorem allBelow_spec : ∀ {n : Nat} {f : Nat → Bool}, allBelow n f = true → ∀ i < n, f i = true
  | 0, _, _, i, hi => absurd hi (Nat.not_lt_zero i)
  | n + 1, f, h, i, hi => by
    simp only [allBelow, Bool.and_eq_true] at h
    rcases Nat.lt_succ_iff_lt_or_eq.mp hi with hi | rfl
    · exact allBelow_spec h.1 i hi
    · exact h.2

/-- The bits of `a` that are not bits of `b`. -/
def andNot (a b : Nat) : Nat := a ^^^ (a &&& b)

theorem testBit_andNot (a b i : Nat) :
    (andNot a b).testBit i = (a.testBit i && !b.testBit i) := by
  simp only [andNot, Nat.testBit_xor, Nat.testBit_and]
  cases a.testBit i <;> cases b.testBit i <;> rfl

/-- Every bit of `a` is a bit of `b`. -/
def subset (a b : Nat) : Bool := a &&& b == a

theorem testBit_of_subset {a b i : Nat} (h : subset a b = true) (ha : a.testBit i = true) :
    b.testBit i = true := by
  have h' : a &&& b = a := by simpa [subset] using h
  have := congrArg (fun x => x.testBit i) h'
  simp only [Nat.testBit_and, ha, Bool.true_and] at this
  exact this

/-- A number with bit `c` set for each `c < n` where `p c` holds. -/
def maskOf : Nat → (Nat → Bool) → Nat
  | 0, _ => 0
  | n + 1, p => maskOf n p ||| (if p n then 2 ^ n else 0)

theorem testBit_maskOf (p : Nat → Bool) (c : Nat) :
    ∀ n, (maskOf n p).testBit c = (decide (c < n) && p c)
  | 0 => by simp [maskOf]
  | n + 1 => by
    rw [maskOf, Nat.testBit_or, testBit_maskOf p c n]
    by_cases hcn : c = n
    · subst hcn
      cases hp : p c <;> simp
    · have hbit : (if p n then 2 ^ n else 0).testBit c = false := by
        split <;> simp [Ne.symm hcn]
      rw [hbit, Bool.or_false]
      have : (c < n) ↔ (c < n + 1) := by omega
      simp only [this]

theorem testBit_maskOfList (c : Nat) : ∀ L : List Nat, (maskOfList L).testBit c = true ↔ c ∈ L
  | [] => by simp [maskOfList]
  | x :: xs => by
    have hcons : maskOfList (x :: xs) = 2 ^ x ||| maskOfList xs := rfl
    rw [hcons, Nat.testBit_or, Bool.or_eq_true, testBit_maskOfList c xs, Nat.testBit_two_pow]
    simp [eq_comm]

/-- `isOpen` without bits: on the board and not in the wall list. -/
theorem isOpen_iff (v : Variant) (c : Nat) : v.isOpen c = true ↔ c < v.cells ∧ c ∉ v.walls := by
  simp [Variant.isOpen, ← testBit_maskOfList]

/-! ## Moving a whole set of players at once -/

/-- The cells from which move `m` steps onto an open neighbor. -/
def canGo (v : Variant) (m : Move) : Nat :=
  maskOf v.cells fun c =>
    match neighbor v c m with
    | some d => v.isOpen d
    | none => false

/-- Shift a bit set by one cell in the direction of a move. -/
def shift (v : Variant) (Y : Nat) : Move → Nat
  | .up => Y >>> v.width
  | .down => Y <<< v.width
  | .left => Y >>> 1
  | .right => Y <<< 1
  | .stay => Y

/-- Where move `m` takes players standing on the cells of `Y`: those who can
step go to the neighbor, the others stay. -/
def image (v : Variant) (m : Move) (Y : Nat) : Nat :=
  shift v (Y &&& canGo v m) m ||| andNot Y (canGo v m)

/-- The cells where the guards stand after the step from turn `t`. -/
def guardsNext (v : Variant) (t : Nat) : Nat :=
  maskOfList (v.guards.map fun route => guardAt route (t + 1))

/-- The cells a player cannot leave by move `m` on turn `t`, because a guard
walks the other way through the player: the guard arrives on this cell from
the cell the move goes to. -/
def swapFrom (v : Variant) (t : Nat) (m : Move) : Nat :=
  maskOfList (v.guards.filterMap fun route =>
    if guardAt route t == moveTo v (guardAt route (t + 1)) m then
      some (guardAt route (t + 1))
    else none)

/-- Where players on the cells of `X` can be after move `m` on turn `t`, if
they are not caught. -/
def safeImage (v : Variant) (t : Nat) (m : Move) (X : Nat) : Nat :=
  andNot (image v m (andNot X (swapFrom v t m))) (guardsNext v t)

theorem shift_of_neighbor {v : Variant} {Y c d : Nat} {m : Move}
    (hY : Y.testBit c = true) (hn : neighbor v c m = some d) :
    (shift v Y m).testBit d = true := by
  cases m with
  | up =>
    simp only [neighbor] at hn
    split at hn
    · cases hn
    · rename_i h
      cases hn
      have hle : v.width ≤ c := by
        rcases Nat.lt_or_ge c v.width with hlt | hge
        · exact absurd (Nat.div_eq_zero_iff.mpr (Or.inr hlt)) h
        · exact hge
      simp only [shift, Nat.testBit_shiftRight]
      rwa [Nat.add_sub_cancel' hle]
  | down =>
    simp only [neighbor] at hn
    split at hn
    · cases hn
      simp [shift, Nat.testBit_shiftLeft, hY]
    · cases hn
  | left =>
    simp only [neighbor] at hn
    split at hn
    · cases hn
    · rename_i h
      cases hn
      have hle : 1 ≤ c := by
        rcases Nat.eq_zero_or_pos c with rfl | hpos
        · simp at h
        · exact hpos
      simp only [shift, Nat.testBit_shiftRight]
      rwa [Nat.add_sub_cancel' hle]
  | right =>
    simp only [neighbor] at hn
    split at hn
    · cases hn
      simp [shift, Nat.testBit_shiftLeft, hY]
    · cases hn
  | stay =>
    simp only [neighbor] at hn
    cases hn
    exact hY

theorem moveTo_lt {v : Variant} {c : Nat} (m : Move) (hc : c < v.cells) :
    moveTo v c m < v.cells := by
  unfold moveTo
  split
  · split
    · rename_i h
      simp only [Variant.isOpen, Bool.and_eq_true, decide_eq_true_eq] at h
      exact h.1
    · exact hc
  · exact hc

theorem image_moveTo {v : Variant} {Y c : Nat} (m : Move) (hc : c < v.cells)
    (hY : Y.testBit c = true) : (image v m Y).testBit (moveTo v c m) = true := by
  unfold image
  rw [Nat.testBit_or, Bool.or_eq_true]
  cases hg : (canGo v m).testBit c with
  | false =>
    right
    have hmove : moveTo v c m = c := by
      simp only [canGo, testBit_maskOf, hc, decide_true, Bool.true_and] at hg
      unfold moveTo
      split
      · rename_i d hn
        simp only [hn] at hg
        simp [hg]
      · rfl
    rw [hmove, testBit_andNot, hY, hg]
    rfl
  | true =>
    left
    have hg' := hg
    simp only [canGo, testBit_maskOf, hc, decide_true, Bool.true_and] at hg'
    split at hg'
    · rename_i d hn
      have hmove : moveTo v c m = d := by simp [moveTo, hn, hg']
      rw [hmove]
      exact shift_of_neighbor (by rw [Nat.testBit_and, hY, hg]; rfl) hn
    · cases hg'

theorem not_caught {v : Variant} {t c : Nat} {m : Move}
    (h : caughtBy v t c (moveTo v c m) = false) :
    (guardsNext v t).testBit (moveTo v c m) = false ∧ (swapFrom v t m).testBit c = false := by
  simp only [caughtBy, List.any_eq_false, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq,
    not_or, not_and] at h
  constructor
  · cases hb : (guardsNext v t).testBit (moveTo v c m) with
    | false => rfl
    | true =>
      rw [guardsNext, testBit_maskOfList, List.mem_map] at hb
      obtain ⟨r, hr, heq⟩ := hb
      exact absurd heq (h r hr).1
  · cases hb : (swapFrom v t m).testBit c with
    | false => rfl
    | true =>
      rw [swapFrom, testBit_maskOfList, List.mem_filterMap] at hb
      obtain ⟨r, hr, heq⟩ := hb
      split at heq
      · rename_i hnow
        cases heq
        simp only [beq_iff_eq] at hnow
        exact absurd rfl ((h r hr).2 hnow)
      · cases heq

theorem safeImage_moveTo {v : Variant} {t c X : Nat} {m : Move} (hc : c < v.cells)
    (hX : X.testBit c = true) (h : caughtBy v t c (moveTo v c m) = false) :
    (safeImage v t m X).testBit (moveTo v c m) = true := by
  obtain ⟨hnext, hswap⟩ := not_caught h
  unfold safeImage
  rw [testBit_andNot, hnext, Bool.not_false, Bool.and_true]
  exact image_moveTo m hc (by rw [testBit_andNot, hX, hswap]; rfl)

/-! ## The check and its proof -/

/-- The certificate check. `R` holds one bit set of cells per turn. -/
def checkRegions (v : Variant) (R : List Nat) : Bool :=
  decide (0 < v.cycle) && decide (v.start < v.cells) && (R.getD 0 0).testBit v.start &&
  allBelow v.cycle fun t =>
    !(R.getD ((t + 1) % v.cycle) 0).testBit v.exit &&
    Move.all.all fun m => subset (safeImage v t m (R.getD t 0)) (R.getD ((t + 1) % v.cycle) 0)

/-- What the certificate says about a state: it is not a win, and while the
game is on, the player is inside the set for the current turn. -/
def Inside (v : Variant) (R : List Nat) (s : State) : Prop :=
  s.status ≠ .escaped ∧
    (s.status = .playing →
      s.pos < v.cells ∧ s.turn < v.cycle ∧ (R.getD s.turn 0).testBit s.pos = true)

theorem inside_step {v : Variant} {R : List Nat} (h : checkRegions v R = true) {s : State}
    (hs : Inside v R s) (m : Move) : Inside v R (step v s m) := by
  obtain ⟨hne, hp⟩ := hs
  simp only [checkRegions, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨hcyc, -⟩, -⟩, hall⟩ := h
  by_cases hplay : s.status = .playing
  · obtain ⟨hpos, hturn, hbit⟩ := hp hplay
    have ht := allBelow_spec hall s.turn hturn
    simp only [Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true] at ht
    have hsub := ht.2 m (by cases m <;> simp [Move.all])
    have hgo : step v s m =
        if caughtBy v s.turn s.pos (moveTo v s.pos m) then
          { pos := moveTo v s.pos m, turn := (s.turn + 1) % v.cycle, gems := s.gems,
            status := .caught }
        else
          { pos := moveTo v s.pos m, turn := (s.turn + 1) % v.cycle,
            gems := collect v (moveTo v s.pos m) s.gems,
            status := if moveTo v s.pos m == v.exit &&
                collect v (moveTo v s.pos m) s.gems == v.allGems then .escaped else .playing } := by
      simp [step, hplay]
    rw [hgo]
    cases hc : caughtBy v s.turn s.pos (moveTo v s.pos m) with
    | true => exact ⟨by simp, by simp⟩
    | false =>
      have hd := testBit_of_subset hsub (safeImage_moveTo hpos hbit hc)
      simp only [Bool.false_eq_true, ite_false]
      split
      · rename_i hwin
        simp only [Bool.and_eq_true, beq_iff_eq] at hwin
        rw [hwin.1] at hd
        rw [ht.1] at hd
        cases hd
      · exact ⟨by simp, fun _ => ⟨moveTo_lt m hpos, Nat.mod_lt _ hcyc, hd⟩⟩
  · have : step v s m = s := by simp [step, hplay]
    rw [this]
    exact ⟨hne, hp⟩

theorem inside_foldl {v : Variant} {R : List Nat} (h : checkRegions v R = true) :
    ∀ (moves : List Move) (s : State), Inside v R s → Inside v R (moves.foldl (step v) s)
  | [], _, hs => hs
  | m :: ms, _, hs => inside_foldl h ms _ (inside_step h hs m)

/-- A certificate that passes the check proves the level cannot be won. -/
theorem unwinnable_of_checkRegions {v : Variant} {R : List Nat}
    (h : checkRegions v R = true) : Unwinnable v := by
  rintro ⟨moves, hwin⟩
  have hstart : Inside v R (start v) := by
    have h' := h
    simp only [checkRegions, Bool.and_eq_true, decide_eq_true_eq] at h'
    obtain ⟨⟨⟨hcyc, hlt⟩, hbit⟩, -⟩ := h'
    exact ⟨by simp [start], fun _ => ⟨hlt, hcyc, hbit⟩⟩
  exact (inside_foldl h moves _ hstart).1 hwin

end Maze

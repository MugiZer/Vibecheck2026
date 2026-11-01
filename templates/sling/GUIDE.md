# Slingshot template: guide for level designers

A side view. The player picks one of the level's allowed angles and powers and
launches a stone from the slingshot. Each tick the stone moves by its velocity,
then gravity takes 2 units per tick off its upward speed (falling speed is
capped at 48). The flight ends at the first block, the target, the ground, or
the edge of the world. Hitting the target wins. A cell is 64 units; the stone
starts at the centre of the slingshot's cell.

Launch speed is the angle's direction times the power. Directions (about
`8 * (cos, sin)`): 0° (8,0), 10° (8,1), 20° (8,3), 30° (7,4), 40° (6,5),
50° (5,6), 60° (4,7), 70° (3,8), 80° (1,8).

## Level data

- `map`: rows of equal length, **top row first**; the last row sits on the
  ground. 4 to 24 wide, 3 to 14 high. `#` block, `.` air, `S` slingshot
  (exactly one), `T` target (exactly one).
- `angles`: allowed launch angles in degrees, distinct, from 0, 10, ..., 80.
- `powers`: allowed powers, distinct, from 1 to 6.

The game offers exactly these angles and powers, and nothing else, so a proof
about every allowed shot covers every way to play.

## What is always checked

`Sling.WellFormed` (the data rules above) and `Sling.Playable`: with every
block taken away, some allowed shot would hit the target. So a rigged level
must have the target in range and let the blocks do the work.

## Design tips

- `try_level` lists the outcome of every allowed shot and which ones win.
- To make every shot miss, shelter the target: walls beside it and a roof
  over it. A narrow chimney or a small window can look like a way in that no
  allowed trajectory actually fits through. Check with `try_level`.
- For "exactly one shot wins", open a small window and adjust it (or the
  allowed powers) until `winningShotCount` is 1.

## Proof

Every sling property is decided by running the real flights in Lean's kernel:

```lean
import Sling
import Candidate
import UserSpec

theorem accepted :
    Sling.WellFormed Candidate.variant ∧ Sling.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, by decide +kernel, ⟨by decide +kernel, by decide, by decide⟩⟩
```

Give one component per conjunct of the requirement: `by decide +kernel` for
`Sling.Unwinnable`, `Sling.Winnable` and `Sling.ExactlyOneWinningShot`, and
`by decide` for simple counts. Do not use `sorry`, `native_decide`, axioms,
or change the statement.

## Theme

Presentation only, not proved: `title`, `story` (one or two sentences),
`material` (wood, stone, glass, metal), `ground` (grass, sand, snow, dirt),
`projectile` and `target` (alienBeige, alienBlue, alienGreen, alienPink,
alienYellow), `sky` (CSS hex colour).

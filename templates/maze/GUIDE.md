# Maze template: guide for level designers

A turn-based maze. Each turn the player moves one cell up, down, left or right,
or stays. Then every guard takes one step along its own loop. The player wins
by picking up every gem and then standing on the exit. The player is caught if
a guard steps onto the player's cell, or if the player and a guard walk through
each other (swap cells).

## Level data

- `map`: rows of equal length, 3 to 16 wide and high.
  `#` wall, `.` floor, `S` start (exactly one), `E` exit (exactly one), `G` gem (0 to 4).
  Put walls around the border.
- `guards`: up to 4 routes. A route is a list of `[x, y]` cells (x = column,
  y = row, both from 0 at the top left). A guard starts on the first cell and
  steps to the next cell each turn, then loops back to the first. Each step,
  including the step from the last cell back to the first, must go to a
  neighbouring open cell or stay put. A guard that walks back and forth along
  a corridor lists the cells out and back, for example
  `[[1,3],[2,3],[3,3],[2,3]]`. A guard that paces between two cells is `[[4,5],[5,5]]`.
- Route lengths decide when all guards line up again (the least common multiple).
  Keep it at most 24: use lengths like 1, 2, 3, 4, 6, 8, 12.
- No guard may start on the player's start cell.

## What is always checked

`Maze.WellFormed` (the data rules above) and `Maze.Playable`: with all guards
removed, a route collects every gem and reaches the exit, and the player has a
first move to a new cell without being caught. So an impossible level must
still look possible.

## Making a level that cannot be won

The proof tool (`Maze.unwinnable_of_checkRegions`) works when, on every turn of
the guards' cycle, the cells the player can reach never include the exit.
Reliable patterns:

- A guard pacing between two cells of a one-cell-wide gap blocks it for ever:
  the player can never slip past (stepping in when it leaves gets you caught
  when it comes back, and stepping through it is a swap).
- Make every route to the exit pass through such a gap.
- Gems alone do not make a level impossible to prove: the certificate ignores
  gems, so the exit itself must be cut off.

## Making a level that can be won

Make sure some timing slips past every guard. `try_level` returns a winning
move list when there is one.

## Proof

`try_level` returns `leanHints`. A complete `Solution.lean` looks like:

```lean
import Maze
import Candidate
import UserSpec

theorem accepted :
    Maze.WellFormed Candidate.variant ∧ Maze.Playable Candidate.variant ∧
      UserSpec.requirement Candidate.variant :=
  ⟨by decide +kernel, PLAYABLE_HINT, REQUIREMENT_PROOF⟩
```

For a requirement `Maze.Unwinnable v ∧ 2 ≤ v.guards.length`, the
requirement proof is `⟨UNWINNABLE_HINT, by decide⟩`. For
`Maze.Winnable v ∧ ...` use `⟨WINNABLE_HINT, by decide, ...⟩`. Use
`by decide` for simple counts. Do not use `sorry`, `native_decide`, axioms, or
change the statement.

## Setting

Every maze is a room in an endless, humming, yellow office: old carpet,
buzzing ceiling lights, no windows. Guards are "watchers" in the story text.
Place no gems (`G`): each maze is a room you get out of, and reaching the exit
wins (with no gems, the rules need none collected).

## Theme

`theme` is presentation only and is not proved: `title`, `story` (one or two
sentences), single emoji for `player`, `guard`, `gem`, `exit`, and CSS hex
colours `wall` and `floor`.

- The title names an ordinary office place made strange, for example
  "The Humming Annex" or "Room With No Lunch Break".
- Do not use names, level numbers, or creatures from any existing Backrooms
  story or game.
- Still give the emoji and the `wall` and `floor` colours: the web page draws
  them. Yellow and brown tones suit the office.

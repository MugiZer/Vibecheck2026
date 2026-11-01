import Maze.Game

/-! The level under test. Generated from validated data; do not edit.

```
#########
#S..#..G#
#.#.#.#.#
#.......#
#.#.#.#.#
#G..#..E#
#########
```
-/

def Candidate.variant : Maze.Variant :=
  { width := 9, height := 7,
    walls := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 17, 18, 20, 22, 24, 26, 27, 35, 36, 38, 40, 42, 44, 45, 49, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62],
    start := 10, exit := 52, gems := [16, 46],
    guards := [[28, 29, 30, 31, 32, 33, 34, 33, 32, 31, 30, 29], [14, 23, 32, 41, 50, 41, 32, 23]] }

"""Template adapters: turn what the agent or an example writes into the exact
data the Lean runtime and the judge read, plus each template's presentation
defaults and claim wording. Untrusted convenience code: the Lean side
validates the level again."""

import json
import re


def canonical(variant):
    """Normalized game data without presentation: a new title is not a new level."""
    return json.dumps(variant, sort_keys=True, separators=(",", ":"))


def _grid(rows, legend):
    if not isinstance(rows, list) or not rows or any(not isinstance(r, str) or len(r) != len(rows[0]) for r in rows):
        raise ValueError("map rows must be strings of the same length")
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch not in legend:
                raise ValueError(f"unknown map character {ch!r} at column {x}, row {y}; use {' '.join(legend)}")
    return len(rows[0]), len(rows)


def _one(cells, ch, what):
    if len(cells) != 1:
        raise ValueError(f"the map needs exactly one {ch} ({what})")
    return cells[0]


def _clean(theme, limits, defaults):
    theme = theme if isinstance(theme, dict) else {}
    out = {}
    for k, n in limits.items():
        v = str(theme.get(k, ""))[:n] if n else theme.get(k)
        if k in defaults and isinstance(defaults[k], str) and defaults[k].startswith("#") and not re.fullmatch(r"#[0-9a-fA-F]{6}", str(v)):
            v = defaults[k]
        out[k] = v or defaults.get(k, "")
    return out


# ---------- maze ----------

def maze_variant(args):
    rows, guards = args.get("map"), args.get("guards") or []
    w, h = _grid(rows, "#.SEG")
    at = lambda ch: [y * w + x for y, r in enumerate(rows) for x, c in enumerate(r) if c == ch]
    routes = []
    for k, route in enumerate(guards):
        cs = []
        for p in route:
            if not (isinstance(p, (list, tuple)) and len(p) == 2 and all(isinstance(n, int) for n in p)):
                raise ValueError(f"guard {k}: each route cell must be [x, y]")
            x, y = p
            if not (0 <= x < w and 0 <= y < h):
                raise ValueError(f"guard {k}: cell [{x}, {y}] is off the board")
            cs.append(y * w + x)
        routes.append(cs)
    return {"width": w, "height": h, "walls": at("#"), "start": _one(at("S"), "S", "start"),
            "exit": _one(at("E"), "E", "exit"), "gems": at("G"), "guards": routes}


def cells_by_turn(regions, cells):
    """Per-turn cell lists from the bit sets of a region certificate (for the
    browser, which cannot hold numbers this large exactly)."""
    if not regions:
        return None
    return [[c for c in range(cells) if r >> c & 1] for r in regions]


def maze_reveal(info, v, solution):
    regions = info.get("regions")
    return {"cellsByTurn": cells_by_turn(regions, v["width"] * v["height"]),
            "winningMoves": info.get("winningMoves"), "cycle": info.get("cycle")}


MAZE = {
    "schema": {"map": {"type": "array", "items": {"type": "string"}},
               "guards": {"type": "array", "items": {"type": "array", "items": {"type": "array", "items": {"type": "integer"}}}}},
    "variant": maze_variant,
    "theme": lambda t: _clean(t, {"title": 60, "story": 300, "player": 8, "guard": 8, "gem": 8, "exit": 8, "wall": 7, "floor": 7},
                              {"title": "Untitled level", "player": "🦊", "guard": "👹", "gem": "💎", "exit": "🚪",
                               "wall": "#3b3355", "floor": "#17142b"}),
    "claims": {
        "unwinnable": ("Proved: no sequence of moves wins this level. Also proved: it looks winnable, "
                       "because with the guards removed a route collects every gem and reaches the exit."),
        "winnable": "Proved: this level can be won. Lean replayed a winning route on the real rules.",
    },
    "scope": ("Turn-based: you move one cell or wait, then every guard takes one step along its loop. "
              "You are caught if a guard lands on you or you swap places. The proof covers every "
              "sequence of moves of any length under exactly these rules, which are the Lean "
              "functions this game runs."),
    "quality": ("Make levels worth playing: use most of the allowed board (about 9 to 15 wide and 7 to 11 "
                "high), several rooms or corridors, gems placed so the player has to travel, and guards "
                "that create tension. A rigged level should look easy at first glance."),
    "reveal": maze_reveal,
}


# ---------- slingshot ----------

def sling_variant(args):
    rows = args.get("map")
    w, h = _grid(rows, "#.ST")
    # Picture rows run top to bottom; Lean numbers rows from the ground up.
    at = lambda ch: [(h - 1 - r) * w + x for r, row in enumerate(rows) for x, c in enumerate(row) if c == ch]
    angles, powers = args.get("angles"), args.get("powers")
    if not isinstance(angles, list) or not all(isinstance(a, int) and a % 10 == 0 for a in angles):
        raise ValueError("angles must be a list of degrees in steps of 10, from 0 to 80")
    if not isinstance(powers, list) or not all(isinstance(p, int) for p in powers):
        raise ValueError("powers must be a list of whole numbers from 1 to 6")
    return {"width": w, "height": h, "blocks": sorted(at("#")), "target": _one(at("T"), "T", "target"),
            "launch": _one(at("S"), "S", "slingshot"), "angles": [a // 10 for a in angles], "powers": powers}


SLING = {
    "schema": {"map": {"type": "array", "items": {"type": "string"}},
               "angles": {"type": "array", "items": {"type": "integer"}},
               "powers": {"type": "array", "items": {"type": "integer"}}},
    "variant": sling_variant,
    "theme": lambda t: _clean(t, {"title": 60, "story": 300, "material": 10, "ground": 10, "projectile": 12,
                                  "target": 12, "sky": 7},
                              {"title": "Untitled level", "material": "wood", "ground": "grass",
                               "projectile": "alienPink", "target": "alienGreen", "sky": "#8fd3ff"}),
    "claims": {
        "unwinnable": ("Proved: none of the shots this slingshot allows hits the target. Also proved: with "
                       "the blocks taken away, some shot would hit it."),
        "winnable": "Proved: at least one of the shots this slingshot allows hits the target.",
        "exactly-one": "Proved: exactly one of the shots this slingshot allows hits the target. Find it.",
    },
    "scope": ("The slingshot offers only the angles and powers on the sliders. Each tick the stone moves "
              "by its velocity, then gravity slows its climb; it stops at the first block, the target, "
              "the ground, or the edge of the world. The proof checks every allowed shot under exactly "
              "these rules, which are the Lean functions this game runs."),
    "quality": ("Make levels worth playing: a world about 16 to 24 wide and 8 to 12 high, a structure of "
                "blocks around the target, and a control set of at least 5 angles and 4 powers so the "
                "player has real choices."),
    "reveal": lambda info, v, solution: {"flights": info.get("flights")},
}

ADAPTERS = {"maze": MAZE, "sling": SLING}


def claim(name, label):
    return ADAPTERS[name]["claims"].get(label, "Checked against your uploaded requirement, shown below.")

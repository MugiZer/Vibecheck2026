"""Template adapters: turn what the agent or an example writes into the exact
data the Lean runtime and the judge read. Untrusted convenience code: the Lean
side validates everything again."""

MAZE_LEGEND = {"#": "wall", ".": "floor", "S": "start", "E": "exit", "G": "gem"}


def maze_from_ascii(rows, guards):
    """Build the numeric maze variant from a picture and guard routes.

    rows: list of equal-length strings using # . S E G
    guards: list of routes, each a list of [x, y] cells
    """
    if not rows or any(len(r) != len(rows[0]) for r in rows):
        raise ValueError("map rows must all have the same length")
    w, h = len(rows[0]), len(rows)
    cells = {ch: [] for ch in MAZE_LEGEND}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch not in MAZE_LEGEND:
                raise ValueError(f"unknown map character {ch!r} at ({x},{y}); use # . S E G")
            cells[ch].append(y * w + x)
    if len(cells["S"]) != 1 or len(cells["E"]) != 1:
        raise ValueError("the map needs exactly one S (start) and one E (exit)")
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
    return {"width": w, "height": h, "walls": cells["#"], "start": cells["S"][0],
            "exit": cells["E"][0], "gems": cells["G"], "guards": routes}


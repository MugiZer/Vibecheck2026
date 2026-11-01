"""The dress step (make dress): fill the place open in Studio with the art kit and each maze
level's decor, in Edit mode, before anyone presses Play.

For each model: insert it through the Studio MCP into the pool ServerStorage.DressPool, strip
it and describe it with fixed Luau, ask the decor gate (app/decor_gate.py, ticket 23), and keep
it only if the gate says yes. A final sweep always runs: if anything that is not allowed is left
in the pool, or any script in the pool or in MaterialService, it destroys the whole pool. During
Play, the game only clones from the pool (tickets 08 and 26). A Script with RunContext = Server
runs even inside ServerStorage once Play starts, so this step refuses to run during Play.

    python3 app/dress.py           the whole dress step
    python3 app/dress.py --check   only the final sweep: run it before any Play you are unsure of

A level's decor is the picks in its decor.json, or else what search_asset finds for the words
after `watcher:` and `decor:` in its brief (else its title). All Luau is fixed text in this file.
The only values put into it pass through luau_value(); brief text is only ever a search string.
"""
import json
import re
import sys
from pathlib import Path
from string import Template

import decor_gate
import studio
import verify

# The material pack's three MaterialVariants to use: a wallpaper, a carpet and a ceiling tile, by
# their number in the list the materials step prints (0 = not chosen yet; choose on the first run).
WALL, FLOOR, CEILING = 0, 0, 0

ART = [("12737467199", "CeilingLight", "prop"),  # Roof Light (map ticket 11)
       ("10699449494", "Watcher", "npc")]  # backrooms monster
MATERIAL_PACK = "89043606186394"  # Yasu's Backrooms Material Pack
GATE = verify.ROOT / ".lake/build/bin/decor-gate"
LOCK = verify.BUILD / "studio.lock"  # one agent drives Studio at a time
LEVEL_ID = re.compile(r"[0-9a-f]{12}")
DIGITS = re.compile(r"[0-9]{1,19}")
WORDS = ("wall", "corner", "watcher", "prop", "npc", "CeilingLight", "Watcher")


class Stop(Exception):
    """The dress step stops, with this message."""


def luau_value(v):
    """The only way a value gets into Luau text. Accepts an int, a str of 1 to 19 digits, a
    level id (12 characters, 0-9 and a-f), or one of the fixed words; raises on anything else.
    None of these can hold a quote, a bracket, or a line break."""
    if type(v) is int:
        return str(v)
    if type(v) is str and (DIGITS.fullmatch(v) or LEVEL_ID.fullmatch(v) or v in WORDS):
        return v
    raise ValueError(f"not allowed in Luau text: {repr(v)[:80]}")


def luau(code, **values):
    """Fixed Luau text with each $name replaced by luau_value(value)."""
    return Template(code).substitute({k: luau_value(v) for k, v in values.items()})


def shown(text):
    """Text from Studio, safe to print: cut, with line breaks and control characters escaped."""
    return str(text)[:300].encode("unicode_escape").decode("ascii")


def call(tool, args):
    """One Studio MCP call. Returns (ok, text); ok is False when the tool reports an error.
    Raises Stop when the MCP does not answer at all."""
    try:
        reply = studio.call(tool, args)
    except Exception as e:  # no launcher, a launcher that hangs (queue.Empty), a broken pipe
        raise Stop(f"{tool}: the Studio MCP did not answer ({e!r})")
    if "error" in reply:
        return False, json.dumps(reply["error"])
    result = reply.get("result") or {}
    text = "".join(str(p.get("text", "")) for p in result.get("content", []) if isinstance(p, dict))
    return not result.get("isError"), text


def run_luau(sid, code, expect):
    """Run Luau in the Edit DataModel; stop unless its result holds `expect`."""
    ok, text = call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
    if not ok or expect not in text:
        raise Stop(f"Luau failed: {shown(text)}")
    return text


def insert(sid, asset, name, parent):
    """insert_asset, only for an asset id that the proved validAssetId accepts. Returns the
    tool's reply text, or None if the id was refused."""
    if not decor_gate.valid_id(asset):
        return None
    return call("insert_asset", {"studio_id": sid, "assetId": asset, "assetName": name, "parentPath": parent})[1]


# The decor gate's three class lists, copied from app/decor/Decor/Gate.lean. The place matches
# the exact ClassName and never uses IsA: a Seat is a kind of Part.
CLASSES = """
local partClasses = { "Part", "MeshPart", "WedgePart", "CornerWedgePart", "UnionOperation" }
local lookClasses = { "Model", "Folder", "Decal", "Texture", "SurfaceAppearance",
  "Attachment", "Weld", "WeldConstraint", "Motor6D" }
local npcClasses = { "Humanoid", "BodyColors", "Shirt", "Pants", "ShirtGraphic", "Accessory" }
local isPart, allowed = {}, {}
for _, c in partClasses do isPart[c] = true; allowed[c] = true end
for _, c in lookClasses do allowed[c] = true end
for _, c in npcClasses do allowed[c] = true end
"""

# Step 2: an empty pool, and no old materials.
RESET = """
local ServerStorage = game:GetService("ServerStorage")
for _, c in ServerStorage:GetChildren() do
  if c.Name == "DressPool" then c:Destroy() end
end
for _, c in game:GetService("MaterialService"):GetChildren() do
  if c.Name == "RA_Wall" or c.Name == "RA_Floor" or c.Name == "RA_Ceiling" then c:Destroy() end
end
local pool = Instance.new("Folder")
pool.Name = "DressPool"
for _, name in { "Art", "Decor" } do
  local f = Instance.new("Folder")
  f.Name = name
  f.Parent = pool
end
pool.Parent = ServerStorage
return "reset"
"""

# Where the model step finds the model: an art model, or decor pick n of a level.
FIND_ART = """
local model = game:GetService("ServerStorage").DressPool.Art:FindFirstChild("$name")
"""
FIND_DECOR = """
local level = game:GetService("ServerStorage").DressPool.Decor:FindFirstChild("$level")
local slot = level and level:FindFirstChild("$where")
local model = slot and slot:FindFirstChild("$n")
"""

# The folders for one level's picks: DressPool.Decor.<level>.<where>.
FOLDERS = """
local decor = game:GetService("ServerStorage").DressPool.Decor
local level = decor:FindFirstChild("$level")
if not level then
  level = Instance.new("Folder")
  level.Name = "$level"
  level.Parent = decor
end
if not level:FindFirstChild("$where") then
  local slot = Instance.new("Folder")
  slot.Name = "$where"
  slot.Parent = level
end
return "folders"
"""

# The model step, after a FIND line: strip the model, fit it into its box, and describe it as
# JSON for the decor gate (ticket 23's format).
MODEL_STEP = CLASSES + """
if not model then return "missing" end
-- 1. No tags or attributes anywhere, and no instance whose class is not allowed: this removes
-- every script, light, sound and effect.
local function clean(inst)
  for _, tag in inst:GetTags() do inst:RemoveTag(tag) end
  for key in inst:GetAttributes() do inst:SetAttribute(key, nil) end
end
clean(model)
for _, d in model:GetDescendants() do
  if d.Parent then -- not already destroyed with an ancestor
    if allowed[d.ClassName] then clean(d) else d:Destroy() end
  end
end
-- 2. Parts do not move, collide, fire touch events, or show up in queries. Humanoids show nothing.
for _, d in model:GetDescendants() do
  if isPart[d.ClassName] then
    d.Anchored = true
    d.CanCollide = false -- before CanQuery: CanQuery can be false only when CanCollide is false
    d.CanTouch = false
    d.CanQuery = false
  elseif d.ClassName == "Humanoid" then
    d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
  end
end
-- 3. Fit the box (studs; the gate's limits), centered on the pivot. 0.95 leaves room for rounding up.
local box = ({ prop = Vector3.new(4, 6, 4), npc = Vector3.new(6, 8, 6) })["$kind"]
model.PrimaryPart = nil
local cf, size = model:GetBoundingBox()
model.WorldPivot = cf
local f = math.min(1, 0.95 * math.min(box.X / size.X, box.Y / size.Y, box.Z / size.Z))
model:ScaleTo(model:GetScale() * f)
-- 4. Describe every instance, the children of every class, as the decor gate reads it.
local pivot = model:GetPivot()
local function up(v, k) return math.ceil(math.abs(v) * k) end -- rounded up, no sign
local function describe(inst)
  local node = { name = inst.Name, cls = inst.ClassName, anchored = false, canCollide = false,
    canTouch = false, canQuery = false, size = { 0, 0, 0 }, off = { 0, 0, 0 }, alongX = { 0, 0, 0 },
    alongY = { 0, 0, 0 }, alongZ = { 0, 0, 0 }, displayDistance = "", healthDisplay = "", children = {} }
  if isPart[inst.ClassName] then
    local p, rel = inst, pivot:ToObjectSpace(inst.CFrame)
    node.anchored, node.canCollide, node.canTouch, node.canQuery = p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery
    node.size = { up(p.Size.X, 10), up(p.Size.Y, 10), up(p.Size.Z, 10) }
    node.off = { up(rel.X, 10), up(rel.Y, 10), up(rel.Z, 10) }
    node.alongX = { up(rel.XVector.X, 1000), up(rel.YVector.X, 1000), up(rel.ZVector.X, 1000) }
    node.alongY = { up(rel.XVector.Y, 1000), up(rel.YVector.Y, 1000), up(rel.ZVector.Y, 1000) }
    node.alongZ = { up(rel.XVector.Z, 1000), up(rel.YVector.Z, 1000), up(rel.ZVector.Z, 1000) }
  elseif inst.ClassName == "Humanoid" then
    node.displayDistance = inst.DisplayDistanceType.Name
    node.healthDisplay = inst.HealthDisplayType.Name
  end
  for _, c in inst:GetChildren() do table.insert(node.children, describe(c)) end
  return node
end
return game:GetService("HttpService"):JSONEncode(describe(model))
"""

# After a FIND line: the decor gate said yes. Ticket 08's checked clone compares its count with this.
ACCEPT = """
if not model then return "missing" end
model:SetAttribute("checkedNodes", $nodes)
return "accepted"
"""

# After a FIND line: the decor gate said no, or did not answer.
DESTROY = """
if model then model:Destroy() end
return "destroyed"
"""

# Step 4: list the pack's MaterialVariants, copy the three chosen ones into MaterialService as
# plain variants on the base materials that ticket 08 paints, then destroy the pack.
MATERIALS = """
local pack = game:GetService("ServerStorage").DressPool:FindFirstChild("Materials")
local variants = {}
if pack then
  for _, d in pack:GetDescendants() do
    if d.ClassName == "MaterialVariant" then table.insert(variants, d) end
  end
end
table.sort(variants, function(a, b) return a.Name < b.Name end)
local lines = {}
for i, v in variants do table.insert(lines, i .. " " .. v.Name .. " " .. v.BaseMaterial.Name) end
local made = 0
for _, t in { { $wall, "RA_Wall", Enum.Material.Plaster }, { $floor, "RA_Floor", Enum.Material.Carpet },
  { $ceiling, "RA_Ceiling", Enum.Material.CeramicTiles } } do
  local c = variants[t[1]] and variants[t[1]]:Clone()
  if c then
    c:ClearAllChildren()
    for _, tag in c:GetTags() do c:RemoveTag(tag) end
    for key in c:GetAttributes() do c:SetAttribute(key, nil) end
    c.Name = t[2]
    c.BaseMaterial = t[3]
    c.Parent = game:GetService("MaterialService")
    made += 1
  end
end
if pack then pack:Destroy() end
return "made " .. made .. "\\n" .. table.concat(lines, "\\n")
"""

# Step 6: count what is not allowed in the pool, and every script in the pool and in
# MaterialService. If the count is not 0, destroy the whole pool.
SWEEP = CLASSES + """
local left, pools = 0, {}
for _, c in game:GetService("ServerStorage"):GetChildren() do
  if c.Name == "DressPool" then
    table.insert(pools, c)
    local all = c:GetDescendants()
    table.insert(all, c)
    for _, d in all do
      if not allowed[d.ClassName] or d:IsA("LuaSourceContainer") then left += 1 end
    end
  end
end
for _, d in game:GetService("MaterialService"):GetDescendants() do
  if d:IsA("LuaSourceContainer") then left += 1 end
end
if left > 0 then
  for _, p in pools do p:Destroy() end
end
return "left " .. left
"""


def model_step(sid, label, find, values, kind):
    """Strip, fit and describe one inserted model, ask the decor gate, then mark the model as
    checked or destroy it. `find` and `values` say where the model is. Prints one [dress] line.
    True if the gate accepted the model, None if it is not in the pool."""
    ok, text = call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit",
                                     "code": luau(find + MODEL_STEP, kind=kind, **values)})
    if ok and text.strip() == "missing":
        return None
    start, end = text.find("{"), text.rfind("}")
    nodes, why = None, f"strip or describe failed: {shown(text)}"
    if ok and 0 <= start < end:
        try:  # the tree goes to the gate as bytes, unchanged: never decoded and re-encoded here
            answer = decor_gate.check_tree(kind, text[start:end + 1].encode())
            why = "rejected by the decor gate"  # the gate gives no reason, and nodes 0 on a no
            if answer.get("ok") is True and type(answer.get("nodes")) is int:
                nodes = answer["nodes"]
        except Exception as e:
            why = f"the decor gate failed: {e!r}"
    if nodes is not None:
        run_luau(sid, luau(find + ACCEPT, nodes=nodes, **values), "accepted")
        print(f"[dress] {label}: accepted, {nodes} nodes")
        return True
    run_luau(sid, luau(find + DESTROY, **values), "destroyed")
    print(f"[dress] {label}: {why}; destroyed")
    return False


def dress_model(sid, label, asset, name, parent, find, values, kind):
    """Insert one model into the pool, then the model step. True if the decor gate accepted it."""
    reply = insert(sid, asset, name, parent)
    if reply is None:
        print(f"[dress] {label}: asset id {asset!r} refused by validAssetId")
        return False
    accepted = model_step(sid, label, find, values, kind)
    if accepted is None:
        print(f"[dress] {label}: not inserted: {shown(reply)}")
    return bool(accepted)


def materials(sid):
    """Step 4. Returns how many of RA_Wall, RA_Floor and RA_Ceiling were made."""
    reply = insert(sid, MATERIAL_PACK, "Materials", "game.ServerStorage.DressPool")
    if reply is None:
        print(f"[dress] materials: asset id {MATERIAL_PACK!r} refused by validAssetId")
        return 0
    text = run_luau(sid, luau(MATERIALS, wall=WALL, floor=FLOOR, ceiling=CEILING), "made ")
    made, *lines = text[text.find("made "):].splitlines()
    for line in lines:
        print(f"[dress] material {shown(line)}")
    if not lines:
        print(f"[dress] materials: no MaterialVariant found; insert reply: {shown(reply)}")
    elif made != "made 3":
        print("[dress] materials: set WALL, FLOOR, CEILING at the top of app/dress.py to the numbers "
              "of a wallpaper, a carpet and a ceiling tile above")
    return int(made.split()[1])


def file_picks(level, path):
    """The picks in a level's decor.json that clean_picks keeps; prints each dropped pick."""
    try:
        raw = json.loads(path.read_text())
    except ValueError:
        print(f"[dress] decor {level}: decor.json is not JSON; no picks")
        return []
    picks = decor_gate.clean_picks(raw)
    kept = 0  # clean_picks keeps good picks in order, so match them against the file in order
    for p in raw if isinstance(raw, list) else [raw]:
        if kept < len(picks) and isinstance(p, dict) and all(
                p.get(k) == picks[kept].get(k) for k in ("id", "kind", "where")):
            kept += 1
        else:
            print(f"[dress] decor {level}: dropped pick {json.dumps(p)[:200]}")
    return picks


def brief_queries(m):
    """(query, kind, where) for a level without decor.json: the text after `watcher:` in its brief is
    the watchers' look (npc); the comma-separated words after `decor:` are props (at most 4). Without
    `decor:` words, the title is the prop query; without `watcher:`, the art watcher stays."""
    brief = str(m.get("brief") or "")
    watcher = re.search(r"watcher:\s*(.*?)\s*(?:;|\n|decor:|$)", brief, re.I)
    words = re.search(r"decor:\s*(.*?)\s*(?:;|\n|watcher:|$)", brief, re.I)
    props = [w.strip() for w in words.group(1).split(",") if w.strip()][:4] if words else []
    title = str((m.get("presentation") or {}).get("title") or "").strip()
    props = props or ([title] if title else [])
    return ([(watcher.group(1), "npc", "watcher")] if watcher and watcher.group(1) else []) + \
        [(q, "prop", "wall") for q in props]


def search(sid, query):
    """search_asset with the fixed filters: the asset ids of the results, in order. The query is
    only ever a search string here, never Luau text."""
    ok, text = call("search_asset", {"studio_id": sid, "query": query[:60], "assetType": "Model",
                                     "scope": "creator_store", "priceFilter": "free",
                                     "verifiedCreatorsOnly": True, "maxResults": 5})
    try:
        results = json.loads(text).get("results") if ok else None
    except (ValueError, AttributeError):
        results = None
    ids = [str(r.get("assetId")) for r in results if isinstance(r, dict)] if isinstance(results, list) else []
    if not ids:
        print(f"[dress] search {shown(query)}: no results: {shown(text)}")
    return ids


def decor(sid):
    """Step 5. Returns (accepted, tried) over every published maze level: the picks in its
    decor.json, else, for each query from its brief, the first search result the gate accepts."""
    accepted = tried = 0
    done = set()  # a level published twice (an example and an artifact) is dressed once
    for m in verify.published():
        if m.get("template") != "maze":
            continue
        level = m.get("id")
        if not (type(level) is str and LEVEL_ID.fullmatch(level)):
            raise Stop(f"{m['dir']}: the level id is not 12 characters of 0-9 and a-f")
        if level in done:
            continue
        done.add(level)
        path = Path(m["dir"]) / "decor.json"
        if path.exists():
            slots = [([p["id"]], p["kind"], p["where"]) for p in file_picks(level, path)]
        else:
            slots = [(search(sid, q), kind, where) for q, kind, where in brief_queries(m)]
        for n, (ids, kind, where) in enumerate(slots, 1):
            tried += 1
            run_luau(sid, luau(FOLDERS, level=level, where=where), "folders")
            parent = f"game.ServerStorage.DressPool.Decor.{luau_value(level)}.{luau_value(where)}"
            # any() stops at the first id the gate accepts; a rejected model is already destroyed
            accepted += any(dress_model(sid, f"decor {level} {where} {n}", a, luau_value(n), parent,
                                        FIND_DECOR, {"level": level, "where": where, "n": n}, kind) for a in ids)
    return accepted, tried


def sweep(sid):
    """Step 6. True if nothing was left; otherwise the pool is destroyed (if the sweep could run)."""
    try:
        ok, text = call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": SWEEP})
    except Stop as e:
        ok, text = False, str(e)
    found = re.search(r"\bleft (\d+)", text) if ok else None
    if not found:
        print(f"[dress] the final sweep failed, so do not press Play: {shown(text)}")
        return False
    if found.group(1) != "0":
        print(f"[dress] the final sweep found {found.group(1)} instances that are not allowed; DressPool destroyed")
        print("[dress] scripts left: do not press Play")
        return False
    return True


def dress(sid):
    """Steps 2 to 6. Returns the exit code."""
    art = made = accepted = tried = 0
    try:
        run_luau(sid, RESET, "reset")
        for asset, name, kind in ART:
            art += dress_model(sid, f"art {name}", asset, luau_value(name), "game.ServerStorage.DressPool.Art",
                               FIND_ART, {"name": name}, kind)
        made = materials(sid)
        accepted, tried = decor(sid)
    finally:
        clean = sweep(sid)
    if not clean:
        return 1
    print(f"[dress] done: art {art}/{len(ART)}, decor {accepted}/{tried} accepted, materials {made}/3, left 0")
    return 0


def main(argv):
    """Step 1, then the dress step (or only the sweep, with --check). Returns the exit code."""
    if argv not in ([], ["--check"]):
        raise Stop("usage: python3 app/dress.py [--check]")
    if not argv and not GATE.exists():
        raise Stop("run `lake build decor-gate` first (one `lake` at a time in this checkout)")
    try:
        sid = studio.studio_id()
    except Exception as e:
        raise Stop(f"list_roblox_studios: the Studio MCP did not answer ({e!r})")
    if not sid:
        raise Stop("open build/RiggedArcade.rbxlx in Studio")
    if argv == ["--check"]:
        if not sweep(sid):
            return 1
        print("[dress] check: left 0")
        return 0
    ok, state = call("get_studio_state", {"studio_id": sid})
    if not ok:
        raise Stop(f"get_studio_state failed: {shown(state)}")
    mode = re.search(r"Current Studio Mode:\s*(\w+)", state)
    if not mode or mode.group(1) != "Edit":
        raise Stop("stop Play first: the dress step runs only in Edit mode")
    verify.BUILD.mkdir(exist_ok=True)
    try:
        LOCK.mkdir()
    except FileExistsError:
        raise Stop("another agent drives Studio")
    try:
        return dress(sid)
    finally:
        LOCK.rmdir()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Stop as e:
        print(f"[dress] {e}")
        sys.exit(1)

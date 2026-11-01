# Rigged Arcade

Players ask for a game level and a property it must have. Claude designs the level, Lean proves the property about that exact level, and the player plays it. This file fixes the words the code, docs, and tickets use.

## Language

### Games and levels

**Template**:
One game the arcade offers (maze, slingshot). Its Lean rules, spec, runtime, and guide live in `templates/<name>/`.
_Avoid_: game type, engine

**Variant**:
The data of one level for a template, as in the Lean type `<Template>.Variant`.
_Avoid_: map, config

**Requirement**:
The Lean predicate `UserSpec.requirement` that a variant must satisfy. It is either a reviewed sample or a file the player uploaded.
_Avoid_: spec (alone), rule

**Artifact**:
A variant the judge accepted, published as a self-contained Lean project in `examples/<id>/` or `artifacts/<id>/`. "Level" in the UI means an artifact.
_Avoid_: result, output

### Who decides

**Runtime**:
The compiled Lean game process for a template (`maze`, `sling`). It is the only code that decides what a move or shot does, and it runs the same functions the proofs are about.
_Avoid_: engine, backend

**Judge**:
The sandboxed build plus `lake comparator` run in `app/verify.py`. Only the judge can publish an artifact.
_Avoid_: verifier (alone), checker

**Coordinator**:
`app/server.py`. It owns jobs, sessions, and the HTTP API, and it talks to the runtimes and the judge.
_Avoid_: backend, API server

**Session**:
One play-through of one artifact. The coordinator keeps its move list and asks the runtime to replay it after each action.

### Who draws

**Renderer**:
A front end that draws the state the runtime returns and sends the player's inputs to the coordinator. It holds no game rules. The web page and the Roblox place are renderers.
_Avoid_: client, frontend, game (for the Roblox side)

**Roblox place**:
The place file built with Rojo from the repo's Roblox folder and opened in Roblox Studio. It is a renderer: its server script calls the coordinator over HTTP.
_Avoid_: experience (that word means a published Roblox game, which this effort does not ship), Roblox game

**Decor**:
Creator Store models placed in a Roblox level for looks only: props, or NPC models when the brief asks for them. Decor never changes play.
_Avoid_: assets, items (alone), furniture

**Decor gate**:
The Lean program that decides whether one fetched decor model may enter the scene, from the instance tree the Roblox place reports.
_Avoid_: sanitizer, filter, scanner

**Dress step**:
`make dress`. With Studio in Edit mode, before Play, it fills the pool `ServerStorage.DressPool` in the open place with the art kit and each level's decor. It removes every class the decor gate does not allow from each model, and keeps a model only if the gate accepts it. The pool is lost when the place closes, so run it again each time Studio opens the place.
_Avoid_: import, insert step

**Show why**:
The view that draws a level's proof evidence: the cells that pass Lean's region check on each guard turn; until a guard catches you, you are always on one (maze), or every allowed shot's flight (slingshot).
_Avoid_: reveal (in UI text), explanation

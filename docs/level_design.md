# How the mines are built

Every level is generated from a short spec in `tools/blender/layout_<id>.py` by `tools/blender/maze.py`, then meshed and dressed by `tools/blender/level.py`. The generator is seeded, so the same spec always produces the same mine.

## Structure
- **Zones and keys.** Coloured key doors split each mine into zones. The key for the next zone lies in the room furthest (by tunnels) from the current zone's entrance. The gate out of a zone leaves from a different room than the key room, so getting the key and then reaching the door means doubling back through the zone. A check proves each key opens its zone in order, and that the reactor can't be reached before the last key.
- **Room graphs, not corridors.** Each zone is grown as a tree of rooms with extra loops: a second tunnel between two rooms, or a junction off the middle of another tunnel. Some levels also have *gated loops*, a second door of the same colour that gives another way into the next zone.
- **Dead ends.** Dead-end nooks hang off rooms and tunnels. Upgrades usually sit in one, so exploring pays. Secret rooms are behind flush panels on metal tunnels and only open to a shot.
- **The finale.** The reactor or boss chamber is the deepest room of the last zone. No straight line from any key door reaches its middle. The escape tunnel always leaves its east wall.

## Room shapes
`box`, `hall` (a long gallery with alcoves and several exits), `pillars`, `ring` (a loop around a solid core), `cyl_v`, `cyl_h` (a big pipe), `dome`, `cave` (overlapping lumps), `ell`, `cross`, `tiered` (a raised shelf), `shaft` (tall, with ledges), `split` (two floors with holes between), `bridge` (a rock beam across the room), `octagon`, and `nook`.

## Tunnel styles
Tunnels are routed with A* through the rock and never touch another space except where they connect:
- `straight`: industrial metal runs.
- `duct`: metal, with a few turns.
- `winding`: rock drifts that wander.
- `diagonal`: staircase steps that the shell smoothing turns into slanting, twisting drifts.
- `wide`: two cells across.
- `drop`: prefers vertical runs.

Long tunnels sometimes bulge into a small chamber.

## Tools
- `python3 tools/maze_preview.py <id> out.png` draws the map from above and from the side. Colours are zones, squares are doors, diamonds are keys and upgrades, and the circle is the objective.
- `godot --path . --resolution 1280x720 res://tests/level_tour.tscn -- <dir> <level index> [n]` photographs the rooms and tunnels the generator suggests and prints the steady FPS at each one.
- `tools/refresh.sh screens` regenerates `docs/level_maps/` and the room tours in `docs/screenshots/levels/<id>/`.

To change a level, edit its spec (seed, shapes, zones, styles, robots, items), then rebuild it with `blender -b --factory-startup --python tools/blender/level.py -- <id>` and run `godot --headless --import --path .`.

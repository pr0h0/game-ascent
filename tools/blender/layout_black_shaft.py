"""Black Shaft: a colossal vertical mine, galleries and wells branching off at every depth."""
from maze import mission

globals().update(mission(dict(
    name="black_shaft", seed=3, keys=["blue", "yellow"],
    shapes={"shaft": 3, "cyl_v": 2, "split": 2, "tiered": 1, "box": 1, "bridge": 1},
    hub="shaft", hub_mat="rock", hub_scale=1.7, scale=1.0, gap=(3, 7), vertical=0.9, spread_y=6, metal=0.5,
    styles={"drop": 4, "straight": 2, "diagonal": 1, "duct": 1},
    zones=[
        dict(rooms=4, loops=1, nooks=2, chain=0.4),
        dict(rooms=3, loops=1, nooks=2),
        dict(rooms=1, loops=0, nooks=1),
    ],
    finale=dict(shape="cathedral", half=(5, 4, 5), hp=1600.0, turrets=2,
                enemies=["bulwark", "bulwark", "lancer", "lancer", "tick", "tick"], pick=["shield", "energy", "ammo"]),
    roster={"tick": 4, "lancer": 5}, heavies=["bulwark"] * 4, enemies=18, tunnel_share=0.25,
    specials=[("upgrade_laser_2", 1)], consumables=18, turrets=5, astronauts=3,
    secrets=[["energy", "ammo"]],
    detail=0.6,
)))
NAME = "black_shaft"
# Molten floors in some caverns (tools/blender/level.py choose_lava_cells).
LAVA = {"zones": ["rock"], "cover": 0.6, "max_cells": 60, "pools": 3}

"""Smelter Row: long furnace halls and charging floors. Melee robots, molten floors, the Crucible."""
from maze import mission

globals().update(mission(dict(
    name="smelter_row", seed=4, keys=["blue", "yellow"],
    shapes={"hall": 3, "cyl_h": 2, "pillars": 2, "box": 1, "ell": 1, "tiered": 1},
    hub="pillars", hub_mat="metal", scale=1.1, gap=(4, 8), vertical=0.2, metal=0.7,
    styles={"straight": 3, "duct": 2, "wide": 2, "winding": 1},
    zones=[
        dict(rooms=4, loops=1, nooks=2, chain=0.5),
        dict(rooms=3, loops=1, nooks=2),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=1,
    finale=dict(shape="box", half=(7, 4, 6), boss="crucible", turrets=3, enemies=["lancer", "ripper", "hornet"],
                pick=["power_invincible", "shield", "shield", "shield", "energy", "energy", "ammo", "ammo_cluster", "ammo_cluster"]),
    roster={"ripper": 3, "tick": 2, "hornet": 3, "lancer": 1, "cinder": 2}, heavies=["bulwark"], enemies=40, tunnel_share=0.25,
    specials=[("upgrade_weapon_cutter", 0), ("ammo_cluster", 1), ("ammo_cluster", 1), ("power_invincible", 1)],
    consumables=20, turrets=8, mines={"prox": 13},
    secrets=[["power_invincible", "shield"], ["ammo", "energy"]],
    detail=0.5,
)))
NAME = "smelter_row"
# Molten floors in some halls (tools/blender/level.py choose_lava_cells).
LAVA = {"zones": ["metal", "rock"], "cover": 0.55, "max_cells": 70, "pools": 3}

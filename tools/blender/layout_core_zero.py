"""Core Zero: everything left in the mine, every kind of working, and Zero at the bottom of it."""
from maze import mission

globals().update(mission(dict(
    name="core_zero", seed=10, keys=["blue", "yellow", "red"],
    shapes={"cave": 2, "hall": 2, "pillars": 1, "ring": 1, "shaft": 1, "split": 1, "cyl_v": 1, "cross": 1, "tiered": 1, "dome": 1, "bridge": 1},
    hub="pillars", hub_mat="rock", hub_scale=1.5, scale=1.15, gap=(4, 9), vertical=0.35, metal=0.45,
    styles={"winding": 2, "diagonal": 2, "straight": 2, "wide": 1, "drop": 1},
    zones=[
        dict(rooms=4, loops=2, nooks=2),
        dict(rooms=4, loops=1, nooks=2),
        dict(rooms=4, loops=1, nooks=2),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=2,
    finale=dict(shape="box", half=(11, 7, 10), boss="zero", turrets=4, enemies=["revenant", "longshot", "hive", "warden"],
                pick=["power_invincible", "power_invincible", "power_cloak", "shield", "shield", "shield", "shield", "energy", "energy", "energy", "ammo", "ammo", "ammo_swarm", "ammo_bunker"]),
    roster={"gravitar": 2, "longshot": 2, "phase": 2, "wraith": 2, "glint": 2, "drillback": 2, "revenant": 1, "shade": 2},
    heavies=["siege", "siege", "hive", "hive", "hive", "bulwark"], enemies=80,
    specials=[("upgrade_weapon_singularity", 0), ("ammo_swarm", 1), ("ammo_swarm", 2), ("ammo_bunker", 1), ("ammo_bunker", 2),
              ("ammo_mine", 1), ("ammo_emp", 2), ("ammo_cluster", 2), ("power_cloak", 1)],
    consumables=30, turrets=21, astronauts=3, mines={"seeker": 10, "tripwire": 10, "pulse": 9},
    secrets=[["power_invincible", "energy"], ["power_cloak", "ammo_swarm"], ["shield", "ammo_bunker"]],
    detail=0.4,
)))
NAME = "core_zero"
# Molten floors in some caverns (tools/blender/level.py choose_lava_cells).
LAVA = {"zones": ["rock", "core"], "cover": 0.5, "max_cells": 110, "pools": 4}

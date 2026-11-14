"""Deep Cut: narrow drill galleries that wind and branch, tripwires and mine layers."""
from maze import mission

globals().update(mission(dict(
    name="deep_cut", seed=6, keys=["blue", "yellow"],
    shapes={"cave": 2, "hall": 2, "cyl_h": 2, "shaft": 1, "tiered": 1, "box": 1, "bridge": 1},
    hub="cross", hub_mat="rock", scale=0.9, gap=(4, 9), vertical=0.35, metal=0.3,
    styles={"winding": 3, "diagonal": 3, "drop": 2, "straight": 1, "duct": 1},
    zones=[
        dict(rooms=5, loops=2, nooks=3, chain=0.6),
        dict(rooms=4, loops=2, nooks=3, chain=0.5),
        dict(rooms=2, loops=1, nooks=1),
    ],
    gated_loops=1,
    finale=dict(shape="tiered", half=(6, 3, 6), hp=2100.0, turrets=3,
                enemies=["drillback", "drillback", "sower", "warden", "spark", "ripper", "cinder"],
                pick=["power_invincible", "shield", "energy", "ammo_bunker"]),
    roster={"drillback": 2, "sower": 3, "ripper": 3, "cinder": 2, "lancer": 3, "shade": 2, "hornet": 1, "spark": 1},
    tunnel_roster={"ripper": 2, "cinder": 2, "lancer": 1, "shade": 1, "drillback": 1},
    heavies=[], enemies=54, tunnel_share=0.3,
    specials=[("upgrade_laser_3", 1), ("ammo_bunker", 0), ("ammo_bunker", 1)],
    consumables=24, turrets=10, astronauts=0,
    mines={"tripwire": 8, "prox": 4, "seeker": 6},
    secrets=[["power_cloak", "ammo"], ["shield", "energy"]],
    detail=0.5,
)))
NAME = "deep_cut"

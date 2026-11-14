"""Hollow Reach: wide natural caverns joined by broad drifts. Arc robots, medics and seeking mines."""
from maze import mission

globals().update(mission(dict(
    name="hollow_reach", seed=5, keys=["blue", "red"],
    shapes={"cave": 4, "dome": 3, "ring": 1, "bridge": 1},
    hub="cave", hub_mat="rock", hub_scale=1.5, scale=1.3, gap=(4, 9), vertical=0.35, metal=0.25,
    styles={"wide": 3, "winding": 3, "diagonal": 2, "drop": 1, "duct": 1},
    zones=[
        dict(rooms=4, loops=2, nooks=2, chain=0.4),
        dict(rooms=4, loops=1, nooks=2),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=1,
    finale=dict(shape="octagon", half=(7, 4, 6), hp=1900.0, turrets=3,
                enemies=["bulwark", "warden", "spark", "spark", "lancer", "ripper", "hornet"], pick=["shield", "energy", "ammo_swarm"]),
    roster={"spark": 2, "warden": 1, "hornet": 2, "ripper": 2, "lancer": 1, "shade": 1, "cinder": 1}, heavies=["bulwark"], enemies=42,
    specials=[("upgrade_weapon_arc", 0), ("ammo_swarm", 1), ("ammo_swarm", 1), ("power_cloak", 1)],
    consumables=20, turrets=9, astronauts=3, mines={"seeker": 8, "prox": 6},
    secrets=[["power_cloak", "energy"], ["ammo_swarm", "shield"]],
    detail=0.45,
)))
NAME = "hollow_reach"

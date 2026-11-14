"""The Overseer's Pit: control rooms and service ducts round one enormous pit, and what runs the mine."""
from maze import mission

globals().update(mission(dict(
    name="overseer_pit", seed=7, keys=["blue", "yellow"],
    shapes={"box": 2, "pillars": 1, "cyl_v": 1, "cross": 1, "ring": 1, "octagon": 1},
    hub="octagon", hub_mat="metal", scale=0.9, gap=(4, 8), vertical=0.3, metal=0.7,
    styles={"straight": 3, "duct": 2, "winding": 1, "diagonal": 1},
    zones=[
        dict(rooms=3, loops=1, nooks=1),
        dict(rooms=2, loops=1, nooks=1),
        dict(rooms=1, loops=0, nooks=0),
    ],
    finale=dict(shape="box", half=(12, 7, 12), boss="overseer", turrets=4, enemies=[],
                pick=["power_invincible", "power_invincible", "power_cloak", "shield", "shield", "shield", "energy", "energy", "energy", "ammo", "ammo", "ammo_bunker"]),
    roster={"hornet": 2, "ripper": 3, "shade": 2, "cinder": 2}, enemies=30,
    specials=[("upgrade_weapon_rail", 0), ("ammo_cluster", 1), ("ammo_bunker", 1), ("ammo_bunker", 1), ("power_cloak", 1)],
    consumables=18, turrets=6, mines={"prox": 7, "seeker": 4},
    secrets=[["power_cloak", "shield"]],
    detail=0.4,
)))
NAME = "overseer_pit"

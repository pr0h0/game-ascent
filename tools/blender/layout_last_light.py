"""Last Light: long halls and big pipes with sightlines for snipers, teleporters and hive carriers."""
from maze import mission

globals().update(mission(dict(
    name="last_light", seed=9, keys=["blue", "yellow"],
    shapes={"hall": 3, "cyl_h": 2, "box": 2, "ring": 1, "pillars": 1},
    hub="ring", hub_mat="metal", hub_scale=1.3, scale=1.25, gap=(5, 10), vertical=0.25, metal=0.6,
    styles={"straight": 4, "wide": 2, "duct": 1, "diagonal": 1},
    zones=[
        dict(rooms=4, loops=1, nooks=2),
        dict(rooms=4, loops=1, nooks=2),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=1,
    finale=dict(shape="cathedral", half=(9, 6, 8), hp=2800.0, turrets=4,
                enemies=["siege", "hive", "longshot", "longshot", "phase", "phase", "warden", "wraith"], pick=["shield", "shield", "energy", "ammo_mine"]),
    roster={"longshot": 3, "phase": 3, "wraith": 2, "revenant": 1, "shade": 1, "hornet": 1}, heavies=["hive", "hive", "siege"], enemies=52,
    specials=[("upgrade_laser_4", 1), ("ammo_mine", 0), ("ammo_mine", 0), ("ammo_mine", 1), ("power_cloak", 0)],
    consumables=22, turrets=13, astronauts=3, mines={"seeker": 7, "tripwire": 7, "pulse": 4},
    secrets=[["power_invincible", "ammo_mine"], ["power_cloak", "shield"]],
    detail=0.4,
)))
NAME = "last_light"

"""Glass Seam: crystal galleries crossing each other, stalkers you cannot see, and pulse mines."""
from maze import mission

globals().update(mission(dict(
    name="glass_seam", seed=8, keys=["blue", "yellow", "red"],
    shapes={"hall": 2, "cross": 2, "ell": 2, "cave": 2, "bridge": 1, "tiered": 1},
    hub="cross", hub_mat="rock", scale=1.0, gap=(4, 8), vertical=0.3, metal=0.35,
    styles={"winding": 2, "diagonal": 2, "straight": 2, "wide": 1},
    zones=[
        dict(rooms=3, loops=1, nooks=2),
        dict(rooms=3, loops=1, nooks=1),
        dict(rooms=3, loops=1, nooks=1),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=2,
    finale=dict(shape="octagon", half=(8, 5, 8), hp=2400.0, turrets=4,
                enemies=["bulwark", "siege", "glint", "glint", "wraith", "warden", "phase"], pick=["shield", "energy", "ammo_emp"]),
    roster={"glint": 3, "wraith": 3, "phase": 2, "revenant": 2, "shade": 2, "spark": 1, "warden": 1}, heavies=["bulwark", "siege"], enemies=55,
    specials=[("upgrade_weapon_prism", 0), ("ammo_emp", 1), ("ammo_emp", 1), ("ammo_emp", 2), ("ammo_swarm", 2), ("power_cloak", 0)],
    consumables=22, turrets=13, astronauts=2, mines={"pulse": 10, "tripwire": 7, "seeker": 1},
    secrets=[["power_invincible", "ammo_emp"], ["shield", "energy"]],
    detail=0.4,
)))
NAME = "glass_seam"

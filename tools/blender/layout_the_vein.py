"""The Vein: the big mine. Rock caverns and old workings, a three-key door chain and survivors."""
from maze import mission

globals().update(mission(dict(
    name="the_vein", seed=2, keys=["blue", "yellow", "red"],
    shapes={"cave": 3, "dome": 2, "box": 1, "split": 1, "pillars": 1, "ring": 1},
    hub="dome", hub_mat="rock", scale=1.0, gap=(4, 8), vertical=0.3, metal=0.4,
    styles={"winding": 3, "diagonal": 2, "straight": 2, "drop": 1, "duct": 1},
    zones=[
        dict(rooms=4, loops=2, nooks=2, chain=0.5),
        dict(rooms=3, loops=1, nooks=1),
        dict(rooms=2, loops=1, nooks=1),
        dict(rooms=1, loops=0, nooks=1),
    ],
    gated_loops=[0, 1],
    finale=dict(shape="pillars", half=(5, 3, 5), hp=1100.0, turrets=3,
                enemies=["lancer", "lancer", "lancer", "tick", "tick", "tick", "tick"], pick=["shield", "energy", "ammo", "shield"]),
    roster={"tick": 5, "lancer": 2}, heavies=["bulwark", "bulwark"], enemies=26, tunnel_share=0.25,
    specials=[("upgrade_dual_fire", 1)], consumables=22, turrets=8, astronauts=5,
    secrets=[["shield", "ammo"]],
    detail=0.6,
)))
NAME = "the_vein"

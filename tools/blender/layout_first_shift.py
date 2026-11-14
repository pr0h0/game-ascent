"""First Shift: a warm-up. A small working with a loop, one key and a tame reactor."""
from maze import mission

globals().update(mission(dict(
    name="first_shift", seed=1, keys=["blue"],
    shapes={"box": 2, "hall": 2, "pillars": 1, "ell": 1},
    hub="hall", hub_mat="metal", hub_scale=0.8, scale=0.6, gap=(3, 6), vertical=0.25, metal=0.7,
    styles={"straight": 3, "duct": 2, "winding": 1, "diagonal": 1},
    zones=[
        dict(rooms=3, loops=1, nooks=1, chain=0.5),
        dict(rooms=1, loops=0, nooks=0),
    ],
    finale=dict(shape="box", half=(3, 2, 3), hp=450.0, nova=False, scale=1.2, turrets=1,
                enemies=["tick", "tick", "lancer"], pick=["shield", "energy"]),
    roster={"tick": 4, "lancer": 1}, enemies=7, tunnel_share=0.3,
    specials=[], consumables=10, turrets=0,
    secrets=[["shield", "ammo"]],
    detail=0.8,
)))
NAME = "first_shift"

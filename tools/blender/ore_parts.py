"""Ore details for the themed rock walls, built into wall_parts.glb next to the stock parts.

Same frame as wall_modules: X and Y along the wall, Z into the room. Every part uses
one material, "glow_ore", which the game swaps for the level theme's ore colour.
"""
import math
import random

from kit import RX, RY, RZ, T
from wall_modules import VARIANTS

ORE = "glow_ore"


def m_nodules(k, M, r):
    """A cluster of rounded ore lumps half sunk into the rock."""
    for _ in range(r.randint(5, 9)):
        x, y = r.uniform(-1.8, 1.8), r.uniform(-1.8, 1.8)
        rad = r.uniform(0.25, 0.75)
        B = M @ T(x, y, rad * 0.1) @ RZ(r.uniform(0, 360)) @ RX(90)
        k.sphere((0, 0, 0), rad, ORE, 4, 7, B, squash=r.uniform(0.6, 0.9))


def m_shards(k, M, r):
    """Big six-sided crystals fanning out of one socket."""
    for _ in range(r.randint(4, 7)):
        x, y = r.uniform(-1.0, 1.0), r.uniform(-1.0, 1.0)
        h = r.uniform(1.6, 4.6)
        rad = r.uniform(0.28, 0.62)
        B = M @ T(x, y, -0.8) @ RZ(r.uniform(0, 360)) @ RY(r.uniform(-34, 34)) @ RX(90 + r.uniform(-30, 30))
        k.lathe([(rad * 0.8, -0.2), (rad, h * 0.62), (rad * 0.55, h * 0.84), (0.002, h)], 6, ORE, B)


def m_veins(k, M, r):
    """A glowing seam that runs along the wall and branches, partly sunk into it."""
    def seam(x, y, angle, length, rad):
        pts = []
        for _ in range(int(length / 0.8) + 1):
            pts.append((x, y, r.uniform(-0.15, 0.0)))
            angle += r.uniform(-0.6, 0.6)
            x += math.cos(angle) * 0.8
            y += math.sin(angle) * 0.8
        k.tube(pts, rad, ORE, 4, M)
        return pts

    main = seam(r.uniform(-3.4, -2.4), r.uniform(-1.2, 1.2), r.uniform(-0.5, 0.5), r.uniform(5.0, 6.5), 0.16)
    for _ in range(r.randint(1, 3)):
        x, y, _z = main[r.randrange(1, len(main) - 1)]
        seam(x, y, r.uniform(0, math.tau), r.uniform(1.4, 2.6), 0.09)


def m_icicles(k, M, r):
    """Ice hanging from a ceiling: Z points down into the room."""
    for _ in range(r.randint(6, 11)):
        x, y = r.uniform(-3.4, 3.4), r.uniform(-3.4, 3.4)
        h = r.uniform(0.8, 3.6)
        rad = r.uniform(0.14, 0.42)
        B = M @ T(x, y, -0.5) @ RZ(r.uniform(0, 360)) @ RX(90 + r.uniform(-8, 8))
        k.lathe([(rad, 0.0), (rad * 0.75, h * 0.35), (rad * 0.3, h * 0.8), (0.002, h + 0.5)], 5, ORE, B)


def _seeded(fn, seed):
    return lambda k, M: fn(k, M, random.Random(seed))


PARTS = {}
for variant in range(VARIANTS):
    PARTS["ore_nodules_%d" % variant] = _seeded(m_nodules, 400 + variant)
    PARTS["ore_shards_%d" % variant] = _seeded(m_shards, 500 + variant)
    PARTS["ore_veins_%d" % variant] = _seeded(m_veins, 600 + variant)
    PARTS["icicles_%d" % variant] = _seeded(m_icicles, 700 + variant)

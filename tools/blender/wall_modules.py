"""Reusable wall details. Each level stores only where these go, not their geometry.

A part is modelled in its own frame: X and Y along the wall, Z pointing into the room.
"""
import math
import random

from level_api import S
from kit import RX, RY, RZ, T

VARIANTS = 4


def m_pipes(k, M, with_box):
    for y, rad, mat in ((3.1, 0.2, "metal_dark"), (2.55, 0.13, "metal_bare"), (2.2, 0.09, "hull_accent")):
        z = rad + 0.1
        k.tube([(-5, y, z), (5, y, z)], rad, mat, 8, M)
    for x in (-3.4, 0.0, 3.4):
        k.cbox((x, 2.65, 0.26), (0.26, 1.5, 0.52), "metal_dark", 0.04, M)
    if with_box:
        k.cbox((1.4, 2.55, 0.32), (1.2, 0.5, 0.5), "hull_grey", 0.05, M)
        k.cbox((1.4, 2.55, 0.585), (0.5, 0.2, 0.04), "glow_amber", 0, M)


def m_lightbar(k, M):
    k.cbox((0, 0, 0.1), (6.4, 0.6, 0.2), "metal_dark", 0.04, M)
    k.cbox((0, 0, 0.205), (6.0, 0.3, 0.04), "glow_white", 0, M)
    for x in (-3.4, 3.4):
        k.cbox((x, 0, 0.14), (0.3, 0.9, 0.28), "hazard", 0.03, M)


def m_vent(k, M):
    k.cbox((0, 0, 0.04), (3.4, 3.4, 0.08), "hull_grey", 0.02, M)
    k.cbox((0, 0, 0.09), (3.0, 3.0, 0.02), "metal_dark", 0, M)
    for i in range(11):
        k.cbox((0, -1.35 + i * 0.27, 0.16), (2.96, 0.14, 0.12), "metal_bare", 0.01, M)
    for x in (-1.55, 1.55):
        for y in (-1.55, 1.55):
            k.lathe([(0.07, 0.08), (0.07, 0.13), (0.03, 0.15)], 6, "metal_bare", M @ T(x, y, 0) @ RX(90))


def m_plates(k, M, r):
    for x, y, w, h in ((-2.2, -1.9, 3.2, 3.0), (1.9, -1.9, 3.6, 3.0), (-2.2, 2.0, 3.2, 3.2), (1.9, 2.0, 3.6, 3.2)):
        if r.random() < 0.72:
            k.cbox((x, y, 0.06), (w, h, 0.12), "wall_metal" if r.random() < 0.7 else "hull_grey", 0.04, M)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    k.lathe([(0.09, 0.1), (0.09, 0.17), (0.04, 0.19)], 6, "metal_bare", M @ T(x + sx * (w / 2 - 0.3), y + sy * (h / 2 - 0.3), 0) @ RX(90))


def m_console(k, M):
    k.cbox((0, -0.4, 0.3), (2.7, 2.2, 0.6), "hull_grey", 0.06, M)
    k.cbox((0, -0.4, 0.61), (2.3, 1.7, 0.03), "metal_dark", 0, M)
    for i in range(3):
        k.cbox((-0.76 + i * 0.76, 0.05, 0.635), (0.64, 0.5, 0.012), "glow_screen" if i != 1 else "glow_green", 0, M)
    for i in range(10):
        k.cbox((-0.9 + i * 0.2, -0.85, 0.635), (0.1, 0.1, 0.03), "glow_red" if i % 4 == 0 else "metal_bare", 0, M)


def m_warning(k, M):
    k.cbox((0, 0, 0.03), (6.6, 1.0, 0.06), "hazard", 0.015, M)


def m_tray(k, M):
    k.cbox((0, 0, 0.6), (10, 1.4, 0.06), "metal_dark", 0, M)
    for sy in (-1, 1):
        k.cbox((0, sy * 0.68, 0.72), (10, 0.05, 0.24), "metal_dark", 0, M)
    for i in range(5):
        k.tube([(-5, -0.48 + i * 0.24, 0.72), (5, -0.48 + i * 0.24, 0.72)], 0.06, "hull_accent" if i == 2 else "hull_dark", 6, M)
    for x in (-3, 3):
        for sy in (-1, 1):
            k.cbox((x, sy * 0.66, 0.3), (0.08, 0.08, 0.6), "metal_bare", 0, M)


def m_floor_grate(k, M):
    k.cbox((0, 0, 0.03), (6, 6, 0.06), "metal_dark", 0.02, M)
    for i in range(12):
        k.cbox((-2.5 + i * 0.46, 0, 0.09), (0.09, 5.6, 0.06), "metal_bare", 0, M)


def m_floor_stripes(k, M):
    k.cbox((0, 3.6, 0.025), (10, 0.5, 0.05), "hazard", 0.01, M)
    k.cbox((0, -3.6, 0.025), (10, 0.5, 0.05), "hazard", 0.01, M)


def m_crystals(k, M, r):
    for _ in range(r.randint(3, 6)):
        x, y = r.uniform(-1.6, 1.6), r.uniform(-1.6, 1.6)
        h = r.uniform(1.0, 3.2)
        rad = r.uniform(0.16, 0.42)
        B = M @ T(x, y, -0.6) @ RZ(r.uniform(0, 360)) @ RY(r.uniform(-22, 22)) @ RX(90 + r.uniform(-22, 22))
        k.lathe([(rad * 0.7, -0.2), (rad, h * 0.25), (rad * 0.7, h * 0.76), (0.002, h)], 5, "glow_crystal", B)


def m_boulder(k, M, r):
    for _ in range(r.randint(2, 4)):
        x, y = r.uniform(-3, 3), r.uniform(-3, 3)
        rad = r.uniform(0.5, 1.2)
        rows = []
        for ri in range(5):
            lat = -math.pi / 2 + (ri + 0.5) / 5 * math.pi
            rows.append([
                (math.cos(lat) * math.sin(a / 8 * math.tau) * rad * r.uniform(0.76, 1.2),
                 math.sin(lat) * rad * r.uniform(0.76, 1.2),
                 math.cos(lat) * math.cos(a / 8 * math.tau) * rad * r.uniform(0.76, 1.2))
                for a in range(8)
            ])
        k.loft(rows, "wall_rock", M=M @ T(x, y, rad * 0.32) @ RX(90))


def m_lamp(k, M):
    k.tube([(0, 0, 0), (0, 0, 0.9)], 0.04, "metal_dark", 6, M)
    k.lathe([(0.34, 0.0), (0.38, 0.28), (0.1, 0.42)], 10, "metal_dark", M @ T(0, 0, 1.2) @ RX(90), cap1=True)
    k.sphere((0, 0, 1.14), 0.2, "glow_amber", 5, 8, M)


def m_rib(k, M, zone):
    """Structural arch around a one-cell tunnel; the tunnel runs along local Z."""
    mat = "metal_dark" if zone == "metal" else "robot_rust"
    w_h = S / 2 - 0.22
    for sx in (-1, 1):
        k.cbox((sx * w_h, 0, 0), (0.44, S - 2.0, 0.7), mat, 0.05, M)
        k.cbox((0, sx * w_h, 0), (S - 2.0, 0.44, 0.7), mat, 0.05, M)
        for sy in (-1, 1):
            B = M @ T(sx * (w_h - 1.05), sy * (w_h - 1.05), 0) @ RZ(45 * sx * sy)
            k.cbox((0, 0, 0), (0.44, 3.4, 0.7), mat, 0.05, B)
    for sx in (-1, 1):
        if zone == "metal":
            k.cbox((sx * (w_h - 0.3), 0, 0.42), (0.16, 3.4, 0.14), "hazard", 0.02, M)


def _seeded(fn, seed):
    return lambda k, M: fn(k, M, random.Random(seed))


PARTS = {
    "pipes_plain": lambda k, M: m_pipes(k, M, False),
    "pipes_box": lambda k, M: m_pipes(k, M, True),
    "lightbar": m_lightbar,
    "vent": m_vent,
    "console": m_console,
    "warning": m_warning,
    "tray": m_tray,
    "floor_grate": m_floor_grate,
    "floor_stripes": m_floor_stripes,
    "lamp": m_lamp,
    "rib_metal": lambda k, M: m_rib(k, M, "metal"),
    "rib_rock": lambda k, M: m_rib(k, M, "rock"),
}
for variant in range(VARIANTS):
    PARTS["plates_%d" % variant] = _seeded(m_plates, 100 + variant)
    PARTS["crystals_%d" % variant] = _seeded(m_crystals, 200 + variant)
    PARTS["boulder_%d" % variant] = _seeded(m_boulder, 300 + variant)

"""The late-campaign robot roster, the Overseer boss, and the mine family. Nose is +Y."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from mathutils import Vector  # noqa: E402


def begin(name):
    reset_scene()
    return empty(name), Kit("Body"), Kit("Glow")


def finish(root, k, g, filename, muzzles=None, extra=()):
    k.build(root)
    g.build(root, None)
    for part in extra:
        part.build(root)
    if muzzles:
        empty("Muzzle_R", muzzles, root)
        empty("Muzzle_L", (-muzzles[0], muzzles[1], muzzles[2]), root)
    export(filename)


def eye(k, g, M, r, glow="glow_red"):
    k.lathe([(r * 1.35, -r * 0.5), (r * 1.4, 0), (r * 1.1, r * 0.08)], 18, "metal_dark", M)
    g.lathe([(r * 0.95, -r * 0.3), (r * 0.5, -r * 0.05), (r * 0.002, r * 0.04)], 18, glow, M)


def gun(k, g, M, r, length, mat="metal_dark", glow="glow_orange"):
    k.lathe([(r * 1.4, -length * 0.2), (r * 1.4, 0), (r, length * 0.1), (r, length * 0.8), (r * 1.4, length * 0.82), (r * 1.4, length), (r * 0.6, length + 0.01)], 10, mat, M)
    g.lathe([(r * 0.55, length), (r * 0.002, length + 0.02)], 8, glow, M)


def hull(k, keys, sides, mat, plate_mat, seed):
    """A lofted, plated body. keys are (y, width, height) along the nose axis."""
    rows = catmull(keys, 16)
    grid = []
    for y, w, h in rows:
        grid.append([(math.sin(i / sides * math.tau) * w, y, math.cos(i / sides * math.tau) * h) for i in range(sides)])
    k.loft(grid, mat)
    r = random.Random(seed)
    row = 1
    while row < 13:
        end = row + r.randint(2, 3)
        for c in range(sides):
            if r.random() < 0.75:
                k.grid_plate(grid, row, c, min(end, 14), c + 1, r.uniform(0.02, 0.05), 0.02, plate_mat if r.random() < 0.45 else mat)
        row = end


def thrusters(k, g, y, radius, spread, count):
    for i in range(count):
        M = RY(i * 360 / count) @ T(0, y, spread)
        k.lathe([(radius * 0.6, -radius), (radius, 0)][::-1][::-1], 12, "metal_burn", M)
        g.lathe([(0.001, -radius * 0.9), (radius * 0.55, -radius * 0.8)], 12, "glow_engine", M)


def ripper():
    root, k, g = begin("Ripper")
    spin = Kit("SpinBlades")
    hull(k, [(-1.3, 0.3, 0.3), (-0.5, 0.8, 0.65), (0.5, 0.75, 0.6), (1.1, 0.35, 0.3)], 8, "robot_shell", "robot_rust", 1)
    eye(k, g, T(0, 1.05, 0.05), 0.2)
    for sx in (-1, 1):
        H = T(sx * 1.1, 0.6, 0)
        k.cbox((-sx * 0.3, 0, 0), (0.9, 0.5, 0.35), "robot_paint", 0.04, H)
        spin.lathe([(0.05, -0.04), (0.8, -0.04), (0.85, 0), (0.8, 0.04), (0.05, 0.04)], 28, "metal_bare", H @ RZ(0) @ RX(90))
        for i in range(12):
            spin.add([(0.78, 0, -0.03), (1.15, 0, 0.0), (0.82, 0.2, 0.03)], [(0, 1, 2), (2, 1, 0)], "metal_burn", H @ RX(90) @ RY(i * 30))
    thrusters(k, g, -1.25, 0.25, 0.42, 3)
    finish(root, k, g, "ripper.glb", extra=[spin])


def drillback():
    root, k, g = begin("Drillback")
    spin = Kit("SpinDrill")
    hull(k, [(-2.6, 0.9, 0.9), (-1.2, 1.9, 1.7), (0.6, 2.0, 1.8), (1.6, 1.5, 1.4)], 10, "robot_rust", "robot_paint", 2)
    spin.lathe([(1.45, 1.6), (0.9, 3.0), (0.4, 4.2), (0.002, 5.0)], 16, "metal_burn")
    for i in range(3):
        rows = [(math.sin(t * 0.85 + i * 2.1) * (1.45 - t * 0.3), 1.6 + t * 0.7, math.cos(t * 0.85 + i * 2.1) * (1.45 - t * 0.3)) for t in range(5)]
        spin.tube(rows, 0.16, "metal_bare", 8, spline=20)
    for sx in (-1, 1):
        eye(k, g, T(sx * 1.2, 1.5, 0.5), 0.2, "glow_amber")
    thrusters(k, g, -2.6, 0.55, 0.7, 4)
    finish(root, k, g, "drillback.glb", extra=[spin])


def cinder():
    root, k, g = begin("Cinder")
    g.sphere((0, 0, 0), 0.72, "glow_orange", 8, 14)
    for i in range(7):
        a = i * 360 / 7
        k.cbox((0, 0, 0.82), (0.4, 1.3, 0.14), "robot_rust", 0.04, RY(a))
        k.cbox((0, 0.68, 0.76), (0.3, 0.14, 0.14), "hazard", 0.02, RY(a))
    eye(k, g, T(0, 0.76, 0), 0.16, "glow_red")
    thrusters(k, g, -0.9, 0.2, 0.3, 3)
    finish(root, k, g, "cinder.glb")


def hornet():
    root, k, g = begin("Hornet")
    hull(k, [(-1.6, 0.14, 0.14), (-0.6, 0.45, 0.4), (0.5, 0.48, 0.42), (1.2, 0.14, 0.14)], 8, "robot_paint", "robot_shell", 3)
    eye(k, g, T(0, 1.05, 0.02), 0.15)
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        k.loft([[(0.42, 0.5, 0.04), (0.42, -0.6, 0.04), (0.42, -0.6, -0.04), (0.42, 0.5, -0.04)], [(1.8, -0.5, 0.01), (1.8, -1.2, 0.01), (1.8, -1.2, -0.01), (1.8, -0.5, -0.01)]], "robot_shell", M=M)
        gun(k, g, M @ T(0.55, 0.3, -0.25), 0.05, 0.7)
    g.lathe([(0.001, -1.82), (0.12, -1.6)], 10, "glow_engine")
    finish(root, k, g, "hornet.glb", (0.55, 1.05, -0.25))


def spark():
    root, k, g = begin("Spark")
    k.sphere((0, 0, 0), 0.8, "robot_shell", 10, 18)
    for z in (-0.5, 0, 0.5):
        k.lathe([(0.8, z - 0.06), (0.92, z - 0.03), (0.92, z + 0.03), (0.8, z + 0.06)], 20, "metal_bare", RX(90))
    eye(k, g, T(0, 0.78, 0.15), 0.18, "glow_cyan")
    for sx in (-1, 1):
        k.tube([(sx * 0.4, 0.4, -0.2), (sx * 0.85, 1.1, -0.2), (sx * 0.5, 1.75, -0.2)], 0.07, "metal_burn", 8, spline=12)
        g.sphere((sx * 0.5, 1.75, -0.2), 0.12, "glow_cyan", 6, 10)
    finish(root, k, g, "spark.glb", (0.5, 1.9, -0.2))


def longshot():
    root, k, g = begin("Longshot")
    hull(k, [(-1.8, 0.3, 0.3), (-0.8, 0.8, 0.6), (0.4, 0.75, 0.55), (1.2, 0.25, 0.2)], 8, "robot_shell", "robot_paint", 4)
    C = T(0, 0, 0.75)
    for sx in (-1, 1):
        k.cbox((sx * 0.13, 1.3, 0), (0.08, 5.0, 0.22), "metal_dark", 0.02, C)
    g.cbox((0, 1.3, 0), (0.05, 4.9, 0.04), "glow_blue", 0, C)
    for i in range(10):
        k.cbox((0, -0.6 + i * 0.42, 0), (0.5, 0.1, 0.36), "robot_paint" if i % 3 else "hazard", 0.03, C)
    eye(k, g, T(0, 1.1, -0.02), 0.16, "glow_blue")
    finish(root, k, g, "longshot.glb", (0.0, 3.9, 0.75))


def glint():
    root, k, g = begin("Glint")
    g.lathe([(0.001, -1.4), (0.6, -0.2), (0.42, 1.0), (0.001, 1.8)], 6, "glow_crystal")
    for i in range(6):
        k.cbox((0, -0.1, 0.72), (0.2, 1.3, 0.1), "robot_shell", 0.03, RY(i * 60 + 30))
    for sx in (-1, 1):
        gun(k, g, T(sx * 0.7, 0.4, 0), 0.08, 0.9, "metal_bare", "glow_crystal")
    finish(root, k, g, "glint.glb", (0.7, 1.35, 0.0))


def gravitar():
    root, k, g = begin("Gravitar")
    k.sphere((0, 0, 0), 1.4, "metal_dark", 12, 20)
    ring = [(2.0, -0.12), (2.3, -0.12), (2.45, 0), (2.3, 0.12), (2.0, 0.12), (2.0, -0.12)]
    for M in (IDENT, RX(90), RZ(90)):
        k.lathe(ring, 44, "robot_paint", M)
        g.lathe([(1.92, -0.05), (2.0, 0), (1.92, 0.05), (1.92, -0.05)], 44, "glow_violet", M)
    eye(k, g, T(0, 1.38, 0), 0.3, "glow_violet")
    finish(root, k, g, "gravitar.glb", (0.0, 2.2, 0.0))


def warden():
    root, k, g = begin("Warden")
    hull(k, [(-1.4, 0.6, 0.6), (-0.4, 1.2, 1.1), (0.7, 1.05, 0.95), (1.3, 0.4, 0.4)], 8, "hull_white", "hull_grey", 5)
    for w, h in ((1.1, 0.26), (0.26, 1.1)):
        g.cbox((0, 1.15, 0.2), (w, 0.04, h), "glow_green", 0)
    for i in range(4):
        k.tube([(0, -0.5, 0), (1.5, -0.6, 0), (1.7, -1.0, 0)], 0.08, "metal_bare", 8, RY(i * 90 + 45), spline=8)
        g.sphere((1.7, -1.0, 0), 0.14, "glow_green", 6, 8, RY(i * 90 + 45))
    gun(k, g, T(0, 0.9, -0.85), 0.07, 0.8)
    finish(root, k, g, "warden.glb", (0.01, 1.7, -0.85))


def hive():
    root, k, g = begin("Hive")
    k.sphere((0, 0, 0), 3.2, "robot_rust", 10, 16, squash=0.8)
    for i in range(24):
        lat, lon = (i % 5 - 2) * 28, i * 137.5
        M = RY(lon) @ RX(lat) @ T(0, 2.6, 0)
        k.lathe([(0.62, 0), (0.62, 0.55), (0.42, 0.6), (0.42, 0.2)], 6, "robot_shell", M)
        g.lathe([(0.42, 0.2), (0.001, 0.22)], 6, "glow_amber", M)
    eye(k, g, T(0, 3.0, 0.3), 0.4)
    gun(k, g, T(0.9, 2.6, -1.0), 0.12, 1.2)
    finish(root, k, g, "hive.glb", (0.9, 3.8, -1.0))


def sower():
    root, k, g = begin("Sower")
    hull(k, [(-2.0, 0.5, 0.4), (-0.8, 1.2, 0.8), (0.8, 1.1, 0.75), (1.6, 0.4, 0.3)], 8, "robot_shell", "hazard", 6)
    k.cbox((0, -0.5, -0.85), (1.3, 2.2, 0.4), "metal_dark", 0.05)
    for iy in range(5):
        for sx in (-1, 0, 1):
            k.sphere((sx * 0.4, -1.4 + iy * 0.45, -1.1), 0.16, "robot_rust", 5, 8)
    eye(k, g, T(0, 1.45, 0.05), 0.2)
    gun(k, g, T(0.8, 0.8, 0.1), 0.07, 0.9)
    thrusters(k, g, -2.0, 0.3, 0.3, 2)
    finish(root, k, g, "sower.glb", (0.8, 1.75, 0.1))


def wraith():
    root, k, g = begin("Wraith")
    hull(k, [(-1.5, 0.1, 0.1), (-0.5, 0.5, 0.3), (0.6, 0.4, 0.25), (1.6, 0.05, 0.05)], 6, "metal_dark", "hull_dark", 7)
    for sx in (-1, 1):
        for a, l in ((35, 2.0), (0, 2.4), (-35, 2.0)):
            B = SC(sx, 1, 1) @ T(0.3, 0.2, 0) @ RZ(-a)
            k.add([(0, 0.25, 0.03), (0, -0.25, 0.03), (l, -0.2, 0.0), (l + 0.5, 0.25, 0.0)], [(0, 1, 2, 3), (3, 2, 1, 0)], "metal_burn", B)
    eye(k, g, T(0, 1.2, 0.02), 0.12, "glow_violet")
    finish(root, k, g, "wraith.glb")


def phase():
    root, k, g = begin("Phase")
    k.lathe([(0.001, -1.5), (0.9, 0), (0.001, 1.5)], 4, "robot_shell", IDENT, phase=math.pi / 4)
    for i in range(4):
        g.cbox((0.5, 0, 0), (0.05, 0.06, 1.3), "glow_violet", 0, RY(i * 90 + 45))
    for i in range(3):
        g.lathe([(1.2 + i * 0.3, -0.03), (1.26 + i * 0.3, 0), (1.2 + i * 0.3, 0.03), (1.2 + i * 0.3, -0.03)], 32, "glow_violet", RX(i * 60))
    eye(k, g, T(0, 0.9, 0.3), 0.14, "glow_violet")
    gun(k, g, T(0.55, 0.4, -0.35), 0.06, 0.8)
    finish(root, k, g, "phase.glb", (0.55, 1.25, -0.35))


def siege():
    root, k, g = begin("Siege")
    hull(k, [(-2.6, 1.4, 1.2), (-1.0, 2.5, 1.9), (1.0, 2.4, 1.8), (2.2, 1.5, 1.2)], 8, "robot_shell", "robot_paint", 8)
    for sx in (-1, 1):
        M = SC(sx, 1, 1) @ T(2.8, 0.2, 0.5)
        k.cbox((0, 0, 0), (1.5, 2.6, 2.0), "robot_paint", 0.1, M)
        for ix in range(3):
            for iz in range(3):
                p = M @ T(-0.45 + ix * 0.45, 1.32, -0.6 + iz * 0.6)
                k.lathe([(0.15, -0.1), (0.15, 0.0), (0.08, 0.004)], 10, "metal_dark", p)
                g.lathe([(0.001, -0.06), (0.08, -0.05)], 10, "glow_red", p @ RZ(180))
    eye(k, g, T(0, 2.2, 0.3), 0.4)
    finish(root, k, g, "siege.glb", (2.8, 1.8, 0.5))


def overseer():
    root, k, g = begin("Overseer")
    spin = Kit("SpinCrown")
    hull(k, [(-7, 3, 3), (-3.5, 7, 6.5), (2.5, 7.5, 7), (6, 4, 3.8)], 12, "robot_shell", "robot_paint", 9)
    eye(k, g, T(0, 6.0, 0.6), 2.0)
    for a in (0, 72, 144, 216, 288):
        B = RY(a) @ T(0, 2.6, 7.0)
        eye(k, g, B, 0.6, "glow_amber")
    for sx in (-1, 1):
        M = SC(sx, 1, 1) @ T(9.0, 0.8, -0.5)
        k.cbox((-1.2, -1.0, 0), (3.5, 4.5, 3.5), "robot_rust", 0.3, M)
        for a in (0, 90, 180, 270):
            gun(k, g, M @ RY(a) @ T(0, 1.4, 0.8), 0.32, 5.0, "metal_burn")
    spin.lathe([(8.0, -0.6), (9.2, -0.6), (9.8, 0), (9.2, 0.6), (8.0, 0.6), (8.0, -0.6)], 64, "wall_core", RX(90))
    for i in range(16):
        spin.cbox((9.6, 0, 0), (3.0, 0.8, 1.4), "hazard" if i % 4 == 0 else "robot_shell", 0.1, RZ(i * 22.5))
    g.lathe([(7.9, -0.3), (8.0, 0), (7.9, 0.3), (7.9, -0.3)], 64, "glow_core", RX(90))
    thrusters(k, g, -7.2, 1.2, 3.0, 4)
    k.text("OVERSEER", T(0, -2.0, 7.3) @ RX(0), 1.6, "hazard", 0.08)
    # The main eye is its weak point (the game checks hits against this marker).
    empty("Weak_Eye", (0, 7.2, 0.6), root)
    finish(root, k, g, "overseer.glb", (9.0, 7.5, -0.5), extra=[spin])


def mine_prox():
    root, k, g = begin("MineProx")
    k.sphere((0, 0, 0), 0.62, "robot_shell", 10, 16)
    k.lathe([(0.65, -0.05), (0.65, 0.05)], 24, "hazard", RX(90))
    for i in range(16):
        y = (i + 0.5) / 8 - 1
        r = math.sqrt(1 - y * y)
        d = Vector((math.cos(i * 2.4) * r, y, math.sin(i * 2.4) * r))
        M = T(*(d * 0.6)) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
        k.lathe([(0.08, 0), (0.05, 0.3), (0.002, 0.44)], 8, "metal_bare", M)
    g.sphere((0, 0, 0.62), 0.12, "glow_red", 6, 8)
    finish(root, k, g, "mine_prox.glb")


def mine_seeker():
    root, k, g = begin("MineSeeker")
    k.lathe([(0.001, -0.7), (0.5, -0.5), (0.55, 0.2), (0.2, 0.8), (0.002, 1.0)], 12, "robot_paint", IDENT)
    for a in (45, 135, 225, 315):
        k.add([(0, -0.6, 0.45), (0, -0.1, 0.5), (0, -0.4, 1.0), (0, -0.85, 0.95)], [(0, 1, 2, 3), (3, 2, 1, 0)], "metal_dark", RY(a))
    g.lathe([(0.001, -0.82), (0.32, -0.66)], 12, "glow_engine")
    eye(k, g, T(0, 0.7, 0.2), 0.12, "glow_red")
    finish(root, k, g, "mine_seeker.glb")


def mine_tripwire():
    root, k, g = begin("MineTripwire")
    k.cbox((0, -0.25, 0), (1.1, 0.5, 1.1), "robot_shell", 0.1)
    k.cbox((0, -0.4, 0), (1.5, 0.2, 1.5), "hazard", 0.04)
    k.lathe([(0.34, 0), (0.3, 0.4), (0.18, 0.5), (0.12, 0.3)], 14, "metal_bare")
    g.lathe([(0.12, 0.3), (0.001, 0.36)], 12, "glow_red")
    finish(root, k, g, "mine_tripwire.glb")


def mine_pulse():
    root, k, g = begin("MinePulse")
    g.sphere((0, 0, 0), 0.5, "glow_cyan", 10, 16)
    for M in (IDENT, RX(90), RZ(90)):
        k.lathe([(0.72, -0.05), (0.86, -0.05), (0.9, 0), (0.86, 0.05), (0.72, 0.05), (0.72, -0.05)], 32, "metal_bare", M)
    for i in range(6):
        k.tube([(0, 0, 0.55), (0, 0, 0.75)], 0.05, "metal_dark", 6, RY(i * 60))
    finish(root, k, g, "mine_pulse.glb")


def shade():
    root, k, g = begin("Shade")
    hull(k, [(-1.4, 0.2, 0.2), (-0.5, 0.7, 0.5), (0.6, 0.65, 0.45), (1.3, 0.15, 0.12)], 8, "hull_dark", "metal_dark", 11)
    eye(k, g, T(0, 1.1, 0.02), 0.16, "glow_violet")
    for sx in (-1, 1):
        gun(k, g, T(sx * 0.55, 0.3, -0.3), 0.06, 0.9, "metal_dark", "glow_violet")
        g.cbox((sx * 0.68, -0.3, 0.1), (0.02, 1.0, 0.05), "glow_violet", 0)
    thrusters(k, g, -1.4, 0.2, 0.2, 2)
    finish(root, k, g, "shade.glb", (0.55, 1.2, -0.3))


def revenant():
    root, k, g = begin("Revenant")
    hull(k, [(-2.2, 0.4, 0.4), (-1.0, 1.0, 0.75), (0.8, 0.9, 0.7), (1.8, 0.3, 0.2)], 10, "metal_dark", "robot_shell", 12)
    C = T(0, 0, 0.82)
    for sx in (-1, 1):
        k.cbox((sx * 0.14, 1.0, 0), (0.09, 3.8, 0.24), "hull_dark", 0.02, C)
    g.cbox((0, 1.0, 0), (0.06, 3.7, 0.04), "glow_violet", 0, C)
    eye(k, g, T(0, 1.6, 0.0), 0.2, "glow_violet")
    for sx in (-1, 1):
        gun(k, g, T(sx * 1.0, 0.4, -0.2), 0.09, 1.1, "metal_burn", "glow_violet")
    thrusters(k, g, -2.2, 0.32, 0.32, 3)
    finish(root, k, g, "revenant.glb", (1.0, 1.5, -0.2))


for build in (shade, revenant, ripper, drillback, cinder, hornet, spark, longshot, glint, gravitar, warden, hive, sower, wraith, phase, siege, overseer, mine_prox, mine_seeker, mine_tripwire, mine_pulse):
    build()

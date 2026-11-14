"""The rogue mining machines. One script, one GLB per robot.

tick     - small fast swarm drone with spinning blade ring
lancer   - rail-cannon gunship
bulwark  - heavy armoured mining hauler with shoulder cannons
sentry   - wall-mounted turret (the 'Head' node aims at the player)

Nose is +Y. Godot animates nodes named Spin* and aims nodes named Head.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from kit import catmull, glow_disk, nozzle, thruster_quad  # noqa: E402


def eye(k, g, M, r):
    """Armoured optic: stepped bezel, lens hood and a glowing iris."""
    k.lathe([(r * 1.35, -r * 0.5), (r * 1.4, 0), (r * 1.25, r * 0.08), (r * 1.1, r * 0.08), (r * 1.05, -r * 0.2)], 20, "metal_dark", M)
    k.lathe([(r * 1.04, -r * 0.2), (r * 0.5, -r * 0.5)], 20, "metal_bare", M)
    g.lathe([(r * 0.92, -r * 0.42), (r * 0.5, -r * 0.08), (r * 0.002, r * 0.02)], 20, "glow_red", M)


def gun(k, g, M, r=0.08, l=1.0, mat="metal_dark"):
    k.lathe([(r * 1.5, -l * 0.25), (r * 1.6, 0), (r * 1.1, l * 0.05), (r, l * 0.75), (r * 1.5, l * 0.76), (r * 1.5, l * 0.95), (r * 0.7, l * 0.97), (r * 0.6, l * 0.7)], 10, mat, M)
    for a in (0, 90, 180, 270):
        k.cbox((0, l * 0.4, r * 1.2), (r * 0.5, l * 0.5, r * 0.25), "metal_bare", 0, M @ RY(a))
    g.lathe([(r * 0.55, l * 0.72), (r * 0.002, l * 0.73)], 8, "glow_orange", M)


def faceted_shell(k, radius, rings, segs, gap, mat, M=IDENT, top=1.0, bottom=1.0, y_squash=1.0):
    """Sphere of separate armour plates with dark gaps between them."""
    rnd = random.Random(int(radius * 1000))
    for ri in range(rings):
        lat0 = -math.pi / 2 + ri / rings * math.pi
        lat1 = -math.pi / 2 + (ri + 1) / rings * math.pi
        if lat1 < -math.pi / 2 * bottom or lat0 > math.pi / 2 * top:
            continue
        ring_segs = max(4, int(segs * math.cos((lat0 + lat1) / 2) + 0.5))
        for si in range(ring_segs):
            lo0 = (si + gap) / ring_segs * math.tau
            lo1 = (si + 1 - gap) / ring_segs * math.tau
            la0, la1 = lat0 + gap / rings * 3, lat1 - gap / rings * 3
            lift = rnd.uniform(0.0, 0.05) * radius
            def pt(lat, lo, rr):
                return (math.cos(lat) * math.sin(lo) * rr, math.sin(lat) * rr * y_squash, math.cos(lat) * math.cos(lo) * rr)
            rr = radius + lift
            n = 3
            outer = [[pt(la0 + (la1 - la0) * a / n, lo0 + (lo1 - lo0) * b / n, rr) for b in range(n + 1)] for a in range(n + 1)]
            inner = [[pt(la0 + (la1 - la0) * a / n, lo0 + (lo1 - lo0) * b / n, rr - radius * 0.08) for b in range(n + 1)] for a in range(n + 1)]
            v = [p for row in outer for p in row] + [p for row in inner for p in row]
            f = []
            cnt = n + 1
            total = cnt * cnt
            for a in range(n):
                for b in range(n):
                    f.append((a * cnt + b, (a + 1) * cnt + b, (a + 1) * cnt + b + 1, a * cnt + b + 1))
            for t in range(n):
                f.append((t, t + 1, t + 1 + total, t + total))
                f.append(((n * cnt) + t + 1, n * cnt + t, n * cnt + t + total, n * cnt + t + 1 + total))
                f.append((t * cnt + n, (t + 1) * cnt + n, (t + 1) * cnt + n + total, t * cnt + n + total)[::-1])
                f.append(((t + 1) * cnt, t * cnt, t * cnt + total, (t + 1) * cnt + total)[::-1])
            k.add(v, f, mat, M)


# =========================================================================== TICK
def tick():
    reset_scene()
    root = empty("Tick")
    k, g = Kit("Body"), Kit("Glow")
    spin = Kit("SpinRing")
    k.sphere((0, 0, 0), 0.78, "metal_dark", 10, 18)
    faceted_shell(k, 0.92, 7, 12, 0.05, "robot_paint", M=RX(90))
    eye(k, g, T(0, 0.84, 0), 0.27)
    # Sensor pods flanking the eye.
    for sx in (-1, 1):
        for z, r in ((0.2, 0.07), (-0.2, 0.05)):
            p = T(sx * 0.46, 0.73, z)
            k.lathe([(r * 1.3, -0.1), (r * 1.3, 0.04), (r * 0.8, 0.05)], 10, "metal_bare", p)
            g.lathe([(r * 0.78, 0.05), (r * 0.001, 0.058)], 10, "glow_amber", p)
    # Spinning cutter ring: blades on a split collar.
    spin.lathe([(1.08, -0.1), (1.12, -0.08), (1.12, 0.08), (1.08, 0.1)], 40, "metal_bare", RX(90))
    spin.lathe([(0.95, 0.1), (0.95, -0.1)], 40, "metal_dark", RX(90))
    for i in range(10):
        a = i * 36
        B = RZ(a)
        spin.add([(1.08, -0.07, 0.03), (1.08, 0.07, 0.03), (1.62, 0.16, 0.012), (1.46, -0.08, 0.012)], [(0, 1, 2, 3), (3, 2, 1, 0)], "metal_bare", B)
        spin.cbox((1.2, 0, 0.0), (0.26, 0.09, 0.1), "robot_shell", 0.018, B)
    # Rear thruster cluster.
    for a in (0, 120, 240):
        M = RY(a) @ T(0, -0.62, 0.42)
        k.lathe([(0.16, 0.1), (0.2, -0.05), (0.26, -0.3), (0.24, -0.32), (0.16, -0.15)][::-1], 14, "metal_burn", M)
        g.lathe([(0.001, -0.18), (0.16, -0.14)], 14, "glow_engine", M)
    # Twin chin guns.
    for sx in (-1, 1):
        gun(k, g, T(sx * 0.32, 0.5, -0.56), 0.055, 0.7)
    k.cbox((0, 0.32, -0.6), (0.8, 0.5, 0.14), "robot_shell", 0.03)
    # Whip antennae.
    for sx, ln in ((-1, 0.6), (1, 0.42)):
        k.tube([(sx * 0.22, -0.3, 0.86), (sx * 0.28, -0.5, 0.86 + ln * 0.8), (sx * 0.38, -0.8, 0.86 + ln)], 0.012, "metal_dark", 5, spline=6)
        g.sphere((sx * 0.38, -0.8, 0.86 + ln), 0.022, "glow_red", 4, 6)
    bo = k.build(root)
    g.build(root, None)
    spin.build(root)
    empty("Muzzle_R", (0.32, 1.24, -0.56), root)
    empty("Muzzle_L", (-0.32, 1.24, -0.56), root)
    print("[tick]", k.tris + g.tris + spin.tris)
    export("tick.glb")


# =========================================================================== LANCER
def lancer():
    reset_scene()
    root = empty("Lancer")
    k, g = Kit("Body"), Kit("Glow")
    keys = [(-2.4, 0.5, 0.35), (-1.6, 0.86, 0.52), (-0.3, 1.0, 0.62), (0.9, 0.82, 0.54), (1.8, 0.5, 0.32), (2.5, 0.16, 0.12)]
    rows = catmull(keys, 22)

    def sec(y, w, h):
        return [(0, y, h * 1.18), (w * 0.55, y, h), (w, y, h * 0.2), (w * 0.9, y, -h * 0.5), (w * 0.4, y, -h), (0, y, -h * 1.12), (-w * 0.4, y, -h), (-w * 0.9, y, -h * 0.5), (-w, y, h * 0.2), (-w * 0.55, y, h)]

    grid = [sec(*r) for r in rows]
    k.loft(grid, "robot_shell")
    rng = random.Random(3)
    r = 1
    while r < 19:
        r2 = r + rng.randint(2, 3)
        for c in range(10):
            if rng.random() < 0.82:
                k.grid_plate(grid, r, c, min(r2, 20), c + 1, rng.uniform(0.02, 0.05), 0.024, "robot_paint" if c in (1, 8) or rng.random() < 0.18 else "robot_shell")
        r = r2

    # Rail cannon along the spine: twin rails, capacitor coils and a glowing bore.
    C = T(0, 0, 0.92)
    for sx in (-1, 1):
        k.cbox((sx * 0.16, 1.2, 0), (0.1, 5.0, 0.26), "metal_dark", 0.024, C)
        k.cbox((sx * 0.125, 1.2, 0), (0.03, 4.9, 0.14), "metal_bare", 0, C)
    g.cbox((0, 1.2, 0), (0.08, 4.86, 0.04), "glow_cyan", 0, C)
    for i in range(11):
        y = -0.9 + i * 0.42
        k.cbox((0, y, 0), (0.62, 0.13, 0.44), "robot_shell" if i % 3 else "robot_paint", 0.04, C)
        k.cbox((0, y, 0.24), (0.18, 0.08, 0.04), "metal_bare", 0.01, C)
        if i % 2 == 0:
            g.cbox((0.32, y, 0), (0.02, 0.05, 0.2), "glow_cyan", 0, C)
            g.cbox((-0.32, y, 0), (0.02, 0.05, 0.2), "glow_cyan", 0, C)
    k.cbox((0, 3.85, 0), (0.52, 0.5, 0.42), "metal_dark", 0.06, C)
    for sx in (-1, 1):
        k.cbox((sx * 0.3, 3.85, 0), (0.16, 0.3, 0.2), "metal_burn", 0.02, C)
    # Cannon power trunk.
    for sx in (-1, 1):
        k.tube([(sx * 0.3, -1.7, 0.4), (sx * 0.6, -1.4, 0.72), (sx * 0.42, -1.0, 0.88)], 0.05, "metal_bare", 8, spline=10)

    # Twin heads with sensor eye under the nose.
    eye(k, g, T(0, 2.48, -0.05), 0.19)
    for sx in (-1, 1):
        eye(k, g, T(sx * 0.5, 1.56, 0.12) @ RZ(sx * -22), 0.09)

    # Outrigger engine pods on swept pylons.
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        pyl = [[(0.8, 0.2, 0.2), (0.8, 0.3, -0.1), (0.8, -1.2, -0.1), (0.8, -1.1, 0.2)], [(2.0, -0.7, 0.08), (2.0, -0.6, -0.08), (2.0, -1.5, -0.08), (2.0, -1.4, 0.08)]]
        k.loft(pyl, "robot_shell", M=M)
        P = M @ T(2.14, -0.6, 0)
        k.lathe([(0.02, 1.2), (0.26, 0.92), (0.34, 0.5), (0.36, -0.5), (0.3, -1.1)][::-1], 16, "robot_paint", P)
        for y in (-0.8, -0.2, 0.42):
            k.lathe([(0.35, y), (0.385, y + 0.015), (0.385, y + 0.09), (0.35, y + 0.105)], 16, "metal_dark", P)
        Bell = nozzle(k, P @ T(0, -1.1, 0), 0.26, 0.42, petals=10)
        glow_disk(g, Bell @ T(0, -0.06, 0), 0.2)
        gun(k, g, P @ T(0, 0.9, -0.4), 0.05, 0.9)
        k.cbox((0, 0.7, -0.27), (0.08, 0.5, 0.16), "metal_dark", 0.02, P)
        for sign in (1, -1):
            vane = [(0, 0.1, 0.34), (0, -0.7, 0.34), (0, -1.0, 0.8), (0, -0.55, 0.8)]
            k.add(vane, [(0, 1, 2, 3), (3, 2, 1, 0)], "robot_shell", P @ RY(sign * 42))
        thruster_quad(k, (0, -0.4, 0), M @ T(0.82, 0.8, 0.04) @ RY(90), 0.13)

    # Belly: magazine, vents, stencil.
    k.cbox((0, -0.5, -0.74), (0.8, 1.7, 0.2), "metal_dark", 0.05)
    for i in range(8):
        k.cbox((0, -1.15 + i * 0.18, -0.86), (0.6, 0.09, 0.04), "hazard", 0.01)
    k.text("L-404", T(0.76, -0.8, 0.28) @ RY(90) @ RZ(90), 0.26, "metal_dark", 0.01)
    k.text("L-404", T(-0.76, -0.8, 0.28) @ RY(-90) @ RZ(-90), 0.26, "metal_dark", 0.01)

    k.build(root)
    g.build(root, None)
    empty("Muzzle_R", (2.14, 1.16, -0.4), root)
    empty("Muzzle_L", (-2.14, 1.16, -0.4), root)
    empty("Muzzle_Main", (0, 4.15, 0.92), root)
    print("[lancer]", k.tris + g.tris)
    export("lancer.glb")


# =========================================================================== BULWARK
def bulwark():
    reset_scene()
    root = empty("Bulwark")
    k, g = Kit("Body"), Kit("Glow")
    spin = Kit("SpinCore")
    N = 8

    def ring(y, r, z_off=0.0, n=N):
        return [(math.sin((i + 0.5) / n * math.tau) * r, y, math.cos((i + 0.5) / n * math.tau) * r * 0.82 + z_off) for i in range(n)]

    hull_keys = [(-2.6, 1.6), (-2.2, 2.2), (-1.0, 2.55), (0.9, 2.5), (1.9, 2.1), (2.5, 1.5)]
    rows = catmull(hull_keys, 18)
    grid = [ring(y, r) for y, r in rows]
    # Subdivided ring so plates have room.
    dense = []
    for row in grid:
        d = []
        for i in range(N):
            a, b = Vector(row[i]), Vector(row[(i + 1) % N])
            d += [tuple(a.lerp(b, t / 3)) for t in range(3)]
        dense.append(d)
    k.loft(dense, "robot_shell")
    rng = random.Random(77)
    for seg in range(N):
        c0 = seg * 3
        r = 1
        while r < 15:
            r2 = min(r + rng.randint(2, 3), 16)
            k.grid_plate(dense, r, c0, r2, c0 + 3, rng.uniform(0.03, 0.08), 0.03, "robot_paint" if seg in (0, 7) and r < 12 else ("robot_rust" if rng.random() < 0.25 else "robot_shell"))
            r = r2 + 0
        # Bolted corner rib along the hull edge.
        for rr in range(2, 14, 3):
            a = Vector(dense[rr][c0])
            b = Vector(dense[rr + 2][c0])
            n = Vector((a.x, 0, a.z)).normalized()
            k.stud_row(a + n * 0.08, b + n * 0.08, 4, n, 0.05, 0.06, "metal_bare")

    # Bow armour face, eye slit and dozer jaw.
    F = T(0, 2.42, 0)
    k.lathe([(1.2, -0.1), (1.56, 0.04), (1.5, 0.12), (1.24, 0.06), (1.02, 0.1)], 8, "robot_paint", F, phase=math.pi / 8)
    for i, x in enumerate((-0.82, 0, 0.82)):
        eye(k, g, T(x, 2.5, 0.3 if i != 1 else 0.48), 0.2 if i != 1 else 0.3)
    for i in range(7):
        x = -1.2 + i * 0.4
        k.cbox((x, 2.75, -1.08), (0.3, 0.7, 0.36), "metal_burn", 0.05)
        k.add([(-0.15, 0, 0.1), (0.15, 0, 0.1), (0, 0.5, -0.05)], [(0, 1, 2), (2, 1, 0)], "metal_bare", T(x, 3.08, -1.08))
    k.cbox((0, 2.5, -1.08), (3.1, 0.3, 0.54), "robot_rust", 0.06)
    k.cbox((0, 2.5, -1.08), (2.6, 0.36, 0.12), "hazard", 0.02)

    # Shoulder gun mounts: quad rotary barrels on recoil housings.
    for sx in (-1, 1):
        M = SC(sx, 1, 1) @ T(2.7, 0.3, 0.55)
        k.lathe([(0.66, -1.4), (0.76, -1.1), (0.8, 0.4), (0.68, 0.9), (0.5, 1.0)], 12, "robot_paint", M, cap0=True)
        for y in (-0.9, -0.2, 0.3):
            k.lathe([(0.8, y), (0.86, y + 0.02), (0.86, y + 0.16), (0.8, y + 0.18)], 12, "metal_dark", M)
        k.cbox((-0.7, -0.4, 0), (0.7, 1.4, 0.7), "metal_dark", 0.08, M)
        for a in (45, 135, 225, 315):
            B = M @ RY(a) @ T(0, 0.9, 0.26)
            gun(k, g, B, 0.12, 2.1, "metal_burn")
        k.lathe([(0.48, 2.3), (0.5, 2.46), (0.1, 2.48)], 12, "metal_dark", M)
        k.lathe([(0.5, 1.5), (0.52, 1.6), (0.1, 1.62)], 12, "metal_dark", M)
        # Missile cell above each mount.
        k.cbox((0, -0.5, 1.0), (1.26, 1.5, 0.5), "robot_shell", 0.07, M)
        for ix in range(3):
            for iz in range(2):
                p = M @ T(-0.38 + ix * 0.38, 0.26, 0.88 + iz * 0.26)
                k.lathe([(0.12, -0.03), (0.15, 0), (0.12, 0.002), (0.09, -0.08)][::-1], 10, "metal_bare", p)
                g.lathe([(0.001, -0.06), (0.09, -0.05)], 10, "glow_red", p @ RZ(180))

    # Open reactor throat on top with a rotating glowing core.
    k.lathe([(1.1, -0.4), (1.3, 0.0), (1.2, 0.14), (0.95, 0.14), (0.85, -0.3)], 24, "metal_dark", T(0, -0.4, 2.0) @ RX(90))
    for i in range(12):
        k.cbox((1.2, 0, 0.1), (0.3, 0.16, 0.12), "hazard", 0.02, T(0, -0.4, 2.0) @ RZ(i * 30))
    g.sphere((0, -0.4, 2.0), 0.72, "glow_core", 8, 14)
    for i in range(3):
        spin.lathe([(0.84, -0.05), (0.88, 0), (0.84, 0.05)], 24, "metal_bare", RZ(i * 60) @ RX(90))
    for sx in (-1, 1):
        k.tube([(sx * 1.1, -2.6, 1.3), (sx * 1.6, -1.8, 1.9), (sx * 1.2, -0.5, 2.1)], 0.09, "metal_bare", 8, spline=12)
        k.tube([(sx * 1.4, -2.5, 1.0), (sx * 1.85, -1.5, 1.72), (sx * 1.25, -0.2, 1.98)], 0.06, "robot_rust", 8, spline=12)

    # Rear drive: four huge bells.
    for sx, sz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        M = T(sx * 0.9, -2.5, sz * 0.72)
        Bell = nozzle(k, M, 0.56, 0.86, petals=14)
        glow_disk(g, Bell @ T(0, -0.1, 0), 0.42)
    k.cbox((0, -2.56, 0), (0.5, 0.2, 2.2), "robot_shell", 0.05)
    k.text("BULWARK", T(0, 0.3, -2.14) @ RX(180), 0.5, "hazard", 0.02)

    k.build(root)
    g.build(root, None)
    sp = spin.build(root)
    sp.location = (0, -0.4, 2.0)
    for sx, name in ((1, "Muzzle_R"), (-1, "Muzzle_L")):
        empty(name, (sx * 2.7, 3.4, 0.55), root)
    empty("Muzzle_Main", (0, 2.6, 2.8), root)
    print("[bulwark]", k.tris + g.tris + spin.tris)
    export("bulwark.glb")


# =========================================================================== SENTRY
def sentry():
    reset_scene()
    root = empty("Sentry")
    base, g = Kit("Base"), Kit("BaseGlow")
    # Base plate sits on the wall: its normal is local +Y.
    base.lathe([(1.5, -0.05), (1.55, 0.05), (1.3, 0.28), (0.95, 0.3), (0.85, 0.5), (0.78, 0.52)], 8, "robot_shell", IDENT, phase=math.pi / 8)
    base.lathe([(1.34, 0.0), (1.34, 0.14)], 8, "hazard", IDENT, phase=math.pi / 8)
    for i in range(8):
        B = RY(i * 45 + 22.5) @ T(0, 0.14, 1.28)
        base.lathe([(0.08, 0), (0.08, 0.05), (0.04, 0.1)], 6, "metal_bare", B)
    for i in range(4):
        g.cbox((0, 0.2, 1.15), (0.3, 0.02, 0.06), "glow_amber", 0, RY(i * 90))
    base.lathe([(0.78, 0.5), (0.72, 0.8), (0.6, 0.86)], 16, "metal_dark", IDENT, cap1=True)
    base.build(root)
    g.build(root, None)

    head = empty("Head", (0, 1.25, 0), root)
    h, hg = Kit("HeadMesh"), Kit("HeadGlow")
    faceted_shell(h, 0.78, 5, 10, 0.05, "robot_paint", M=RX(90))
    h.sphere((0, 0, 0), 0.72, "metal_dark", 8, 14)
    eye(h, hg, T(0, 0.74, 0.26), 0.15)
    for sx in (-1, 1):
        G = T(sx * 0.36, 0.5, -0.18)
        gun(h, hg, G, 0.1, 1.5, "metal_burn")
        h.cbox((sx * 0.36, 0.36, -0.18), (0.32, 0.6, 0.32), "robot_shell", 0.05)
    h.cbox((0, -0.6, 0), (0.6, 0.6, 0.5), "robot_shell", 0.06)
    for i in range(5):
        h.cbox((0, -0.92, -0.16 + i * 0.08), (0.46, 0.03, 0.03), "metal_bare")
    h.build(head)
    hg.build(head, None)
    empty("Muzzle_R", (0.36, 2.05, -0.18), head)
    empty("Muzzle_L", (-0.36, 2.05, -0.18), head)
    print("[sentry]", base.tris + g.tris + h.tris + hg.tris)
    export("sentry.glb")


tick()
lancer()
bulwark()
sentry()

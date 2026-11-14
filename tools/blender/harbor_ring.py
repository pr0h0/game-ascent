"""Harbor Ring: the station at home, detailed enough to hold up in close shots.

The ring lies in the XY plane around +Z (Godot's Y), radius 70. Its docking arm points
along -Y (Godot's +Z), ending at the bay the ship returns to.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import RX, RZ, T, Kit, empty, export, reset_scene  # noqa: E402

R = 70.0
SEGMENTS = 24
SPOKES = 6


def habitat(k, g):
    arc = 360.0 / SEGMENTS
    length = math.tau * R / SEGMENTS
    for i in range(SEGMENTS):
        a = i * arc
        M = RZ(a) @ T(R, 0, 0)
        joint = RZ(a + arc / 2) @ T(R, 0, 0)
        k.cbox((0, 0, 0), (9.0, length * 0.86, 10.5), "hull_grey", 0.5, M)
        k.cbox((0, 0, 5.4), (6.4, length * 0.72, 0.5), "hull_dark", 0.1, M)
        k.cbox((0, 0, -5.4), (6.4, length * 0.72, 0.5), "hull_dark", 0.1, M)
        k.cbox((4.65, 0, 0), (0.4, length * 0.7, 7.4), "metal_dark", 0.05, M)
        k.cbox((-4.65, 0, 0), (0.4, length * 0.7, 7.4), "metal_dark", 0.05, M)
        k.cbox((0, 0, 0), (11.0, 2.4, 12.4), "hull_dark", 0.3, joint)
        k.cbox((0, 0, 6.3), (3.4, 2.9, 0.8), "hazard", 0.05, joint)
        k.cbox((0, 0, -6.3), (3.4, 2.9, 0.8), "hazard", 0.05, joint)
        # Rows of lit windows, broken up so they read as cabins.
        for row in (2.5, 0.0, -2.5):
            for w in range(-5, 6):
                if (w + row * 2 + i) % 5 == 0:
                    continue
                y = w * length * 0.062
                g.cbox((4.92, y, row), (0.12, length * 0.046, 1.0), "glow_amber" if (w + i) % 3 else "glow_white", 0, M)
                g.cbox((-4.92, y, row), (0.12, length * 0.046, 1.0), "glow_white" if (w + i) % 4 else "glow_amber", 0, M)
        if i % 2 == 0:
            for side in (-1, 1):
                k.tube([(2.4, -length * 0.3, side * 6.7), (2.4, length * 0.3, side * 6.7)], 0.8, "metal_bare", 8, M)
                k.tube([(-2.4, -length * 0.3, side * 6.7), (-2.4, length * 0.3, side * 6.7)], 0.8, "metal_bare", 8, M)
        if i % 3 == 0:
            for fin in range(-3, 4):
                k.cbox((fin * 1.5, 0, 8.3), (0.28, length * 0.56, 4.0), "metal_dark", 0.02, M)
            k.cbox((0, 0, 6.4), (10.0, length * 0.6, 0.5), "hull_accent", 0.06, M)
        if i % 4 == 1:
            k.cbox((5.8, 0, 0), (2.2, 6.0, 6.0), "hull_accent", 0.3, M)
            k.tube([(6.9, 0, 0), (9.0, 0, 0)], 1.8, "metal_dark", 12, M)
            g.sphere((9.1, 0, 0), 1.2, "glow_blue", 6, 12, M)
        if i % 6 == 2:
            k.tube([(5, 0, 0), (15, 0, 3)], 0.14, "metal_bare", 5, M)
            g.sphere((15, 0, 3), 0.35, "glow_red" if i % 12 == 2 else "glow_green", 5, 8, M)
        g.sphere((0, 0, 8.6), 0.4, "glow_red" if i % 2 else "glow_green", 5, 8, M)


def spokes(k, g):
    for i in range(SPOKES):
        M = RZ(i * 360.0 / SPOKES + 15.0)
        k.tube([(14, 0, 0), (66, 0, 0)], 1.7, "hull_grey", 12, M)
        for side in (-1, 1):
            k.tube([(16, side * 3.2, 0), (65, side * 3.2, 0)], 0.42, "metal_bare", 6, M)
        for s in range(9):
            x = 20.0 + s * 5.5
            k.cbox((x, 0, 0), (0.5, 7.0, 0.6), "metal_dark", 0.02, M)
            k.cbox((x, 0, 0), (2.5, 4.3, 4.3), "hull_dark", 0.2, M) if s % 3 == 1 else None
            if s % 2 == 0:
                g.cbox((x + 2.6, 0, 1.75), (2.2, 0.8, 0.12), "glow_white", 0, M)
        k.cbox((42, 0, 0), (9, 8, 7), "hull_accent", 0.5, M)
        g.cbox((42, 0, 3.58), (6.4, 5.4, 0.1), "glow_screen", 0, M)


def hub(k, g):
    M = RX(90)
    k.lathe([(15, -30), (17.5, -27), (18, -20), (13, -16), (12, -8), (12, 8), (13, 16), (18, 20), (17.5, 27), (15, 30)], 36, "hull_grey", M, cap0=True, cap1=True)
    for h in (-26, -22, 22, 26):
        k.lathe([(18.2, h - 0.8), (19.0, h - 0.4), (19.0, h + 0.4), (18.2, h + 0.8)], 36, "hull_dark", M)
    for h in (-11.0, -3.5, 3.5, 11.0):
        k.lathe([(12.0, h - 1.2), (13.2, h - 0.8), (13.2, h + 0.8), (12.0, h + 1.2)], 36, "hull_dark", M)
    # Windows round the hub's two drums.
    for i in range(36):
        a = i * 10.0
        for z, mat in ((24.0, "glow_amber"), (-24.0, "glow_white")):
            if i % 4:
                g.cbox((18.1, 0, z), (0.12, 1.9, 2.0), mat, 0, RZ(a))
    # Docking collars and a comms mast at the poles.
    for side in (-1, 1):
        k.lathe([(9, 30), (8.5, 34), (9.6, 34.4), (9.6, 36), (0.1, 36)], 28, "hull_dark", RX(90 * -side) if side < 0 else RX(90))
        k.tube([(0, 0, side * 36), (0, 0, side * 58)], 0.5, "metal_bare", 8)
        for h in (42, 48, 54):
            k.tube([(-4.5, 0, side * h), (4.5, 0, side * h)], 0.14, "metal_bare", 5)
            g.sphere((4.5, 0, side * h), 0.3, "glow_red", 5, 8)
    # Solar wings off the upper drum.
    for i in range(4):
        W = RZ(i * 90.0 + 45.0)
        k.tube([(17, 0, 13), (62, 0, 13)], 0.5, "metal_bare", 8, W)
        for p in range(4):
            x = 25.0 + p * 10.0
            k.cbox((x, 0, 13), (9.0, 15.0, 0.2), "metal_dark", 0.02, W)
            for c in range(4):
                g.cbox((x, -5.25 + c * 3.5, 13.12), (8.2, 3.0, 0.04), "glow_screen", 0, W)


def dock(k, g):
    """The arm and bay the ship comes home to, on the rim's outer edge at -Y."""
    M = RZ(-90)
    k.cbox((R + 10.5, 0, 0), (13, 11, 9), "hull_grey", 0.6, M)
    k.cbox((R + 21.0, 0, 0), (8, 22, 13), "hull_grey", 0.6, M)
    for s in (-1, 1):
        k.cbox((R + 25.5, s * 9.8, 0), (1.4, 2.4, 13), "hazard", 0.08, M)
        k.cbox((R + 25.5, 0, s * 5.9), (1.4, 22, 1.6), "hazard", 0.08, M)
        k.cbox((R + 14.0, s * 7.0, 0), (6.0, 2.0, 7.0), "hull_dark", 0.3, M)
        g.cbox((R + 24.3, s * 8.6, 0), (0.2, 0.5, 10.5), "glow_green", 0, M)
    k.cbox((R + 25.0, 0, 0), (0.6, 18.4, 10.6), "metal_dark", 0.02, M)
    g.cbox((R + 25.4, 0, 0), (0.1, 16.4, 8.8), "glow_white", 0, M)
    for z in (-2.5, 2.5):
        k.cbox((R + 25.6, 0, z), (0.1, 16.6, 0.3), "hull_dark", 0, M)
    for y in (-10.0, 10.0):
        g.sphere((R + 25.8, y, 7.0), 0.5, "glow_red", 5, 8, M)


def main():
    reset_scene()
    root = empty("HarborRing")
    k, g = Kit("Station", uv_scale=0.12), Kit("StationLights")
    habitat(k, g)
    spokes(k, g)
    hub(k, g)
    dock(k, g)
    for a in (35.0, 215.0):
        k.text("HARBOR RING", RZ(a) @ T(R + 4.74, 0, 0) @ RZ(90) @ RX(90), 3.4, "hazard", 0.08)
    k.build(root)
    g.build(root, None)
    print(f"[ring] triangles: {k.tris + g.tris}")
    export("harbor_ring.glb")


main()

"""Three candidate player ships, for comparing against the WREN-9. Not used by the game.

Run with: blender -b --python ship_concepts.py
Writes tools/concepts/concept_<name>.glb. Same scale and axes as wren9.glb:
+Y is the nose, +Z is up, about 8 m long.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import RY, RZ, SC, T, Kit, empty, export, glow_disk, nozzle, reset_scene, thruster_quad  # noqa: E402

OUT = "../../tools/concepts/concept_%s.glb"


def plate(k, pts, thick, mat, M):
    """A flat convex panel: points in local XY, thickness along local Z."""
    n = len(pts)
    verts = [(x, y, thick / 2) for x, y in pts] + [(x, y, -thick / 2) for x, y in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j, j))
    k.add(verts, faces, mat, M)


def ellipse(y, rx, rz, zc=0.0, n=18):
    return [(math.sin(a) * rx, y, zc + math.cos(a) * rz) for a in (i / n * math.tau for i in range(n))]


def nav_lights(g, left, right):
    g.sphere(left, 0.07, "glow_red", 5, 8)
    g.sphere(right, 0.07, "glow_green", 5, 8)


def finish(name, kits):
    root = empty("Concept_" + name)
    for kit in kits:
        kit.build(root, None if kit.name.endswith("Glow") else 32.0)
    print(f"[concept] {name}: {sum(kit.tris for kit in kits)} tris")
    export(OUT % name)


# ---------------------------------------------------------------------------- Kestrel
def kestrel():
    """Twin-boom striker: a slim crew pod between two engine booms, forward-swept wings."""
    reset_scene()
    k, glass, g = Kit("Hull"), Kit("Canopy"), Kit("KestrelGlow")
    pod = [(-2.3, 0.5, 0.46), (-1.4, 0.8, 0.66), (-0.2, 0.92, 0.78), (1.2, 0.86, 0.72), (2.4, 0.62, 0.52), (3.3, 0.34, 0.3), (3.9, 0.08, 0.08)]
    k.loft([ellipse(y, rx, rz) for y, rx, rz in pod], "hull_grey")
    for y, rx, rz in pod[1:5]:
        k.loft([ellipse(y - 0.04, rx * 1.01, rz * 1.01), ellipse(y + 0.04, rx * 1.01, rz * 1.01)], "hull_dark")
    glass.sphere((0, 1.0, 0.55), 0.62, "glass", 10, 18, SC(0.85, 1.9, 0.75))
    k.loft([ellipse(y, 0.5 * s, 0.42 * s, -0.42) for y, s in ((-1.6, 0.6), (-0.8, 1.0), (1.3, 1.0), (2.0, 0.5))], "hull_accent")
    for sx in (-1, 1):
        x = sx * 2.15
        k.lathe([(0.42, -2.0), (0.5, -1.2), (0.5, 1.6), (0.36, 2.3), (0.12, 2.6)], 18, "hull_grey", T(x, 0, 0.05))
        k.lathe([(0.56, -3.1), (0.6, -2.4), (0.55, -1.7)], 20, "hull_dark", T(x, 0, 0.05))
        bell = nozzle(k, T(x, -3.1, 0.05), 0.46, 0.8, petals=14)
        glow_disk(g, bell @ T(0, -0.1, 0), 0.34)
        k.tube([(x, 2.4, -0.2), (x, 3.5, -0.2)], 0.07, "metal_dark", 8)
        k.cbox((x, 2.2, -0.2), (0.24, 0.5, 0.24), "metal_dark", 0.04)
        k.cbox((x, 0.4, 0.5), (0.12, 2.4, 0.1), "hazard", 0.02)
        plate(k, [(0.0, -2.7), (0.0, -1.1), (1.15, -1.8), (1.35, -3.0)], 0.12, "hull_accent", T(x, 0, 0.42) @ RY(-90))
        # Forward-swept wings: root to the pod, then on past the boom.
        inner = [(0.8, -1.0), (0.8, 1.2), (1.8, 1.7), (1.8, -0.4)]
        tip = [(2.55, -0.2), (2.55, 1.3), (4.0, 2.5), (4.1, 1.6)]
        for shape, z in ((inner, 0.12), (tip, 0.1)):
            plate(k, shape if sx > 0 else [(-x2, y2) for x2, y2 in reversed(shape)], 0.16, "hull_grey", T(0, 0, z))
        k.cbox((sx * 2.2, 0.6, 0.22), (2.6, 0.5, 0.04), "hull_accent", 0.01, RZ(sx * 22))
        k.cbox((sx * 4.08, 2.1, 0.1), (0.18, 0.9, 0.18), "metal_dark", 0.03)
        k.tube([(sx * 4.08, 2.5, 0.1), (sx * 4.08, 3.3, 0.1)], 0.05, "metal_dark", 8)
        thruster_quad(k, (x, -0.2, 0.55))
    nav_lights(g, (-4.12, 1.65, 0.1), (4.12, 1.65, 0.1))
    finish("kestrel", [k, glass, g])


# ----------------------------------------------------------------------------- Mantis
def mantis():
    """Flat wedge lifting body: a stealthy, wide interceptor with canted fins."""
    reset_scene()
    k, glass, g = Kit("Hull"), Kit("Canopy"), Kit("MantisGlow")

    def hexa(y, w, h):
        return [(-w, y, 0.0), (-w * 0.7, y, h), (w * 0.7, y, h), (w, y, 0.0), (w * 0.62, y, -h * 0.55), (-w * 0.62, y, -h * 0.55)]

    body = [(-3.0, 1.9, 0.48), (-1.6, 2.35, 0.62), (0.0, 2.05, 0.64), (1.5, 1.35, 0.55), (2.9, 0.62, 0.34), (4.1, 0.12, 0.1)]
    k.loft([hexa(*s) for s in body], "hull_grey")
    k.loft([hexa(y, w * 1.005, h * 1.02) for y, w, h in ((-0.9, 2.2, 0.63), (-0.8, 2.2, 0.63))], "hull_dark")
    k.loft([hexa(y, w * 1.005, h * 1.02) for y, w, h in ((1.0, 1.6, 0.58), (1.1, 1.55, 0.58))], "hull_dark")
    glass.sphere((0, 1.15, 0.6), 0.5, "glass", 10, 18, SC(1.0, 2.2, 0.55))
    k.cbox((0, -0.6, 0.66), (0.9, 2.2, 0.12), "hull_accent", 0.05)
    for sx in (-1, 1):
        plate(k, [(0, -2.8), (0, -0.4), (1.5, -1.8), (1.6, -3.0)], 0.12, "hull_grey", T(sx * 2.0, 0, 0.02) @ SC(sx, 1, 1))
        plate(k, [(0.0, -2.9), (0.0, -1.5), (1.15, -2.3), (1.3, -3.1)], 0.1, "hull_accent", T(sx * 1.35, 0, 0.55) @ RY(-sx * 65))
        k.cbox((sx * 1.45, 0.6, -0.12), (0.5, 1.6, 0.42), "metal_dark", 0.08)
        g.cbox((sx * 1.45, 1.42, -0.12), (0.36, 0.04, 0.28), "glow_blue", 0)
        k.tube([(sx * 0.5, 2.6, -0.28), (sx * 0.5, 3.9, -0.28)], 0.06, "metal_dark", 8)
        k.cbox((sx * 2.9, -1.6, 0.0), (1.4, 0.1, 0.06), "hazard", 0.01)
    for x in (-0.95, 0.0, 0.95):
        bell = nozzle(k, T(x, -3.0, 0.08), 0.32, 0.6, petals=12)
        glow_disk(g, bell @ T(0, -0.08, 0), 0.24)
    thruster_quad(k, (0, 2.4, 0.42))
    nav_lights(g, (-3.55, -2.9, 0.02), (3.55, -2.9, 0.02))
    finish("mantis", [k, glass, g])


# ------------------------------------------------------------------------------ Atlas
def atlas():
    """Heavy gunship: a round armoured hull, X-fins and a ring-shrouded main engine."""
    reset_scene()
    k, glass, g = Kit("Hull"), Kit("Canopy"), Kit("AtlasGlow")
    k.lathe([(0.7, -3.0), (1.0, -2.6), (1.15, -1.5), (1.12, 1.2), (0.92, 2.6), (0.5, 3.6), (0.06, 4.0)], 28, "hull_grey", cap0=True)
    for y in (1.6, 0.2, -1.2):
        k.lathe([(1.16, y - 0.12), (1.2, y - 0.06), (1.2, y + 0.06), (1.16, y + 0.12)], 28, "hull_dark")
    glass.sphere((0, 2.05, 0.72), 0.52, "glass", 10, 18, SC(0.9, 1.7, 0.7))
    k.cbox((0, -0.4, 1.1), (0.7, 2.6, 0.28), "hull_accent", 0.08)
    for i in range(4):
        a = 45 + i * 90
        R = RY(a)
        plate(k, [(1.0, -2.9), (1.0, -0.6), (1.75, -1.4), (2.05, -2.9)], 0.12, "hull_accent" if i % 2 else "hull_grey", R)
        k.cbox((2.0, -2.45, 0.0), (0.26, 0.9, 0.26), "metal_dark", 0.05, R)
        if i < 2:
            g.sphere((2.33, -2.45, 0.0), 0.08, "glow_red" if i == 0 else "glow_green", 5, 8, R)
    k.lathe([(1.95, -2.95), (2.25, -2.95), (2.25, -2.0), (1.95, -2.0), (1.95, -2.95)], 36, "hull_dark")
    g.lathe([(1.93, -2.75), (1.93, -2.2)], 36, "glow_engine")
    bell = nozzle(k, T(0, -3.0, 0), 0.72, 1.0, petals=18)
    glow_disk(g, bell @ T(0, -0.1, 0), 0.55)
    for sx in (-1, 1):
        k.cbox((sx * 0.55, 2.4, -0.82), (0.36, 1.0, 0.36), "metal_dark", 0.06)
        k.tube([(sx * 0.55, 2.9, -0.82), (sx * 0.55, 4.0, -0.82)], 0.09, "metal_dark", 8)
        thruster_quad(k, (sx * 1.12, 1.9, 0.0), RZ(90 * sx))
    finish("atlas", [k, glass, g])


kestrel()
mantis()
atlas()

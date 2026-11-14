"""The world outside the mine: a starfield panorama and the mined-out asteroid."""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
from kit import ROOT, RY, T, Kit, empty, export, reset_scene  # noqa: E402

W, H = 4096, 2048
ASTEROID_RADIUS = 180.0
rng = np.random.default_rng(404)


def fractal(size, beta):
    f = np.fft.fft2(rng.normal(size=(size, size)))
    fx = np.fft.fftfreq(size) * size
    r = np.sqrt(fx[:, None] ** 2 + fx[None, :] ** 2)
    r[0, 0] = 1
    f *= r ** (-beta / 2)
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    return (out - out.min()) / (out.max() - out.min())


def starfield():
    # Cropping a square tile keeps the panorama seamless left to right.
    cloud = fractal(W, 2.6)[:H]
    tint = fractal(W, 2.2)[:H]
    density = np.clip((cloud - 0.5) * 3.2, 0, 1) ** 1.6
    sky = np.zeros((H, W, 3), np.float32)
    teal, violet = np.array((0.03, 0.17, 0.2)), np.array((0.17, 0.05, 0.24))
    sky += (density * tint)[..., None] * teal + (density * (1 - tint))[..., None] * violet
    for _ in range(9000):
        x, y = int(rng.integers(0, W)), int(rng.integers(0, H))
        bright = float(rng.power(5.0))
        color = np.array((1.0, 0.92, 0.82)) if rng.random() < 0.5 else np.array((0.78, 0.88, 1.0))
        sky[y, x] += color * bright
        if bright > 0.82:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                sky[(y + dy) % H, (x + dx) % W] += color * bright * 0.4
    rgba = np.dstack((np.clip(sky, 0, 1), np.ones((H, W))))
    img = bpy.data.images.new("space_sky", W, H, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.flipud(rgba).astype(np.float32).ravel())
    path = os.path.join(ROOT, "assets", "textures", "space_sky.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\ndetect_3d/compress_to=0\n')
    print("[space] sky")


HOLE_ROW = 70  # the last ring of rock, 7.5 degrees from the pole
SHAFT_END = 92.0
# From just under the rock rim, down a funnel and along the shaft (radius, height).
# Listed from the rim down, so the surfaces face into the shaft.
SHAFT_PROFILE = [(23.5, 167.5), (20.5, 164.0), (15.5, 158.0), (13.0, 150.0), (13.0, SHAFT_END)]


def _smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _ellipsoid(d, a, b, c):
    return 1.0 / math.sqrt((d.x / a) ** 2 + (d.y / b) ** 2 + (d.z / c) ** 2)


def _far_hit(d, centre, radius):
    """Distance along d from the origin to where it leaves a sphere, or 0 if it misses."""
    along = d.dot(centre)
    miss = centre.length_squared - along * along
    if along <= 0:
        return 0.0
    if miss > radius * radius:
        # Falls away smoothly past the lobe's edge, so the blend below has no step.
        return max(0.0, along - 2.0 * math.sqrt(miss - radius * radius))
    return along + math.sqrt(radius * radius - miss)


def _crater(d, centre, size, depth):
    """A bowl with a raised rim. size is the crater's angular radius in radians."""
    ang = math.acos(max(-1.0, min(1.0, d.dot(centre))))
    x = ang / size
    if x < 1.0:
        return -depth * (1 - x * x) + depth * 0.35 * x ** 6
    return depth * 0.35 * math.exp(-((x - 1.0) / 0.25) ** 2)


def shape_plan(kind, r):
    """Random but fixed per shape: craters, cutting planes, lobes."""
    away = lambda: Vector((r.gauss(0, 1), r.gauss(0, 1) - 0.6, r.gauss(0, 1))).normalized()
    plan = {"craters": [], "planes": []}
    if kind == "plain":
        return plan
    if kind in ("cratered", "pit", "lumpy", "fractured"):
        count = {"cratered": 11, "pit": 7, "lumpy": 3, "fractured": 4}[kind]
        for _ in range(count):
            plan["craters"].append((away(), r.uniform(0.2, 0.45), r.uniform(0.1, 0.2)))
    if kind == "pit":
        plan["craters"].append((Vector((0.75, -0.25, 0.6)).normalized(), 0.95, 0.3))
    if kind in ("blocky", "crystalline"):
        for _ in range(16 if kind == "blocky" else 26):
            n = away()
            plan["planes"].append((n, r.uniform(0.6, 0.82) if kind == "blocky" else r.uniform(0.8, 0.95)))
    if kind == "fractured":
        plan["rifts"] = [Vector((r.gauss(0, 1), r.gauss(0, 0.3), r.gauss(0, 1))).normalized() for _ in range(3)]
    return plan


def shape_scale(kind, d, plan):
    """Multiplies the lumpy base radius in direction d to give each asteroid its outline."""
    m = 1.0
    if kind == "elongated":
        m = _ellipsoid(d, 1.6, 1.0, 0.82)
    elif kind == "spindle":
        m = _ellipsoid(d, 0.78, 1.0, 1.5)
        around = math.atan2(d.x, d.y)
        m *= 1.0 + 0.08 * math.sin(around * 7.0)
    elif kind == "disc":
        m = _ellipsoid(d, 1.45, 1.0, 0.62)
    elif kind == "twin":
        lobe = _far_hit(d, Vector((-0.95, -0.45, 0.25)), 0.72)
        # Soft union of the two bodies, so a waist joins them instead of a crease.
        m = math.log(math.exp(8.0) + math.exp(8.0 * lobe)) / 8.0
    for n, h in plan["planes"]:
        facing = d.dot(n)
        if facing > 0.05:
            m = min(m, h / facing)
    for centre, size, depth in plan["craters"]:
        m += _crater(d, centre, size, depth)
    for n in plan.get("rifts", []):
        m -= 0.07 * math.exp(-(d.dot(n) / 0.035) ** 2)
    return m


# One asteroid per level, named after the level. The shaft is at the +Y pole on all of them.
def build_asteroid(name, kind="plain", material="wall_rock", glow="glow_ore", seed=7):
    reset_scene()
    root = empty("Asteroid")
    k, g = Kit("Rock", uv_scale=0.02), Kit("Glow")
    r = random.Random(seed)
    plan = shape_plan(kind, random.Random(seed * 31 + 5))
    # Less of the shared lumpiness where it would hide the shape's own features.
    lumps = {"blocky": 0.35, "crystalline": 0.4, "cratered": 0.55, "pit": 0.6, "spindle": 0.6, "disc": 0.7, "twin": 0.8, "elongated": 0.8}.get(kind, 1.0)
    waves = [(Vector((r.gauss(0, 1), r.gauss(0, 1), r.gauss(0, 1))).normalized(), r.uniform(0, 6.28), f, a)
             for f, a in [(1.6, 0.13), (2.9, 0.09), (5.3, 0.05), (9.0, 0.03), (15.0, 0.016)] for _ in range(5)]
    rows = []
    # The top rows stop short of the +Y pole, leaving a real opening for the shaft.
    for i in range(1, HOLE_ROW):
        lat = -math.pi / 2 + i / 72 * math.pi
        ring = []
        for j in range(120):
            lon = j / 120 * math.tau
            d = Vector((math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon)))
            height = sum(math.sin(d.dot(w) * f * 3.0 + p) * a for w, p, f, a in waves) * lumps
            # Smooth towards the opening, so its rim is a clean circle for the shaft to meet.
            from_pole = math.degrees(math.acos(min(1.0, d.y)))
            height *= min(1.0, max(0.0, (from_pole - 7.5) / 12.0))
            # A shallow quarry bowl around the mine entrance at the +Y pole.
            bowl = max(0.0, d.y - 0.965) * 2.6
            # The shape takes over away from the opening, so every rim and shaft is the same.
            shaped = 1.0 + (shape_scale(kind, d, plan) - 1.0) * _smooth(16.0, 48.0, from_pole)
            ring.append(tuple(d * ASTEROID_RADIUS * (1.0 + height * 0.42 - bowl) * shaped))
        rows.append(ring)
    k.loft(rows, material, cap1=False)
    if kind == "crystalline":
        # Crystal spires breaking out of the faceted rock, well clear of the shaft.
        for _ in range(16):
            d = Vector((r.gauss(0, 1), r.gauss(0, 1) - 0.5, r.gauss(0, 1))).normalized()
            if d.y > 0.55:
                continue
            base = d * ASTEROID_RADIUS * 0.82
            length = r.uniform(40.0, 95.0)
            tilt = (d + Vector((r.gauss(0, 0.25), r.gauss(0, 0.25), r.gauss(0, 0.25)))).normalized()
            rot = tilt.to_track_quat("Y", "Z").to_matrix().to_4x4()
            rad = r.uniform(7.0, 15.0)
            g.lathe([(rad * 0.8, 0.0), (rad, length * 0.6), (rad * 0.5, length * 0.85), (0.01, length)], 6, glow, T(*base) @ rot)

    # The tunnel mouth, seated in the bowl and facing +Y.
    M = T(0, ASTEROID_RADIUS * 0.93, 0)
    k.lathe(SHAFT_PROFILE, 40, "metal_dark")
    g.lathe([(0.1, SHAFT_END + 0.5), (12.6, SHAFT_END + 0.5)], 40, "glow_orange")
    for i in range(8):
        B = RY(i * 45 + 22.5)
        g.cbox((0, (SHAFT_END + 150.0) * 0.5, 12.6), (0.9, 150.0 - SHAFT_END - 6.0, 0.25), "glow_amber", 0, B)
    for i in range(8):
        B = M @ RY(i * 45)
        k.cbox((0, 2, 13.5), (11.5, 12, 3.0), "hull_grey", 0.4, B)
        k.cbox((0, 8.4, 11.9), (9.0, 0.8, 0.5), "hazard", 0.06, B)
        g.cbox((0, 8.3, 12.6), (7.0, 0.3, 0.5), "glow_amber", 0, B)
    # Beacons scattered round the quarry.
    for i in range(14):
        a = i / 14 * math.tau
        d = Vector((math.sin(a) * 0.2, 1.0, math.cos(a) * 0.2)).normalized()
        p = d * ASTEROID_RADIUS * 0.985
        k.tube([tuple(p), tuple(p + d * 14)], 0.5, "metal_dark", 6)
        g.sphere(tuple(p + d * 14), 1.1, "glow_red", 5, 8)
    k.build(root, sharp_deg=None if kind not in ("blocky", "crystalline") else 50.0)
    g.build(root, None)
    export(name + ".glb")


def asteroid():
    build_asteroid("asteroid")


def asteroids():
    from themes import THEMES  # noqa: E402
    for i, (level_id, theme) in enumerate(THEMES.items()):
        build_asteroid("asteroid_" + level_id, theme["asteroid"], "rock_" + level_id, "glow_ore_" + level_id, 7 + i * 13)
        print("[space] asteroid", level_id, theme["asteroid"])


# "blender ... gen_space.py -- asteroid" rebuilds only the named asset.
only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for build in (starfield, asteroid, asteroids):
    if not only or build.__name__ in only:
        build()
print("[space] done")

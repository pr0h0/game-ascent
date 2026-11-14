"""Hardpoint models the player's ship wears: one gun per primary, one round per missile.

Every gun is built along +Y from its origin, which sits on the ship's Mount_Gun_*
empty, and carries a "Muzzle" empty at the barrel tip. Missile rounds are centred on
their origin, nose +Y, and hang from the slots of rack.glb (empties Slot_0..Slot_2),
which hangs from Mount_Missile_*. Sizes are kept to a wing-tip pod's radius, so the
same parts fit any hull that names its mounts the same way.

Design language follows arsenal.py: banded housings, burned metal prongs, glow cores.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from mathutils import Vector  # noqa: E402


def begin(name):
    reset_scene()
    return empty(name), Kit(name + "Mesh"), Kit(name + "Glow")


# Guns are drawn at a wing-tip pod's radius, then enlarged so they still read from the chase camera.
GUN_SCALE = 1.3


def finish(root, k, g, filename, muzzle=None):
    if muzzle is not None:
        root.scale = (GUN_SCALE,) * 3
    k.build(root)
    if g.faces:
        g.build(root, None)
    if muzzle is not None:
        empty("Muzzle", muzzle, root)
    print(f"[mounts] {filename}: {k.tris + g.tris} tris")
    export("mounts/" + filename)


def housing(k, length, radius, mat="hull_grey"):
    """Gun breech: mounting collar at y=0, banded casing, tapered front."""
    k.lathe([(radius * 0.8, 0.0), (radius, 0.04), (radius, length * 0.75), (radius * 0.78, length)], 14, mat, cap0=True, cap1=True)
    k.lathe([(radius * 1.02, 0.0), (radius * 1.12, 0.02), (radius * 1.12, 0.09), (radius * 1.02, 0.11)], 14, "metal_dark")
    for y in (0.3, 0.5):
        y *= length
        k.lathe([(radius * 0.98, y), (radius * 1.08, y + 0.012), (radius * 1.08, y + 0.05), (radius * 0.98, y + 0.062)], 14, "hull_dark")
    k.cbox((0, length * 0.45, radius * 1.02), (radius * 0.8, length * 0.5, radius * 0.22), "hull_dark", 0.012)


def barrel(k, y0, y1, r, mat="metal_dark"):
    k.lathe([(r * 1.25, y0), (r, y0 + 0.02), (r, y1 - r * 2), (r * 1.3, y1 - r * 1.6), (r * 1.3, y1), (r * 0.55, y1 + 0.005), (r * 0.45, y1 - r * 3)], 10, mat)


# ---------------------------------------------------------------- guns
def gun_pulse():
    """Pulse cannon: the stock emitter. Its tip glow is tinted per laser level in Godot."""
    root, k, g = begin("GunPulse")
    housing(k, 0.62, 0.15)
    k.lathe([(0.11, 0.6), (0.11, 1.08), (0.095, 1.12), (0.08, 1.12)], 12, "metal_dark")
    for i in range(8):
        k.cbox((0, 0.86, 0.108), (0.024, 0.36, 0.01), "metal_bare", 0, RY(i * 45))
    barrel(k, 1.06, 1.62, 0.052, "metal_burn")
    for a in (0, 90, 180, 270):
        k.cbox((0, 1.52, 0.07), (0.036, 0.07, 0.008), "metal_dark", 0, RY(a))
    g.lathe([(0.03, 1.3), (0.033, 1.63)], 8, "glow_green")
    g.lathe([(0.112, 0.98), (0.112, 1.02)], 12, "glow_green", cap0=True, cap1=True)
    finish(root, k, g, "gun_pulse.glb", (0, 1.66, 0))


def gun_cutter():
    """Plasma cutter: a short breech feeding a flat glowing blade between two prongs."""
    root, k, g = begin("GunCutter")
    housing(k, 0.55, 0.16)
    k.lathe([(0.17, 0.5), (0.19, 0.54), (0.19, 0.64), (0.17, 0.68)], 14, "hazard")
    for sx in (-1, 1):
        k.cbox((sx * 0.15, 0.95, 0), (0.05, 0.85, 0.2), "metal_burn", 0.015)
        k.cbox((sx * 0.15, 1.42, 0), (0.05, 0.12, 0.12), "metal_dark", 0.01, RX(0))
    k.cbox((0, 0.6, 0), (0.34, 0.12, 0.14), "hull_dark", 0.02)
    g.cbox((0, 1.0, 0), (0.24, 0.9, 0.025), "glow_orange", 0)
    finish(root, k, g, "gun_cutter.glb", (0, 1.5, 0))


def gun_arc():
    """Arc caster: two curved tines arching to a charged tip ball, ringed with coils."""
    root, k, g = begin("GunArc")
    housing(k, 0.6, 0.15)
    for sx in (-1, 1):
        k.tube([(sx * 0.07, 0.5, 0), (sx * 0.18, 0.9, 0), (sx * 0.17, 1.25, 0), (sx * 0.06, 1.5, 0)], 0.032, "metal_burn", 8, spline=12)
        for y, x in ((0.82, 0.17), (1.04, 0.19), (1.26, 0.165)):
            g.lathe([(0.055, -0.014), (0.055, 0.014)], 8, "glow_cyan", T(sx * x, y, 0), cap0=True, cap1=True)
    k.lathe([(0.04, 0.55), (0.04, 1.45)], 8, "metal_dark")
    g.sphere((0, 1.54, 0), 0.07, "glow_cyan", 6, 10)
    finish(root, k, g, "gun_arc.glb", (0, 1.6, 0))


def gun_rail():
    """Rail lance: long twin rails with a blue core and stacked accelerator coils."""
    root, k, g = begin("GunRail")
    housing(k, 0.55, 0.16, "hull_dark")
    for sx in (-1, 1):
        k.cbox((sx * 0.075, 1.15, 0), (0.05, 1.5, 0.15), "metal_dark", 0.01)
        k.cbox((sx * 0.05, 1.15, 0), (0.012, 1.45, 0.07), "metal_bare")
    g.cbox((0, 1.15, 0), (0.022, 1.42, 0.022), "glow_blue", 0)
    for i in range(6):
        y = 0.55 + i * 0.2
        k.cbox((0, y, 0), (0.26, 0.05, 0.24), "hull_accent" if i % 3 == 0 else "hull_grey", 0.02)
    k.cbox((0, 1.9, 0), (0.22, 0.06, 0.2), "metal_dark", 0.015)
    finish(root, k, g, "gun_rail.glb", (0, 1.95, 0))


def gun_prism():
    """Prism repeater: white hex barrel ending in a faceted crystal."""
    root, k, g = begin("GunPrism")
    housing(k, 0.6, 0.15, "hull_white")
    k.lathe([(0.12, 0.58), (0.1, 1.08), (0.14, 1.12), (0.14, 1.18), (0.08, 1.2)], 6, "hull_grey", cap0=True, phase=math.pi / 6)
    for i in range(6):
        k.cbox((0, 0.85, 0.105), (0.04, 0.4, 0.015), "metal_bare", 0, RY(i * 60))
    g.lathe([(0.001, 1.14), (0.1, 1.32), (0.07, 1.5), (0.001, 1.62)], 6, "glow_crystal", phase=math.pi / 6)
    finish(root, k, g, "gun_prism.glb", (0, 1.62, 0))


def gun_singularity():
    """Singularity projector: a dark core held in three gyro rings at the front."""
    root, k, g = begin("GunSingularity")
    housing(k, 0.6, 0.17, "hull_dark")
    C = T(0, 0.98, 0)
    k.sphere((0, 0, 0), 0.13, "metal_dark", 8, 12, C)
    for axis in (RX(0), RX(90) @ RZ(30), RZ(90)):
        k.lathe([(0.2, -0.018), (0.24, -0.018), (0.255, 0), (0.24, 0.018), (0.2, 0.018), (0.2, -0.018)], 24, "hull_grey", C @ axis)
        g.lathe([(0.185, -0.008), (0.2, 0), (0.185, 0.008), (0.185, -0.008)], 24, "glow_violet", C @ axis)
    for sx in (-1, 1):
        k.tube([(sx * 0.1, 0.5, 0.05), (sx * 0.24, 0.75, 0), (sx * 0.24, 0.98, 0)], 0.025, "metal_bare", 6, spline=8)
    g.sphere((0, 0, 0), 0.07, "glow_violet", 6, 10, C)
    finish(root, k, g, "gun_singularity.glb", (0, 1.25, 0))


# ---------------------------------------------------------------- missile rack and rounds
def rack():
    """Triple ejector rack: one round under the beam and one at each shoulder."""
    root, k, g = begin("MissileRack")
    k.cbox((0, 0, -0.04), (0.1, 0.8, 0.08), "hull_dark", 0.02)
    k.cbox((0, 0, -0.12), (0.5, 0.62, 0.07), "metal_dark", 0.02)
    for sx in (-1, 1):
        k.cbox((sx * 0.21, 0, -0.17), (0.07, 0.5, 0.07), "hull_grey", 0.015, RY(sx * -35))
    for y in (-0.22, 0.22):
        k.cbox((0, y, -0.165), (0.05, 0.05, 0.05), "metal_bare", 0.01)
        g.cbox((0.26, y, -0.12), (0.01, 0.04, 0.02), "glow_amber", 0)
    for i, (x, z) in enumerate(((0.0, -0.3), (-0.235, -0.235), (0.235, -0.235))):
        empty(f"Slot_{i}", (x, 0.0, z), root)
    finish(root, k, g, "rack.glb")


def fins(k, half, r, mat="hull_dark", span=0.08, chord=0.22):
    for a in (45, 135, 225, 315):
        k.add([(0, -half, r), (0, -half + chord, r), (0, -half + chord * 0.5, r + span), (0, -half - 0.03, r + span)], [(0, 1, 2, 3), (3, 2, 1, 0)], mat, RY(a))


def round_homing():
    root, k, g = begin("RoundHoming")
    k.lathe([(0.05, -0.5), (0.085, -0.48), (0.085, 0.3)], 12, "hull_white", cap0=True)
    k.lathe([(0.085, 0.3), (0.06, 0.45), (0.002, 0.56)], 12, "hull_accent")
    k.lathe([(0.087, 0.12), (0.087, 0.18)], 12, "hazard")
    fins(k, 0.5, 0.085)
    g.lathe([(0.001, -0.53), (0.05, -0.5)], 10, "glow_orange")
    finish(root, k, g, "round_homing.glb")


def round_cluster():
    root, k, g = begin("RoundCluster")
    k.lathe([(0.05, -0.5), (0.095, -0.47), (0.095, 0.26)], 12, "hull_white", cap0=True)
    k.lathe([(0.095, 0.26), (0.07, 0.42), (0.002, 0.54)], 12, "hull_accent")
    for i in range(6):
        for y in (-0.1, 0.12):
            k.sphere((0, y, 0.09), 0.028, "hazard", 3, 6, RY(i * 60 + (30 if y > 0 else 0)))
    fins(k, 0.5, 0.095)
    g.lathe([(0.001, -0.53), (0.05, -0.5)], 10, "glow_orange")
    finish(root, k, g, "round_cluster.glb")


def round_swarm():
    """A pod of micro-rockets: four noses peeking from a square tube."""
    root, k, g = begin("RoundSwarm")
    k.cbox((0, -0.05, 0), (0.19, 0.8, 0.19), "hull_grey", 0.025)
    for ix in (-1, 1):
        for iz in (-1, 1):
            M = T(ix * 0.048, 0.35, iz * 0.048)
            k.lathe([(0.038, 0.0), (0.038, 0.06), (0.02, 0.13), (0.002, 0.17)], 8, "hull_accent", M)
    k.cbox((0, -0.05, 0), (0.2, 0.06, 0.2), "hull_dark", 0.01)
    g.cbox((0, -0.05, 0.097), (0.1, 0.5, 0.006), "glow_green", 0)
    finish(root, k, g, "round_swarm.glb")


def round_bunker():
    """Bunker buster: fat dark casing and a bare penetrator spike."""
    root, k, g = begin("RoundBunker")
    k.lathe([(0.06, -0.55), (0.11, -0.52), (0.11, 0.22)], 12, "hull_dark", cap0=True)
    k.lathe([(0.11, 0.22), (0.08, 0.38), (0.035, 0.44)], 12, "metal_burn")
    k.lathe([(0.035, 0.44), (0.022, 0.6), (0.002, 0.68)], 8, "metal_bare")
    for y in (-0.25, 0.0):
        k.lathe([(0.112, y), (0.112, y + 0.07)], 12, "hazard")
    fins(k, 0.55, 0.11, "metal_dark", 0.09, 0.26)
    g.lathe([(0.001, -0.58), (0.07, -0.55)], 10, "glow_orange")
    finish(root, k, g, "round_bunker.glb")


def round_emp():
    root, k, g = begin("RoundEmp")
    k.lathe([(0.05, -0.5), (0.08, -0.48), (0.08, 0.28)], 12, "hull_grey", cap0=True)
    k.lathe([(0.08, 0.28), (0.05, 0.4), (0.03, 0.42)], 12, "hull_dark")
    for y in (-0.15, 0.0, 0.15):
        k.lathe([(0.08, y), (0.105, y + 0.015), (0.105, y + 0.045), (0.08, y + 0.06)], 12, "metal_bare")
    g.lathe([(0.03, 0.42), (0.05, 0.48), (0.002, 0.56)], 10, "glow_cyan")
    fins(k, 0.5, 0.08)
    finish(root, k, g, "round_emp.glb")


def round_mine():
    """Proximity mine on a launch cradle: spiked sphere with red sensor beads."""
    root, k, g = begin("RoundMine")
    k.lathe([(0.03, -0.2), (0.06, -0.16), (0.06, 0.16), (0.03, 0.2)], 8, "metal_dark", cap0=True, cap1=True)
    k.sphere((0, 0, 0), 0.105, "hull_dark", 6, 12)
    k.lathe([(0.108, -0.015), (0.108, 0.015)], 14, "hazard", RX(90))
    n = 10
    for i in range(n):
        yy = 1 - (i + 0.5) / n * 2
        rr = math.sqrt(1 - yy * yy)
        a = i * 2.4
        d = Vector((math.cos(a) * rr, yy, math.sin(a) * rr))
        M = T(*(d * 0.1)) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
        k.lathe([(0.018, 0), (0.01, 0.05), (0.002, 0.07)], 5, "metal_bare", M)
        if i % 2 == 0:
            g.sphere(tuple(d * 0.105), 0.012, "glow_red", 3, 5)
    finish(root, k, g, "round_mine.glb")


for build in (gun_pulse, gun_cutter, gun_arc, gun_rail, gun_prism, gun_singularity, rack, round_homing, round_cluster, round_swarm, round_bunker, round_emp, round_mine):
    build()

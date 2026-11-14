"""Upgrade pickups, plus concept models for weapons and missiles still to come."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from mathutils import Vector  # noqa: E402


def begin(name):
    reset_scene()
    return empty(name), Kit("Mesh"), Kit("Glow")


def finish(root, k, g, filename):
    k.build(root)
    g.build(root, None)
    export(filename)


def barrel(k, M, r, length, mat="metal_dark"):
    k.lathe([(r * 1.2, 0), (r, r), (r, length - r * 2), (r * 1.25, length - r), (r * 1.25, length), (r * 0.6, length + 0.01), (r * 0.5, length - r * 3)], 12, mat, M)


def body(k, length, radius, mat="hull_grey"):
    """A gun housing running along +Y with a banded rear casing."""
    k.lathe([(0.02, -length * 0.5), (radius * 0.7, -length * 0.48), (radius, -length * 0.3), (radius, length * 0.2), (radius * 0.75, length * 0.45)], 20, mat, cap1=True)
    for y in (-0.3, -0.1, 0.1):
        y *= length
        k.lathe([(radius * 0.98, y), (radius * 1.07, y + 0.015), (radius * 1.07, y + 0.07), (radius * 0.98, y + 0.085)], 20, "hull_dark")
    k.cbox((0, -length * 0.1, radius * 1.08), (radius * 0.9, length * 0.4, radius * 0.25), "hull_dark", 0.02)


# ---------------------------------------------------------------- upgrades
def upgrade_dual():
    root, k, g = begin("UpgradeDual")
    for sx in (-1, 1):
        barrel(k, T(sx * 0.32, -0.9, 0), 0.14, 1.9, "hull_grey")
        for y in (-0.5, 0.0, 0.5):
            k.lathe([(0.18, y), (0.2, y + 0.02), (0.2, y + 0.12), (0.18, y + 0.14)], 14, "hull_dark", T(sx * 0.32, 0, 0))
        g.lathe([(0.06, 0.98), (0.001, 1.04)], 10, "glow_cyan", T(sx * 0.32, 0, 0))
    for y in (-0.7, 0.05, 0.72):
        k.cbox((0, y, 0), (0.64, 0.14, 0.18), "hull_accent", 0.03)
        g.cbox((0, y, 0.098), (0.46, 0.05, 0.012), "glow_cyan", 0)
    finish(root, k, g, "pickup_upgrade_dual.glb")


def upgrade_overcharge():
    root, k, g = begin("UpgradeOvercharge")
    g.lathe([(0.001, -0.75), (0.2, -0.7), (0.24, 0), (0.2, 0.7), (0.001, 0.75)], 18, "glow_violet", RX(90))
    for i in range(9):
        z = -0.72 + i * 0.18
        k.lathe([(0.3, -0.05), (0.42, -0.05), (0.45, 0), (0.42, 0.05), (0.3, 0.05), (0.3, -0.05)], 24, "metal_bare", T(0, 0, z) @ RX(90))
    for cap in (-1, 1):
        k.lathe([(0.1, -0.1), (0.5, -0.1), (0.5, 0.1), (0.1, 0.1), (0.1, -0.1)], 8, "hull_dark", T(0, 0, cap * 0.92) @ RX(90))
    for i in range(4):
        k.cbox((0.44, 0, 0), (0.05, 0.08, 1.8), "hull_accent", 0.01, RZ(i * 90))
    finish(root, k, g, "pickup_upgrade_overcharge.glb")


def power_invincible():
    root, k, g = begin("PowerInvincible")
    g.sphere((0, 0, 0), 0.55, "glow_amber", 10, 16)
    for i in range(8):
        k.cbox((0, 0, 0.95), (0.3, 0.14, 0.5), "hull_accent", 0.04, RZ(i * 45))
    for M in (RX(90), RZ(90)):
        k.lathe([(0.7, -0.05), (0.8, -0.05), (0.84, 0), (0.8, 0.05), (0.7, 0.05), (0.7, -0.05)], 32, "metal_bare", M)
    finish(root, k, g, "power_invincible.glb")


def power_cloak():
    root, k, g = begin("PowerCloak")
    k.sphere((0, 0, 0), 0.55, "metal_dark", 10, 16)
    for i in range(3):
        g.lathe([(0.78, -0.02), (0.82, 0), (0.78, 0.02), (0.78, -0.02)], 36, "glow_violet", RX(i * 60 + 30))
    for a in (0, 120, 240):
        k.cbox((0, 0, 0.62), (0.16, 0.16, 0.3), "glass", 0.03, RY(a))
    finish(root, k, g, "power_cloak.glb")


def door_secret():
    """Two plain leaves in wall plating, with nothing to give them away."""
    reset_scene()
    root = empty("DoorSecret")
    S = 10.6
    for name, sign in (("Upper", 1), ("Lower", -1)):
        ob = empty(name, (0, 0, 0), root)
        k = Kit(name + "Mesh")
        k.cbox((0, 0, sign * S / 4), (S, 0.5, S / 2), "wall_metal", 0.02)
        k.build(ob)
    export("door_secret.glb")


# ---------------------------------------------------------------- experimental weapons
def arc_caster():
    root, k, g = begin("ArcCaster")
    body(k, 1.6, 0.3)
    for sx in (-1, 1):
        k.tube([(sx * 0.14, 0.6, 0), (sx * 0.34, 1.2, 0), (sx * 0.2, 1.9, 0)], 0.06, "metal_burn", 10, spline=14)
        for t in (0.9, 1.25, 1.6):
            g.lathe([(0.1, -0.02), (0.1, 0.02)], 10, "glow_cyan", T(sx * (0.28 if t < 1.5 else 0.25), t, 0), cap0=True, cap1=True)
    g.sphere((0, 1.95, 0), 0.1, "glow_cyan", 8, 12)
    finish(root, k, g, "weapon_arc_caster.glb")


def plasma_cutter():
    root, k, g = begin("PlasmaCutter")
    body(k, 1.3, 0.3, "hull_grey")
    for sx in (-1, 1):
        k.cbox((sx * 0.28, 1.2, 0), (0.08, 1.4, 0.34), "metal_burn", 0.03)
    g.cbox((0, 1.35, 0), (0.42, 1.7, 0.06), "glow_orange", 0)
    k.lathe([(0.34, 0.5), (0.38, 0.58), (0.38, 0.72), (0.34, 0.78)], 16, "hazard")
    finish(root, k, g, "weapon_plasma_cutter.glb")


def rail_lance():
    root, k, g = begin("RailLance")
    body(k, 1.5, 0.34, "hull_dark")
    for sx in (-1, 1):
        k.cbox((sx * 0.16, 1.5, 0), (0.1, 2.6, 0.3), "metal_dark", 0.02)
        k.cbox((sx * 0.1, 1.5, 0), (0.03, 2.5, 0.16), "metal_bare")
    g.cbox((0, 1.5, 0), (0.05, 2.46, 0.05), "glow_blue", 0)
    for i in range(9):
        y = 0.45 + i * 0.26
        k.cbox((0, y, 0), (0.56, 0.1, 0.5), "hull_accent" if i % 3 == 0 else "hull_grey", 0.04)
    finish(root, k, g, "weapon_rail_lance.glb")


def prism_repeater():
    root, k, g = begin("PrismRepeater")
    body(k, 1.4, 0.3, "hull_white")
    k.lathe([(0.26, 0.6), (0.22, 1.35), (0.3, 1.4), (0.3, 1.5), (0.16, 1.52)], 6, "hull_grey")
    for i in range(6):
        k.cbox((0, 1.0, 0.255), (0.08, 0.6, 0.03), "metal_bare", 0, RY(i * 60 + 30))
    g.lathe([(0.001, 1.4), (0.2, 1.72), (0.13, 2.08), (0.001, 2.3)], 6, "glow_crystal")
    finish(root, k, g, "weapon_prism_repeater.glb")


def singularity_launcher():
    root, k, g = begin("SingularityLauncher")
    body(k, 1.5, 0.38, "hull_dark")
    C = T(0, 1.42, 0)
    k.sphere((0, 0, 0), 0.34, "metal_dark", 12, 18, C)
    for i, axis in enumerate((RX(0), RX(90), RZ(90))):
        k.lathe([(0.52, -0.05), (0.62, -0.05), (0.66, 0), (0.62, 0.05), (0.52, 0.05), (0.52, -0.05)], 36, "hull_grey", C @ axis)
        g.lathe([(0.49, -0.02), (0.52, 0), (0.49, 0.02), (0.49, -0.02)], 36, "glow_violet", C @ axis)
    for sx in (-1, 1):
        k.tube([(sx * 0.3, 0.5, 0.1), (sx * 0.62, 1.0, 0), (sx * 0.62, 1.42, 0)], 0.05, "metal_bare", 8, spline=10)
    finish(root, k, g, "weapon_singularity_launcher.glb")


# ---------------------------------------------------------------- experimental missiles
def shell(k, g, length, radius, mat="hull_white", nose="hull_accent"):
    half = length / 2
    k.lathe([(0.001, -half), (radius, -half + 0.03), (radius, half * 0.5)], 14, mat)
    k.lathe([(radius, half * 0.5), (radius * 0.7, half * 0.82), (0.002, half + 0.2)], 14, nose)
    g.lathe([(0.001, -half - 0.08), (radius * 0.72, -half + 0.01)], 14, "glow_orange")
    for a in (45, 135, 225, 315):
        B = RY(a)
        k.add([(0, -half, radius), (0, -half + 0.5, radius), (0, -half + 0.2, radius + 0.26), (0, -half - 0.1, radius + 0.26)], [(0, 1, 2, 3), (3, 2, 1, 0)], "hull_dark", B)


def missile_cluster():
    root, k, g = begin("MissileCluster")
    shell(k, g, 2.0, 0.26)
    for i in range(10):
        for y in (-0.15, 0.25):
            k.sphere((0, y, 0.25), 0.075, "hazard", 5, 8, RY(i * 36))
    k.lathe([(0.27, -0.42), (0.27, -0.36)], 14, "hull_dark")
    finish(root, k, g, "missile_cluster.glb")


def missile_swarm():
    root, k, g = begin("MissileSwarm")
    k.cbox((0, -0.1, 0), (0.86, 1.4, 0.86), "hull_grey", 0.08)
    for ix in (-1, 0, 1):
        for iz in (-1, 0, 1):
            if ix == 0 and iz == 0:
                continue
            M = T(ix * 0.27, 0.6, iz * 0.27)
            k.lathe([(0.1, -0.1), (0.1, 0.1), (0.06, 0.26), (0.002, 0.34)], 10, "hull_accent", M)
            k.lathe([(0.12, -0.02), (0.13, 0), (0.12, 0.02)], 10, "metal_dark", M)
    g.cbox((0, -0.1, 0.44), (0.5, 0.9, 0.012), "glow_green", 0)
    finish(root, k, g, "missile_swarm.glb")


def missile_bunker():
    root, k, g = begin("MissileBunker")
    shell(k, g, 2.4, 0.3, "hull_dark", "metal_burn")
    k.lathe([(0.12, 1.2), (0.09, 2.0), (0.002, 2.5)], 12, "metal_bare")
    for y in (-0.6, -0.1, 0.4):
        k.lathe([(0.31, y), (0.31, y + 0.18)], 14, "hazard")
    finish(root, k, g, "missile_bunker.glb")


def missile_emp():
    root, k, g = begin("MissileEmp")
    shell(k, g, 2.0, 0.24, "hull_grey", "hull_dark")
    for y in (-0.35, -0.1, 0.15, 0.4):
        k.lathe([(0.25, y), (0.34, y + 0.03), (0.34, y + 0.09), (0.25, y + 0.12)], 16, "metal_bare")
    g.lathe([(0.1, 1.08), (0.17, 1.26), (0.002, 1.44)], 12, "glow_cyan")
    finish(root, k, g, "missile_emp.glb")


def missile_mine():
    root, k, g = begin("MissileMine")
    k.sphere((0, 0, 0), 0.6, "hull_dark", 10, 18)
    k.lathe([(0.63, -0.05), (0.63, 0.05)], 24, "hazard", RX(90))
    for i in range(14):
        a = i * 2.4
        d = Vector((math.cos(a) * math.sqrt(1 - ((i + 0.5) / 7 - 1) ** 2), (i + 0.5) / 7 - 1, math.sin(a) * math.sqrt(1 - ((i + 0.5) / 7 - 1) ** 2)))
        M = T(*(d * 0.58)) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
        k.lathe([(0.09, 0), (0.05, 0.28), (0.002, 0.4)], 8, "metal_bare", M)
        g.sphere(tuple(d * 0.6), 0.05, "glow_red", 4, 6)
    finish(root, k, g, "missile_mine.glb")


power_invincible()
power_cloak()
door_secret()
upgrade_dual()
upgrade_overcharge()
plasma_cutter()
arc_caster()
rail_lance()
prism_repeater()
singularity_launcher()
missile_cluster()
missile_swarm()
missile_bunker()
missile_emp()
missile_mine()

"""Reactor core, doors, pickups, the homing missile and the cockpit interior."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from mathutils import Vector  # noqa: E402


def reactor():
    reset_scene()
    root = empty("Reactor")
    k, g = Kit("Frame"), Kit("FrameGlow")
    # Floor pedestal and ceiling clamp: stepped lathes along the vertical (RX(-90) maps +Y to +Z).
    up = RX(90)
    for flip in (1, -1):
        M = SC(1, 1, flip) @ T(0, 0, -11) @ up
        k.lathe([(7.6, -9), (7.6, 0.6), (7.0, 1.0), (6.1, 1.0), (5.6, 2.2), (4.2, 2.6), (3.6, 4.2), (3.3, 4.6), (2.2, 4.7)], 16, "wall_core", M, cap1=True, phase=math.pi / 16)
        k.lathe([(6.3, 1.0), (6.4, 1.1), (6.4, 1.3), (6.1, 1.34)], 16, "hazard", M, phase=math.pi / 16)
        for i in range(16):
            a = (i + 0.5) * 22.5
            B = M @ RY(a) @ T(0, 0, 4.8)
            k.cbox((0, 1.6, 0), (0.42, 3.2, 1.2), "metal_dark", 0.08, B)
            k.cbox((0, 2.6, 0.62), (0.2, 1.0, 0.1), "metal_bare", 0.02, B)
            g.cbox((0, 1.4, 0.62), (0.12, 1.2, 0.02), "glow_amber", 0, B)
        for i in range(8):
            B = M @ RY(i * 45) @ T(0, 2.6, 3.9)
            k.tube([(0, 0, 0), (0, 2.3, -1.4), (0, 3.2, -2.9)], 0.2, "metal_bare", 10, B, spline=12)
            k.cbox((0, 0, 0), (0.7, 0.4, 0.7), "metal_dark", 0.06, B)
    # Containment pylons with insulator stacks that aim at the core.
    for i in range(6):
        B = up @ RY(i * 60)
        k.tube([(0, -8.6, 7.2), (0, -4.0, 8.6), (0, 4.0, 8.6), (0, 8.6, 7.2)], 0.5, "wall_core", 12, B, spline=20)
        for z in range(9):
            y = -3.6 + z * 0.9
            k.lathe([(0.62, y - 0.1), (0.95, y), (0.62, y + 0.1)], 12, "metal_dark", B @ T(0, 0, 8.6))
        C = B @ T(0, 0, 8.6) @ RX(90) @ SC(1, -1, 1)
        k.lathe([(0.8, 0), (0.75, 1.0), (0.4, 1.3), (0.34, 2.2), (0.55, 2.3), (0.55, 2.6), (0.2, 2.66)], 12, "metal_bare", C, cap1=True)
        g.lathe([(0.2, 2.66), (0.001, 2.86)], 12, "glow_core", C)
    k.build(root)
    g.build(root, None)

    # Three gimballed rings, each its own node so Godot can spin them.
    for idx, (radius, phase) in enumerate(((5.4, 0), (4.5, 60), (3.6, 120))):
        ring = Kit(f"Ring{idx}")
        rg = Kit(f"Ring{idx}Glow")
        ring.lathe([(radius - 0.32, -0.3), (radius + 0.12, -0.34), (radius + 0.3, -0.12), (radius + 0.3, 0.12), (radius + 0.12, 0.34), (radius - 0.32, 0.3)], 64, "wall_core", IDENT, phase=0)
        ring.lathe([(radius - 0.32, 0.3), (radius - 0.32, -0.3)], 64, "metal_dark")
        for i in range(24):
            B = RY(i * 15) @ T(0, 0, radius + 0.31)
            ring.cbox((0, 0, 0), (0.5, 0.5, 0.06), "metal_bare" if i % 3 else "hazard", 0.03, B)
            if i % 2 == 0:
                rg.cbox((0, 0, 0.038), (0.34, 0.1, 0.012), "glow_cyan", 0, B)
        ob = ring.build(root)
        ob2 = rg.build(ob, None)
        ob.rotation_euler = (math.radians(phase), math.radians(phase * 0.5), 0)

    core = Kit("Core")
    core.sphere((0, 0, 0), 2.7, "glow_core", 14, 28)
    core.build(root, None)
    shell = Kit("CoreCage")
    for i in range(8):
        B = RZ(i * 45)
        arc = [(math.cos(a / 16 * math.pi) * 3.05, 0, math.sin(a / 16 * math.pi) * 3.05) for a in range(17)]
        shell.tube(arc, 0.07, "metal_dark", 6, B)
    for lat in (-50, 0, 50):
        r = math.cos(math.radians(lat)) * 3.05
        z = math.sin(math.radians(lat)) * 3.05
        shell.lathe([(r - 0.08, -0.06), (r + 0.08, -0.06), (r + 0.08, 0.06), (r - 0.08, 0.06)], 40, "metal_bare", T(0, 0, z) @ up)
    shell.build(root)
    export("reactor.glb")


def door():
    reset_scene()
    root = empty("Door")
    # Modelled facing the corridor axis (+Y), 10x10 opening.
    S = 10.6
    for name, sign in (("Upper", 1), ("Lower", -1)):
        ob = empty(name, (0, 0, 0), root)
        k, g = Kit(name + "Mesh"), Kit(name + "Glow")
        zc = sign * S / 4
        k.cbox((0, 0, zc), (S, 0.8, S / 2), "wall_core", 0.09)
        # Raised structural ribs and the toothed meeting edge.
        for i in range(5):
            x = -S / 2 + S * (i + 0.5) / 5
            for f in (-1, 1):
                k.cbox((x, f * 0.42, zc), (S * 0.14, 0.16, S / 2 - 0.4), "metal_dark", 0.05)
                k.cbox((x, f * 0.5, zc + sign * 0.4), (S * 0.08, 0.08, S / 2 - 1.8), "wall_metal", 0.02)
        for i in range(9):
            x = -S / 2 + S * (i + 0.5) / 9
            for f in (-1, 1):
                k.add([(-0.52, 0, 0), (0.52, 0, 0), (0, 0, -0.42 * sign * 1)], [(0, 1, 2), (2, 1, 0)], "hazard", T(x, f * 0.41, sign * 0.42))
        for f in (-1, 1):
            k.cbox((0, f * 0.46, sign * 0.62), (S * 0.96, 0.12, 0.3), "hazard", 0.03)
            # Glowing lock ring half, recoloured per door in Godot.
            g.cbox((0, f * 0.54, sign * 1.15), (2.6, 0.03, 0.16), "glow_blue", 0)
            # Broad colour bars so the lock colour reads from across a cavern.
            g.cbox((0, f * 0.58, sign * 2.7), (S * 0.74, 0.03, 0.3), "glow_blue", 0)
            for x in (-3.2, -1.6, 0.0, 1.6, 3.2):
                g.cbox((x, f * 0.58, sign * 3.9), (0.9, 0.03, 0.9), "glow_blue", 0, T(x, 0, sign * 3.9) @ RY(45) @ T(-x, 0, -sign * 3.9))
            k.cbox((0, f * 0.5, sign * 1.15), (2.9, 0.06, 0.4), "metal_dark", 0.02)
        k.build(ob)
        g.build(ob, None)
    export("door.glb")


def pickups():
    def base(name):
        reset_scene()
        root = empty(name)
        return root, Kit("Mesh"), Kit("Glow")

    # Shield: cage around a glowing orb.
    root, k, g = base("PickupShield")
    g.sphere((0, 0, 0), 0.5, "glow_cyan", 10, 16)
    for i in range(6):
        k.tube([(math.cos(a / 8 * math.pi) * 0.85, 0, math.sin(a / 8 * math.pi) * 0.85) for a in range(17)], 0.04, "metal_bare", 6, RZ(i * 30))
    k.lathe([(0.82, -0.06), (0.96, -0.06), (0.96, 0.06), (0.82, 0.06)], 24, "hull_grey", RX(90))
    k.build(root)
    g.build(root, None)
    export("pickup_shield.glb")

    # Energy: stacked battery cell.
    root, k, g = base("PickupEnergy")
    k.lathe([(0.3, -0.75), (0.5, -0.7), (0.5, -0.42), (0.34, -0.38)], 12, "hull_grey", RX(90), cap0=True)
    k.lathe([(0.34, 0.38), (0.5, 0.42), (0.5, 0.7), (0.3, 0.75)], 12, "hull_grey", RX(90), cap1=True)
    g.lathe([(0.3, -0.42), (0.34, 0), (0.3, 0.42)], 12, "glow_amber", RX(90))
    for i in range(4):
        k.tube([(0.44 * math.sin(i * 1.57), 0.44 * math.cos(i * 1.57), -0.5), (0.44 * math.sin(i * 1.57), 0.44 * math.cos(i * 1.57), 0.5)], 0.04, "metal_bare", 6)
    k.build(root)
    g.build(root, None)
    export("pickup_energy.glb")

    # Ammo: strapped crate of three missile tips.
    root, k, g = base("PickupAmmo")
    k.cbox((0, 0, 0), (1.4, 0.8, 0.8), "hull_accent", 0.07)
    k.cbox((0, 0, 0.41), (1.0, 0.5, 0.03), "hazard", 0.006)
    for x in (-0.4, 0, 0.4):
        k.cbox((x, 0, 0), (0.1, 0.86, 0.86), "metal_dark", 0.015)
        k.lathe([(0.15, 0.42), (0.15, 0.52), (0.1, 0.72), (0.002, 0.82)], 12, "hull_white", T(x, 0, 0))
    g.cbox((0, -0.41, 0), (0.8, 0.02, 0.1), "glow_red", 0)
    k.build(root)
    g.build(root, None)
    export("pickup_ammo.glb")

    # Access key: a skeleton key spinning about its shaft. A flat key would vanish
    # edge-on, so the head is two crossed rings and the teeth sit on two adjacent sides.
    root, k, g = base("PickupKey")
    up = RX(90)
    ring_radius, tube = 0.42, 0.085
    ring = []
    for a in range(13):
        t = a / 12 * math.tau - math.pi / 2
        ring.append((ring_radius + math.cos(t) * tube, math.sin(t) * tube))
    head = T(0, 0, 0.72)
    g.lathe(ring, 36, "glow_blue", head)
    g.lathe(ring, 36, "glow_blue", head @ RZ(90))
    # Shaft with metal collars so the body catches light against the glow.
    g.lathe([(0.11, -0.95), (0.11, 0.32)], 14, "glow_blue", up, cap0=True, cap1=True)
    for z, r in ((0.3, 0.15), (-0.28, 0.13)):
        k.lathe([(r * 0.8, z - 0.06), (r, z - 0.03), (r, z + 0.03), (r * 0.8, z + 0.06)], 16, "metal_bare", up)
    k.sphere((0, 0, 0.72), 0.13, "metal_bare", 7, 12)
    # Stepped teeth near the tip on two adjacent sides: one side is always in
    # profile as it spins, and the lopsided outline is what makes it read as a key.
    for i in range(2):
        B = RZ(i * 90)
        for z, reach in ((-0.86, 0.4), (-0.62, 0.27), (-0.42, 0.36)):
            g.cbox((0.09 + reach / 2, 0, z), (reach, 0.12, 0.15), "glow_blue", 0.012, B)
    k.build(root)
    g.build(root, None)
    export("pickup_key.glb")


def missile():
    reset_scene()
    root = empty("Missile")
    k, g = Kit("Mesh"), Kit("Glow")
    k.lathe([(0.001, -0.9), (0.15, -0.88), (0.16, -0.7), (0.16, 0.6), (0.13, 0.9), (0.07, 1.15), (0.002, 1.3)], 12, "hull_white", IDENT)
    for y in (-0.5, 0.2):
        k.lathe([(0.163, y), (0.163, y + 0.08)], 12, "hazard")
    k.lathe([(0.163, 0.62), (0.15, 0.82)], 12, "hull_accent")
    for a in (45, 135, 225, 315):
        B = RY(a)
        k.add([(0, -0.88, 0.14), (0, -0.4, 0.14), (0, -0.62, 0.42), (0, -0.92, 0.42)], [(0, 1, 2, 3), (3, 2, 1, 0)], "hull_dark", B)
        k.add([(0, 0.5, 0.14), (0, 0.78, 0.14), (0, 0.6, 0.26), (0, 0.48, 0.26)], [(0, 1, 2, 3), (3, 2, 1, 0)], "hull_dark", B)
    g.lathe([(0.001, -0.97), (0.12, -0.89)], 12, "glow_orange")
    k.build(root)
    g.build(root, None)
    export("missile.glb")


def gear_cannon():
    """Gallery model: one wing-tip pulse cannon, off the ship."""
    reset_scene()
    root = empty("Cannon")
    k, g = Kit("Mesh"), Kit("Glow")
    k.lathe([(0.02, -0.75), (0.2, -0.62), (0.31, -0.3), (0.34, 0.3), (0.32, 1.1), (0.26, 1.72), (0.22, 1.92)], 20, "hull_grey", cap0=True)
    for y in (0.0, 0.34, 0.68, 1.02):
        k.lathe([(0.325, y), (0.352, y + 0.012), (0.352, y + 0.05), (0.325, y + 0.062)], 20, "hull_dark")
    k.lathe([(0.15, 1.94), (0.15, 2.72), (0.13, 2.76)], 16, "metal_dark")
    for i in range(12):
        for j in range(3):
            k.cbox((0, -0.27 + j * 0.27, 0.004), (0.028, 0.2, 0.008), "metal_bare", 0, RY(i * 30) @ T(0, 2.32, 0.15))
    k.lathe([(0.075, 2.6), (0.075, 3.05), (0.1, 3.06), (0.105, 3.25), (0.075, 3.26), (0.075, 3.45), (0.09, 3.46), (0.09, 3.56), (0.05, 3.57), (0.04, 3.2)], 14, "metal_burn")
    g.lathe([(0.036, 3.2), (0.039, 3.56)], 10, "glow_orange")
    k.cbox((0, 0.2, 0.34), (0.2, 0.74, 0.1), "hull_dark", 0.024)
    for i in range(5):
        k.cbox((0, i * 0.1, 0.4), (0.14, 0.05, 0.03), "metal_bare", 0.006)
    k.build(root)
    g.build(root, None)
    export("gear_cannon.glb")


def gear_flare():
    """Gallery model: a flare cartridge with its burner lit."""
    reset_scene()
    root = empty("FlareCartridge")
    k, g = Kit("Mesh"), Kit("Glow")
    k.lathe([(0.001, -0.5), (0.15, -0.5), (0.16, -0.46), (0.16, 0.25), (0.12, 0.3)], 16, "hull_accent", RX(90), cap0=True)
    for z in (-0.32, 0.12):
        k.lathe([(0.163, z), (0.163, z + 0.08)], 16, "hazard", RX(90))
    k.lathe([(0.12, 0.3), (0.1, 0.42)], 16, "metal_bare", RX(90))
    g.lathe([(0.1, 0.42), (0.07, 0.52), (0.002, 0.58)], 12, "glow_amber", RX(90))
    k.build(root)
    g.build(root, None)
    export("gear_flare.glb")


def astronaut():
    """A survivor in a bulky suit, about 1.9 m tall. ArmR pivots at the shoulder to wave."""
    reset_scene()
    root = empty("Astronaut")
    k, g = Kit("Body"), Kit("Glow")
    white, trim, dark = "hull_white", "hull_accent", "hull_dark"
    # Torso, chest control unit and life-support pack.
    k.cbox((0, 0, 0.32), (0.56, 0.36, 0.66), white, 0.1)
    k.cbox((0, 0, -0.06), (0.46, 0.3, 0.16), dark, 0.05)
    k.cbox((0, 0.2, 0.36), (0.3, 0.09, 0.22), trim, 0.03)
    for i in range(3):
        g.cbox((-0.08 + i * 0.08, 0.247, 0.4), (0.045, 0.006, 0.045), "glow_green" if i else "glow_red", 0)
    g.cbox((0, 0.247, 0.31), (0.18, 0.006, 0.05), "glow_screen", 0)
    k.cbox((0, -0.3, 0.36), (0.46, 0.26, 0.72), "hull_grey", 0.07)
    k.cbox((0, -0.44, 0.5), (0.3, 0.04, 0.3), dark, 0.015)
    for sx in (-1, 1):
        k.tube([(sx * 0.16, -0.18, 0.66), (sx * 0.22, 0.02, 0.76), (sx * 0.1, 0.12, 0.72)], 0.028, "metal_bare", 6, spline=8)
    # Helmet with a gold visor and a shoulder ring.
    k.lathe([(0.17, 0.62), (0.21, 0.66), (0.21, 0.7), (0.15, 0.73)], 18, "metal_bare", RX(90))
    k.sphere((0, 0, 0.9), 0.235, white, 10, 20)
    g.sphere((0, 0.085, 0.91), 0.195, "glow_visor", 10, 20)
    k.cbox((0.24, 0, 0.98), (0.03, 0.12, 0.09), dark, 0.01)
    # Legs: thigh, knee joint, shin and boot.
    for sx in (-1, 1):
        k.tube([(sx * 0.15, 0, -0.1), (sx * 0.17, 0.03, -0.46)], 0.115, white, 12)
        k.sphere((sx * 0.17, 0.03, -0.48), 0.125, "hull_grey", 6, 12)
        k.tube([(sx * 0.17, 0.03, -0.5), (sx * 0.17, -0.02, -0.86)], 0.105, white, 12)
        k.tube([(sx * 0.17, 0.02, -0.68), (sx * 0.17, 0.0, -0.74)], 0.112, trim, 12)
        k.cbox((sx * 0.17, 0.05, -0.97), (0.2, 0.36, 0.16), dark, 0.05)
    # Left arm hangs relaxed; the right is its own node so it can wave.
    k.sphere((-0.34, 0, 0.56), 0.115, "hull_grey", 6, 12)
    k.tube([(-0.36, 0, 0.54), (-0.43, 0.04, 0.22)], 0.09, white, 10)
    k.tube([(-0.43, 0.04, 0.22), (-0.44, 0.13, -0.05)], 0.085, white, 10)
    k.tube([(-0.43, 0.06, 0.12), (-0.435, 0.09, 0.06)], 0.092, trim, 10)
    k.sphere((-0.445, 0.15, -0.11), 0.095, trim, 6, 10)
    k.build(root)
    g.build(root, None)
    arm = empty("ArmR", (0.34, 0, 0.56), root)
    a = Kit("ArmRMesh")
    a.sphere((0, 0, 0), 0.115, "hull_grey", 6, 12)
    a.tube([(0, 0, 0), (0.16, 0.02, 0.3)], 0.09, white, 10)
    a.tube([(0.16, 0.02, 0.3), (0.2, 0.03, 0.62)], 0.085, white, 10)
    a.tube([(0.18, 0.02, 0.42), (0.19, 0.03, 0.48)], 0.092, trim, 10)
    a.sphere((0.21, 0.03, 0.7), 0.095, trim, 6, 10)
    a.build(arm)
    export("astronaut.glb")


def cockpit():
    """First-person cabin. Origin is the pilot's eye, looking along +Y.

    A wraparound canopy with lit trim, a slim dash that keeps the forward view
    clear, and mounts (Screen_*) where Godot places live displays.
    """
    reset_scene()
    root = empty("Cockpit")
    k, g = Kit("Frame"), Kit("Trim")

    def bow(y, w, h, base, grow=0.0):
        return [(-math.cos(a / 24 * math.pi) * (w + grow), y, base + math.sin(a / 24 * math.pi) * (h + grow)) for a in range(25)]

    # Canopy: a heavy forward bow with a lit inner edge, and a slim rear bow.
    k.tube(bow(1.35, 2.3, 1.85, -0.62), 0.042, "hull_dark", 10)
    k.tube(bow(1.35, 2.3, 1.85, -0.62, 0.055), 0.018, "hull_accent", 8)
    g.tube(bow(1.33, 2.3, 1.85, -0.62, -0.05), 0.007, "glow_trim", 6)
    k.tube(bow(0.1, 2.5, 1.9, -0.62), 0.03, "hull_dark", 8)
    for sx in (-1, 1):
        # Raked A-pillars, sill rails and a lit strip following each sill.
        k.tube([(sx * 1.72, 1.2, -0.56), (sx * 1.52, 1.34, 0.32), (sx * 1.16, 1.36, 0.98)], 0.03, "hull_dark", 8, spline=10)
        k.tube([(sx * 2.3, 1.35, -0.62), (sx * 2.25, 0.2, -0.64), (sx * 2.0, -0.6, -0.62)], 0.07, "hull_grey", 10, spline=10)
        g.tube([(sx * 2.2, 1.3, -0.56), (sx * 2.16, 0.2, -0.58), (sx * 1.92, -0.6, -0.56)], 0.008, "glow_trim", 6, spline=10)

    # Dash: only a slim strip along the bottom of the screen. Its far edge is close
    # to the pilot on purpose; every metre of depth here costs a band of forward view.
    def dash_top(x):
        return -0.85 + (abs(x) / 2.3) ** 1.7 * 0.1

    rings = []
    lip = []
    span = 26
    for i in range(span + 1):
        x = -2.3 + i / span * 4.6
        top = dash_top(x)
        rings.append([(x, 1.1, top + 0.02), (x, 0.92, top), (x, 0.8, top - 0.1), (x, 0.8, -1.4), (x, 1.1, -1.4)])
        lip.append((x, 1.11, top + 0.02))
    k.loft(rings, "hull_dark", M=IDENT)
    k.tube(lip, 0.014, "hull_grey", 8)
    g.tube([(p[0], p[1], p[2] + 0.02) for p in lip], 0.006, "glow_trim", 6)

    # Display pods in the lower corners, turned in to face the pilot; Godot fills the Screen_* mounts.
    # Each pod is its own mesh under its mount, so moving a mount moves frame and display together.
    for sx, name in ((-1, "Screen_L"), (1, "Screen_R")):
        tilt = RX(-30)
        M = T(sx * 1.08, 1.2, -0.63) @ RZ(-sx * 38) @ tilt
        scr = empty(name, tuple(M.to_translation() + M.to_3x3() @ Vector((0, -0.006, 0.01))), root)
        scr.rotation_mode = "QUATERNION"
        scr.rotation_quaternion = M.to_quaternion()
        pod = Kit("Pod_" + name[-1])
        local = T(0, 0.006, -0.01)
        pod.cbox((0, 0.035, 0), (0.5, 0.05, 0.36), "hull_grey", 0.02, local)
        pod.cbox((0, 0.008, 0), (0.46, 0.02, 0.31), "metal_dark", 0.004, local)
        for i in range(6):
            pod.cbox((-0.2 + i * 0.08, -0.008, -0.165), (0.05, 0.012, 0.016), "glow_dash" if i % 2 else "metal_bare", 0, local)
        pod.build(scr)

    # Side consoles: switch banks, throttle quadrant and stick grip in the lower corners.
    for sx in (-1, 1):
        k.cbox((sx * 1.72, -0.2, -1.0), (0.64, 2.2, 0.3), "hull_dark", 0.05)
        k.cbox((sx * 1.72, -0.2, -0.845), (0.54, 2.0, 0.016), "metal_dark", 0)
        for row in range(3):
            for i in range(9):
                lit = (row + i) % 4 == 0
                g.cbox((sx * (1.54 + row * 0.18), -0.5 + i * 0.16, -0.834), (0.1, 0.06, 0.006), "glow_amber" if lit else "metal_bare", 0)
    k.tube([(-1.2, 0.62, -1.1), (-1.2, 0.72, -0.86)], 0.026, "metal_bare", 8)
    k.cbox((-1.2, 0.74, -0.82), (0.16, 0.12, 0.1), "hull_accent", 0.03)
    k.tube([(1.2, 0.62, -1.1), (1.2, 0.7, -0.88)], 0.03, "metal_bare", 8)
    k.cbox((1.2, 0.72, -0.82), (0.11, 0.13, 0.17), "hull_grey", 0.04)
    g.cbox((1.2, 0.788, -0.77), (0.05, 0.004, 0.03), "glow_red", 0)
    k.build(root)
    g.build(root, None)
    export("cockpit.glb")


# "blender ... props.py -- cockpit" rebuilds only the named models.
only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for build in (reactor, door, pickups, missile, gear_cannon, gear_flare, astronaut, cockpit):
    if not only or build.__name__ in only:
        build()

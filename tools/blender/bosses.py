"""The two machines that guard Smelter Row and Core Zero. Nose is +Y, up is +Z.

crucible - level 4: a walking-pace foundry vessel. Its mouth pours slag, three
           heat vents open on its back to cool after a pour, and a cooling fan turns
           at the rear. Godot animates Mouth, Vent0-2 (hinged hatches), Fan, Arm_L/R.
zero     - level 10: the mind the Overseer was only the voice of. A violet core in
           a lattice cage, six armour petals that open to fire, four conduit pods
           that can be shot off, and two gyroscope rings. Godot animates Core,
           Petal0-5, Conduit0-3, SpinRing and Ring2.

Empties named Weak_* mark the weak points the game checks hits against.
Run: blender -b --factory-startup --python tools/blender/bosses.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from mathutils import Vector  # noqa: E402


def rivet_ring(k, y, radius, count, mat="metal_bare", M=IDENT):
    for i in range(count):
        a = i / count * 360
        k.sphere((0, 0, 0), 0.22, mat, 3, 6, M @ RY(a) @ T(0, y, radius))


def band(k, y, radius, width, depth, mat, M=IDENT, segs=40):
    """A raised hoop around the +Y axis."""
    k.lathe([(radius, y - width / 2), (radius + depth, y - width / 2 + 0.05), (radius + depth, y + width / 2 - 0.05), (radius, y + width / 2)], segs, mat, M)


def hinge_frame(normal, up_hint=(0, 0, 1)):
    """Rotation whose local +Z is the given outward normal."""
    n = Vector(normal).normalized()
    return n.to_track_quat("Z", "X" if abs(n.y) > 0.9 else "Y").to_matrix().to_4x4()


# ---------------------------------------------------------------------- The Crucible
def crucible():
    reset_scene()
    root = empty("Crucible")
    k = Kit("Body")
    g = Kit("Glow")
    # The vessel: a heavy drum lying nose-first, its open mouth at the front.
    profile = [(4.2, -8.6), (6.8, -8.2), (8.4, -6.6), (9.0, -4.0), (9.2, 1.5), (8.8, 4.6), (8.2, 6.0), (8.6, 6.4), (8.6, 7.0), (6.4, 7.2), (5.6, 6.2)]
    k.lathe(profile, 40, "robot_rust", cap0=True)
    # The inner wall of the mouth, glowing at its throat.
    k.lathe([(5.6, 6.2), (5.2, 4.6), (4.2, 3.6)], 40, "metal_burn")
    for y, radius, mat in ((-6.9, 8.3, "metal_dark"), (1.0, 9.15, "hazard"), (4.0, 8.95, "metal_dark")):
        band(k, y, radius, 1.4, 0.35, mat)
        rivet_ring(k, y, radius + 0.45, 24)
    # Lip spout: a forward-pointing pour channel along the bottom of the mouth.
    k.cbox((0, 7.8, -6.4), (4.0, 3.2, 1.0), "metal_dark", 0.25)
    for sx in (-1, 1):
        k.cbox((sx * 2.2, 7.8, -5.8), (0.5, 3.2, 1.6), "metal_burn", 0.12)
    g.cbox((0, 7.9, -5.85), (3.2, 2.9, 0.12), "glow_orange", 0.0)
    # Clamp yoke and arms: the gantry that carries the vessel.
    for sx in (-1, 1):
        k.cbox((sx * 9.7, 0.6, 0.0), (1.6, 6.5, 6.5), "robot_paint", 0.4)
        k.cbox((sx * 10.8, 0.6, 0.0), (0.8, 3.6, 3.6), "metal_dark", 0.2)
        k.lathe([(1.8, -0.8), (1.8, 0.8)], 20, "metal_bare", T(sx * 11.4, 0.6, 0) @ RZ(90), cap0=True, cap1=True)
    for side, sx in (("Arm_L", -1), ("Arm_R", 1)):
        arm = Kit(side)
        # Built around its shoulder pivot, so it can swing.
        arm.cbox((sx * 1.6, 0, -3.2), (1.8, 2.4, 7.0), "robot_paint", 0.3)
        arm.cbox((sx * 1.6, 0.8, -7.4), (2.6, 4.6, 1.6), "metal_dark", 0.3)
        for dy in (-0.8, 0.8, 2.4):
            arm.cbox((sx * 1.6, dy, -8.6), (0.5, 0.6, 1.4), "metal_burn", 0.1)
        arm.tube([(sx * 0.2, -1.2, 1.0), (sx * 2.4, -1.4, -2.0), (sx * 2.6, -1.4, -5.6)], 0.35, "metal_bare", 10)
        arm.tube([(sx * 0.2, 1.2, 1.0), (sx * 2.4, 1.4, -2.0), (sx * 2.6, 1.4, -5.6)], 0.35, "metal_bare", 10)
        ob = arm.build(root)
        ob.location = (sx * 11.6, 0.6, 0.0)
    # Smokestacks with ember caps.
    for sx in (-1, 1):
        base = (sx * 3.4, -5.0, 7.6)
        k.lathe([(1.3, 0), (1.1, 0.6), (1.0, 5.5), (1.3, 5.8), (1.3, 6.4), (0.9, 6.5)], 16, "metal_dark", T(*base) @ RX(90))
        g.lathe([(0.85, 6.3), (0.001, 6.2)], 16, "glow_orange", T(*base) @ RX(90))
    # Slag tanks slung under the belly.
    for sx in (-1, 1):
        k.sphere((sx * 4.6, -2.5, -9.0), 2.4, "metal_burn", 8, 14, squash=0.8)
        band(k, 0, 2.3, 0.5, 0.15, "metal_dark", T(sx * 4.6, -2.5, -9.0) @ RX(90), 20)
    # Drip nozzles under the vessel.
    for x in (-1.6, 0, 1.6):
        k.lathe([(0.6, 0), (0.45, 1.2), (0.55, 1.5)], 12, "metal_dark", T(x, 3.0, -8.6) @ RX(-90))
        g.lathe([(0.35, 1.45), (0.001, 1.5)], 12, "glow_orange", T(x, 3.0, -8.6) @ RX(-90))
    # Mortar tubes on the shoulders, raked forward.
    for sx in (-1, 1):
        M = T(sx * 4.6, 2.5, 8.3) @ RX(55)
        k.cbox((0, 0, 0), (2.6, 1.4, 2.6), "metal_dark", 0.3, M)
        k.lathe([(1.0, -0.2), (1.0, 3.6), (1.25, 3.7), (1.25, 4.4), (0.75, 4.45), (0.7, 3.4)], 16, "metal_burn", M)
        g.lathe([(0.6, 3.5), (0.001, 3.55)], 12, "glow_orange", M)
    # Heat vent sockets: a glowing grate under each hinged hatch.
    vents = [((0, -2.6, 9.0), (0, 0, 1)), ((-8.8, -2.6, 2.4), (-0.96, 0, 0.27)), ((8.8, -2.6, 2.4), (0.96, 0, 0.27))]
    for i, (pos, nrm) in enumerate(vents):
        R = hinge_frame(nrm)
        F = T(*pos) @ R
        k.cbox((0, 0, -0.3), (5.0, 5.0, 0.9), "metal_dark", 0.2, F)
        g.cbox((0, 0, 0.12), (4.0, 4.0, 0.1), "glow_orange", 0.0, F)
        for j in range(5):
            k.cbox((0, -1.6 + j * 0.8, 0.25), (4.2, 0.18, 0.3), "metal_burn", 0.0, F)
        hatch = Kit("Vent%d" % i)
        # Local origin sits on the hinge edge.
        hatch.cbox((0, 2.4, 0.35), (4.8, 4.8, 0.5), "robot_paint", 0.15)
        hatch.cbox((0, 2.4, 0.7), (3.6, 3.6, 0.25), "hazard", 0.08)
        hatch.lathe([(0.4, -2.2), (0.4, 2.2)], 10, "metal_bare", RZ(90) @ T(0, 0, 0), cap0=True, cap1=True)
        ob = hatch.build(root)
        # Hinged at the front, so it lifts away from the clamp yoke.
        ob.matrix_world = T(*pos) @ R @ RZ(180) @ T(0, -2.4, 0.0)
        empty("Weak_Vent%d" % i, tuple(Vector(pos) + Vector(nrm) * 0.8), root)
    # Rear cooling fan in a shroud.
    k.lathe([(4.6, -8.4), (4.8, -9.4), (4.2, -9.6)], 32, "metal_dark")
    fan = Kit("Fan")
    fan.lathe([(1.1, -0.3), (1.1, 0.3)], 16, "metal_dark", cap0=True, cap1=True)
    for i in range(7):
        fan.add([(0.9, -0.15, 0), (4.0, 0.15, 0.6), (4.0, -0.15, -0.6), (0.9, 0.15, 0)], [(0, 1, 2), (0, 2, 3), (2, 1, 0), (3, 2, 0)], "metal_bare", RY(i * 360 / 7))
    ob = fan.build(root)
    ob.location = (0, -9.1, 0)
    g.lathe([(4.2, -8.9), (0.001, -8.8)], 28, "glow_orange")
    # The molten face in the mouth: its own object so the game can make it flare.
    mouth = Kit("Mouth")
    mouth.lathe([(4.6, 4.2), (3.0, 4.5), (1.2, 4.7), (0.001, 4.75)], 32, "glow_orange")
    mouth.build(root)
    empty("Weak_Mouth", (0, 7.4, 0), root)
    # A grate across the mouth and cast teeth round its lip, so it reads as a furnace.
    for x in (-3.6, -1.8, 0.0, 1.8, 3.6):
        h = math.sqrt(max(0.0, 5.9 ** 2 - x * x))
        k.cbox((x, 6.5, 0), (0.45, 0.6, h * 2.0), "metal_dark", 0.08)
    k.cbox((0, 6.5, 0), (11.6, 0.6, 0.45), "metal_dark", 0.08)
    for i in range(14):
        k.add([(-0.7, 0, 0), (0.7, 0, 0), (0, 0.4, -1.3)], [(0, 1, 2), (2, 1, 0)], "metal_burn", RY(i * 360 / 14) @ T(0, 7.0, 6.5))
    g.lathe([(8.85, 5.45), (8.9, 5.6), (8.85, 5.75)], 40, "glow_orange")
    # Stencils.
    k.text("CRUCIBLE", T(0, 2.5, 9.18), 1.1, "hazard", 0.06)
    k.build(root)
    g.build(root, None)
    empty("Muzzle_R", (4.6, 5.4, 12.0), root)
    empty("Muzzle_L", (-4.6, 5.4, 12.0), root)
    export("crucible.glb")


# ---------------------------------------------------------------------- Zero
PETAL_DIRS = [(0, 1, 0), (0, -1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]
CONDUIT_DIRS = [(1, 1, 1), (-1, -1, 1), (-1, 1, -1), (1, -1, -1)]


def petal(name, root, direction, seed):
    """A curved armour cap facing local +Z, rotated to face its direction."""
    p = Kit(name)
    r = random.Random(seed)
    outer, inner, half = 9.4, 8.6, math.radians(41)
    rows, cols = 7, 24
    grid_o, grid_i = [], []
    for i in range(rows + 1):
        lat = half * i / rows
        ro, ri = [], []
        for j in range(cols):
            lo = j / cols * math.tau
            d = Vector((math.sin(lat) * math.cos(lo), math.sin(lat) * math.sin(lo), math.cos(lat)))
            ro.append(tuple(d * outer))
            ri.append(tuple(d * inner))
        grid_o.append(ro)
        grid_i.append(ri)
    p.loft(grid_o[::-1], "robot_shell", True, True, False)
    p.loft(grid_i, "metal_dark", True, False, False)
    # Rim joining the two skins.
    p.loft([grid_i[-1], grid_o[-1]], "metal_burn", True, False, False)
    for j in range(0, cols, 2):
        if r.random() < 0.8:
            p.grid_plate(grid_o, 2, j, rows - 1, j + 2, 0.12, 0.05, "hull_dark" if r.random() < 0.5 else "robot_shell")
    # Seam stripe and a sensor slot.
    p.cbox((0, 0, outer - 0.1), (2.8, 0.9, 0.7), "metal_dark", 0.12)
    p.cbox((0, 0, outer + 0.22), (2.2, 0.25, 0.1), "glow_violet", 0.0)
    ob = p.build(root)
    ob.matrix_world = hinge_frame(direction)
    return ob


def zero():
    reset_scene()
    root = empty("Zero")
    k = Kit("Body")
    g = Kit("Glow")
    core = Kit("Core")
    core.sphere((0, 0, 0), 4.6, "glow_violet", 12, 20)
    core.build(root)
    # The cage: struts along a cuboctahedron's edges, with nodes at its corners.
    corners = []
    for a in (-1, 1):
        for b in (-1, 1):
            corners += [(a, b, 0), (a, 0, b), (0, a, b)]
    corners = [Vector(c).normalized() * 6.6 for c in corners]
    for i, a in enumerate(corners):
        for b in corners[i + 1:]:
            if (a - b).length < 6.7:
                k.tube([tuple(a), tuple(b)], 0.28, "metal_dark", 8)
    for c in corners:
        k.sphere(tuple(c), 0.6, "metal_bare", 4, 8)
    # Conduit arms out to the pods that feed the core.
    for i, d in enumerate(CONDUIT_DIRS):
        n = Vector(d).normalized()
        k.tube([tuple(n * 5.0), tuple(n * 10.0)], 0.9, "metal_burn", 10)
        for t in (6.5, 8.0, 9.3):
            band(k, 0, 1.0, 0.4, 0.25, "metal_dark", T(*(n * t)) @ hinge_frame(n) @ RX(90), 14)
        pod = Kit("Conduit%d" % i)
        pod.lathe([(0.001, -1.6), (1.4, -1.0), (1.7, 0.2), (1.2, 1.4), (0.001, 1.8)], 16, "glow_cyan", RX(90))
        ob = pod.build(root)
        ob.matrix_world = T(*(n * 11.0)) @ hinge_frame(n)
        k.lathe([(2.0, -1.4), (2.2, -0.3), (1.9, -0.1)], 16, "metal_dark", T(*(n * 11.0)) @ hinge_frame(n) @ RX(90))
        empty("Weak_Conduit%d" % i, tuple(n * 11.0), root)
    empty("Weak_Core", (0, 0, 0), root)
    for i, d in enumerate(PETAL_DIRS):
        petal("Petal%d" % i, root, d, 40 + i)
    # Gyroscope rings with emitter studs, so their turning reads.
    ring = Kit("SpinRing")
    ring.lathe([(14.0, -0.7), (14.8, -0.7), (15.1, 0), (14.8, 0.7), (14.0, 0.7), (13.8, 0), (14.0, -0.7)], 72, "wall_core", RX(90))
    for i in range(12):
        ring.cbox((14.9, 0, 0), (1.8, 1.0, 1.8), "hazard" if i % 3 == 0 else "metal_dark", 0.12, RZ(i * 30))
        g.cbox((15.6, 0, 0), (0.3, 0.5, 0.9), "glow_violet", 0.0, RZ(i * 30 + 15))
    ring.build(root)
    ring2 = Kit("Ring2")
    ring2.lathe([(16.4, -0.5), (17.0, -0.5), (17.2, 0), (17.0, 0.5), (16.4, 0.5), (16.2, 0), (16.4, -0.5)], 80, "metal_dark")
    for i in range(8):
        ring2.cbox((0, 0, 17.1), (2.2, 1.2, 1.0), "robot_shell", 0.12, RY(i * 45))
        g.cbox((0, 0, 17.7), (1.2, 0.3, 0.3), "glow_violet", 0.0, RY(i * 45 + 22.5))
    ring2.build(root)
    # Mounting spars from the cage to the inner ring, so nothing floats.
    for a in (0, 90, 180, 270):
        k.tube([(0, 0, 0), (13.8, 0, 0)], 0.45, "metal_dark", 8, RZ(a + 45))
    k.build(root)
    g.build(root, None)
    empty("Muzzle_R", (5.0, 9.6, 0.0), root)
    empty("Muzzle_L", (-5.0, 9.6, 0.0), root)
    export("zero.glb")


which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for build in (crucible, zero):
    if not which or build.__name__ in which:
        build()

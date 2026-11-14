"""WREN-9 tunnel interceptor: the player's ship, built entirely from code.

An original forward-swept, twin-engine design: armoured lifting fuselage, glazed
cockpit with a modelled interior, wing-tip gun hardpoints, dorsal radiator spine,
V-tail, missile pylons, and layers of panels, conduits, vents and RCS blocks.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import *  # noqa: E402,F403
from kit import catmull, glow_disk, nozzle, thruster_quad  # noqa: E402

reset_scene()
random.seed(9)

root = empty("Wren9")
hull = Kit("Hull")
glass = Kit("Canopy")
glow = Kit("EngineGlow")


# ------------------------------------------------------------------ fuselage
def section(y, w, top, bot, zc):
    """Faceted 20-point cross-section, ordered +Z -> +X -> -Z -> -X."""
    half = [(0.0, top), (0.3, 0.985), (0.58, 0.9), (0.8, 0.66), (0.95, 0.3), (1.0, 0.0), (0.95, -0.34), (0.8, -0.74), (0.5, -0.97), (0.22, -1.0), (0.0, -1.0)]
    pts = []
    for i, (px, pz) in enumerate(half):
        z = top if i == 0 else (pz * top if pz > 0 else pz * bot)
        pts.append((px * w, y, zc + z))
    for px, y2, z in reversed(pts[1:-1]):
        pts.append((-px, y2, z))
    return pts


KEYS = [
    (-3.25, 0.74, 0.40, 0.36, 0.02),
    (-2.6, 1.02, 0.54, 0.44, 0.02),
    (-1.5, 1.18, 0.68, 0.50, 0.0),
    (-0.4, 1.14, 0.78, 0.50, 0.0),
    (0.7, 1.00, 0.76, 0.44, 0.0),
    (1.6, 0.84, 0.60, 0.38, -0.03),
    (2.5, 0.60, 0.40, 0.29, -0.08),
    (3.3, 0.33, 0.22, 0.17, -0.12),
    (3.95, 0.08, 0.05, 0.05, -0.14),
]
ROWS = 40
rows = catmull(KEYS, ROWS)
grid = [section(*r) for r in rows]
COLS = len(grid[0])
CANOPY_Y = (0.5, 2.5)


def in_canopy(r, c):
    y = rows[r][0]
    return CANOPY_Y[0] < y < CANOPY_Y[1] and (c <= 2 or c >= COLS - 2)


hull.loft(grid, "hull_white", skip=in_canopy)

# Layered armour plating following the hull grid.
plate_rng = random.Random(4)
r = 1
while r < ROWS - 4:
    span = plate_rng.randint(2, 4)
    r2 = min(r + span, ROWS - 2)
    y_low, y_high = rows[r][0], rows[r2][0]
    for c0, c1 in ((1, 3), (3, 5), (5, 7), (7, 9), (9, 11), (11, 13), (13, 15), (15, 17), (17, 19)):
        if y_high > CANOPY_Y[0] - 0.15 and y_low < CANOPY_Y[1] + 0.15 and (c0 < 3 or c1 > 17):
            continue
        roll = plate_rng.random()
        if roll < 0.14:
            continue
        mat = "hull_accent" if (roll > 0.8 and 3 <= c0 <= 15) else ("hull_grey" if roll > 0.6 else "hull_white")
        hull.grid_plate(grid, r, c0, r2, c1, plate_rng.uniform(0.014, 0.034), 0.016, mat)
    r = r2

# Rivet lines along major seams.
for r_i in range(2, ROWS - 8, 6):
    for c in (4, 6, 14, 16):
        a = Vector(grid[r_i][c])
        b = Vector(grid[r_i + 5][c])
        n = Vector((a.x, 0, a.z - rows[r_i][4])).normalized()
        hull.stud_row(a + n * 0.03, b + n * 0.03, 5, n, 0.013, 0.022, "metal_bare")

# Nose: sensor cone, radome joint, pitot probes, chin gimbal.
hull.lathe([(0.11, 3.86), (0.13, 3.95), (0.09, 4.14), (0.03, 4.3), (0.002, 4.38)], 16, "hull_dark", T(0, 0, -0.14))
hull.lathe([(0.14, 3.72), (0.15, 3.9)], 16, "metal_bare", T(0, 0, -0.14))
for sx in (-1, 1):
    hull.tube([(sx * 0.13, 3.25, -0.05), (sx * 0.22, 3.5, -0.05), (sx * 0.23, 4.05, -0.05)], 0.011, "metal_bare", 6)
    hull.lathe([(0.016, 3.95), (0.016, 4.06), (0.004, 4.13)], 6, "glow_red" if sx < 0 else "metal_dark", T(sx * 0.23, 0, -0.05))
chin = T(0, 2.78, -0.42)
hull.lathe([(0.2, 0), (0.24, 0.06), (0.24, 0.14), (0.2, 0.2)], 20, "hull_dark", chin @ RX(-90) @ T(0, -0.1, 0))
hull.sphere((0, 0, -0.14), 0.19, "metal_dark", 8, 18, chin)
hull.lathe([(0.1, 0.13), (0.125, 0.17), (0.125, 0.22), (0.08, 0.24)], 18, "metal_bare", chin @ T(0, 0, -0.14), cap1=True)
glow.lathe([(0.076, 0.241), (0.001, 0.26)], 18, "glow_cyan", chin @ T(0, 0, -0.14))

# Ventral keel with access hatches and landing gear doors.
keel_sections = []
for y, h, w in ((-2.9, 0.02, 0.1), (-2.2, 0.17, 0.2), (-0.6, 0.21, 0.26), (1.0, 0.16, 0.2), (2.1, 0.02, 0.08)):
    z = -0.52 if y < 1 else -0.42
    keel_sections.append([(0, y, z), (w, y, z), (w * 0.7, y, z - h), (-w * 0.7, y, z - h), (-w, y, z)])
hull.loft(keel_sections, "hull_grey")
for i, y in enumerate((-1.75, -0.65, 0.42)):
    for sx in (-1, 1):
        hull.cbox((sx * 0.46, y, -0.545), (0.42, 0.86, 0.022), "hull_dark", 0.008)
        hull.stud_row((sx * 0.3, y - 0.36, -0.558), (sx * 0.3, y + 0.36, -0.558), 6, (0, 0, -1), 0.012, 0.014, "metal_bare")
    hull.cbox((0, y, -0.73), (0.2, 0.34, 0.03), "hazard", 0.006)

# ------------------------------------------------------------------ cockpit
RIM_Y = [2.55, 2.1, 1.6, 1.1, 0.75, 0.46]
RIM_W = [0.3, 0.52, 0.64, 0.68, 0.62, 0.46]
RIM_Z = [0.26, 0.44, 0.58, 0.68, 0.72, 0.72]
RIM_H = [0.03, 0.3, 0.46, 0.5, 0.42, 0.1]


def canopy_ring(i, grow=0.0, n=12):
    pts = []
    w, zb, h, y = RIM_W[i] + grow, RIM_Z[i], RIM_H[i] + grow, RIM_Y[i]
    for s in range(n + 1):
        a = math.pi * s / n
        pts.append((-math.cos(a) * w, y, zb + math.sin(a) ** 0.72 * h))
    return pts


ring_keys = [tuple(c for p in canopy_ring(i) for c in p) for i in range(len(RIM_Y))]
smooth = catmull(ring_keys, 22)
glass_rings = [[(row[j], row[j + 1], row[j + 2]) for j in range(0, len(row), 3)] for row in smooth]
# rows run nose->tail, so reverse the ring order for outward normals.
glass.loft([list(reversed(rg)) for rg in glass_rings], "glass", closed=False)

# Frame bows and spine.
for i in (0, 1, 3, 4, 5):
    hull.tube(canopy_ring(i, 0.012), 0.024, "hull_dark", 8)
spine = [(0.0, RIM_Y[i], RIM_Z[i] + RIM_H[i] + 0.012) for i in range(len(RIM_Y))]
hull.tube(spine, 0.03, "hull_dark", 8, spline=16)
for side in (0, 12):
    rail = [canopy_ring(i, 0.015)[side] for i in range(len(RIM_Y))]
    hull.tube(rail, 0.045, "hull_grey", 8, spline=18)

# Cockpit tub, seat, pilot and instrument consoles beneath the glass.
# The tub is an inward-facing loft under the canopy rim, so it follows the hull taper.
tub = []
for i in reversed(range(len(RIM_Y))):
    w, y, z = RIM_W[i] * 0.97, RIM_Y[i], RIM_Z[i] - 0.015
    tub.append([(-w, y, z), (-w * 0.82, y, 0.3), (w * 0.82, y, 0.3), (w, y, z)])
hull.loft(tub, "metal_dark", closed=False)
for sx in (-1, 1):
    hull.cbox((sx * 0.5, 1.15, 0.46), (0.2, 1.1, 0.2), "hull_dark", 0.018)
    for j in range(6):
        hull.cbox((sx * (0.42 + j % 3 * 0.075), 0.86 + (j // 3) * 0.17, 0.568), (0.05, 0.1, 0.022), "glow_green" if j == 4 else "metal_bare", 0.006)
hull.cbox((0, 0.92, 0.5), (0.5, 0.1, 0.32), "hull_dark", 0.02)
hull.cbox((0, 0.9, 0.82), (0.44, 0.1, 0.42), "hull_dark", 0.03, RX(-12) @ T(0, 0.14, 0.02))
hull.cbox((0, 0.84, 0.47), (0.56, 0.3, 0.1), "hull_grey", 0.012)
hull.cbox((0, 0.97, 1.06), (0.26, 0.05, 0.16), "hull_grey", 0.02, RX(-12) @ T(0, 0.15, 0.02))
hull.sphere((0, 1.06, 0.95), 0.14, "hull_accent", 8, 16)
hull.sphere((0, 1.115, 0.955), 0.1, "glass", 6, 14, squash=0.9)
hull.cbox((0, 1.05, 0.68), (0.34, 0.2, 0.34), "hull_dark", 0.05)
hull.cbox((0, 1.48, 0.46), (0.05, 0.05, 0.3), "metal_bare", 0.01, RX(14))
hull.cbox((0, 2.08, 0.53), (0.66, 0.2, 0.17), "hull_dark", 0.024)
for sx in (-0.2, 0.2, 0.0):
    M = T(sx, 1.97, 0.585) @ RX(38)
    hull.cbox((0, 0, 0), (0.17, 0.016, 0.13), "metal_dark", 0.003, M)
    hull.cbox((0, -0.011, 0), (0.15, 0.006, 0.11), "glow_screen", 0.0, M)

# ------------------------------------------------------------------ wings
def wing_section(x, y_le, chord, z, thick):
    prof = [(0.0, 0.0), (0.06, 0.55), (0.24, 1.0), (0.55, 0.85), (0.85, 0.34), (1.0, 0.04), (1.0, -0.04), (0.85, -0.3), (0.55, -0.68), (0.24, -0.82), (0.06, -0.48)]
    return [(x, y_le - p[0] * chord, z + p[1] * thick) for p in prof]


WING_KEYS = [
    (0.74, 0.62, 2.8, -0.04, 0.17),
    (1.5, 1.05, 2.25, -0.16, 0.13),
    (2.4, 1.72, 1.76, -0.27, 0.095),
    (3.05, 2.15, 1.42, -0.34, 0.075),
]
WING_ROWS = 16
wing_stations = catmull(WING_KEYS, WING_ROWS)
wing_grid = [wing_section(*s) for s in wing_stations]


def add_wing(sx):
    M = SC(sx, 1, 1)
    # Lofted panel, with plates along the upper surface.
    if sx > 0:
        hull.loft(wing_grid, "hull_white", cap0=False, cap1=True)
    else:
        hull.loft([[(-p[0], p[1], p[2]) for p in reversed(rg)] for rg in wing_grid], "hull_white", cap0=False, cap1=True)
    grid = wing_grid if sx > 0 else [[(-p[0], p[1], p[2]) for p in reversed(rg)] for rg in wing_grid]
    rng = random.Random(21 * sx)
    stations = list(range(0, WING_ROWS - 1, 2))
    for st0, st1 in zip(stations, stations[1:] + [WING_ROWS - 1]):
        # Plates on upper chord; indices vary because the mirrored wing reverses ring order.
        spans = ((1, 3), (3, 5)) if sx > 0 else ((7, 9), (5, 7))
        for c0, c1 in spans:
            hull.grid_plate(grid, st0, c0, st1, c1, rng.uniform(0.008, 0.02), 0.012, "hull_accent" if st0 % 6 == 0 and c0 == spans[0][0] else "hull_grey" if rng.random() < 0.3 else "hull_white")
        # Lower surface
        spans = ((6, 8), (8, 10)) if sx > 0 else ((2, 4), (0, 2))
        for c0, c1 in spans:
            hull.grid_plate(grid, st0, c0, st1, c1, 0.012, 0.012, "hull_dark")

    # Leading edge cuff, control flap and tracks in mirrored local space.
    flap_ins = [(1.02, 2.1), (1.95, 3.0)]
    for x0, x1 in flap_ins:
        s0 = [s for s in wing_stations if s[0] >= x0][0]
        s1 = [s for s in wing_stations if s[0] >= x1 - 0.02 or s is wing_stations[-1]][0]
        y0 = s0[1] - s0[2]
        y1 = s1[1] - s1[2]
        chord0 = s0[2] * 0.2
        chord1 = s1[2] * 0.2
        flap = [
            [(x0, y0 + chord0, s0[3] + 0.018), (x0, y0 + 0.06, s0[3] + 0.006), (x0, y0 + 0.06, s0[3] - 0.012), (x0, y0 + chord0, s0[3] - 0.024)],
            [(x1, y1 + chord1, s1[3] + 0.018), (x1, y1 + 0.06, s1[3] + 0.006), (x1, y1 + 0.06, s1[3] - 0.012), (x1, y1 + chord1, s1[3] - 0.024)],
        ]
        hull.loft(flap, "hull_accent", M=M)
        # Actuator housings beneath the flap hinge.
        for t in (0.25, 0.75):
            xm = x0 + (x1 - x0) * t
            ym = y0 + (y1 - y0) * t + (chord0 + chord1) * 0.5
            zm = s0[3] + (s1[3] - s0[3]) * t - 0.07
            hull.cbox((xm, ym, zm), (0.05, 0.42, 0.075), "hull_dark", 0.016, M)
            hull.tube([(xm, ym + 0.2, zm), (xm, ym - 0.24, zm)], 0.011, "metal_bare", 6, M)

    # Wing-root vortex fence and walkway stripes.
    for x, h in ((1.6, 0.09), (2.5, 0.07)):
        s = min(wing_stations, key=lambda q: abs(q[0] - x))
        fence = [(x, s[1] + 0.02, s[3] + s[4] * 0.4), (x, s[1] - s[2] * 0.75, s[3] + s[4] * 0.8), (x, s[1] - s[2] * 0.75, s[3] + s[4] * 0.8 + h), (x, s[1] - 0.1, s[3] + s[4] + h * 0.8)]
        hull.add(fence + [(p[0] + 0.012, p[1], p[2]) for p in fence], [(0, 1, 2, 3), (7, 6, 5, 4), (4, 5, 1, 0), (5, 6, 2, 1), (6, 7, 3, 2), (7, 4, 0, 3)], "hull_grey", M)
    s = wing_stations[3]
    M2 = M @ T(s[0] + 0.04, s[1] - s[2] * 0.42, s[3] + s[4] + 0.022)
    if sx > 0:
        hull.text("NO STEP", M2 @ RZ(-90), 0.09, "hull_dark")

    # ------------------------------------------------------------- wing tip hardpoint pod
    # The gun itself is a separate model (ship_mounts.py) bolted to Mount_Gun_*.
    pod = M @ T(3.12, 0, -0.34) @ SC(0.8, 1.0, 0.8)
    # Short, so the mounted gun forms the front half of the pod and reads from behind.
    hull.lathe([(0.02, -0.75), (0.2, -0.62), (0.31, -0.3), (0.34, 0.3), (0.33, 0.8), (0.27, 1.0), (0.25, 1.04)], 16, "hull_grey", pod, cap0=True, cap1=True)
    for y in (0.0, 0.34, 0.68):
        hull.lathe([(0.325, y), (0.352, y + 0.012), (0.352, y + 0.05), (0.325, y + 0.062)], 16, "hull_dark", pod)
    # Hardpoint face plate with locking lugs.
    hull.lathe([(0.27, 1.0), (0.29, 1.02), (0.29, 1.1), (0.14, 1.11)], 16, "metal_dark", pod, cap1=True)
    for a in (45, 135, 225, 315):
        hull.cbox((0, 1.06, 0.26), (0.07, 0.09, 0.06), "metal_bare", 0.01, pod @ RY(a))

    # Ammunition feed and pod pylon.
    hull.cbox((0, 0.2, 0.33), (0.2, 0.74, 0.1), "hull_dark", 0.024, pod)
    for i in range(5):
        hull.cbox((0, 0.0 + i * 0.1, 0.39), (0.14, 0.05, 0.03), "metal_bare", 0.006, pod)
    hull.cbox((0, 0.6, -0.34), (0.16, 0.6, 0.06), "hull_dark", 0.016, pod)
    # Tip nav light + tiny aft engine.
    glow.sphere((0, 0.8, 0.34), 0.035, "glow_red" if sx < 0 else "glow_green", 5, 8, pod)
    hull.lathe([(0.12, -0.72), (0.15, -0.9), (0.14, -0.94), (0.12, -0.92)][::-1], 14, "metal_burn", pod)
    glow.lathe([(0.001, -0.86), (0.11, -0.84)], 14, "glow_engine", pod)

    # RCS blocks, one top and one bottom of the wing.
    thruster_quad(hull, (2.3, 0.15, -0.14), M)
    thruster_quad(hull, (0, 0, 0), M @ T(2.3, 0.15, -0.38) @ RY(180))

    # ------------------------------------------------------------- missile pylon
    # One hardpoint per wing; the rack and rounds hang from Mount_Missile_*.
    P = M @ T(2.15, 0.85, -0.45)
    hull.loft([[(-0.03, 0.5, 0.16), (0.03, 0.5, 0.16), (0.03, 0.44, -0.06), (-0.03, 0.44, -0.06)], [(-0.03, -0.62, 0.16), (0.03, -0.62, 0.16), (0.03, -0.4, -0.06), (-0.03, -0.4, -0.06)]][::-1], "hull_dark", M=P)
    hull.cbox((0, 0.03, -0.09), (0.08, 0.86, 0.06), "metal_dark", 0.012, P)


add_wing(1)
add_wing(-1)

# ------------------------------------------------------------------ intakes and side systems
for sx in (-1, 1):
    M = SC(sx, 1, 1)
    # Trapezoid intake duct riding the fuselage flank.
    rows_d = []
    for y, off, w, h in ((-1.6, 0.0, 0.05, 0.16), (-0.8, 0.0, 0.24, 0.26), (0.2, 0.0, 0.32, 0.33), (0.96, 0.0, 0.34, 0.36), (1.08, 0.0, 0.34, 0.36)):
        x = 1.04 - (0.1 if y > 0.2 else 0)
        rows_d.append([(x, y, 0.08 + h), (x + w, y, 0.05 + h * 0.85), (x + w * 1.08, y, 0.0 - h * 0.45), (x, y, 0.0 - h)])
    hull.loft(rows_d, "hull_grey", cap0=True, cap1=False, M=M)
    # Hazard lip and recessed compressor fan.
    x = 0.94
    lip = [(x + 0.04, 1.09, 0.42), (x + 0.32, 1.09, 0.34), (x + 0.36, 1.09, -0.16), (x + 0.04, 1.09, -0.34)]
    inner = [(x + 0.08, 1.09, 0.35), (x + 0.26, 1.09, 0.29), (x + 0.3, 1.09, -0.12), (x + 0.08, 1.09, -0.27)]
    verts = lip + inner + [(p[0], 0.6, p[2]) for p in inner]
    faces = [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)]
    hull.add(verts, faces, "hazard", M)
    well = [(4 + (i + 1) % 4, 8 + (i + 1) % 4, 8 + i, 4 + i) for i in range(4)]
    hull.add(verts, well + [(8, 9, 10, 11)], "metal_dark", M)
    hub = M @ T(x + 0.18, 0.62, 0.03)
    hull.lathe([(0.0, 0.2), (0.07, 0.16), (0.08, 0.02)][::-1], 12, "metal_bare", hub)
    for i in range(14):
        a = i * 360 / 14
        hull.cbox((0, 0.04, 0.18), (0.075, 0.018, 0.22), "metal_bare", 0, hub @ RY(a) @ RZ(32))
    for i in range(6):
        hull.cbox((x + 0.18, 1.04, -0.2 + i * 0.09), (0.3, 0.02, 0.012), "metal_dark", 0, M)
    # Conduit bundle running from intake to engine bay, with clamps.
    for j, (dz, rad, mat) in enumerate(((0.3, 0.022, "metal_bare"), (0.24, 0.03, "hull_accent"), (0.17, 0.018, "metal_dark"))):
        hull.tube([(1.14, 0.95, dz - 0.02), (1.2, 0.1, dz), (1.22, -1.0, dz + 0.02), (1.14, -1.8, dz + 0.02), (0.98, -2.55, dz)], rad, mat, 8, M, spline=20)
    for y in (0.7, 0.05, -0.65, -1.3):
        hull.cbox((1.21, y, 0.24), (0.07, 0.05, 0.2), "hull_dark", 0.012, M)
    # Exhaust vent louvres aft of the intake, with heat glow behind.
    glow.cbox((1.12, -1.7, -0.14), (0.02, 0.56, 0.2), "glow_orange", 0, M)
    for i in range(7):
        hull.cbox((1.15, -1.45 - i * 0.08, -0.14), (0.05, 0.03, 0.26), "hull_dark", 0.004, M @ T(0, 0, 0))
    B = M @ T(0.8, 2.1, 0.02) @ RY(62)
    thruster_quad(hull, (0, 0, 0.02), B, 0.1)
    B = M @ T(1.2, -2.25, -0.06) @ RY(90)
    thruster_quad(hull, (0, 0, 0.04), B, 0.12)
    # Formation strip light on the flank.

# ------------------------------------------------------------------ dorsal spine and radiators
spine_rows = []
for y, h, w in ((0.3, 0.0, 0.12), (-0.25, 0.14, 0.22), (-1.5, 0.22, 0.3), (-2.6, 0.2, 0.3), (-3.25, 0.1, 0.24)):
    z = 0.72 if y > -1.6 else (0.62 if y > -2.7 else 0.44)
    spine_rows.append([(0, y, z + h), (w * 0.72, y, z + h * 0.7), (w, y, z), (w, y, z - 0.2), (-w, y, z - 0.2), (-w, y, z), (-w * 0.72, y, z + h * 0.7)])
hull.loft(spine_rows[::-1], "hull_grey")
# Radiator block: a stack of fins either side of the spine.
for sx in (-1, 1):
    M = SC(sx, 1, 1)
    for i in range(26):
        y = -0.55 - i * 0.075
        h = 0.14 + 0.04 * math.sin(i * 0.37)
        hull.cbox((0.27, y, 0.74), (0.2, 0.024, h), "metal_bare" if i % 5 else "hull_accent", 0, M)
    glow.cbox((0.17, -1.5, 0.72), (0.01, 1.86, 0.18), "glow_orange", 0, M)
    hull.cbox((0.38, -1.5, 0.74), (0.024, 2.02, 0.2), "hull_dark", 0.006, M)
    hull.tube([(0.26, -0.4, 0.62), (0.32, -1.5, 0.6), (0.26, -2.6, 0.5)], 0.024, "metal_bare", 8, M, spline=14)

# Sensor mast and comm blade.
hull.cbox((0, -0.28, 0.98), (0.05, 0.3, 0.28), "hull_dark", 0.01, RX(-20) @ T(0, 0.3, 0.3))
for h, w in ((1.2, 0.44), (1.08, 0.3), (0.98, 0.2)):
    hull.tube([(-w / 2, -0.28, h), (w / 2, -0.28, h)], 0.008, "metal_bare", 5)
for i, (x, y, l) in enumerate(((-0.2, -0.6, 0.5), (-0.26, -0.7, 0.34), (-0.14, -2.75, 0.42))):
    hull.lathe([(0.012, 0.0), (0.006, l)], 5, "metal_dark", T(x, y, 0.82) @ RX(-90 + 8))

# ------------------------------------------------------------------ V-tail
def fin(sx):
    M = SC(sx, 1, 1) @ T(0.54, 0, 0.58) @ RY(30)
    sec = lambda z, y0, c, t: [(0.0, y0, z), (t * 0.8, y0 - c * 0.26, z), (t, y0 - c * 0.5, z), (t * 0.6, y0 - c * 0.85, z), (0.004, y0 - c, z), (-t * 0.6, y0 - c * 0.85, z), (-t, y0 - c * 0.5, z), (-t * 0.8, y0 - c * 0.26, z)]
    keys = [(0.0, -1.55, 1.68, 0.06), (0.3, -1.85, 1.44, 0.05), (0.72, -2.32, 1.08, 0.038), (1.08, -2.72, 0.8, 0.026)]
    rings = [sec(*k) for k in keys]
    # Ring points run -> +x going aft, so reverse for outward normals on the loft.
    hull.loft([list(reversed(r)) for r in rings], "hull_white", M=M)
    hull.loft([[(-0.066, -1.5, 0.02), (0.066, -1.5, 0.02), (0.066, -3.26, 0.02), (-0.066, -3.26, 0.02)], [(-0.09, -1.5, -0.24), (0.09, -1.5, -0.24), (0.09, -3.26, -0.24), (-0.09, -3.26, -0.24)]], "hull_grey", M=M)
    # Rudder panel, hazard strip tip, and registration text.
    hull.loft([[(-0.038, -3.0, 0.1), (0.038, -3.0, 0.1), (0.038, -3.28, 0.1), (-0.038, -3.28, 0.1)], [(-0.02, -3.33, 1.08), (0.02, -3.33, 1.08), (0.02, -3.54, 1.08), (-0.02, -3.54, 1.08)]][::-1], "hull_accent", M=M)
    hull.cbox((0, -3.08, 1.02), (0.07, 0.72, 0.1), "hazard", 0.012, M)
    glow.sphere((0, -3.38, 1.1), 0.03, "glow_white", 5, 8, M)
    for face in (1, -1):
        # The extra X mirror cancels the mirrored fin so the lettering stays readable.
        Q = M @ T(face * 0.058, -2.4, 0.42) @ RY(face * 90) @ RZ(face * 90) @ SC(sx, 1, 1)
        hull.text("WR-9", Q, 0.22, "hull_dark", 0.004)


fin(1)
fin(-1)

# ------------------------------------------------------------------ main engines
for sx in (-1, 1):
    M = SC(sx, 1, 1) @ T(0.52, -2.95, 0.02)
    hull.lathe([(0.6, -0.1), (0.62, 0.0), (0.68, 0.5), (0.7, 1.1), (0.62, 1.5)], 28, "hull_grey", M)
    for y in (0.08, 0.3, 0.72, 1.05):
        hull.lathe([(0.65 + y * 0.05, y), (0.71 + y * 0.03, y + 0.015), (0.71 + y * 0.03, y + 0.06), (0.65 + y * 0.05, y + 0.075)], 28, "hull_dark", M)
    for i in range(10):
        hull.cbox((0, 0.42, 0.68), (0.09, 0.42, 0.024), "metal_bare", 0.006, M @ RY(i * 36 + 18))
    Bell = nozzle(hull, M @ T(0, -0.1, 0), 0.54, 0.9, petals=18)
    glow_disk(glow, Bell @ T(0, -0.1, 0), 0.4)
    empty(f"EngineFX_{'R' if sx > 0 else 'L'}", (sx * 0.52, -3.95, 0.02), root)

# Aft fairing between the engines and the APU exhaust.
hull.cbox((0, -3.15, 0.0), (0.46, 0.5, 0.7), "hull_dark", 0.06)
hull.lathe([(0.1, 0), (0.14, -0.22), (0.13, -0.24), (0.08, -0.05)][::-1], 14, "metal_burn", T(0, -3.35, 0.15))
glow.lathe([(0.001, -0.14), (0.09, -0.12)], 14, "glow_orange", T(0, -3.35, 0.15))
for sx in (-1, 1):
    hull.cbox((sx * 0.14, -3.41, -0.2), (0.1, 0.02, 0.22), "hazard", 0.004)


hull_ob = hull.build(root)
glass.build(root, sharp_deg=None)
glow.build(root, sharp_deg=None)

# Attachment points read by the Godot player script.
# Mount_* are hardpoints scripts/ship_loadout.gd bolts the equipped weapons to; the
# _L ones are mirrored so a model built for the right side fits the left.
# Muzzle_* and MissilePort_* stay as fallbacks for a ship with nothing mounted.
for sx, side in ((1, "R"), (-1, "L")):
    empty(f"Mount_Gun_{side}", (sx * 3.12, 1.11, -0.34), root).scale = (sx, 1, 1)
    empty(f"Mount_Missile_{side}", (sx * 2.15, 0.85, -0.57), root).scale = (sx, 1, 1)
    empty(f"Muzzle_{side}", (sx * 3.12, 3.3, -0.34), root)
    empty(f"MissilePort_{side}", (sx * 2.15, 1.6, -0.85), root)

print(f"[ship] total triangles: {hull.tris + glass.tris + glow.tris}")
export("wren9.glb")

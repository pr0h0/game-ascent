"""Second round of player-ship concepts: four compact tunnel fighters in the WREN-9's spirit.

Not used by the game. Same scale and axes as wren9.glb (+Y nose, +Z up, roughly 7-8 m
long), same material names, similar detail density. Each one is meant to read as a
tough little ship that fits in a mine corridor and brawls with robots up close.

Run with: blender -b --factory-startup --python tools/blender/ship_concepts_v2.py -- [name ...]
Writes tools/concepts/v2_<name>.glb.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit import RX, RY, RZ, SC, T, Kit, Vector, catmull, empty, export, glow_disk, nozzle, reset_scene, thruster_quad  # noqa: E402

OUT = "../../tools/concepts/v2_%s.glb"

# Half cross-sections, top centre -> right flank -> bottom centre (mirrored for the left).
ROUND = [(0.0, 1.0), (0.3, 0.985), (0.58, 0.9), (0.8, 0.66), (0.95, 0.3), (1.0, 0.0), (0.95, -0.34), (0.8, -0.74), (0.5, -0.97), (0.22, -1.0), (0.0, -1.0)]
SLAB = [(0.0, 1.0), (0.32, 1.0), (0.6, 0.97), (0.84, 0.84), (0.98, 0.5), (1.0, 0.0), (0.98, -0.45), (0.86, -0.8), (0.58, -0.98), (0.26, -1.0), (0.0, -1.0)]
BOX = [(0.0, 1.0), (0.34, 1.0), (0.62, 0.99), (0.84, 0.82), (1.0, 0.5), (1.0, 0.0), (1.0, -0.42), (0.88, -0.78), (0.62, -1.0), (0.3, -1.0), (0.0, -1.0)]


# ============================================================================ shared parts
def section(y, w, top, bot, zc, half):
    pts = []
    for i, (px, pz) in enumerate(half):
        z = top if i == 0 else (pz * top if pz > 0 else pz * bot)
        pts.append((px * w, y, zc + z))
    for px, y2, z in reversed(pts[1:-1]):
        pts.append((-px, y2, z))
    return pts


class Body:
    """A lofted fuselage with an optional cockpit opening in its top."""

    def __init__(self, k, keys, half, nrows, canopy_y=None, a=2, mat="hull_white"):
        self.rows = catmull(keys, nrows)
        self.grid = [section(*r, half) for r in self.rows]
        self.cols = len(self.grid[0])
        self.canopy_y, self.a = canopy_y, a
        self.open_rows = [r for r in range(nrows) if canopy_y and canopy_y[0] < self.rows[r][0] < canopy_y[1]]
        k.loft(self.grid, mat, skip=self.in_canopy)

    def in_canopy(self, r, c):
        return r in self.open_rows and (c < self.a or c >= self.cols - self.a)

    def plates(self, k, seed, height=(0.014, 0.034), mats=None, skip_chance=0.14, accent_cols=(3, 15)):
        rng = random.Random(seed)
        nrows = len(self.rows)
        r = 1
        lo = self.open_rows[0] - 1 if self.open_rows else -9
        hi = self.open_rows[-1] + 2 if self.open_rows else -9
        pairs = [(c, c + 2) for c in range(1, self.cols - 2, 2)]
        while r < nrows - 4:
            r2 = min(r + rng.randint(2, 4), nrows - 2)
            for c0, c1 in pairs:
                if r2 > lo and r < hi and (c0 < self.a + 1 or c1 > self.cols - self.a - 1):
                    continue
                roll = rng.random()
                if roll < skip_chance:
                    continue
                if mats:
                    mat = mats(roll, c0)
                else:
                    mat = "hull_accent" if (roll > 0.8 and accent_cols[0] <= c0 <= accent_cols[1]) else ("hull_grey" if roll > 0.6 else "hull_white")
                k.grid_plate(self.grid, r, c0, r2, c1, rng.uniform(*height), 0.016, mat)
            r = r2

    def rivets(self, k, cols=(4, 6, 14, 16), step=6, stop=8):
        nrows = len(self.rows)
        for r in range(2, nrows - stop, step):
            for c in cols:
                a = Vector(self.grid[r][c])
                b = Vector(self.grid[min(r + 5, nrows - 1)][c])
                n = Vector((a.x, 0, a.z - self.rows[r][4])).normalized()
                k.stud_row(a + n * 0.03, b + n * 0.03, 5, n, 0.013, 0.022, "metal_bare")

    def at(self, y):
        """Interpolated (w, top, bot, zc) of the hull at station y."""
        rows = self.rows
        for i in range(len(rows) - 1):
            if rows[i][0] <= y <= rows[i + 1][0]:
                f = (y - rows[i][0]) / max(rows[i + 1][0] - rows[i][0], 1e-6)
                return tuple(rows[i][j] + (rows[i + 1][j] - rows[i][j]) * f for j in range(1, 5))
        return rows[0][1:] if y < rows[0][0] else rows[-1][1:]

    # --------------------------------------------------------------- cockpit
    def canopy(self, k, glass, height, n=14, sharp=False, bars=(), frame_every=5, bias=0.55):
        """Glass bubble that seals exactly onto the cockpit opening, with tub and pilot."""
        a, cols = self.a, self.cols
        rr = list(range(self.open_rows[0], self.open_rows[-1] + 2))
        rings, edges = [], []
        for j, r in enumerate(rr):
            t = j / (len(rr) - 1)
            # Peak sits forward of centre so the bubble rakes back like a fighter canopy.
            u = t ** (math.log(0.5) / math.log(bias))
            hh = height * math.sin(math.pi * u) ** 0.55
            edge = [self.grid[r][(cols - a + i) % cols] for i in range(2 * a + 1)]
            edges.append(edge)
            if sharp:
                pts = []
                for i in range(n + 1):
                    f = i / n * (len(edge) - 1)
                    i0 = min(int(f), len(edge) - 2)
                    pts.append(tuple(Vector(edge[i0]).lerp(Vector(edge[i0 + 1]), f - i0)))
                lift = lambda s: min(1.0, math.sin(math.pi * s) * 1.6)
            else:
                pts = catmull(edge, n + 1)
                lift = lambda s: math.sin(math.pi * s) ** 0.6
            rings.append([(p[0] * (1 + 0.08 * hh * math.sin(math.pi * i / n)), p[1], p[2] + hh * lift(i / n)) for i, p in enumerate(pts)])
        glass.loft(rings, "glass", closed=False)
        self.glass_rings = rings
        # Frame bows, spine and sill rails.
        for j in range(0, len(rings), frame_every):
            if 0 < j < len(rings) - 1:
                k.tube([(p[0] * 1.012, p[1], p[2] + 0.012) for p in rings[j]], 0.024, "hull_dark", 6)
        mid = n // 2
        k.tube([(0, rg[mid][1], rg[mid][2] + 0.014) for rg in rings], 0.028, "hull_dark", 8)
        for side in (0, n):
            k.tube([(rg[side][0] * 1.01, rg[side][1], rg[side][2] + 0.01) for rg in rings], 0.042, "hull_grey", 8)
        for fj in bars:
            j = round(fj * (len(rings) - 1))
            k.tube([(p[0] * 1.03, p[1], p[2] + 0.05) for p in rings[j]], 0.036, "hull_dark", 8)
            for i in (n // 4, n - n // 4):
                p = rings[j][i]
                k.cbox((p[0], p[1], p[2] + 0.03), (0.07, 0.07, 0.06), "metal_bare", 0.01)
        # Tub: sides and floor under the glass so the hull never looks hollow.
        ys = [e[0][1] for e in edges]
        floor = min(e[0][2] for e in edges) - 0.36
        tub = []
        for e in edges:
            l, rgt = e[0], e[-1]
            tub.append([l, (l[0] * 0.86, l[1], floor), (rgt[0] * 0.86, l[1], floor), rgt])
        k.loft(tub, "metal_dark", closed=False)
        for ring, face in ((tub[0], 1), (tub[-1], -1)):
            k.add(ring, [(0, 1, 2, 3), (3, 2, 1, 0)], "metal_dark")
        # Seat, pilot and consoles.
        y0, y1 = ys[0], ys[-1]
        span = y1 - y0
        ypk = y0 + span * bias
        w = min(abs(e[0][0]) for e in edges[len(edges) // 4: 3 * len(edges) // 4]) * 0.86
        zr = edges[len(edges) // 2][0][2]
        seat_y = ypk - span * 0.16
        top = max(p[2] for p in rings[min(range(len(rings)), key=lambda j: abs(ys[j] - seat_y))])
        head_z = min(top - 0.17, zr + 0.42)
        k.cbox((0, seat_y - 0.18, (floor + head_z) / 2), (0.44, 0.1, head_z - floor + 0.08), "hull_dark", 0.03)
        k.cbox((0, seat_y + 0.02, floor + 0.12), (0.5, 0.36, 0.22), "hull_dark", 0.02)
        k.cbox((0, seat_y, (floor + head_z) / 2 - 0.05), (0.32, 0.2, head_z - floor - 0.25), "hull_grey", 0.05)
        k.sphere((0, seat_y + 0.02, head_z), 0.13, "hull_accent", 8, 16)
        k.sphere((0, seat_y + 0.07, head_z + 0.005), 0.095, "glass", 6, 14, squash=0.9)
        k.cbox((0, seat_y - 0.03, head_z - 0.2), (0.36, 0.18, 0.1), "hull_grey", 0.03)
        for sx in (-1, 1):
            k.cbox((sx * w * 0.8, seat_y + 0.1, floor + 0.16), (0.16, 0.8, 0.18), "hull_dark", 0.016)
            for jj in range(4):
                k.cbox((sx * (w * 0.8 - 0.04 + jj % 2 * 0.07), seat_y - 0.05 + (jj // 2) * 0.17, floor + 0.255), (0.05, 0.1, 0.02), "glow_green" if jj == 3 else "metal_bare", 0.006)
        dash_y = min(seat_y + span * 0.32, y1 - 0.25)
        dz = zr - 0.02
        k.cbox((0, dash_y, dz - 0.08), (w * 1.7, 0.2, 0.16), "hull_dark", 0.024)
        for sx in (-0.2, 0.0, 0.2):
            M = T(sx, dash_y - 0.1, dz + 0.0) @ RX(38)
            k.cbox((0, 0, 0), (0.17, 0.016, 0.13), "metal_dark", 0.003, M)
            k.cbox((0, -0.011, 0), (0.15, 0.006, 0.11), "glow_screen", 0.0, M)


def engine(k, g, root, M, r, length=1.6, petals=18, name=None, bands=(0.08, 0.3, 0.72, 1.05)):
    s = r / 0.7
    k.lathe([(0.6 * s, -0.1), (0.62 * s, 0.0), (0.68 * s, length * 0.33), (0.7 * s, length * 0.73), (0.62 * s, length)], 24, "hull_grey", M, cap0=True, cap1=True)
    for y in bands:
        y *= length / 1.5
        k.lathe([((0.65 + y * 0.05) * s, y), ((0.71 + y * 0.03) * s, y + 0.015), ((0.71 + y * 0.03) * s, y + 0.06), ((0.65 + y * 0.05) * s, y + 0.075)], 24, "hull_dark", M)
    for i in range(10):
        k.cbox((0, 0.42 * length / 1.5, 0.68 * s), (0.09 * s, 0.42 * length / 1.5, 0.024), "metal_bare", 0.006, M @ RY(i * 36 + 18))
    bell = nozzle(k, M @ T(0, -0.1, 0), 0.54 * s, 0.9 * s, petals=petals)
    glow_disk(g, bell @ T(0, -0.1, 0), 0.4 * s)
    if name:
        p = M @ Vector((0, -0.1 - 0.9 * s, 0))
        empty(name, tuple(p), root)


def gun_pod(k, g, P, sx, aft_engine=True, feed=True, light=True):
    """Rotary-cooled cannon pod along +Y; returns the muzzle point."""
    k.lathe([(0.02, -0.75), (0.2, -0.62), (0.31, -0.3), (0.34, 0.3), (0.32, 1.1), (0.26, 1.72), (0.22, 1.92), (0.2, 1.94)], 16, "hull_grey", P, cap0=True)
    for y in (0.0, 0.34, 0.68, 1.02, 1.36):
        a, b = (0.325, 0.352) if y < 1.1 else (0.3, 0.32)
        k.lathe([(a, y), (b, y + 0.012), (b, y + 0.05), (a, y + 0.062)], 16, "hull_dark", P)
    k.lathe([(0.15, 1.94), (0.15, 2.72), (0.13, 2.76), (0.115, 2.76)], 16, "metal_dark", P)
    for i in range(12):
        rot = P @ RY(i * 30) @ T(0, 2.32, 0.15)
        for j in range(3):
            k.cbox((0, -0.27 + j * 0.27, 0.004), (0.028, 0.2, 0.008), "metal_bare", 0, rot)
    k.lathe([(0.075, 2.6), (0.075, 3.05), (0.1, 3.06), (0.105, 3.25), (0.075, 3.26), (0.075, 3.45), (0.09, 3.46), (0.09, 3.56), (0.05, 3.57), (0.04, 3.2)], 14, "metal_burn", P)
    for a in (0, 90, 180, 270):
        k.cbox((0, 3.155, 0.1), (0.045, 0.1, 0.01), "metal_dark", 0, P @ RY(a))
    g.lathe([(0.036, 3.2), (0.039, 3.56)], 10, "glow_orange", P)
    if feed:
        k.cbox((0, 0.2, 0.33), (0.2, 0.74, 0.1), "hull_dark", 0.024, P)
        for i in range(5):
            k.cbox((0, 0.0 + i * 0.1, 0.39), (0.14, 0.05, 0.03), "metal_bare", 0.006, P)
    if light:
        g.sphere((0, 1.58, 0.33), 0.035, "glow_red" if sx < 0 else "glow_green", 5, 8, P)
    if aft_engine:
        k.lathe([(0.12, -0.72), (0.15, -0.9), (0.14, -0.94), (0.12, -0.92)][::-1], 14, "metal_burn", P)
        g.lathe([(0.001, -0.86), (0.11, -0.84)], 14, "glow_engine", P)
    return P @ Vector((0, 3.56, 0))


def missile(k, P):
    """Pylon and missile hanging below P."""
    k.loft([[(-0.03, 0.45, 0.14), (0.03, 0.45, 0.14), (0.03, 0.42, -0.06), (-0.03, 0.42, -0.06)], [(-0.03, -0.58, 0.14), (0.03, -0.58, 0.14), (0.03, -0.38, -0.06), (-0.03, -0.38, -0.06)]][::-1], "hull_dark", M=P)
    k.cbox((0, 0.03, -0.1), (0.07, 0.86, 0.06), "metal_dark", 0.012, P)
    Mi = P @ T(0, 0, -0.22)
    k.lathe([(0.0, -0.72), (0.09, -0.7), (0.095, -0.62), (0.095, 0.5), (0.08, 0.72), (0.04, 0.9), (0.002, 1.0)], 12, "hull_white", Mi)
    k.lathe([(0.097, 0.3), (0.097, 0.4)], 12, "hazard", Mi)
    k.lathe([(0.097, -0.3), (0.097, -0.26)], 12, "hull_accent", Mi)
    for a in (45, 135, 225, 315):
        k.add([(0, -0.7, 0.08), (0, -0.24, 0.08), (0, -0.42, 0.22), (0, -0.74, 0.22)], [(3, 2, 1, 0), (0, 1, 2, 3)], "hull_dark", Mi @ RY(a))
        k.add([(0, 0.5, 0.08), (0, 0.68, 0.08), (0, 0.56, 0.15), (0, 0.46, 0.15)], [(3, 2, 1, 0), (0, 1, 2, 3)], "hull_dark", Mi @ RY(a))
    return Mi @ Vector((0, 1.0, 0))


WING_PROF = [(0.0, 0.0), (0.06, 0.55), (0.24, 1.0), (0.55, 0.85), (0.85, 0.34), (1.0, 0.04), (1.0, -0.04), (0.85, -0.3), (0.55, -0.68), (0.24, -0.82), (0.06, -0.48)]


def wing(k, keys, sx, rows=12, seed=1, mat="hull_white", flap=True):
    """Lofted wing panel from (x, y_le, chord, z, thick) stations with plates and a flap."""
    stations = catmull(keys, rows)
    grid = [[(x, y - p[0] * c, z + p[1] * t) for p in WING_PROF] for x, y, c, z, t in stations]
    if sx < 0:
        grid = [[(-p[0], p[1], p[2]) for p in reversed(rg)] for rg in grid]
    k.loft(grid, mat, cap0=False, cap1=True)
    rng = random.Random(seed * 7 + (sx > 0))
    up = ((1, 3), (3, 5))
    lo = ((6, 8), (8, 10))
    if sx < 0:
        up = tuple((10 - b, 10 - a) for a, b in up)
        lo = tuple((10 - b, 10 - a) for a, b in lo)
    st = list(range(0, rows - 1, 2))
    for s0, s1 in zip(st, st[1:] + [rows - 1]):
        for i, (c0, c1) in enumerate(up):
            m = "hull_accent" if (s0 % 6 == 0 and i == 0) else ("hull_grey" if rng.random() < 0.3 else mat)
            k.grid_plate(grid, s0, c0, s1, c1, rng.uniform(0.008, 0.02), 0.012, m)
        for c0, c1 in lo:
            k.grid_plate(grid, s0, c0, s1, c1, 0.012, 0.012, "hull_dark")
    if flap:
        M = SC(sx, 1, 1)
        i0, i1 = rows // 4, rows - 2
        s0, s1 = stations[i0], stations[i1]
        y0, y1 = s0[1] - s0[2], s1[1] - s1[2]
        c0, c1 = s0[2] * 0.2, s1[2] * 0.2
        fl = [
            [(s0[0], y0 + c0, s0[3] + 0.018), (s0[0], y0 + 0.06, s0[3] + 0.006), (s0[0], y0 + 0.06, s0[3] - 0.012), (s0[0], y0 + c0, s0[3] - 0.024)],
            [(s1[0], y1 + c1, s1[3] + 0.018), (s1[0], y1 + 0.06, s1[3] + 0.006), (s1[0], y1 + 0.06, s1[3] - 0.012), (s1[0], y1 + c1, s1[3] - 0.024)],
        ]
        k.loft(fl, "hull_accent", M=M)
        for t in (0.25, 0.75):
            xm = s0[0] + (s1[0] - s0[0]) * t
            ym = y0 + (y1 - y0) * t + (c0 + c1) * 0.5
            zm = s0[3] + (s1[3] - s0[3]) * t - 0.06
            k.cbox((xm, ym, zm), (0.05, 0.36, 0.07), "hull_dark", 0.016, M)
            k.tube([(xm, ym + 0.17, zm), (xm, ym - 0.22, zm)], 0.011, "metal_bare", 6, M)
    return stations


def fin(k, g, M, keys, label, sx, mat="hull_white"):
    """Swept fin from (z, y_le, chord, thick) keys in M's frame (fin grows along +Z)."""
    sec = lambda z, y0, c, t: [(0.0, y0, z), (t * 0.8, y0 - c * 0.26, z), (t, y0 - c * 0.5, z), (t * 0.6, y0 - c * 0.85, z), (0.004, y0 - c, z), (-t * 0.6, y0 - c * 0.85, z), (-t, y0 - c * 0.5, z), (-t * 0.8, y0 - c * 0.26, z)]
    k.loft([list(reversed(sec(*kk))) for kk in keys], mat, M=M)
    z0, yl0, c0, t0 = keys[0]
    k.loft([[(-t0 * 1.1, yl0 + 0.05, 0.03), (t0 * 1.1, yl0 + 0.05, 0.03), (t0 * 1.1, yl0 - c0 - 0.05, 0.03), (-t0 * 1.1, yl0 - c0 - 0.05, 0.03)],
            [(-t0 * 1.5, yl0 + 0.05, -0.2), (t0 * 1.5, yl0 + 0.05, -0.2), (t0 * 1.5, yl0 - c0 - 0.05, -0.2), (-t0 * 1.5, yl0 - c0 - 0.05, -0.2)]], "hull_grey", M=M)
    z1, yl1, c1, t1 = keys[-1]
    k.cbox((0, yl1 - c1 * 0.45, z1 - 0.05), (t1 * 2.6, c1 * 0.8, 0.1), "hazard", 0.012, M)
    # Rudder strip along the trailing edge.
    k.loft([[(-t0 * 0.6, yl0 - c0 * 0.78, z0 + 0.1), (t0 * 0.6, yl0 - c0 * 0.78, z0 + 0.1), (t0 * 0.6, yl0 - c0 - 0.02, z0 + 0.1), (-t0 * 0.6, yl0 - c0 - 0.02, z0 + 0.1)],
            [(-t1 * 0.7, yl1 - c1 * 0.7, z1 - 0.12), (t1 * 0.7, yl1 - c1 * 0.7, z1 - 0.12), (t1 * 0.7, yl1 - c1 - 0.02, z1 - 0.12), (-t1 * 0.7, yl1 - c1 - 0.02, z1 - 0.12)]][::-1], "hull_accent", M=M)
    g.sphere((0, yl1 - c1 - 0.02, z1), 0.03, "glow_white", 5, 8, M)
    if label:
        km = keys[len(keys) // 2]
        for face in (1, -1):
            Q = M @ T(face * (keys[0][3] + 0.006), km[1] - km[2] * 0.5, km[0] * 0.75) @ RY(face * 90) @ RZ(face * 90) @ SC(sx, 1, 1)
            k.text(label, Q, 0.2, "hull_dark", 0.004)


def intake(k, sx, x, y, scale=1.0, conduit_to=None):
    """Flank intake duct with hazard lip, compressor fan and louvres, mouth at station y."""
    M = SC(sx, 1, 1) @ T(x, y, 0) @ SC(scale)
    rows_d = []
    for yy, w, h in ((-2.7, 0.05, 0.16), (-1.9, 0.24, 0.26), (-0.9, 0.32, 0.33), (-0.12, 0.34, 0.36), (0.0, 0.34, 0.36)):
        xx = 0.0 - (0.1 if yy > -0.9 else 0)
        rows_d.append([(xx, yy, 0.08 + h), (xx + w, yy, 0.05 + h * 0.85), (xx + w * 1.08, yy, -h * 0.45), (xx, yy, -h)])
    k.loft(rows_d, "hull_grey", cap0=True, cap1=False, M=M)
    x0 = -0.1
    lip = [(x0 + 0.04, 0.01, 0.42), (x0 + 0.32, 0.01, 0.34), (x0 + 0.36, 0.01, -0.16), (x0 + 0.04, 0.01, -0.34)]
    inner = [(x0 + 0.08, 0.01, 0.35), (x0 + 0.26, 0.01, 0.29), (x0 + 0.3, 0.01, -0.12), (x0 + 0.08, 0.01, -0.27)]
    verts = lip + inner + [(p[0], -0.48, p[2]) for p in inner]
    k.add(verts, [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)], "hazard", M)
    k.add(verts, [(4 + (i + 1) % 4, 8 + (i + 1) % 4, 8 + i, 4 + i) for i in range(4)] + [(8, 9, 10, 11)], "metal_dark", M)
    hub = M @ T(x0 + 0.18, -0.46, 0.03)
    k.lathe([(0.0, 0.2), (0.07, 0.16), (0.08, 0.02)][::-1], 12, "metal_bare", hub)
    for i in range(12):
        k.cbox((0, 0.04, 0.17), (0.075, 0.018, 0.2), "metal_bare", 0, hub @ RY(i * 30) @ RZ(32))
    for i in range(6):
        k.cbox((x0 + 0.18, -0.04, -0.2 + i * 0.09), (0.3, 0.02, 0.012), "metal_dark", 0, M)
    for j, (dz, rad, mat) in enumerate(((0.3, 0.022, "metal_bare"), (0.24, 0.03, "hull_accent"), (0.17, 0.018, "metal_dark"))):
        k.tube([(0.1, -0.13, dz - 0.02), (0.16, -0.98, dz), (0.18, -2.0, dz + 0.02), (0.1, -2.7, dz + 0.02)], rad, mat, 8, M, spline=16)
    for yy in (-0.4, -1.05, -1.7):
        k.cbox((0.17, yy, 0.24), (0.07, 0.05, 0.2), "hull_dark", 0.012, M)


def radiator(k, g, y0, count, x=0.27, z=0.74, pitch=0.075, h=0.14, sx_list=(-1, 1)):
    for sx in sx_list:
        M = SC(sx, 1, 1)
        for i in range(count):
            y = y0 - i * pitch
            hh = h + 0.04 * math.sin(i * 0.37)
            k.cbox((x, y, z), (0.2, 0.024, hh), "metal_bare" if i % 5 else "hull_accent", 0, M)
        L = count * pitch
        g.cbox((x - 0.1, y0 - L / 2, z - 0.02), (0.01, L * 0.95, h + 0.04), "glow_orange", 0, M)
        k.cbox((x + 0.11, y0 - L / 2, z), (0.024, L * 1.04, h + 0.06), "hull_dark", 0.006, M)


def spine(k, rows_def, mat="hull_grey"):
    out = []
    for y, z, h, w in rows_def:
        out.append([(0, y, z + h), (w * 0.72, y, z + h * 0.7), (w, y, z), (w, y, z - 0.25), (-w, y, z - 0.25), (-w, y, z), (-w * 0.72, y, z + h * 0.7)])
    k.loft(out[::-1], mat)


def louvres(k, g, M, n=7, h=0.26):
    g.cbox((-0.03, -0.24, 0), (0.02, n * 0.08, h * 0.75), "glow_orange", 0, M)
    for i in range(n):
        k.cbox((0, -i * 0.08, 0), (0.05, 0.03, h), "hull_dark", 0.004, M)


def nose_sensor(k, g, y, zc, r=0.12):
    k.lathe([(r * 0.9, y - 0.1), (r, y), (r * 0.7, y + 0.19), (r * 0.25, y + 0.35), (0.002, y + 0.43)], 16, "hull_dark", T(0, 0, zc))
    k.lathe([(r * 1.1, y - 0.24), (r * 1.15, y - 0.05)], 16, "metal_bare", T(0, 0, zc))


def chin_turret(k, g, y, z, s=1.0):
    chin = T(0, y, z) @ SC(s)
    k.lathe([(0.2, 0), (0.24, 0.06), (0.24, 0.14), (0.2, 0.2)], 20, "hull_dark", chin @ RX(-90) @ T(0, -0.1, 0))
    k.sphere((0, 0, -0.14), 0.19, "metal_dark", 8, 18, chin)
    k.lathe([(0.1, 0.13), (0.125, 0.17), (0.125, 0.22), (0.08, 0.24)], 18, "metal_bare", chin @ T(0, 0, -0.14), cap1=True)
    g.lathe([(0.076, 0.241), (0.001, 0.26)], 18, "glow_cyan", chin @ T(0, 0, -0.14))


def spotlight(k, g, M, r=0.13):
    k.lathe([(r * 0.5, -0.16), (r, -0.04), (r * 1.08, 0.06), (r * 1.08, 0.1)], 14, "hull_dark", M, cap0=True)
    g.lathe([(0.001, 0.07), (r * 0.95, 0.05)], 14, "glow_white", M)
    k.lathe([(r * 1.1, 0.09), (r * 1.14, 0.11)], 14, "metal_bare", M)


def finish(name, root, kits):
    for kit in kits:
        kit.build(root, None if kit.name.endswith("Glow") or kit.name == "Canopy" else 32.0)
    print(f"[concept] {name}: {sum(kit.tris for kit in kits)} tris")
    export(OUT % name)


def start(name):
    reset_scene()
    random.seed(len(name))
    return empty("Concept_" + name), Kit("Hull"), Kit("Canopy"), Kit("EngineGlow")


# ============================================================================ BADGER
def badger():
    """Short, fat and armoured: slab plating, stub wings, fused cannon pods."""
    root, k, glass, g = start("badger")
    keys = [
        (-2.75, 0.95, 0.56, 0.5, 0.02),
        (-2.15, 1.3, 0.74, 0.58, 0.02),
        (-1.0, 1.44, 0.88, 0.62, 0.0),
        (0.3, 1.38, 0.9, 0.6, 0.0),
        (1.4, 1.16, 0.78, 0.52, -0.03),
        (2.3, 0.84, 0.54, 0.4, -0.08),
        (2.95, 0.46, 0.3, 0.26, -0.12),
        (3.3, 0.12, 0.08, 0.08, -0.14),
    ]
    b = Body(k, keys, SLAB, 36, canopy_y=(0.15, 2.05), a=2)
    b.plates(k, 11, height=(0.03, 0.06), skip_chance=0.06,
             mats=lambda roll, c0: "hull_accent" if (roll > 0.92 and 3 <= c0 <= 15) else ("hull_grey" if roll > 0.55 else "hull_white"))
    b.rivets(k)
    b.canopy(k, glass, 0.4, n=14, bars=(0.3, 0.55, 0.8), frame_every=99, bias=0.6)
    nose_sensor(k, g, 3.2, -0.14, 0.1)
    # Armoured nose cowl and dozer chin guard.
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        k.loft([[(0.0, 2.45, -0.5), (0.45, 2.45, -0.46), (0.82, 2.25, -0.3), (0.82, 2.25, -0.56), (0.0, 2.45, -0.62)],
                [(0.0, 3.1, -0.36), (0.22, 3.1, -0.34), (0.42, 3.0, -0.26), (0.42, 3.0, -0.4), (0.0, 3.1, -0.44)]], "hull_grey", M=M)
    k.cbox((0, 2.6, -0.62), (1.2, 0.18, 0.08), "hazard", 0.02)
    chin_turret(k, g, 1.95, -0.6, 0.9)
    # Heavy cheek armour slabs along the flanks, bolted on.
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        for i, (y, l) in enumerate(((-1.75, 0.9), (-0.75, 1.0), (0.3, 0.95))):
            w = b.at(y)[0]
            k.cbox((w + 0.05, y, -0.08), (0.14, l, 0.62), "hull_grey" if i != 1 else "hull_accent", 0.04, M)
            k.stud_row((w + 0.125, y - l * 0.4, 0.14), (w + 0.125, y + l * 0.4, 0.14), 5, (1, 0, 0), 0.016, 0.02, "metal_bare")
            k.stud_row((w + 0.125, y - l * 0.4, -0.3), (w + 0.125, y + l * 0.4, -0.3), 5, (1, 0, 0), 0.016, 0.02, "metal_bare")
        louvres(k, g, M @ T(b.at(-2.3)[0] + 0.02, -2.15, 0.06) @ SC(1, 1, 1), 6, 0.3)
        thruster_quad(k, (0, 0, 0.02), M @ T(0.86, 2.0, 0.1) @ RY(62), 0.1)
    # Ventral keel.
    keel = []
    for y, h, w in ((-2.5, 0.02, 0.1), (-1.8, 0.16, 0.24), (-0.4, 0.2, 0.3), (1.0, 0.14, 0.22), (1.8, 0.02, 0.1)):
        z = -0.58
        keel.append([(0, y, z), (w, y, z), (w * 0.7, y, z - h), (-w * 0.7, y, z - h), (-w, y, z)])
    k.loft(keel, "hull_grey")
    for y in (-1.4, -0.3):
        for sx in (-1, 1):
            k.cbox((sx * 0.5, y, -0.6), (0.42, 0.8, 0.03), "hull_dark", 0.008)
        k.cbox((0, y, -0.79), (0.2, 0.34, 0.03), "hazard", 0.006)
    # Stub wings with fused cannon pods and one missile each.
    wkeys = [(1.2, 0.55, 2.4, -0.12, 0.2), (1.85, 0.32, 2.0, -0.2, 0.16), (2.35, 0.12, 1.7, -0.26, 0.13)]
    for sx in (-1, 1):
        wing(k, wkeys, sx, rows=10, seed=3)
        P = SC(sx, 1, 1) @ T(2.45, -0.95, -0.26) @ SC(0.88, 0.95, 0.88)
        mz = gun_pod(k, g, P, sx)
        empty("Muzzle_" + ("R" if sx > 0 else "L"), tuple(mz), root)
        k.cbox((2.45, -0.15, -0.26), (0.2, 1.6, 0.2), "hull_dark", 0.03, SC(sx, 1, 1))
        tip = missile(k, SC(sx, 1, 1) @ T(1.72, 0.05, -0.36))
        empty("MissilePort_" + ("R" if sx > 0 else "L"), tuple(tip), root)
        thruster_quad(k, (1.85, -0.6, -0.1), SC(sx, 1, 1), 0.11)
    # Dorsal armour hump with radiators, twin stubby fins.
    spine(k, [(0.15, 0.82, 0.0, 0.14), (-0.3, 0.8, 0.16, 0.26), (-1.5, 0.78, 0.22, 0.34), (-2.4, 0.66, 0.18, 0.32), (-2.85, 0.5, 0.08, 0.26)])
    radiator(k, g, -0.5, 22, x=0.46, z=0.84, h=0.16)
    for sx in (-1, 1):
        fin(k, g, SC(sx, 1, 1) @ T(0.62, 0, 0.74) @ RY(14), [(0.0, -1.7, 1.25, 0.06), (0.35, -1.95, 1.0, 0.05), (0.66, -2.25, 0.72, 0.035)], "BG-4", sx)
    # Twin engines, set close.
    for sx in (-1, 1):
        engine(k, g, root, SC(sx, 1, 1) @ T(0.56, -2.9, 0.02), 0.7, 1.5, name="EngineFX_" + ("R" if sx > 0 else "L"))
    k.cbox((0, -3.1, 0.0), (0.42, 0.5, 0.74), "hull_dark", 0.06)
    for sx in (-1, 1):
        k.cbox((sx * 0.14, -3.36, -0.22), (0.1, 0.02, 0.22), "hazard", 0.004)
    finish("badger", root, [k, glass, g])


# ============================================================================ FERRET
def ferret():
    """Narrow core hull hugging two oversized cannon pods: all guns, almost no span."""
    root, k, glass, g = start("ferret")
    keys = [
        (-2.9, 0.72, 0.46, 0.42, 0.05),
        (-2.2, 0.95, 0.62, 0.5, 0.03),
        (-0.9, 1.06, 0.76, 0.52, 0.0),
        (0.6, 0.98, 0.78, 0.48, 0.0),
        (1.7, 0.76, 0.6, 0.38, -0.04),
        (2.7, 0.5, 0.38, 0.27, -0.1),
        (3.5, 0.2, 0.14, 0.12, -0.14),
        (3.85, 0.05, 0.04, 0.04, -0.15),
    ]
    b = Body(k, keys, ROUND, 38, canopy_y=(0.1, 2.35), a=2)
    b.plates(k, 5)
    b.rivets(k)
    b.canopy(k, glass, 0.44, n=14, frame_every=6, bias=0.58)
    nose_sensor(k, g, 3.72, -0.15, 0.09)
    chin_turret(k, g, 2.55, -0.36, 0.8)
    for sx in (-1, 1):
        k.tube([(sx * 0.12, 3.0, -0.08), (sx * 0.2, 3.3, -0.08), (sx * 0.2, 3.9, -0.08)], 0.011, "metal_bare", 6)
    # Gun pods on short, thick pylons either side of the cockpit.
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        P = M @ T(1.5, -1.55, -0.12) @ SC(1.25, 1.2, 1.25)
        mz = gun_pod(k, g, P, sx)
        empty("Muzzle_" + ("R" if sx > 0 else "L"), tuple(mz), root)
        # Second, under-slung barrel.
        U = M @ T(1.5, -0.2, -0.56)
        k.cbox((0, 0.4, 0.06), (0.22, 1.5, 0.16), "hull_dark", 0.03, U)
        k.lathe([(0.06, 1.1), (0.06, 2.5), (0.08, 2.52), (0.08, 2.7), (0.04, 2.72), (0.03, 2.4)], 12, "metal_burn", U)
        g.lathe([(0.028, 2.4), (0.03, 2.71)], 8, "glow_orange", U)
        # Pylon: a stubby aerofoil plus a load strut.
        wing(k, [(0.8, 0.35, 1.8, -0.1, 0.16), (1.4, 0.25, 1.7, -0.12, 0.14)], sx, rows=6, seed=9, mat="hull_grey", flap=False)
        fin(k, g, M @ T(1.5, 0, 0.22) @ RY(12), [(0.0, -1.35, 1.1, 0.055), (0.5, -1.7, 0.85, 0.045), (0.78, -1.95, 0.6, 0.032)], "FR-2", sx)
        k.tube([(0.86, -0.7, -0.38), (1.2, -0.8, -0.4)], 0.05, "metal_dark", 8, M)
        k.cbox((1.04, -0.75, -0.39), (0.12, 0.14, 0.12), "hull_dark", 0.02, M)
        tip = missile(k, M @ T(1.5, -1.2, -0.62))
        empty("MissilePort_" + ("R" if sx > 0 else "L"), tuple(tip), root)
        thruster_quad(k, (0, 0, 0.02), M @ T(1.5, 0.15, 0.34), 0.1)
        louvres(k, g, M @ T(b.at(-1.6)[0] - 0.02, -1.3, 0.12), 7, 0.24)
        thruster_quad(k, (0, 0, 0.02), M @ T(0.72, 2.0, 0.08) @ RY(62), 0.09)
    # Dorsal spine, radiator and single tall-ish fin.
    spine(k, [(0.1, 0.72, 0.0, 0.1), (-0.4, 0.72, 0.14, 0.2), (-1.6, 0.66, 0.2, 0.26), (-2.6, 0.52, 0.16, 0.24), (-3.0, 0.4, 0.06, 0.18)])
    radiator(k, g, -0.6, 22, x=0.33, z=0.72, h=0.13)
    for x, y, l in ((-0.16, -0.7, 0.42), (0.12, -2.4, 0.34)):
        k.lathe([(0.012, 0.0), (0.006, l)], 5, "metal_dark", T(x, y, 0.8) @ RX(-82))
    # Belly keel and hatches.
    keel = []
    for y, h, w in ((-2.6, 0.02, 0.1), (-1.9, 0.16, 0.2), (-0.5, 0.2, 0.24), (1.0, 0.15, 0.18), (1.9, 0.02, 0.08)):
        keel.append([(0, y, -0.48), (w, y, -0.48), (w * 0.7, y, -0.48 - h), (-w * 0.7, y, -0.48 - h), (-w, y, -0.48)])
    k.loft(keel, "hull_grey")
    k.cbox((0, -0.5, -0.69), (0.2, 0.4, 0.03), "hazard", 0.006)
    # One big central engine, flanked by RCS.
    engine(k, g, root, T(0, -3.0, 0.03), 0.7, 1.4, petals=20, name="EngineFX_R")
    empty("EngineFX_L", (0, -4.1, 0.03), root)
    for sx in (-1, 1):
        thruster_quad(k, (0, 0, 0.04), SC(sx, 1, 1) @ T(0.72, -2.5, -0.1) @ RY(90), 0.11)
    finish("ferret", root, [k, glass, g])


# ============================================================================ MOLE
def mole():
    """Boxy mining tug turned gunboat: tall cab up front, ram bumper, four engines in a block."""
    root, k, glass, g = start("mole")
    keys = [
        (-2.2, 1.12, 0.74, 0.62, 0.05),
        (-1.5, 1.26, 0.82, 0.66, 0.05),
        (-0.3, 1.28, 0.84, 0.66, 0.0),
        (1.0, 1.22, 0.82, 0.62, 0.0),
        (1.9, 1.08, 0.72, 0.56, -0.03),
        (2.5, 0.9, 0.56, 0.48, -0.06),
        (2.8, 0.76, 0.42, 0.4, -0.08),
    ]
    b = Body(k, keys, BOX, 30, canopy_y=(0.45, 2.45), a=2, mat="hull_white")
    b.plates(k, 21, height=(0.02, 0.045), skip_chance=0.1,
             mats=lambda roll, c0: "hull_accent" if roll > 0.88 else ("hull_grey" if roll > 0.5 else "hull_white"))
    b.rivets(k, cols=(3, 5, 15, 17), step=5, stop=4)
    b.canopy(k, glass, 0.6, n=6, sharp=True, frame_every=3, bias=0.62)
    # Roll cage over the cab.
    rings = b.glass_rings
    hoops = (2, len(rings) // 2, len(rings) - 4)
    for j in hoops:
        k.tube([(p[0] * 1.06, p[1], p[2] + 0.08) for p in rings[j]], 0.04, "hazard" if j == 2 else "metal_dark", 8)
    for sx in (-1, 1):
        k.tube([(rings[j][3 + sx * 2][0] * 1.06, rings[j][0][1], rings[j][3 + sx * 2][2] + 0.08) for j in hoops], 0.034, "metal_dark", 8)
    for j in hoops:
        for side in (0, 6):
            p = rings[j][side]
            k.cbox((p[0] * 1.06, p[1], p[2] + 0.03), (0.1, 0.1, 0.1), "hull_dark", 0.02)
    # Flat nose plate with a ram bumper, spotlights and twin guns.
    w, top, bot, zc = b.at(2.8)
    k.cbox((0, 2.82, zc), (w * 1.6, 0.06, (top + bot) * 0.9), "hull_dark", 0.02)
    k.cbox((0, 3.02, -0.32), (2.4, 0.22, 0.26), "hazard", 0.04)
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        k.cbox((0.6, 2.88, -0.32), (0.14, 0.24, 0.2), "metal_dark", 0.02, M)
        k.cbox((1.12, 2.92, -0.32), (0.18, 0.22, 0.4), "hull_dark", 0.03, M)
        for z in (0.24, 0.02):
            spotlight(k, g, M @ T(0.42, 2.84, z), 0.1)
        # Gun under each bumper end.
        P = M @ T(0.95, -0.1, -0.62) @ SC(0.8, 0.85, 0.8)
        mz = gun_pod(k, g, P, sx, aft_engine=False)
        empty("Muzzle_" + ("R" if sx > 0 else "L"), tuple(mz), root)
        k.cbox((0.95, 0.8, -0.42), (0.16, 1.0, 0.16), "hull_dark", 0.03, M)
    k.text("MOLE", T(0, 3.14, -0.32) @ RZ(180) @ RX(90), 0.14, "hull_dark", 0.004)
    # Side outrigger thruster pods on stub booms.
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        k.loft([[(1.0, 0.7, 0.18), (1.0, -0.9, 0.18), (1.0, -0.9, -0.06), (1.0, 0.7, -0.06)],
                [(2.1, 0.5, 0.14), (2.1, -0.6, 0.14), (2.1, -0.6, -0.02), (2.1, 0.5, -0.02)]], "hull_grey", M=M)
        k.cbox((1.55, -0.2, 0.17), (1.0, 0.1, 0.04), "hazard", 0.01, M)
        k.cbox((2.3, -0.05, 0.06), (0.5, 1.9, 0.5), "hull_white", 0.07, M)
        k.cbox((2.3, -0.05, 0.32), (0.34, 1.6, 0.06), "hazard", 0.02, M)
        k.cbox((2.56, -0.05, 0.06), (0.04, 1.4, 0.3), "hull_dark", 0.01, M)
        thruster_quad(k, (0, 0, 0.02), M @ T(2.3, 0.5, 0.31), 0.11)
        thruster_quad(k, (0, 0, 0.02), M @ T(2.3, 0.5, -0.19) @ RY(180), 0.11)
        k.lathe([(0.13, -0.0), (0.17, -0.2), (0.16, -0.24), (0.13, -0.22)][::-1], 14, "metal_burn", M @ T(2.3, -1.0, 0.06))
        g.lathe([(0.001, -0.16), (0.13, -0.14)], 14, "glow_engine", M @ T(2.3, -1.0, 0.06))
        k.lathe([(0.2, 0.9), (0.16, 1.02), (0.002, 1.06)], 12, "hull_dark", M @ T(2.3, 0, 0.06))
        g.sphere((2.3, 0.98, 0.22), 0.03, "glow_red" if sx < 0 else "glow_green", 5, 8, M)
        tip = missile(k, M @ T(2.3, 0.0, -0.1))
        empty("MissilePort_" + ("R" if sx > 0 else "L"), tuple(tip), root)
        # Folded grab arm along the lower flank.
        x = b.at(0)[0]
        k.tube([(x - 0.02, -1.7, -0.3), (x + 0.1, -0.6, -0.34), (x + 0.1, 1.3, -0.38)], 0.06, "hull_accent", 8, M, spline=10)
        k.cbox((x + 0.04, -1.7, -0.3), (0.2, 0.3, 0.3), "hull_dark", 0.04, M)
        k.cbox((x + 0.1, 1.45, -0.38), (0.18, 0.3, 0.22), "metal_dark", 0.03, M)
        for z in (-0.29, -0.47):
            k.cbox((x + 0.1, 1.72, z), (0.07, 0.36, 0.06), "metal_bare", 0.01, M)
        # Side radiators and pipework.
        for i in range(12):
            k.cbox((x + 0.02, -0.95 - i * 0.07, 0.48), (0.12, 0.025, 0.2), "metal_bare" if i % 4 else "hull_accent", 0, M)
        g.cbox((x - 0.04, -1.34, 0.48), (0.01, 0.82, 0.18), "glow_orange", 0, M)
        for j, dz in enumerate((0.3, 0.38)):
            k.tube([(x - 0.06, 2.1, dz), (x + 0.04, 1.0, dz), (x + 0.04, -1.9, dz)], 0.025, "metal_bare" if j else "hull_accent", 8, M, spline=12)
    # Dorsal winch housing and small fins.
    k.cbox((0, -1.0, 0.86), (0.9, 1.6, 0.22), "hull_dark", 0.05)
    k.lathe([(0.2, -0.4), (0.2, 0.4)], 16, "metal_dark", T(0, -1.0, 1.08) @ RZ(90), cap0=True, cap1=True)
    k.lathe([(0.21, -0.25), (0.21, 0.25)], 16, "hazard", T(0, -1.0, 1.08) @ RZ(90))
    for sx in (-1, 1):
        k.cbox((sx * 0.48, -1.0, 1.02), (0.06, 0.5, 0.36), "hull_grey", 0.02)
        fin(k, g, SC(sx, 1, 1) @ T(0.78, 0, 0.78) @ RY(8), [(0.0, -1.5, 0.95, 0.055), (0.55, -1.65, 0.75, 0.045)], "MT-1", sx, mat="hull_white")
    # Ventral skid rails.
    for sx in (-1, 1):
        k.cbox((sx * 0.7, -0.2, -0.72), (0.12, 3.6, 0.1), "metal_dark", 0.03)
        for y in (-1.4, 1.0):
            k.cbox((sx * 0.7, y, -0.66), (0.08, 0.12, 0.14), "hull_dark", 0.01)
    # Four engines through a heavy rear bulkhead.
    for sx in (-1, 1):
        for sz, z in (("U", 0.36), ("D", -0.3)):
            engine(k, g, root, T(sx * 0.58, -2.45, z), 0.4, 0.9, petals=12, bands=(0.1, 0.6), name=f"EngineFX_{'R' if sx > 0 else 'L'}{sz}")
    k.cbox((0, -2.3, 0.04), (2.36, 0.2, 1.66), "hull_dark", 0.05)
    for sx in (-1, 1):
        k.cbox((sx * 1.12, -2.75, 0.04), (0.14, 0.8, 1.6), "hull_grey", 0.04)
        k.cbox((sx * 1.2, -2.75, 0.04), (0.04, 0.6, 1.3), "hazard", 0.01)
    k.cbox((0, -2.75, 0.83), (2.1, 0.8, 0.1), "hull_grey", 0.03)
    k.cbox((0, -2.75, -0.75), (2.1, 0.8, 0.1), "hull_grey", 0.03)
    k.cbox((0, -2.75, 0.04), (0.16, 0.8, 1.5), "metal_dark", 0.03)
    finish("mole", root, [k, glass, g])


# ============================================================================ SWIFT
def swift():
    """The slick one: long smooth nose, cranked compact delta, one big engine and two small."""
    root, k, glass, g = start("swift")
    keys = [
        (-3.2, 0.62, 0.4, 0.34, 0.04),
        (-2.5, 0.86, 0.52, 0.4, 0.03),
        (-1.3, 0.98, 0.64, 0.44, 0.0),
        (-0.1, 0.96, 0.7, 0.44, 0.0),
        (1.1, 0.8, 0.64, 0.38, -0.02),
        (2.2, 0.58, 0.46, 0.3, -0.07),
        (3.25, 0.3, 0.24, 0.17, -0.12),
        (4.1, 0.05, 0.04, 0.04, -0.15),
    ]
    b = Body(k, keys, ROUND, 42, canopy_y=(-0.15, 2.45), a=2)
    b.plates(k, 17, height=(0.01, 0.022), skip_chance=0.22)
    b.rivets(k, step=7)
    b.canopy(k, glass, 0.42, n=16, frame_every=8, bias=0.62)
    nose_sensor(k, g, 4.0, -0.15, 0.08)
    for sx in (-1, 1):
        k.tube([(sx * 0.1, 3.2, -0.1), (sx * 0.17, 3.5, -0.1), (sx * 0.17, 4.1, -0.1)], 0.01, "metal_bare", 6)
        k.lathe([(0.015, 4.0), (0.015, 4.1), (0.004, 4.16)], 6, "glow_red" if sx < 0 else "metal_dark", T(sx * 0.17, 0, -0.1))
    chin_turret(k, g, 2.6, -0.34, 0.75)
    # Cranked delta wings with compact tip cannons and drooped tips.
    wkeys = [(0.6, 0.6, 3.1, -0.06, 0.15), (1.4, -0.05, 2.4, -0.12, 0.12), (2.2, -0.75, 1.7, -0.18, 0.085), (2.6, -1.05, 1.32, -0.22, 0.065)]
    for sx in (-1, 1):
        M = SC(sx, 1, 1)
        wing(k, wkeys, sx, rows=14, seed=6)
        P = M @ T(2.7, -2.0, -0.22) @ SC(0.62, 0.82, 0.62)
        mz = gun_pod(k, g, P, sx)
        empty("Muzzle_" + ("R" if sx > 0 else "L"), tuple(mz), root)
        tip = missile(k, M @ T(1.55, -0.55, -0.24))
        empty("MissilePort_" + ("R" if sx > 0 else "L"), tuple(tip), root)
        thruster_quad(k, (2.0, -1.2, -0.08), M, 0.1)
        intake(k, sx, 0.92, 0.95, 0.8)
        louvres(k, g, M @ T(b.at(-1.9)[0] + 0.02, -1.6, -0.12), 6, 0.22)
        thruster_quad(k, (0, 0, 0.02), M @ T(0.7, 2.1, 0.04) @ RY(60), 0.09)
        # Canted ventral strakes.
        fin(k, g, M @ T(0.38, 0, -0.38) @ RY(150), [(0.0, -1.6, 1.4, 0.05), (0.4, -2.05, 0.95, 0.035)], None, sx)
    # Dorsal ridge flowing from canopy into the fin.
    spine(k, [(-0.05, 0.74, 0.0, 0.1), (-0.7, 0.72, 0.16, 0.18), (-1.9, 0.62, 0.18, 0.22), (-2.9, 0.48, 0.12, 0.2), (-3.3, 0.4, 0.04, 0.16)])
    radiator(k, g, -0.75, 18, x=0.3, z=0.7, h=0.11)
    fin(k, g, T(0, 0, 0.72), [(0.0, -1.4, 1.75, 0.065), (0.45, -1.95, 1.3, 0.05), (0.9, -2.55, 0.9, 0.035), (1.12, -2.85, 0.65, 0.026)], "SW-3", 1)
    # One main engine plus two small outboard.
    engine(k, g, root, T(0, -3.15, 0.05), 0.62, 1.5, petals=20, name="EngineFX_R")
    empty("EngineFX_L", (0, -4.1, 0.05), root)
    for sx in (-1, 1):
        engine(k, g, root, T(sx * 0.82, -2.75, -0.12), 0.34, 1.1, petals=12, bands=(0.1, 0.5, 0.9))
    keel = []
    for y, h, w in ((-2.6, 0.02, 0.1), (-1.8, 0.14, 0.2), (-0.4, 0.17, 0.22), (1.0, 0.12, 0.16), (1.8, 0.02, 0.06)):
        keel.append([(0, y, -0.42), (w, y, -0.42), (w * 0.7, y, -0.42 - h), (-w * 0.7, y, -0.42 - h), (-w, y, -0.42)])
    k.loft(keel, "hull_grey")
    finish("swift", root, [k, glass, g])


SHIPS = {"badger": badger, "ferret": ferret, "mole": mole, "swift": swift}
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for name in args or SHIPS:
    SHIPS[name]()

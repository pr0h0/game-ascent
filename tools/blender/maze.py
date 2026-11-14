"""Mine generator: rooms of many shapes, wired by routed tunnels into a looping, gated mine.

Works on the same 10 m cell grid as level_api (cells are carved out of solid rock) and
returns the same globals a layout module has always defined, so level.py is unchanged.

Structure, per level spec:
  * zones separated by coloured key doors; the key to zone k+1 lies deep in zone k,
  * every zone is a tree of rooms grown out of each other, plus extra loops between them,
    tunnel junctions, dead-end nooks (loot, hostages, ambushes) and hidden secret rooms,
  * tunnels are routed with A* through the rock: straight industrial runs, wandering
    rock drifts (staircase steps the shell smoothing turns into slopes), wide galleries,
    vertical drops, and bulges where a tunnel opens into a small chamber,
  * the reactor (or boss) chamber is the last room of the last zone, out of sight of
    its door, with the standard escape tunnel leaving its east wall.

Any two different spaces keep at least one solid cell between them (Chebyshev), so
nothing joins by accident: the only ways between spaces are the tunnels routed here.
"""
import heapq
import math
import random

from level_api import S, cells

DIR6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
HORIZ = ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1))
NEAR = tuple((i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1))
NEAR2 = tuple((i, j, k) for i in range(-2, 3) for j in range(-2, 3) for k in range(-2, 3))
SPINE = 9
ESCAPE_LEGS = (17, 11, 8, 18)
# Spawn room and airlock live here (tools/blender/level.py SPAWN_ROOMS): nothing else may.
SPAWN_BOX = ((-5, -2, 0), (5, 4, 13))


WHY = {}


class Fail(Exception):
    pass


def add(a, d, n=1):
    return (a[0] + d[0] * n, a[1] + d[1] * n, a[2] + d[2] * n)


def neg(d):
    return (-d[0], -d[1], -d[2])


def box(a, b):
    return {(i, j, k) for i in range(a[0], b[0] + 1) for j in range(a[1], b[1] + 1) for k in range(a[2], b[2] + 1)}


def bbox(cs):
    xs, ys, zs = zip(*cs)
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def _world(cell):
    return [cell[0] * S, cell[1] * S, cell[2] * S]


# ----------------------------------------------------------------------------- shapes
# Each returns a set of cells around the origin. r: Random, k: size scale.
def _n(r, lo, hi, k):
    return max(1, int(round(r.randint(lo, hi) * k)))


def ellipsoid(rx, ry, rz, centre=(0, 0, 0)):
    out = set()
    for i in range(-int(rx) - 1, int(rx) + 2):
        for j in range(-int(ry) - 1, int(ry) + 2):
            for k in range(-int(rz) - 1, int(rz) + 2):
                if (i / (rx + 0.45)) ** 2 + (j / (ry + 0.45)) ** 2 + (k / (rz + 0.45)) ** 2 <= 1.0:
                    out.add((i + centre[0], j + centre[1], k + centre[2]))
    return out


def sh_box(r, k):
    hx, hz = _n(r, 2, 5, k), _n(r, 2, 5, k)
    return box((-hx, -r.randint(1, 2), -hz), (hx, r.randint(0, 2), hz))


def sh_hall(r, k):
    """A long gallery with side alcoves: one of the 'long halls with many exits'."""
    L, h = _n(r, 6, 10, k), r.randint(0, 1)
    out = box((-L, -1, -1), (L, h, 1))
    for _ in range(r.randint(2, 4)):
        x = r.randint(-L + 2, L - 2)
        side = r.choice((-1, 1))
        out |= box((x - 1, -1, side * 2), (x + 1, 0, side * 3)) if side > 0 else box((x - 1, -1, -3), (x + 1, 0, -2))
    return out if r.random() < 0.5 else {(c[2], c[1], c[0]) for c in out}


def sh_pillars(r, k):
    hx, hz, hy = _n(r, 3, 6, k), _n(r, 3, 6, k), r.randint(1, 2)
    out = box((-hx, -hy, -hz), (hx, hy, hz))
    for x in range(-hx + 2, hx - 1):
        for z in range(-hz + 2, hz - 1):
            if x % 3 == 0 and z % 3 == 0:
                out -= box((x, -hy, z), (x, hy, z))
    return out


def sh_ring(r, k):
    """A gallery running round a solid core: a loop inside one room."""
    hx, hz, hy = _n(r, 3, 6, k), _n(r, 3, 6, k), r.randint(0, 2)
    out = box((-hx, -1, -hz), (hx, hy, hz))
    return out - box((-hx + 2, -1, -hz + 2), (hx - 2, hy, hz - 2))


def sh_cyl_v(r, k):
    rad, hy = _n(r, 3, 5, k), r.randint(1, 4)
    return {(i, j, z) for i in range(-rad, rad + 1) for z in range(-rad, rad + 1) for j in range(-hy, hy + 1)
            if i * i + z * z <= (rad + 0.4) ** 2}


def sh_cyl_h(r, k):
    rad, L = r.randint(1, 2), _n(r, 5, 9, k)
    out = {(x, j, z) for x in range(-L, L + 1) for j in range(-rad, rad + 1) for z in range(-rad, rad + 1)
           if j * j + z * z <= (rad + 0.45) ** 2}
    return out if r.random() < 0.5 else {(c[2], c[1], c[0]) for c in out}


def sh_dome(r, k):
    rx, rz, ry = _n(r, 3, 6, k), _n(r, 3, 6, k), r.randint(2, 4)
    return {c for c in ellipsoid(rx, ry, rz) if c[1] >= -1}


def sh_cave(r, k):
    """Overlapping lumps: an irregular natural cavern."""
    centres = [(0, 0, 0)]
    out = ellipsoid(r.uniform(2, 3.2) * k, r.uniform(1.5, 2.5), r.uniform(2, 3.2) * k)
    for _ in range(r.randint(2, 4)):
        base = r.choice(centres)
        c = (base[0] + r.randint(-4, 4), base[1] + r.randint(-2, 2), base[2] + r.randint(-4, 4))
        centres.append(c)
        out |= ellipsoid(r.uniform(1.5, 3.0) * k, r.uniform(1.2, 2.2), r.uniform(1.5, 3.0) * k, c)
    return out


def sh_ell(r, k):
    a, b = _n(r, 4, 7, k), _n(r, 4, 7, k)
    w = r.randint(1, 2)
    out = box((-a, -1, -w), (a, 1, w)) | box((a - 2 * w, -1, -w), (a, 1, b))
    if r.random() < 0.5:
        out = {(-c[0], c[1], c[2]) for c in out}
    return out if r.random() < 0.5 else {(c[2], c[1], c[0]) for c in out}


def sh_cross(r, k):
    a, b = _n(r, 4, 7, k), _n(r, 4, 7, k)
    return box((-a, -1, -1), (a, 1, 1)) | box((-1, -1, -b), (1, 1, b)) | box((-2, -1, -2), (2, 2, 2))


def sh_tiered(r, k):
    """A raised shelf along one side, and a lower ceiling over the other."""
    hx, hz = _n(r, 3, 5, k), _n(r, 3, 5, k)
    out = box((-hx, -2, -hz), (hx, 2, hz))
    out -= box((-hx, -2, -hz), (-1, -1, hz))
    if r.random() < 0.5:
        out -= box((2, 2, -hz), (hx, 2, hz))
    return out if r.random() < 0.5 else {(c[2], c[1], c[0]) for c in out}


def sh_shaft(r, k):
    """A tall shaft with ledges at different depths."""
    w, h = r.choice((1, 1, 2)), _n(r, 5, 8, k)
    out = box((-w, -h, -w), (w, h, w))
    for _ in range(r.randint(2, 4)):
        y = r.randint(-h + 1, h - 2)
        d = r.choice(HORIZ)
        c = (d[0] * (w + 1), y, d[2] * (w + 1))
        out |= box((c[0] - 1 + min(0, d[0]), y, c[2] - 1 + min(0, d[2])), (c[0] + 1 + max(0, d[0]), y + 1, c[2] + 1 + max(0, d[2])))
    return out


def sh_split(r, k):
    """Two floors, with holes in the slab between them."""
    hx, hz = _n(r, 3, 5, k), _n(r, 3, 5, k)
    out = box((-hx, -2, -hz), (hx, -1, hz)) | box((-hx, 1, -hz), (hx, 2, hz))
    for _ in range(r.randint(1, 3)):
        x, z = r.randint(-hx + 1, hx - 2), r.randint(-hz + 1, hz - 2)
        out |= box((x, 0, z), (x + 1, 0, z + 1))
    return out


def sh_bridge(r, k):
    """A rock beam spanning the room at mid-height."""
    hx, hz = _n(r, 3, 5, k), _n(r, 3, 5, k)
    out = box((-hx, -2, -hz), (hx, 2, hz))
    out -= box((-hx, 0, -1), (hx, 0, 0)) if r.random() < 0.5 else box((-1, 0, -hz), (0, 0, hz))
    return out


def sh_octagon(r, k):
    hx, hz, hy = _n(r, 3, 6, k), _n(r, 3, 6, k), r.randint(1, 3)
    cut = min(hx, hz) - 1
    return {c for c in box((-hx, -hy, -hz), (hx, hy, hz)) if abs(c[0]) + abs(c[2]) <= hx + hz - cut}


def sh_nook(r, k):
    """Dead-end alcove: a little pocket off a tunnel."""
    if r.random() < 0.5:
        return box((-1, -1, -1), (1, 0, 1))
    return ellipsoid(r.uniform(1.2, 2.0), 1.0, r.uniform(1.2, 2.0))


SHAPES = {
    "box": sh_box, "hall": sh_hall, "pillars": sh_pillars, "ring": sh_ring, "cyl_v": sh_cyl_v,
    "cyl_h": sh_cyl_h, "dome": sh_dome, "cave": sh_cave, "ell": sh_ell, "cross": sh_cross,
    "tiered": sh_tiered, "shaft": sh_shaft, "split": sh_split, "bridge": sh_bridge,
    "octagon": sh_octagon, "nook": sh_nook,
}


def arena(r, shape, half):
    """The reactor or boss chamber: boxy, with a clear middle and a flat east wall."""
    hx, hy, hz = half
    out = box((-hx, -hy, -hz), (hx, hy, hz))
    if shape == "octagon":
        cut = min(hx, hz) // 2
        out = {c for c in out if abs(c[0]) + abs(c[2]) <= hx + hz - cut or abs(c[2]) <= 1}
    elif shape == "pillars":
        for x in (-hx + 2, hx - 2):
            for z in (-hz + 2, hz - 2):
                out -= box((x, -hy, z), (x, hy, z))
    elif shape == "cathedral":
        out = box((-hx, -hy, -hz), (hx, hy - 2, hz)) | box((-hx + 2, hy - 1, -hz + 2), (hx - 2, hy, hz - 2))
    elif shape == "tiered":
        out -= box((-hx, -hy, -hz), (-hx + 2, -hy, hz))
        out -= box((-hx, -hy, -hz), (hx, -hy, -hz + 1))
    return out


# ----------------------------------------------------------------------------- noise
class Noise:
    """Smooth value noise on a lattice of `period` cells, for tunnel wander."""

    def __init__(self, seed, period=4.0):
        self.seed = int(seed * 2 ** 31) & 0x7FFFFFFF
        self.p = period

    def _v(self, q):
        h = (q[0] * 73856093) ^ (q[1] * 19349663) ^ (q[2] * 83492791) ^ self.seed
        h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

    def __call__(self, c):
        x, y, z = (c[0] / self.p, c[1] / self.p, c[2] / self.p)
        qx, qy, qz = math.floor(x), math.floor(y), math.floor(z)
        fx, fy, fz = x - qx, y - qy, z - qz
        fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
        out = 0.0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                    out += self._v((qx + dx, qy + dy, qz + dz)) * w
        return out


# Tunnel styles: (turn penalty, wander, vertical step cost, material, widen, bulge chance, zig).
# zig: extra cost per step once a run is two cells long, so the tunnel keeps stepping
# sideways: a staircase the shell smoothing turns into a slanting, twisting drift.
STYLES = {
    "straight": (5.0, 0.4, 1.4, "metal", False, 0.0, 0.0),
    "winding": (0.15, 3.0, 1.2, "rock", False, 0.35, 0.0),
    "diagonal": (0.0, 1.2, 0.9, "rock", False, 0.25, 1.6),
    "wide": (2.0, 1.2, 1.5, "rock", True, 0.25, 0.0),
    "drop": (1.0, 1.0, 0.45, "rock", False, 0.2, 0.6),
    "duct": (3.0, 0.8, 1.0, "metal", False, 0.0, 0.0),
}


class Space:
    def __init__(self, sid, kind, zone, mat, cs, shape=""):
        self.id, self.kind, self.zone, self.mat, self.cells, self.shape = sid, kind, zone, mat, set(cs), shape
        self.ports = []
        self.links = set()
        self.depth = 0


class Mine:
    def __init__(self, spec, seed):
        self.spec = spec
        self.r = random.Random(seed)
        self.owner = {}
        self.spaces = []
        self.doors = []
        self.zone_rooms = []
        # Cells whose material differs from their space's: metal round key doors.
        self.matover = {}

    # ------------------------------------------------------------------ occupancy
    def free(self, c, ignore=(), margin=NEAR):
        if c in self.owner:
            return False
        for d in margin:
            o = self.owner.get((c[0] + d[0], c[1] + d[1], c[2] + d[2]))
            if o is not None and o not in ignore:
                return False
        return True

    def new_space(self, kind, zone, mat, cs, shape=""):
        sp = Space(len(self.spaces), kind, zone, mat, cs, shape)
        self.spaces.append(sp)
        for c in cs:
            self.owner[c] = sp.id
        return sp

    def room_cells_clear(self, cs):
        return all(self.free(c, margin=NEAR2) for c in cs)

    # ------------------------------------------------------------------ ports
    def port(self, sp, d, toward):
        """A cell on sp's face d, as near the target as it can be, away from other ports."""
        opts = []
        for c in sp.cells:
            o = add(c, d)
            if o in sp.cells:
                continue
            if sp.kind == "tunnel":
                # Junctions only off straight runs, square to the run.
                axis = [i for i in range(3) if d[i]][0]
                runs = [a for a in range(3) if a != axis and all(add(c, e) in sp.cells for e in DIR6 if e[a])]
                if not runs:
                    continue
            if any(max(abs(c[i] - p[i]) for i in range(3)) <= 2 for p, _ in sp.ports):
                continue
            # The way out must leave the room behind, not run back into another part of it.
            far = add(c, d, 3)
            if any(add(c, d, k) in sp.cells for k in (1, 2, 3, 4)) or any(add(far, e) in sp.cells for e in NEAR):
                continue
            score = sum((o[i] - toward[i]) ** 2 for i in range(3) if not d[i]) + self.r.random() * 6
            opts.append((score, c))
        if not opts:
            return None
        opts.sort()
        return opts[min(len(opts) - 1, int(self.r.random() ** 2 * 3))][1]

    # ------------------------------------------------------------------ routing
    def route(self, start, sdir, goal, style, avoid):
        turn, wander, vert, _m, _w, _b, zig = STYLES[style]
        noise = Noise(self.r.random(), self.r.choice((3.0, 4.0, 6.0)))
        lo = [min(start[i], goal[i]) - 12 for i in range(3)]
        hi = [max(start[i], goal[i]) + 12 for i in range(3)]
        manhattan = sum(abs(start[i] - goal[i]) for i in range(3))
        unit = 1.0 + wander * 0.5 + zig * 0.3
        cap = (manhattan * 3.0 + 30) * unit
        hw = unit * 1.15
        di0 = DIR6.index(sdir)
        heap = [(manhattan, 0.0, start, di0, 0)]
        best = {(start, di0, 0): 0.0}
        came = {}
        free_cache = {}
        expanded = 0
        while heap:
            f, g, c, di, run = heapq.heappop(heap)
            if best.get((c, di, run), 1e18) < g:
                continue
            expanded += 1
            if expanded > 40000 or g > cap:
                WHY.setdefault("cut", []).append((manhattan, expanded, round(g)))
                break
            for ni, d in enumerate(DIR6):
                if ni == (di ^ 1):
                    continue
                n = add(c, d)
                if n == goal:
                    path = []
                    state = (c, di, run)
                    while state[0] != start:
                        path.append(state[0])
                        state = came[state]
                    return path[::-1]
                if not all(lo[i] <= n[i] <= hi[i] for i in range(3)) or n in avoid:
                    continue
                ok = free_cache.get(n)
                if ok is None:
                    ok = free_cache[n] = self.free(n)
                if not ok:
                    continue
                nrun = min(run + 1, 3) if ni == di else 0
                step = (vert if d[1] else 1.0) + wander * noise(n) + (turn if ni != di else 0.0) + (zig if nrun >= 2 else 0.0)
                ng = g + step
                key = (n, ni, nrun)
                if ng < best.get(key, 1e18):
                    best[key] = ng
                    came[key] = (c, di, run)
                    h = sum(abs(n[i] - goal[i]) for i in range(3))
                    heapq.heappush(heap, (ng + h * hw, ng, n, ni, nrun))
        WHY.setdefault("exhaust", []).append((manhattan, expanded))
        return None

    def connect(self, a, b, zone, lock=None, style=None, toward_a=None, toward_b=None, stubs=None):
        """Routes a tunnel between spaces a and b. Returns the tunnel, or None."""
        r = self.r
        ca = toward_a or centre(b.cells)
        cb = toward_b or centre(a.cells)
        da = self.face_dir(a, ca, horizontal=lock is not None)
        db = self.face_dir(b, cb, horizontal=False)
        pa = self.port(a, da, ca)
        pb = self.port(b, db, cb)
        if pa is None or pb is None:
            WHY["port"] = WHY.get("port", 0) + 1
            return None
        if style is None:
            style = pick(r, self.spec["styles"])
        la = 3 if lock else (stubs or r.choice((1, 1, 2)))
        lb = r.choice((1, 1, 2))
        sa = [add(pa, da, n) for n in range(1, la + 1)]
        sb = [add(pb, db, n) for n in range(1, lb + 1)]
        for s, room in ((sa, a), (sb, b)):
            for i, c in enumerate(s):
                if not self.free(c, ignore=(room.id,)) or c in room.cells:
                    WHY["stub%d" % i] = WHY.get("stub%d" % i, 0) + 1
                    return None
        if set(sa) & set(sb):
            return None
        avoid = set(sa) | set(sb)
        for c in sa[:-1] + sb[:-1]:
            avoid |= {add(c, d) for d in NEAR}
        avoid.discard(sa[-1])
        avoid.discard(sb[-1])
        if lock:
            # Square shoulders round the door: nothing may hug it.
            for c in sa[:-1]:
                avoid |= {add(c, d) for d in NEAR}
            avoid.discard(sa[-1])
            avoid |= {add(sa[-1], d) for d in NEAR if any(d[i] and not da[i] for i in range(3))}
        def can_leave(c, d):
            n = add(c, d)
            return n not in avoid and self.free(n)
        if not can_leave(sa[-1], da) or not can_leave(sb[-1], db):
            for c, d, nm in ((sa[-1], da, "a"), (sb[-1], db, "b")):
                n = add(c, d)
                if n in avoid:
                    WHY.setdefault("boxed", []).append(nm + " avoid")
                elif not self.free(n):
                    near = {self.spaces[self.owner[add(n, e)]].kind + ("=a" if self.owner[add(n, e)] == a.id else "=b" if self.owner[add(n, e)] == b.id else "") for e in NEAR if add(n, e) in self.owner}
                    WHY.setdefault("boxed", []).append(nm + " " + ",".join(sorted(near)))
            return None
        path = self.route(sa[-1], da, sb[-1], style, avoid)
        if path is None:
            WHY["route"] = WHY.get("route", 0) + 1
            return None
        body = list(path)
        extra = set()
        turn, wander, vert, mat, widen, bulge, _z = STYLES[style]
        if widen and len(body) > 4:
            side = r.choice(DIR6)
            for i, c in enumerate(body[2:-2], 2):
                step = tuple(body[i + 1][j] - c[j] for j in range(3))
                s = side if not any(side[j] and step[j] for j in range(3)) else next(e for e in DIR6 if not any(e[j] and step[j] for j in range(3)) and e != neg(side))
                n = add(c, s)
                if self.free(n) and n not in avoid and all(self.free(add(n, e)) or add(n, e) in body or add(n, e) in extra for e in DIR6):
                    extra.add(n)
        if bulge and len(body) > 8 and r.random() < bulge * 2:
            for _ in range(r.randint(1, 2)):
                c = body[r.randint(3, len(body) - 4)]
                lump = ellipsoid(r.uniform(1.0, 1.6), r.uniform(0.8, 1.3), r.uniform(1.0, 1.6), c)
                lump -= set(body)
                if all(self.free(n) and n not in avoid for n in lump):
                    extra |= lump
        if mat == "metal" and r.random() > self.spec.get("metal", 0.5) + 0.2:
            mat = "rock"
        if mat == "rock" and style == "straight":
            mat = "metal"
        t = self.new_space("tunnel", zone, mat, sa + body + sb[::-1] + sorted(extra), style)
        t.path = sa + body + sb[::-1]
        a.ports.append((pa, da))
        b.ports.append((pb, db))
        t.ports += [(sa[0], da), (sb[0], db)]
        a.links.add(b.id)
        b.links.add(a.id)
        t.ends = (a.id, b.id)
        if lock:
            for c in sa + body[:2] + sb[::-1][-1:]:
                self.matover[c] = "metal"
            self.doors.append({"lock": lock, "cell": sa[1], "axis": "x" if da[0] else "z", "dir": da, "tunnel": t.id})
        return t

    def face_dir(self, sp, target, horizontal):
        c = centre(sp.cells)
        v = [target[i] - c[i] for i in range(3)]
        if horizontal:
            v[1] = 0
        opts = HORIZ if horizontal else DIR6
        weights = [max(0.01, sum(v[i] * d[i] for i in range(3))) ** 2 for d in opts]
        if sp.kind == "tunnel":
            weights = [w + 0.5 for w in weights]
        return self.r.choices(opts, weights)[0]

    # ------------------------------------------------------------------ rooms
    def grow_room(self, parent, zone, shape, lock=None, cs=None, tries=40, need=None, reserve=None):
        r = self.spec
        for _ in range(tries):
            rel = cs if cs is not None else SHAPES[shape](self.r, r.get("scale", 1.0))
            if lock:
                d = self.r.choice(HORIZ)
            else:
                v = r.get("vertical", 0.2)
                d = self.r.choices(DIR6, [1, 1, v * 2, v * 2, 1, 1])[0]
            pa, pb = bbox(parent.cells)
            ra, rb = bbox(rel)
            gap = self.r.randint(*r.get("gap", (3, 8))) + (2 if lock else 0)
            off = [0, 0, 0]
            for i in range(3):
                if d[i] > 0:
                    off[i] = pb[i] + gap + 1 - ra[i]
                elif d[i] < 0:
                    off[i] = pa[i] - gap - 1 - rb[i]
                else:
                    spread = r.get("spread", 6) if i != 1 else r.get("spread_y", 3)
                    mid = (pa[i] + pb[i]) // 2
                    off[i] = mid + self.r.randint(-spread, spread) - (ra[i] + rb[i]) // 2
            placed = {add(c, tuple(off)) for c in rel}
            if not self.room_cells_clear(placed):
                continue
            if need is not None and not need(placed):
                continue
            mat = "rock" if self.r.random() > r.get("metal", 0.5) else "metal"
            if shape in ("cave", "dome"):
                mat = "rock"
            room = self.new_space("room", zone, mat, placed, shape)
            extra = reserve(room) if reserve else None
            t = self.connect(parent, room, zone, lock=lock)
            if t is None:
                self.drop(room)
                if extra is not None:
                    self.drop(extra)
                continue
            room.extra = extra
            room.depth = parent.depth + 1
            room.parent = parent.id
            return room
        return None

    def drop(self, sp):
        for c in sp.cells:
            if self.owner.get(c) == sp.id:
                del self.owner[c]
        sp.cells = set()
        sp.kind = "dead"


def centre(cs):
    n = len(cs)
    return tuple(sum(c[i] for c in cs) / n for i in range(3))


def pick(r, weights):
    keys = sorted(weights)
    return r.choices(keys, [weights[k] for k in keys])[0]


# ----------------------------------------------------------------------------- build
def build(spec):
    for attempt in range(int(__import__("os").environ.get("MAZE_ATTEMPTS", 40))):
        mine = Mine(spec, spec["seed"] * 1000 + attempt)
        try:
            out = _build(mine, spec)
            print(f"[maze] {spec.get('name', '?')}: attempt {attempt}, {len(mine.owner)} cells, "
                  f"{sum(1 for s in mine.spaces if s.kind == 'room')} rooms, {sum(1 for s in mine.spaces if s.kind == 'tunnel')} tunnels")
            return mine, out
        except Fail as e:
            print(f"[maze] attempt {attempt} failed: {e}")
    raise RuntimeError("level generation failed")


def _build(m, spec):
    r = m.r
    keys = spec["keys"]
    zones = spec["zones"]
    assert len(zones) == len(keys) + 1
    m.new_space("reserve", -1, "metal", box(*SPAWN_BOX))
    spine = m.new_space("tunnel", 0, "metal", [(0, 1, -k) for k in range(1, SPINE + 1)], "spine")
    # The spawn reserve's margin would forbid the spine's first cell; it is the one way in.
    spine.path = [(0, 1, -k) for k in range(1, SPINE + 1)]
    spine.ports = [((0, 1, -1), (0, 0, 1))]
    hub_shape = spec.get("hub") or pick(r, spec["shapes"])
    # The hub hangs straight off the spine's far end.
    hub = None
    for _ in range(60):
        rel = SHAPES[hub_shape](r, spec.get("scale", 1.0) * spec.get("hub_scale", 1.2))
        ra, rb = bbox(rel)
        gap = r.randint(2, 4)
        off = (-(ra[0] + rb[0]) // 2 + r.randint(-1, 1), 1 - (ra[1] + rb[1]) // 2 + r.randint(-1, 1), -SPINE - gap - 1 - rb[2])
        placed = {add(c, off) for c in rel}
        if not m.room_cells_clear(placed):
            continue
        hub = m.new_space("room", 0, spec.get("hub_mat", "metal"), placed, hub_shape)
        if not hub_link(m, spine, hub):
            m.drop(hub)
            hub = None
            continue
        break
    if hub is None:
        raise Fail("no hub")
    zone_rooms = [[hub]]
    gates = []
    entry = hub
    for z, zs in enumerate(zones):
        rooms = zone_rooms[z]
        target = zs["rooms"] + (0 if z else 0)
        stall = 0
        while len(rooms) < target and stall < 30:
            parent = pick_parent(r, rooms, zs.get("chain", 0.5))
            shape = pick(r, zs.get("shapes", spec["shapes"]))
            room = m.grow_room(parent, z, shape, tries=12)
            if room is None:
                stall += 1
                continue
            rooms.append(room)
        if len(rooms) < max(1, target - 1):
            raise Fail(f"zone {z}: only {len(rooms)} rooms")
        add_loops(m, rooms, zs.get("loops", 0), z)
        if z == len(zones) - 1:
            break
        # The gate to the next zone leaves from somewhere other than the key room.
        key_room = deepest(m, rooms, entry)
        m.key_rooms = getattr(m, "key_rooms", []) + [key_room]
        cand = [x for x in rooms if x is not key_room] or rooms
        r.shuffle(cand)
        nxt = None
        for parent in cand[:6]:
            nxt = m.grow_room(parent, z + 1, pick(r, zones[z + 1].get("shapes", spec["shapes"])), lock=keys[z], tries=10)
            if nxt is not None:
                break
        if nxt is None:
            raise Fail(f"no gate out of zone {z}")
        zone_rooms.append([nxt])
        gates.append(nxt)
        entry = nxt
    m.zone_rooms = zone_rooms
    # Reactor or boss chamber, deepest in the last zone.
    finale = spec["finale"]
    last = zone_rooms[-1]
    reactor_room = None
    order = sorted(last, key=lambda x: -x.depth)
    for parent in order[:4] * 2:
        rel = arena(r, finale.get("shape", "box"), finale["half"])
        cand = m.grow_room(parent, len(zones) - 1, "arena", cs=rel, tries=25, need=lambda cs: escape_fits(m, cs), reserve=lambda room: carve_escape(m, room))
        if cand is None:
            continue
        cand.mat = "core"
        if not hidden(m, cand):
            undo_room(m, cand)
            continue
        reactor_room = cand
        break
    if reactor_room is None:
        raise Fail("no reactor chamber")
    esc = reactor_room.extra
    # Extra ways across a gate: the same key opens another door.
    gl = spec.get("gated_loops", 0)
    for z in (gl if isinstance(gl, list) else [r.randrange(len(keys)) for _ in range(gl)]):
        a_side, b_side = zone_rooms[z], [x for x in zone_rooms[z + 1] if x is not reactor_room]
        pairs = sorted(((dist(a, b), a.id, b.id) for a in a_side for b in b_side))
        for _, ai, bi in pairs[:6]:
            if m.connect(m.spaces[ai], m.spaces[bi], z, lock=keys[z]):
                break
        else:
            if isinstance(gl, list):
                raise Fail(f"no second {keys[z]} door")
    # Dead-end nooks, junction spurs, then secrets.
    for z, zs in enumerate(zones):
        for _ in range(zs.get("nooks", 0)):
            for _try in range(6):
                pool = [s for s in m.spaces if s.zone == z and s.kind in ("room", "tunnel") and s is not reactor_room and s.cells and s.shape not in ("spine",)]
                parent = r.choice(pool)
                nook = m.grow_room(parent, z, "nook", tries=4)
                if nook is not None:
                    nook.kind = "nook"
                    break
    secrets = []
    for loot in spec.get("secrets", []):
        s = secret_room(m)
        if s is None:
            raise Fail("no place for a secret room")
        secrets.append((s, loot))
    repair(m)
    check_doors(m)
    for c, sid in m.owner.items():
        if m.spaces[sid].kind != "reserve":
            cells[c] = m.matover.get(c, m.spaces[sid].mat)
    m.reactor_room, m.esc, m.secrets = reactor_room, esc, secrets
    progression(m, keys)
    return populate(m, spec, reactor_room, esc, secrets)


def hub_link(m, spine, hub):
    """Spine's end straight on into the hub (the cutscene needs the spine straight)."""
    start = (0, 1, -SPINE - 1)
    pb = m.port(hub, (0, 0, 1), start)
    if pb is None:
        return False
    sb = [add(pb, (0, 0, 1), n) for n in (1, 2)]
    if not all(m.free(c, ignore=(hub.id, spine.id)) for c in sb) or not m.free(start, ignore=(spine.id, hub.id)):
        return False
    if start in sb:
        cs = [start] + [c for c in sb if c != start]
    else:
        avoid = {add(sb[0], d) for d in NEAR} - {sb[-1]}
        path = m.route(start, (0, 0, -1), sb[-1], "straight", avoid)
        if path is None:
            return False
        cs = [start] + path + sb[::-1]
    t = m.new_space("tunnel", 0, "metal", cs, "straight")
    t.path = cs
    t.ends = (spine.id, hub.id)
    hub.ports.append((pb, (0, 0, 1)))
    spine.links.add(hub.id)
    hub.links.add(spine.id)
    return True


def pick_parent(r, rooms, chain):
    if r.random() < chain:
        return rooms[-1]
    return r.choice(rooms)


def dist(a, b):
    ca, cb = centre(a.cells), centre(b.cells)
    return sum(abs(ca[i] - cb[i]) for i in range(3))


def add_loops(m, rooms, n, zone):
    made = 0
    pairs = sorted((dist(a, b) + m.r.random() * 8, a.id, b.id) for i, a in enumerate(rooms) for b in rooms[i + 1:]
                   if b.id not in a.links and dist(a, b) < 60)
    for _, ai, bi in pairs:
        if made >= n:
            break
        # Sometimes the loop joins a tunnel instead of a room: a junction mid-run.
        a, b = m.spaces[ai], m.spaces[bi]
        if m.r.random() < 0.3:
            tunnels = [s for s in m.spaces if s.kind == "tunnel" and s.zone == zone and len(s.cells) > 6 and s.shape != "spine" and b.id not in s.ends]
            if tunnels:
                a = min(tunnels, key=lambda s: dist(s, b) + m.r.random() * 10)
        if m.connect(a, b, zone):
            made += 1


def deepest(m, rooms, entry):
    """Rooms furthest from the zone's entrance by tunnel hops: where the key goes."""
    from collections import deque
    seen = {entry.id: 0}
    q = deque([entry.id])
    while q:
        s = q.popleft()
        for t in m.spaces[s].links:
            if t not in seen and m.spaces[t].zone == entry.zone:
                seen[t] = seen[s] + 1
                q.append(t)
    cand = [x for x in rooms if x is not entry] or rooms
    return max(cand, key=lambda x: (seen.get(x.id, 0), len(x.cells) < 400, m.r.random()))


def escape_legs(door):
    run = (door[0] + ESCAPE_LEGS[0], door[1], door[2])
    north = (run[0], run[1], run[2] - ESCAPE_LEGS[1])
    up = (north[0], north[1] + ESCAPE_LEGS[2], north[2])
    end = (up[0] + ESCAPE_LEGS[3], up[1], up[2])
    return [door, run, north, up, end]


def leg_cells(points):
    out = []
    for a, b in zip(points, points[1:]):
        for c in sorted(box(tuple(min(a[i], b[i]) for i in range(3)), tuple(max(a[i], b[i]) for i in range(3)))):
            if c not in out:
                out.append(c)
    return out


def escape_door(cs):
    cx, cy, cz = (round(v) for v in centre(cs))
    row = [c for c in cs if c[1] == cy and c[2] == cz]
    ex = max(c[0] for c in row)
    return (ex + 1, cy, cz)


def escape_fits(m, cs):
    door = escape_door(cs)
    legs = leg_cells(escape_legs(door))
    return all(m.free(c, margin=NEAR2) for c in legs[2:]) and all(m.free(c) for c in legs[:2])


def carve_escape(m, room):
    door = escape_door(room.cells)
    pts = escape_legs(door)
    sp = m.new_space("escape", room.zone, "metal", leg_cells(pts), "escape")
    # Middle legs are bare rock, as before.
    sp.rock = set(leg_cells(pts[1:4])) - {pts[1], pts[3]}
    sp.points = pts
    return sp


def undo_room(m, room):
    """Drops a room and the tunnel that was just routed to it."""
    for s in m.spaces:
        if s.kind == "tunnel" and getattr(s, "ends", (None, None))[1] == room.id:
            m.drop(s)
            m.doors = [d for d in m.doors if d["tunnel"] != s.id]
            m.spaces[s.ends[0]].links.discard(room.id)
            m.spaces[s.ends[0]].ports = m.spaces[s.ends[0]].ports[:-1]
    if getattr(room, "extra", None) is not None:
        m.drop(room.extra)
    m.drop(room)


def hidden(m, room):
    """No straight line from any door into this zone reaches the chamber's middle."""
    ctr = tuple(v * S for v in centre(room.cells))
    for d in m.doors:
        c = [v * S for v in d["cell"]]
        axis = "xyz".index(d["axis"])
        others = [i for i in range(3) if i != axis]
        for along in (-16, -8, 0, 6, 12):
            for o1 in (-3.5, 0, 3.5):
                for o2 in (-3.5, 0, 3.5):
                    p = list(c)
                    p[axis] += along
                    p[others[0]] += o1
                    p[others[1]] += o2
                    if clear_line(m, p, ctr):
                        return False
    return True


def clear_line(m, a, b):
    n = int(math.dist(a, b) / 0.5) + 1
    deep = 0
    for i in range(n + 1):
        t = i / n
        p = [a[j] + (b[j] - a[j]) * t for j in range(3)]
        c = tuple(int(round(v / S)) for v in p)
        if c not in m.owner:
            # Count only points well inside solid rock: smoothing never opens those.
            inner = all(abs(p[j] / S - c[j]) < 0.38 for j in range(3))
            if inner:
                deep += 1
                if deep >= 2:
                    return False
    return True


def secret_room(m):
    """A small hidden room behind a flush panel on a straight metal tunnel."""
    r = m.r
    runs = []
    for s in m.spaces:
        if s.kind != "tunnel" or s.shape in ("spine",) or s.zone < 0:
            continue
        for c in getattr(s, "path", []):
            if m.matover.get(c, s.mat) != "metal":
                continue
            for axis in (0, 2):
                e = tuple(1 if i == axis else 0 for i in range(3))
                if add(c, e) in s.cells and add(c, neg(e)) in s.cells and m.matover.get(add(c, e), s.mat) == "metal" and m.matover.get(add(c, neg(e)), s.mat) == "metal":
                    runs.append((s, c, e))
    door_cells = [d["cell"] for d in m.doors]
    runs = [x for x in runs if all(max(abs(x[1][i] - dc[i]) for i in range(3)) > 1 for dc in door_cells)]
    r.shuffle(runs)
    for s, c, e in runs[:80]:
        side = (0, 0, r.choice((-1, 1))) if e[0] else (r.choice((-1, 1)), 0, 0)
        if any(add(c, d) in m.owner for d in DIR6 if d != e and d != neg(e)):
            continue
        door = add(c, side)
        corridor = [door, add(door, side), add(door, side, 2)]
        rel = box((-2, -1, -2), (2, 1, 2))
        far = add(door, side, 5)
        room = {add(x, far) for x in rel}
        if not all(m.free(x, ignore=(s.id,)) for x in corridor[:1]):
            continue
        if not all(m.free(x) for x in corridor[1:]) or not m.room_cells_clear(room):
            continue
        sp = m.new_space("secret", s.zone, "metal", corridor + sorted(room), "secret")
        sp.door = {"id": f"secret_{door}", "cell": list(door), "axis": "x" if side[0] else "z", "lock": "secret",
                   "offset": [-side[0] * S * 0.5, 0.0, -side[2] * S * 0.5]}
        sp.room = room
        return sp
    return None


def block_ok(m, o):
    blk = [(o[0] + i, o[1] + j, o[2] + k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    for want in (True, False):
        group = [c for c in blk if (c in m.owner) == want]
        if len(group) <= 1:
            continue
        seen = {group[0]}
        stack = [group[0]]
        while stack:
            c = stack.pop()
            for d in DIR6:
                n = add(c, d)
                if n in group and n not in seen:
                    seen.add(n)
                    stack.append(n)
        if len(seen) != len(group):
            return False, blk
    return True, blk


def repair(m):
    """Opens cells wherever open space meets only along an edge or a corner.

    The shell is built from shared grid vertices, so such joints would be non-manifold.
    """
    for _ in range(8):
        bad = 0
        origins = {add(c, (-i, -j, -k)) for c in m.owner for i in (0, 1) for j in (0, 1) for k in (0, 1)}
        for o in sorted(origins):
            ok, blk = block_ok(m, o)
            if ok:
                continue
            bad += 1
            owners = {m.owner[c] for c in blk if c in m.owner}
            kinds = {m.spaces[x].kind for x in owners}
            if len(owners) > 1 and not (len(owners) == 2 and "reserve" not in kinds):
                raise Fail(f"spaces {owners} touch at {o}")
            sid = max(owners, key=lambda x: sum(1 for c in blk if m.owner.get(c) == x))
            if m.spaces[sid].kind in ("reserve", "escape"):
                raise Fail(f"bad joint by {m.spaces[sid].kind} at {o}")
            closed = [c for c in blk if c not in m.owner]
            closed.sort(key=lambda c: -sum(1 for d in DIR6 if add(c, d) in m.owner))
            c = closed[0]
            m.owner[c] = sid
            m.spaces[sid].cells.add(c)
        if not bad:
            return
    raise Fail("could not repair joints")


def check_doors(m):
    for d in m.doors:
        c = d["cell"]
        e = d["dir"]
        if add(c, e) not in m.owner or add(c, neg(e)) not in m.owner:
            raise Fail(f"door {c} lost its tunnel")
        for s in DIR6:
            if s != e and s != neg(e) and add(c, s) in m.owner:
                raise Fail(f"door {c} has an open side")


def progression(m, keys):
    """Keys open their zones in order; nothing reaches the reactor without them all."""
    from collections import deque
    doors = {tuple(d["cell"]): d["lock"] for d in m.doors}
    esc = set(m.esc.cells)
    start = (0, 1, -1)
    have = set()
    key_cells = {k: None for k in keys}
    for k, room in zip(keys, m.key_rooms):
        key_cells[k] = room
    reached_before = []
    for step in range(len(keys) + 1):
        seen = {start}
        q = deque([start])
        while q:
            c = q.popleft()
            for d in DIR6:
                n = add(c, d)
                if n in seen or n not in m.owner or n in esc:
                    continue
                if n in doors and doors[n] not in have:
                    continue
                seen.add(n)
                q.append(n)
        room_in = any(c in seen for c in m.reactor_room.cells)
        if step < len(keys):
            if room_in:
                raise Fail(f"reactor reachable with only {sorted(have)}")
            kr = key_cells[keys[step]]
            if not any(c in seen for c in kr.cells):
                raise Fail(f"key {keys[step]} unreachable with {sorted(have)}")
            have.add(keys[step])
        else:
            if not room_in:
                raise Fail("reactor unreachable with every key")
            secret_cells = set()
            for s in m.secrets if hasattr(m, "secrets") else []:
                secret_cells |= s[0].cells
            missing = [c for c in m.owner if c not in seen and c not in esc and m.spaces[m.owner[c]].kind not in ("reserve", "secret")]
            if missing:
                raise Fail(f"{len(missing)} cells unreachable, e.g. {missing[0]}")


# ----------------------------------------------------------------------------- populate
def populate(m, spec, reactor_room, esc, secrets):
    r = m.r
    out = {"DOORS": [], "ROBOTS": [], "TURRETS": [], "PICKUPS": [], "MINES": [], "ASTRONAUTS": []}
    used = set()
    spawn_guard = {(0, 1, -k) for k in range(1, SPINE + 1)}

    def interior(c, sp):
        return all(add(c, d) in sp.cells for d in DIR6)

    def roomy(c, sp):
        return all(add(c, d) in sp.cells for d in NEAR)

    def take(pool, n, pred=None):
        pool = [c for c in sorted(pool) if c not in used and (pred is None or pred(c))]
        got = r.sample(pool, min(n, len(pool)))
        used.update(got)
        return got

    doors = m.doors
    for i, d in enumerate(doors):
        out["DOORS"].append({"id": f"{d['lock']}_{i}", "cell": list(d["cell"]), "axis": d["axis"], "lock": d["lock"]})
        used.add(d["cell"])
        used |= {add(d["cell"], d["dir"]), add(d["cell"], neg(d["dir"]))}
    for s, loot in secrets:
        out["DOORS"].append(s.door)
        for kind, c in zip(loot, take(s.room, len(loot))):
            out["PICKUPS"].append((kind, _world(c)))

    rooms = [s for s in m.spaces if s.kind in ("room", "nook") and s is not reactor_room and s.cells]
    tunnels = [s for s in m.spaces if s.kind == "tunnel" and s.cells and s.shape != "spine"]
    nooks = [s for s in rooms if s.kind == "nook"]
    big = [s for s in rooms if s.kind == "room"]

    # Keys: one per zone, in the room furthest from the zone's entrance.
    for k, room in zip(spec["keys"], m.key_rooms):
        c = take(room.cells, 1, lambda c: interior(c, room)) or take(room.cells, 1)
        out["PICKUPS"].append(("key_" + k, _world(c[0])))

    # Specials: upgrades in nooks or side rooms, ordered by zone hint.
    for item in spec.get("specials", []):
        name, zone = item if isinstance(item, tuple) else (item, None)
        pool = [s for s in (nooks if name.startswith("upgrade") and nooks else rooms) if zone is None or s.zone == zone]
        pool = pool or [s for s in rooms if zone is None or s.zone == zone] or rooms
        sp = r.choice(pool)
        c = take(sp.cells, 1)
        if c:
            out["PICKUPS"].append((name, _world(c[0])))
    # Consumables: some in every room, extra in nooks.
    kinds = ("shield", "energy", "ammo")
    n_cons = spec.get("consumables", 20)
    homes = rooms + nooks * 2
    for i in range(n_cons):
        sp = homes[i % len(homes)] if i < len(homes) else r.choice(homes)
        c = take(sp.cells, 1)
        if c:
            out["PICKUPS"].append((kinds[i % 3] if r.random() < 0.7 else r.choice(kinds), _world(c[0])))

    # Robots: rooms by volume, a share in tunnels, heavies where there is room to fly.
    roster = spec["roster"]
    total = spec["enemies"]
    in_tunnels = int(total * spec.get("tunnel_share", 0.25))
    for kind in spec.get("heavies", []):
        pool = [s for s in big if s.zone > 0 or len(big) == 1] or big
        sp = r.choice(pool)
        c = take(sp.cells, 1, lambda c: roomy(c, sp)) or take(sp.cells, 1, lambda c: interior(c, sp)) or take(sp.cells, 1)
        if c:
            out["ROBOTS"].append((kind, _world(c[0])))
    weights = [max(1, len(s.cells)) ** 0.6 for s in rooms]
    hub_id = m.zone_rooms[0][0].id
    for _ in range(total - in_tunnels):
        sp = r.choices(rooms, weights)[0]
        c = take(sp.cells, 1, lambda c: interior(c, sp) or sp.kind == "nook") or take(sp.cells, 1)
        if c:
            out["ROBOTS"].append((pick(r, roster), _world(c[0])))
    tun_cells = [c for s in tunnels for c in getattr(s, "path", s.cells)[2:-1]]
    for c in take(tun_cells, in_tunnels, lambda c: c not in spawn_guard):
        out["ROBOTS"].append((pick(r, spec.get("tunnel_roster", roster)), _world(c)))

    # Mines in tunnels; tripwires on side walls of one-cell runs.
    def one_wide(c):
        for axis in range(3):
            e = tuple(1 if i == axis else 0 for i in range(3))
            if add(c, e) in m.owner and add(c, neg(e)) in m.owner and all(add(c, d) not in m.owner for d in DIR6 if not d[axis]):
                return e
        return None
    for kind, n in sorted(spec.get("mines", {}).items()):
        for c in take(tun_cells, n, lambda c: c not in spawn_guard and (kind != "tripwire" or one_wide(c) is not None)):
            if kind == "tripwire":
                e = one_wide(c)
                sides = ((0, 0, 1), (0, 0, -1)) if e[0] else ((1, 0, 0), (-1, 0, 0))
                side = sides[0]
                pos = [c[i] * S + side[i] * (S / 2 - 0.5) for i in range(3)]
                out["MINES"].append({"type": "tripwire", "pos": pos, "normal": [-v for v in side]})
            else:
                out["MINES"].append({"type": kind, "pos": _world(c), "normal": [0, 1, 0]})

    # Wall turrets in rooms, on walls and ceilings away from doorways.
    port_cells = {p for s in m.spaces for p, _ in s.ports}
    def mounts(sp):
        opts = []
        for c in sorted(sp.cells):
            if any(max(abs(c[i] - p[i]) for i in range(3)) <= 1 for p in port_cells):
                continue
            for d in DIR6:
                if d == (0, -1, 0) or add(c, d) in m.owner:
                    continue
                opts.append(([c[i] * S + d[i] * (S / 2 - 0.5) for i in range(3)], [-d[0], -d[1], -d[2]]))
        return opts
    n_tur = spec.get("turrets", 6)
    tur_rooms = [s for s in big if len(s.cells) > 60] or big
    for i in range(n_tur):
        sp = tur_rooms[i % len(tur_rooms)] if i < len(tur_rooms) else r.choice(tur_rooms)
        opts = mounts(sp)
        if opts:
            out["TURRETS"].append(r.choice(opts))

    # Hostages wait in a nook or a quiet side room in the middle of the mine.
    n_astro = spec.get("astronauts", 0)
    if n_astro:
        pool = [s for s in rooms if s.zone == min(1, len(spec["keys"]))] or rooms
        sp = max(pool, key=lambda s: (s.kind == "room", len(s.cells) < 300, r.random()))
        for c in take(sp.cells, n_astro):
            out["ASTRONAUTS"].append(_world(c))

    # The finale.
    f = spec["finale"]
    ctr = tuple(int(round(v)) for v in centre(reactor_room.cells))
    used.add(ctr)
    vol = reactor_room.cells
    far = lambda c: max(abs(c[i] - ctr[i]) for i in range(3)) >= 3
    if f.get("boss"):
        out["ROBOTS"].append((f["boss"], _world(ctr)))
        out["REACTOR"] = None
        out["REACTOR_SCALE"], out["REACTOR_HP"], out["REACTOR_NOVA"] = 2.0, 0.0, False
    else:
        hy = min(ctr[1] - min(c[1] for c in vol if c[0] == ctr[0] and c[2] == ctr[2]),
                 max(c[1] for c in vol if c[0] == ctr[0] and c[2] == ctr[2]) - ctr[1])
        out["REACTOR"] = _world(ctr)
        out["REACTOR_SCALE"] = f.get("scale", min(2.0, (hy * S + S / 2 - 1.0) / 21.0))
        out["REACTOR_HP"] = f["hp"]
        out["REACTOR_NOVA"] = f.get("nova", True)
    for kind in f.get("enemies", []):
        c = take(vol, 1, lambda c: far(c) and interior(c, reactor_room)) or take(vol, 1, lambda c: max(abs(c[i] - ctr[i]) for i in range(3)) >= 2) or take(vol, 1)
        if c:
            out["ROBOTS"].append((kind, _world(c[0])))
    for kind in f.get("pick", []):
        c = take(vol, 1, far)
        if c:
            out["PICKUPS"].append((kind, _world(c[0])))
    opts = mounts(reactor_room)
    for t in r.sample(opts, min(f.get("turrets", 2), len(opts))):
        out["TURRETS"].append(t)
    spawns = take(vol, 4, lambda c: far(c) and interior(c, reactor_room))
    spawns += take(vol, 4 - len(spawns), lambda c: max(abs(c[i] - ctr[i]) for i in range(3)) >= 2)
    out["ALARM_SPAWNS"] = [_world(c) for c in spawns]

    # Escape tunnel.
    pts = esc.points
    out["DOORS"].append({"id": "escape", "cell": list(pts[0]), "axis": "x", "lock": "reactor"})
    for c in esc.rock:
        cells[c] = "rock"
    out["ESCAPE_END"] = _world(pts[-1])
    out["ESCAPE_PATH"] = [_world(p) for p in pts]
    out["ESCAPE_TRIGGER"] = _world(add(pts[0], (1, 0, 0), 3))
    out["CATCH_UP"] = [_world((0, 1, -k)) for k in range(2, 10)]
    out["DETAIL_DENSITY"] = spec.get("detail", 0.5)
    # Lights along tunnels that bend: straight runs are lit by level.py already.
    lights = []
    for s in tunnels:
        path = getattr(s, "path", [])
        for i in range(1, len(path) - 1, 3):
            c = path[i]
            straight = any(add(c, e) in m.owner and add(c, neg(e)) in m.owner and all(add(c, d) not in m.owner for d in DIR6 if d not in (e, neg(e))) for e in ((1, 0, 0), (0, 1, 0), (0, 0, 1)))
            if not straight:
                lights.append(_world(c))
    out["TUNNEL_LIGHTS"] = lights
    # Ceiling lights can't reach the bottom of a tall room: floodlights on its walls.
    flood = []
    for s in m.spaces:
        if s.kind not in ("room",) or not s.cells:
            continue
        lo_, hi_ = bbox(s.cells)
        if hi_[1] - lo_[1] < 5:
            continue
        for y in range(lo_[1] + 1, hi_[1], 3):
            layer = sorted(c for c in s.cells if c[1] == y)
            walls = [(c, d) for c in layer for d in HORIZ if add(c, d) not in m.owner]
            for c, d in r.sample(walls, min(2, len(walls))):
                flood.append({"pos": [c[i] * S + d[i] * 3.6 for i in range(3)], "color": [1.0, 0.8, 0.62], "energy": 11.0, "range": 52.0})
    out["EXTRA_LIGHTS"] = flood
    # Viewpoints for docs and review: from a far corner of each room, and down some tunnels.
    tour = []
    for s in sorted((s for s in m.spaces if s.kind == "room" and s.cells), key=lambda s: (s.zone, s.id)):
        ctr = centre(s.cells)
        inner = [c for c in s.cells if all(add(c, d) in s.cells for d in DIR6)] or sorted(s.cells)
        eye = max(sorted(inner), key=lambda c: sum((c[i] - ctr[i]) ** 2 for i in range(3)) - 2 * abs(c[1] - ctr[1]))
        look = [2 * ctr[i] - eye[i] for i in range(3)]
        tour.append([f"z{s.zone}_{s.shape}_{s.id}", _world(eye), [v * S for v in look]])
    for s in [s for s in tunnels if len(getattr(s, "path", [])) > 10][:6]:
        tour.append([f"z{s.zone}_tunnel_{s.shape}_{s.id}", _world(s.path[2]), _world(s.path[7])])
    out["TOUR"] = tour
    out["SPACES"] = [{"kind": s.kind, "shape": s.shape, "zone": s.zone, "cells": len(s.cells)} for s in m.spaces if s.cells]
    return out


LAST = None


def mission(spec):
    global LAST
    mine, out = build(spec)
    LAST = mine
    return out

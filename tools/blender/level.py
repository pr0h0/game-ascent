"""Builds the mine: a sparse grid of carved cells becomes a rounded inward shell.

Coordinates in this file are Godot's (x right, y up, -z north). The G2B matrix
maps them to Blender, and the glTF exporter maps them straight back.

Run with: blender -b --python level.py -- <layout id>

Outputs assets/models/<id>.glb (Shell_*: visual+collision, Detail_*: visual)
and assets/levels/<id>.json (cells for pathfinding, lights, spawns, doors).
"""
import importlib
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
from level_api import S, c, carve, cells, fill  # noqa: E402
from wall_modules import VARIANTS  # noqa: E402
from kit import ROOT, RY, T, Kit, empty, export, reset_scene  # noqa: E402
from themes import THEMES  # noqa: E402

N = 4  # shell subdivisions per cell edge
CHUNK = 8  # cells per render/collision chunk
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
LEVEL_ID = sys.argv[sys.argv.index("--") + 1]
layout = importlib.import_module("layout_" + LEVEL_ID)
DOORS, REACTOR, ROBOTS, ASTRONAUTS, TURRETS, PICKUPS = layout.DOORS, layout.REACTOR, layout.ROBOTS, layout.ASTRONAUTS, layout.TURRETS, layout.PICKUPS
ESCAPE_END, ESCAPE_PATH, ESCAPE_TRIGGER, ALARM_SPAWNS = layout.ESCAPE_END, layout.ESCAPE_PATH, layout.ESCAPE_TRIGGER, layout.ALARM_SPAWNS
DETAIL_DENSITY = getattr(layout, "DETAIL_DENSITY", 1.0)
THEME = THEMES[LEVEL_ID]
ROCK_MAT = "rock_" + LEVEL_ID
LAVA_MAT = "lava_" + LEVEL_ID
# Optional molten floors: {"zones": [...], "cover": 0..1, "max_cells": n}. See choose_lava().
LAVA = getattr(layout, "LAVA", None)
DOOR_GLOW = {"blue": "glow_blue", "yellow": "glow_yellow", "red": "glow_red", "reactor": "glow_green", "entry": "glow_amber"}

# ----------------------------------------------------------------------- spawn rooms
# Every level starts in its own room: (low corner, high corner, zone, trim, trim light, bay).
# Each contains the start cell (0, 1, 2) and the way out through (0, 1, 0).
SPAWN_ROOMS = {
    "first_shift": ((-2, 0, 0), (2, 2, 4), "metal", "glow_amber", (1.0, 0.72, 0.36), 1),
    "the_vein": ((-1, 0, 0), (1, 3, 4), "rock", "glow_green", (0.45, 1.0, 0.6), 2),
    "black_shaft": ((-3, 0, 0), (3, 1, 3), "metal", "glow_red", (1.0, 0.42, 0.3), 3),
    "smelter_row": ((-2, 0, 0), (2, 3, 5), "metal", "glow_orange", (1.0, 0.56, 0.2), 4),
    "hollow_reach": ((-3, -1, 0), (3, 3, 5), "rock", "glow_blue", (0.42, 0.68, 1.0), 5),
    "deep_cut": ((-1, 0, 0), (2, 2, 6), "rock", "glow_amber", (1.0, 0.7, 0.34), 6),
    "overseer_pit": ((-2, 0, 0), (2, 2, 3), "core", "glow_red", (1.0, 0.3, 0.24), 7),
    "glass_seam": ((-2, -1, 0), (2, 3, 4), "rock", "glow_blue", (0.5, 0.86, 1.0), 8),
    "last_light": ((-2, 1, 0), (2, 1, 5), "metal", "glow_green", (0.5, 1.0, 0.66), 9),
    "core_zero": ((-4, 0, 0), (4, 3, 5), "core", "glow_white", (0.86, 0.92, 1.0), 10),
}
AIRLOCK_CELLS = 6
ROOM_LOW, ROOM_HIGH, ROOM_ZONE, ROOM_TRIM, ROOM_TRIM_LIGHT, ROOM_NUMBER = SPAWN_ROOMS[LEVEL_ID]


def build_spawn_room():
    """Swaps the stock launch bay for this level's room, with a sealed airlock behind it."""
    fill((-2, 0, 0), (2, 2, 4))
    room = {(i, j, k) for i in range(ROOM_LOW[0], ROOM_HIGH[0] + 1)
            for j in range(ROOM_LOW[1], ROOM_HIGH[1] + 1)
            for k in range(ROOM_LOW[2], ROOM_HIGH[2] + 1)}
    door_z = ROOM_HIGH[2] + 1
    airlock = {(0, 1, door_z + n) for n in range(AIRLOCK_CELLS)}
    way_out = (0, 1, -1)
    for cell in room | airlock:
        for d in DIRS:
            near = (cell[0] + d[0], cell[1] + d[1], cell[2] + d[2])
            if near in cells and near != way_out:
                raise ValueError(f"{LEVEL_ID}: spawn room cell {cell} touches level cell {near}")
    if way_out not in cells:
        raise ValueError(f"{LEVEL_ID}: nothing connects to the spawn room")
    carve(ROOM_LOW, ROOM_HIGH, ROOM_ZONE)
    carve((0, 1, door_z), (0, 1, door_z + AIRLOCK_CELLS - 1), "metal")
    DOORS.append({"id": "entry", "cell": [0, 1, door_z], "axis": "z", "lock": "entry"})

build_spawn_room()


# ----------------------------------------------------------------------- shell
def value_noise(p, seed):
    rng = np.random.default_rng(seed)
    lat = rng.random((32, 32, 32))
    q = np.floor(p).astype(int)
    f = p - np.floor(p)
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                wx = f[:, 0] if dx else 1 - f[:, 0]
                wy = f[:, 1] if dy else 1 - f[:, 1]
                wz = f[:, 2] if dz else 1 - f[:, 2]
                out = out + lat[(q[:, 0] + dx) % 32, (q[:, 1] + dy) % 32, (q[:, 2] + dz) % 32] * wx * wy * wz
    return out * 2 - 1


vert_ids = {}
verts = []
quads = []  # vertex indices
quad_info = []  # (cell, axis, sign, zone)
ZONE_ROCK = {"rock": 1.0, "metal": 0.0, "core": 0.0}
for cell, zone in cells.items():
    for d, (dx, dy, dz) in enumerate(DIRS):
        if (cell[0] + dx, cell[1] + dy, cell[2] + dz) in cells:
            continue
        a = d // 2
        s = dx + dy + dz
        ua, va = (a + 1) % 3, (a + 2) % 3
        plane = cell[a] * N + s * N // 2
        for iu in range(N):
            for iv in range(N):
                corners = []
                for ou, ov in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    key = [0, 0, 0]
                    key[a] = plane
                    key[ua] = cell[ua] * N - N // 2 + iu + ou
                    key[va] = cell[va] * N - N // 2 + iv + ov
                    key = tuple(key)
                    if key not in vert_ids:
                        vert_ids[key] = len(verts)
                        verts.append(key)
                    corners.append(vert_ids[key])
                # A wall on the +axis side must face -axis (into the cell).
                quads.append(corners[::-1] if s > 0 else corners)
                quad_info.append((cell, a, s, zone))

base = np.array(verts, dtype=np.float64) * (S / N)
Q = np.array(quads, dtype=np.int64)
pos = base.copy()
print(f"[level] cells={len(cells)} quads={len(Q)} verts={len(pos)}")

edges = np.concatenate([Q[:, [0, 1]], Q[:, [1, 2]], Q[:, [2, 3]], Q[:, [3, 0]]])
edges = np.unique(np.sort(edges, axis=1), axis=0)
degree = np.zeros(len(pos))
np.add.at(degree, edges[:, 0], 1)
np.add.at(degree, edges[:, 1], 1)

rockness = np.zeros(len(pos))
weight = np.zeros(len(pos))
for qi, info in enumerate(quad_info):
    rockness[Q[qi]] += ZONE_ROCK[info[3]]
    weight[Q[qi]] += 1
rockness /= np.maximum(weight, 1)


def neighbour_mean(p):
    total = np.zeros_like(p)
    np.add.at(total, edges[:, 0], p[edges[:, 1]])
    np.add.at(total, edges[:, 1], p[edges[:, 0]])
    return total / degree[:, None]


def vertex_normals(p):
    n = np.zeros_like(p)
    fn = np.cross(p[Q[:, 1]] - p[Q[:, 0]], p[Q[:, 3]] - p[Q[:, 0]])
    for col in range(4):
        np.add.at(n, Q[:, col], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)


# Laplacian rounding: flat areas don't move, so only edges get chamfered.
for it in range(7):
    lam = 0.55 if it < 2 else 0.55 * rockness
    lam = np.asarray(lam)
    lam = lam[:, None] if lam.ndim else lam
    pos += (neighbour_mean(pos) - pos) * lam

n = vertex_normals(pos)
noise = value_noise(pos * 0.085 + 7.3, 3) * 1.25 + value_noise(pos * 0.22 + 2.1, 4) * 0.55 + value_noise(pos * 0.55, 5) * 0.18
pos += n * (noise * rockness * THEME["bump"])[:, None]
pos += (neighbour_mean(pos) - pos) * 0.25 * rockness[:, None]
n = vertex_normals(pos)

# Baked grime: darken concave creases and mottle by large-scale noise.
concavity = np.sum((neighbour_mean(pos) - pos) * n, axis=1)
grime = value_noise(base * 0.06, 9) * 0.5 + 0.5
shade = np.clip(1.0 - np.clip(concavity * 1.15, 0, 0.72), 0.2, 1.0) * (0.72 + 0.34 * grime)
colors = np.stack((shade, shade * (0.985 - 0.02 * rockness), shade * (0.97 - 0.05 * rockness), np.ones_like(shade)), 1)

# ----------------------------------------------------------------------- lava
LAVA_SURFACE = {"rock": 0.6, "metal": 0.2, "core": 0.2}  # metres above the cell's floor plane
LAVA_HEAT = 3.2  # matches scripts/lava.gd: the hazard reaches this far above the surface
QUAD = S / N


def choose_lava_cells():
    """Floor cells that may melt: inside a room (open all round), with open space above.

    So a pool never fills a tunnel, and every pool can be flown over a whole cell up.
    """
    if not LAVA:
        return set()
    spawn = {(i, j, k) for i in range(ROOM_LOW[0] - 1, ROOM_HIGH[0] + 2)
             for j in range(ROOM_LOW[1] - 1, ROOM_HIGH[1] + 2)
             for k in range(ROOM_LOW[2] - 1, ROOM_HIGH[2] + AIRLOCK_CELLS + 2)}
    keep_clear = [tuple(d["cell"]) for d in DOORS]
    item_cells = {tuple(int(round(v / S)) for v in p) for _, p in PICKUPS} | {tuple(int(round(v / S)) for v in p) for p in ASTRONAUTS}
    out = set()
    for cell, zone in cells.items():
        i, j, k = cell
        if zone not in LAVA["zones"] or cell in spawn or cell in item_cells:
            continue
        if (i, j - 1, k) in cells or (i, j + 1, k) not in cells:
            continue
        if any((i + di, j, k + dk) not in cells for di in (-1, 0, 1) for dk in (-1, 0, 1)):
            continue
        if any(abs(d[0] - i) <= 2 and abs(d[2] - k) <= 2 and abs(d[1] - j) <= 1 for d in keep_clear):
            continue
        out.add(cell)
    limit = LAVA.get("max_cells", 10 ** 6)
    if len(out) > limit:
        # Keep whole pools: the cells nearest a few seeded centres.
        r = random.Random(LEVEL_ID)
        seeds = r.sample(sorted(out), max(1, LAVA.get("pools", 3)))
        out = set(sorted(out, key=lambda c_: min(sum((c_[a] - s_[a]) ** 2 for a in range(3)) for s_ in seeds))[:limit])
    return out


def lava_quad(cell, zone, centre):
    """Whether one floor quad of a lava cell is molten. Rock melts in blobs, metal floors in troughs."""
    if zone == "metal":
        return (centre[0] % 20.0) > 5.0 and (centre[0] % 20.0) < 12.6
    v = value_noise(np.array([[centre[0] * 0.045, 0.0, centre[2] * 0.045]]) + 3.1, 17)[0]
    return v > LAVA.get("cover", 0.0) * 2 - 1


lava_cells = choose_lava_cells()
LAVA_QUADS = set()
for qi, (cell, a, s_, zone) in enumerate(quad_info):
    if a == 1 and s_ < 0 and cell in lava_cells:
        if lava_quad(cell, zone, base[Q[qi]].mean(axis=0)):
            LAVA_QUADS.add(qi)
lavaness = np.zeros(len(pos))
LAVA_HAZARD = []
LAVA_CELLS = set()
if LAVA_QUADS:
    on_lava = np.zeros(len(pos))
    for qi in LAVA_QUADS:
        on_lava[Q[qi]] += 1
    interior = (on_lava == weight).astype(np.float64) * (weight > 0)
    lavaness = interior * np.clip(neighbour_mean(interior[:, None])[:, 0] * 1.4 - 0.3, 0, 1)
    surface_y = np.zeros(len(pos))
    for qi in LAVA_QUADS:
        cell, _, _, zone = quad_info[qi]
        surface_y[Q[qi]] = cell[1] * S - S / 2 + LAVA_SURFACE[zone]
    flat = lavaness > 0
    blend = np.clip(lavaness * 2.0, 0, 1)
    pos[flat, 1] = pos[flat, 1] * (1 - blend[flat]) + surface_y[flat] * blend[flat]
    n = vertex_normals(pos)
    colors[:, 3] = lavaness
    for qi in LAVA_QUADS:
        if lavaness[Q[qi]].max() > 0:
            cell, _, _, zone = quad_info[qi]
            c_ = base[Q[qi]].mean(axis=0)
            LAVA_HAZARD.append([int(math.floor(c_[0] / QUAD)), int(math.floor(c_[2] / QUAD)), round(cell[1] * S - S / 2 + LAVA_SURFACE[zone], 2)])
            LAVA_CELLS.add(cell)
print(f"[level] lava cells={len(LAVA_CELLS)} quads={len(LAVA_QUADS)} hazard quads={len(LAVA_HAZARD)}")

# Lookup used to seat rock props on the displaced surface.
surface_at = {key: i for key, i in vert_ids.items()}


def g2b(arr):
    return np.stack((arr[:, 0], -arr[:, 2], arr[:, 1]), 1)


def chunk_key(cell):
    return (cell[0] // CHUNK, cell[1] // CHUNK, cell[2] // CHUNK)


MATS = {"wall_metal": 0.15, "floor_metal": 0.25, ROCK_MAT: 0.085, "wall_core": 0.15, LAVA_MAT: 0.13}


def face_material(axis, sign, zone, qi=None):
    if qi in LAVA_QUADS:
        return LAVA_MAT
    if zone == "rock":
        return ROCK_MAT
    if axis == 1 and sign < 0:  # wall below the cell: a floor
        return "floor_metal"
    return "wall_metal" if zone == "metal" else "wall_core"


def build_shell(root):
    chunks = {}
    for qi, info in enumerate(quad_info):
        chunks.setdefault(chunk_key(info[0]), []).append(qi)
    b_pos = g2b(pos)
    b_n = g2b(n)
    total = 0
    for key, idx in chunks.items():
        idx = np.array(idx)
        used, inverse = np.unique(Q[idx], return_inverse=True)
        faces = inverse.reshape(-1, 4)
        name = "Shell_%d_%d_%d" % key
        me = bpy.data.meshes.new(name)
        me.from_pydata(b_pos[used].tolist(), [], faces.tolist())
        mat_ids = []
        names = []
        for qi in idx:
            _, ax, s, zone = quad_info[qi]
            mn = face_material(ax, s, zone, qi)
            if mn not in names:
                names.append(mn)
                me.materials.append(bpy.data.materials.get(mn) or bpy.data.materials.new(mn))
            mat_ids.append(names.index(mn))
        me.polygons.foreach_set("material_index", mat_ids)
        uv = me.uv_layers.new(name="UVMap")
        uvdata = np.zeros(len(faces) * 8)
        for fi, qi in enumerate(idx):
            _, ax, s, zone = quad_info[qi]
            scale = MATS[face_material(ax, s, zone, qi)]
            ua, va = (ax + 1) % 3, (ax + 2) % 3
            for corner in range(4):
                p = base[Q[qi, corner]]
                uvdata[fi * 8 + corner * 2] = p[ua] * scale
                uvdata[fi * 8 + corner * 2 + 1] = p[va] * scale
        uv.data.foreach_set("uv", uvdata)
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        attr.data.foreach_set("color", colors[used].ravel())
        me.color_attributes.active_color = attr
        me.shade_smooth()
        me.update()
        me.normals_split_custom_set_from_vertices(b_n[used].tolist())
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = root
        total += len(faces) * 2
    print(f"[level] shell chunks={len(chunks)} tris={total}")


# ----------------------------------------------------------------------- detail modules
detail_kits = {}
PLACED = {}
PART_CHUNKS = 2  # wider batches than the shell: more parts per draw, slightly less culling
B2G = G2B.inverted()
LIGHTS = []
ZONE_LIGHT = {"metal": ([1.0, 0.86, 0.68], 8.0), "rock": (list(THEME["lamp"][0]), THEME["lamp"][1]), "core": ([0.45, 0.8, 1.0], 13.0)}
LAVA_FLOORS = {key for key in (tuple(cell) for cell in LAVA_CELLS)}


# About as many ore lights per wall as the old crystal clusters had, however much ore a theme has.
ORE_LIGHT_CHANCE = min(0.3, 0.021 / max(0.01, sum(ch for p_, ch, w_ in THEME["ore"] if p_ != "icicles")))


def ore_part(r, is_floor, is_ceiling):
    """Picks this theme's ore detail for one rock wall, or None."""
    roll = r.random()
    acc = 0.0
    for prefix, chance, where in THEME["ore"]:
        fits = where == "any" or (where == "floor" and is_floor) or (where == "ceiling" and is_ceiling) or (where == "wall" and not (is_floor or is_ceiling))
        if not fits:
            continue
        acc += chance
        if roll < acc:
            return "%s_%d" % (prefix, r.randrange(VARIANTS))
    return None


def kit_for(cell):
    key = chunk_key(cell)
    if key not in detail_kits:
        detail_kits[key] = Kit("Detail_%d_%d_%d" % key, uv_scale=0.4)
    return detail_kits[key]


def frame(center, u, v, nrm):
    """Local X=u, Y=v, Z=into the room, placed at center (Godot coordinates)."""
    m = Matrix((
        (u[0], v[0], nrm[0], center[0]),
        (u[1], v[1], nrm[1], center[1]),
        (u[2], v[2], nrm[2], center[2]),
        (0, 0, 0, 1),
    ))
    return G2B @ m


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def place(cell, part, M):
    """Records one use of a shared wall part, in a chunk so distant ones can be culled."""
    local = B2G @ M
    flat = [round(local[row][col], 3) for row in range(3) for col in range(4)]
    key = tuple(v // PART_CHUNKS for v in chunk_key(cell))
    PLACED.setdefault("%d_%d_%d" % key, {}).setdefault(part, []).extend(flat)


def rib_ring(cell, axis, zone):
    """Structural arch around a one-cell tunnel, at the cell's trailing edge."""
    a = "xyz".index(axis)
    ua, va = (a + 1) % 3, (a + 2) % 3
    u, v, w = [0, 0, 0], [0, 0, 0], [0, 0, 0]
    u[ua], v[va], w[a] = 1, 1, 1
    center = [cell[i] * S for i in range(3)]
    center[a] += -S / 2 + 0.4
    place(cell, "rib_metal" if zone == "metal" else "rib_rock", frame(center, u, v, cross(u, v)))


def door_frame(door):
    cell = tuple(door["cell"])
    k = kit_for(cell)
    a = "xyz".index(door["axis"])
    ua, va = (a + 1) % 3, (a + 2) % 3
    u, v = [0, 0, 0], [0, 0, 0]
    u[ua], v[va] = 1, 1
    M = frame([cell[i] * S for i in range(3)], u, v, cross(u, v))
    for sx in (-1, 1):
        k.cbox((sx * 4.7, 0, 0), (0.8, 10.4, 2.4), "metal_dark", 0.1, M)
        k.cbox((0, sx * 4.7, 0), (10.4, 0.8, 2.4), "metal_dark", 0.1, M)
        k.cbox((sx * 4.26, 0, 0), (0.16, 8.6, 2.0), "hazard", 0.03, M)
        k.cbox((0, sx * 4.26, 0), (8.6, 0.16, 2.0), "hazard", 0.03, M)
        for sz in (-1, 1):
            k.cbox((sx * 4.2, 0, sz * 1.06), (0.1, 7.4, 0.08), DOOR_GLOW[door["lock"]], 0, M)
            k.cbox((0, sx * 4.2, sz * 1.06), (7.4, 0.1, 0.08), DOOR_GLOW[door["lock"]], 0, M)


def dress():
    for cell, zone in cells.items():
        r = random.Random(cell[0] * 73856093 ^ cell[1] * 19349663 ^ cell[2] * 83492791)
        openings = [d for d in DIRS if (cell[0] + d[0], cell[1] + d[1], cell[2] + d[2]) in cells]
        for d in DIRS:
            if d in openings:
                continue
            nrm = (-d[0], -d[1], -d[2])
            ax = [i for i in range(3) if d[i] != 0][0]
            # Long axis for strip-like modules: whichever tangent direction stays open.
            tangents = [i for i in range(3) if i != ax]
            run = tangents[0]
            for t in tangents:
                plus = tuple(1 if i == t else 0 for i in range(3))
                minus = tuple(-p for p in plus)
                if plus in openings and minus in openings:
                    run = t
                    break
            u = [0.0, 0.0, 0.0]
            u[run] = 1.0
            v = cross(nrm, u)
            center = [cell[i] * S + d[i] * (S / 2) for i in range(3)]
            if zone == "rock":
                key = tuple(cell[i] * N + d[i] * N // 2 for i in range(3))
                if key in surface_at:
                    center = pos[surface_at[key]].tolist()
            M = frame(center, u, v, nrm)
            roll = r.random()
            # Larger maps carry fewer greebles per wall, or they would be too heavy to draw.
            detailed = r.random() < DETAIL_DENSITY
            add = (lambda part: place(cell, part, M)) if detailed else (lambda part: None)
            is_floor, is_ceiling = d == (0, -1, 0), d == (0, 1, 0)
            if zone == "rock":
                ore = None if (is_floor and cell in LAVA_FLOORS) else ore_part(r, is_floor, is_ceiling)
                if ore is not None:
                    add(ore)
                    if detailed and not ore.startswith("icicles") and r.random() < ORE_LIGHT_CHANCE:
                        LIGHTS.append({"pos": [center[i] + nrm[i] * 2.5 for i in range(3)], "color": list(THEME["ore_light"]), "energy": 2.5, "range": 14.0})
                elif is_floor and roll < 0.45:
                    add("boulder_%d" % r.randrange(VARIANTS))
                elif is_ceiling and roll < 0.5:
                    add("lamp")
            else:
                if is_floor:
                    if roll < 0.4:
                        add("floor_grate")
                    elif roll < 0.7:
                        add("floor_stripes")
                elif is_ceiling:
                    if roll < 0.55:
                        add("tray")
                else:
                    plates = "plates_%d" % r.randrange(VARIANTS)
                    pipes = "pipes_box" if r.random() < 0.5 else "pipes_plain"
                    table = [(pipes, 0.34), (plates, 0.24), ("vent", 0.12), ("console", 0.08), ("warning", 0.08)]
                    acc = 0.0
                    for part, p in table:
                        acc += p
                        if roll < acc:
                            add(part)
                            break
            # Room lighting: a fixture and a real light on a regular ceiling lattice.
            if is_ceiling and (cell[0] % 3 == 0) and (cell[2] % 3 == 0):
                col, energy = ZONE_LIGHT[zone]
                place(cell, "lightbar" if zone != "rock" else "lamp", M)
                LIGHTS.append({"pos": [center[0], center[1] - 3.0, center[2]], "color": col, "energy": energy, "range": 48.0})
        # Tunnel ribs every cell along straight one-cell runs.
        for axis, (p, m) in zip("xyz", (((1, 0, 0), (-1, 0, 0)), ((0, 1, 0), (0, -1, 0)), ((0, 0, 1), (0, 0, -1)))):
            if p in openings and m in openings and len(openings) == 2 and zone != "core":
                rib_ring(cell, axis, zone)
                if cell["xyz".index(axis)] % 3 == 0:
                    col, energy = ZONE_LIGHT[zone]
                    LIGHTS.append({"pos": [cell[i] * S + (1 if i != "xyz".index(axis) else 0) * (2.0 if i == 1 else 0) for i in range(3)], "color": col, "energy": energy * 0.75, "range": 24.0})
                    other = [i for i in range(3) if i != "xyz".index(axis)]
                    ceil_dir = 1 if 1 in other else other[0]
                    u = [0.0, 0.0, 0.0]
                    u["xyz".index(axis)] = 1.0
                    nrm = [0.0, 0.0, 0.0]
                    nrm[ceil_dir] = -1.0
                    center = [cell[i] * S for i in range(3)]
                    center[ceil_dir] += 5.0
                    place(cell, "lightbar", frame(center, u, cross(nrm, u), nrm))


def extra_setpieces():
    # Light at the end of the escape tunnel, where the cinematic cuts outside.
    k = kit_for(tuple(int(round(v / S)) for v in ESCAPE_END))
    M = frame([ESCAPE_END[0] + 4.8, ESCAPE_END[1], ESCAPE_END[2]], (0, 0, 1), (0, 1, 0), (-1, 0, 0))
    k.cbox((0, 0, 0.1), (9.0, 9.0, 0.2), "glow_white", 0, M)

    # Green emergency frame around the sealed escape door, on the chamber's east wall.
    door_cell = next(d["cell"] for d in DOORS if d["lock"] == "reactor")
    k = kit_for((door_cell[0] - 1, door_cell[1], door_cell[2]))
    M = frame([door_cell[0] * S - S / 2 - 0.2, door_cell[1] * S, door_cell[2] * S], (0, 0, 1), (0, 1, 0), (-1, 0, 0))
    for sx in (-1, 1):
        k.cbox((sx * 6.4, 0, 0.1), (0.5, 13.3, 0.2), "glow_green", 0, M)
        k.cbox((0, sx * 6.4, 0.1), (13.3, 0.5, 0.2), "glow_green", 0, M)
        for i in range(3):
            k.cbox((sx * (8.0 + i * 1.5), 0, 0.1), (0.7, 3.2 - i * 0.7, 0.2), "glow_green", 0, M)
    # Spawn room: docking gantry around the sealed entry door, numbered per level.
    k = kit_for((0, 1, ROOM_HIGH[2]))
    wall_z = (ROOM_HIGH[2] + 0.5) * S
    gantry_z = wall_z - 3.0
    half_width = (max(-ROOM_LOW[0], ROOM_HIGH[0]) + 0.5) * S
    floor_y = (ROOM_LOW[1] - 0.5) * S
    ceiling_y = (ROOM_HIGH[1] + 0.5) * S
    middle_y = (floor_y + ceiling_y) * 0.5
    leg_x = min(14.0, half_width - 3.0)
    for x in (-leg_x, leg_x):
        k.cbox((x, middle_y, gantry_z), (2.4, ceiling_y - floor_y, 2.4), "hull_grey", 0.2, G2B)
        y = floor_y + 4.0
        while y < ceiling_y - 2.0:
            k.cbox((x * 0.72, y, gantry_z), (8, 0.6, 0.6), "metal_dark", 0.04, G2B)
            y += 4.0
    if ceiling_y >= 22.0:
        beam_y = 17.5
        k.cbox((0, beam_y, gantry_z), (leg_x * 2.0 + 2.0, 1.4, 1.4), "hull_grey", 0.14, G2B)
        k.cbox((0, beam_y + 0.76, gantry_z), (leg_x * 2.0 - 2.0, 0.1, 0.6), ROOM_TRIM, 0, G2B)
        sign_at = (0, beam_y + 3.2, wall_z - 0.15)
    else:
        sign_at = (-11.0, 9.0, wall_z - 0.15)
    k.text(f"BAY {ROOM_NUMBER:02d}", G2B @ T(*sign_at) @ RY(180), 3.2, "hazard", 0.05)
    # The door surround takes the room's colour, so each room reads differently at once.
    for sx in (-1, 1):
        k.cbox((sx * 6.2, 10, wall_z - 0.12), (0.5, 11, 0.2), ROOM_TRIM, 0, G2B)
    trim_y = min(ceiling_y - 2.0, 16.4)
    k.cbox((0, trim_y, wall_z - 0.12), (12.9, 0.5, 0.2), ROOM_TRIM, 0, G2B)
    LIGHTS.append({"pos": [0.0, trim_y - 2.0, wall_z - 7.0], "color": list(ROOM_TRIM_LIGHT), "energy": 7.0, "range": 34.0})


reset_scene()
random.seed(2024)
root = empty("Level01")
build_shell(root)
dress()
for p_ in getattr(layout, "TUNNEL_LIGHTS", []):
    # Bends and slopes in routed tunnels: dress() only lights straight runs.
    col, energy = ZONE_LIGHT[cells.get(tuple(int(round(v / S)) for v in p_), "rock")]
    LIGHTS.append({"pos": [p_[0], p_[1] + 1.5, p_[2]], "color": col, "energy": energy * 0.7, "range": 24.0})
for extra in getattr(layout, "EXTRA_LIGHTS", []):
    LIGHTS.append(extra)
    kit_for(tuple(int(round(v / S)) for v in extra["pos"])).sphere(extra["pos"], 0.7, "glow_amber", 5, 8, G2B)
for door in DOORS:
    if door["lock"] != "secret":
        door_frame(door)
for start, end in getattr(layout, "SUPPORTS", []):
    brace = kit_for(tuple(int(round(v / S)) for v in start))
    brace.tube([start, end], 0.9, "metal_dark", 10, G2B)
    brace.tube([[start[i] + (end[i] - start[i]) * 0.48 for i in range(3)], [start[i] + (end[i] - start[i]) * 0.52 for i in range(3)]], 1.15, "hazard", 10, G2B)
    for point in (start, end):
        brace.cbox(point, (4.2, 4.2, 4.2), "hull_grey", 0.4, G2B)
extra_setpieces()
for cell in sorted(LAVA_CELLS):
    # Heat glow: a warm light over every third lava cell each way.
    if cell[0] % 3 == 0 and cell[2] % 3 == 0:
        zone = cells[cell]
        y = cell[1] * S - S / 2 + LAVA_SURFACE[zone] + 3.5
        LIGHTS.append({"pos": [cell[0] * S, y, cell[2] * S], "color": [1.0, 0.42, 0.1], "energy": 3.0, "range": 22.0})
total = 0
for k in detail_kits.values():
    k.build(root, sharp_deg=36.0)
    total += k.tris
placed = sum(len(flat) // 12 for parts in PLACED.values() for flat in parts.values())
print(f"[level] baked detail chunks={len(detail_kits)} tris={total} lights={len(LIGHTS)} instanced parts={placed}")

# ----------------------------------------------------------------------- gameplay data
def seat_on_surface(p, nrm):
    """Moves a wall mount onto the rounded, noise-displaced shell at that spot."""
    wall = [p[i] - nrm[i] * 0.5 for i in range(3)]
    key = tuple(int(round(wall[i] / (S / N))) for i in range(3))
    if key not in surface_at:
        raise ValueError(f"turret at {p} is not on a wall")
    return pos[surface_at[key]].tolist()


def pick_view():
    """A camera spot that shows off the level's theme: over a lava pool, or inside a rock cavern."""
    if LAVA_CELLS:
        pool = sorted(LAVA_CELLS)
        mid = [sum(c_[a] for c_ in pool) / len(pool) for a in range(3)]
        at = min(pool, key=lambda c_: sum((c_[a] - mid[a]) ** 2 for a in range(3)))
        at = [at[0] * S, at[1] * S - S / 2, at[2] * S]
    else:
        # A rock floor cell a few cells from a rock wall, with room behind to stand back in.
        def room(c_):
            return sum((c_[0] + i, c_[1] + j, c_[2] + k) in cells for i in (-2, -1, 0, 1, 2) for j in (-1, 0, 1) for k in (-2, -1, 0, 1, 2))
        best, best_score = None, -1
        for c_, z in cells.items():
            if z != "rock" or (c_[0], c_[1] - 1, c_[2]) in cells or (c_[0], c_[1] + 1, c_[2]) not in cells:
                continue
            for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)):
                run = 0
                while run < 6 and cells.get((c_[0] + d[0] * (run + 1), c_[1], c_[2] + d[2] * (run + 1))) == "rock":
                    run += 1
                if run == 6 or run < 2:
                    continue
                behind = [(c_[0] - d[0] * n, c_[1] + 1, c_[2] - d[2] * n) for n in (1, 2)]
                if not all(cells.get(b_) == "rock" for b_ in behind):
                    continue
                score = room(c_) * 10 - abs(run - 3)
                if score > best_score:
                    best, best_score = (c_, d, run), score
        if best is None:
            # No rock cavern: look down the longest straight rock tunnel instead.
            runs = []
            for c_, z in cells.items():
                for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)):
                    run = 0
                    while run < 8 and cells.get((c_[0] + d[0] * (run + 1), c_[1], c_[2] + d[2] * (run + 1))) == "rock":
                        run += 1
                    if z == "rock":
                        runs.append((run, c_, d))
            if not runs:
                return None
            run, c_, d = max(runs)
            eye = [c_[0] * S, c_[1] * S + 1.5, c_[2] * S]
            at = [(c_[0] + d[0] * run) * S, c_[1] * S - 1.0, (c_[2] + d[2] * run) * S]
            return {"eye": eye, "at": at}
        c_, d, run = best
        at = [(c_[0] + d[0] * (run + 0.3)) * S, c_[1] * S - S * 0.2, (c_[2] + d[2] * (run + 0.3)) * S]
        eye = [(c_[0] - d[0] * 1.6) * S, (c_[1] + 0.7) * S, (c_[2] - d[2] * 1.6) * S]
        return {"eye": eye, "at": at}
    # Back off along the longest open line, a little up, so walls and floor both show.
    cell = tuple(int(round(v / S)) for v in at)
    best_dir, best_run = (0, 0, 1), -1
    for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)):
        run = 0
        while run < 6 and (cell[0] + d[0] * (run + 1), cell[1], cell[2] + d[2] * (run + 1)) in cells:
            run += 1
        if run > best_run:
            best_dir, best_run = d, run
    back = max(1, best_run) * S * 0.85
    up = 1 if (cell[0], cell[1] + 1, cell[2]) in cells else 0
    eye = [at[0] + best_dir[0] * back, at[1] + S * 0.4 + up * S * 0.6, at[2] + best_dir[2] * back]
    return {"eye": eye, "at": at}


data = {
    "cell_size": S,
    "cells": [list(key) for key in cells],
    "start": c(0, 1, 2),
    "lights": LIGHTS,
    "wall_parts": PLACED,
    "robots": [{"type": t, "pos": p} for t, p in ROBOTS],
    "turrets": [{"pos": seat_on_surface(p, n), "normal": n} for p, n in TURRETS],
    "pickups": [{"type": t, "pos": p} for t, p in PICKUPS],
    "doors": DOORS,
    "reactor": REACTOR,
    "reactor_scale": getattr(layout, "REACTOR_SCALE", 2.0),
    "reactor_hp": getattr(layout, "REACTOR_HP", 1100.0),
    "reactor_nova": getattr(layout, "REACTOR_NOVA", True),
    "astronauts": ASTRONAUTS,
    "mines": [dict(m, pos=seat_on_surface(m["pos"], m["normal"]) if m["type"] == "tripwire" else m["pos"]) for m in getattr(layout, "MINES", [])],
    "catch_up": getattr(layout, "CATCH_UP", []),
    "escape_path": ESCAPE_PATH,
    "escape_trigger": ESCAPE_TRIGGER,
    "alarm_spawns": ALARM_SPAWNS,
    "theme": LEVEL_ID,
    "lava": LAVA_HAZARD,
    "lava_cells": [list(cell) for cell in sorted(LAVA_CELLS)],
    "lava_heat": LAVA_HEAT,
    "view": pick_view(),
    "tour": getattr(layout, "TOUR", []),
}
# The .glb is written only once the gameplay data built without error (seat_on_surface
# can raise), so a failed run never leaves a new mesh next to a stale .json.
export(LEVEL_ID + ".glb")
path = os.path.join(ROOT, "assets", "levels", LEVEL_ID + ".json")
with open(path, "w") as f:
    json.dump(data, f)
print("[level] wrote", path)

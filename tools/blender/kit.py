"""Procedural hard-surface modeling kit used by every asset script.

Convention: Blender +Y is the model's nose, +Z is up, +X is right. The glTF
exporter turns that into Godot's -Z forward / +Y up automatically.

Geometry is accumulated as plain vert/face lists per Kit, then turned into one
mesh object with box-projected UVs. Material names are the contract with Godot:
scripts/mats.gd swaps each named material for a real PBR one at runtime.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
IDENT = Matrix.Identity(4)


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def RY(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def RZ(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def SC(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return Matrix.Diagonal((x, y, z, 1.0))


MIRROR_X = SC(-1, 1, 1)


def catmull(keys, count):
    """Resample a list of equal-length tuples through a Catmull-Rom spline."""
    out = []
    n = len(keys)
    if n == 0 or count <= 0:
        return out
    # One key has no curve to follow, and one sample has no spacing to divide by.
    if n == 1 or count == 1:
        return [tuple(keys[0])] * count
    for s in range(count):
        t = s / (count - 1) * (n - 1)
        i = min(int(t), n - 2)
        f = t - i
        p0, p1, p2, p3 = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, n - 1)]
        row = []
        for a, b, c, d in zip(p0, p1, p2, p3):
            row.append(
                0.5 * (2 * b + (c - a) * f + (2 * a - 5 * b + 4 * c - d) * f * f + (3 * b - a - 3 * c + d) * f * f * f)
            )
        out.append(tuple(row))
    return out


class Kit:
    """Accumulates geometry for a single mesh object."""

    def __init__(self, name, uv_scale=0.34):
        self.name = name
        self.uv_scale = uv_scale
        self.verts = []
        self.faces = []
        self.face_mats = []
        self.mats = []

    def _mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    @property
    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def add(self, verts, faces, mat, M=IDENT):
        base = len(self.verts)
        flip = M.determinant() < 0
        idx = self._mat(mat)
        self.verts.extend((M @ Vector(v)).to_tuple() for v in verts)
        seen = set()
        for f in faces:
            f = tuple(i + base for i in f)
            key = frozenset(f)
            if key in seen:
                # A face and its reverse (two-sided fin) must not share verts,
                # or Blender treats them as one duplicated face.
                start = len(self.verts)
                self.verts.extend(self.verts[i] for i in f)
                f = tuple(range(start, start + len(f)))
            seen.add(key)
            self.faces.append(f[::-1] if flip else f)
            self.face_mats.append(idx)
        return base

    # ------------------------------------------------------------------ primitives
    def quad(self, a, b, c, d, mat, M=IDENT):
        self.add([a, b, c, d], [(0, 1, 2, 3)], mat, M)

    def cbox(self, center, size, mat, ch=0.0, M=IDENT):
        """Axis-aligned box with chamfered edges (ch=0 gives a plain box)."""
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        if ch <= 0:
            v = [(sx * hx + cx, sy * hy + cy, sz * hz + cz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
            self.add(v, f, mat, M)
            return
        ch = min(ch, hx * 0.95, hy * 0.95, hz * 0.95)
        v, ids = [], {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    for axis in range(3):
                        px = sx * (hx - (ch if axis != 0 else 0))
                        py = sy * (hy - (ch if axis != 1 else 0))
                        pz = sz * (hz - (ch if axis != 2 else 0))
                        ids[(sx, sy, sz, axis)] = len(v)
                        v.append((px + cx, py + cy, pz + cz))
        g = lambda *k: ids[k]
        f = []
        # Main faces
        for s in (-1, 1):
            q = [g(s, -1, -1, 0), g(s, 1, -1, 0), g(s, 1, 1, 0), g(s, -1, 1, 0)]
            f.append(tuple(q if s > 0 else q[::-1]))
            q = [g(-1, s, -1, 1), g(-1, s, 1, 1), g(1, s, 1, 1), g(1, s, -1, 1)]
            f.append(tuple(q if s > 0 else q[::-1]))
            q = [g(-1, -1, s, 2), g(1, -1, s, 2), g(1, 1, s, 2), g(-1, 1, s, 2)]
            f.append(tuple(q if s > 0 else q[::-1]))
        # Edge chamfers
        for sy in (-1, 1):
            for sz in (-1, 1):
                q = [g(-1, sy, sz, 1), g(-1, sy, sz, 2), g(1, sy, sz, 2), g(1, sy, sz, 1)]
                f.append(tuple(q if sy * sz > 0 else q[::-1]))
        for sx in (-1, 1):
            for sz in (-1, 1):
                q = [g(sx, -1, sz, 0), g(sx, -1, sz, 2), g(sx, 1, sz, 2), g(sx, 1, sz, 0)]
                f.append(tuple(q[::-1] if sx * sz > 0 else q))
        for sx in (-1, 1):
            for sy in (-1, 1):
                q = [g(sx, sy, -1, 0), g(sx, sy, -1, 1), g(sx, sy, 1, 1), g(sx, sy, 1, 0)]
                f.append(tuple(q if sx * sy > 0 else q[::-1]))
        # Corners
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    t = [g(sx, sy, sz, 0), g(sx, sy, sz, 1), g(sx, sy, sz, 2)]
                    f.append(tuple(t if sx * sy * sz > 0 else t[::-1]))
        self.add(v, f, mat, M)

    def loft(self, sections, mat, closed=True, cap0=True, cap1=True, M=IDENT, skip=None):
        """Skin a list of point rings. skip(row, col) can omit individual quads."""
        rows, cols = len(sections), len(sections[0])
        v = [p for sec in sections for p in sec]
        f = []
        col_count = cols if closed else cols - 1
        for r in range(rows - 1):
            for c in range(col_count):
                if skip and skip(r, c):
                    continue
                a = r * cols + c
                b = r * cols + (c + 1) % cols
                d = (r + 1) * cols + c
                e = (r + 1) * cols + (c + 1) % cols
                f.append((a, b, e, d))
        if closed and cap0:
            f.append(tuple(range(cols))[::-1])
        if closed and cap1:
            f.append(tuple((rows - 1) * cols + c for c in range(cols)))
        self.add(v, f, mat, M)

    def lathe(self, profile, segs, mat, M=IDENT, cap0=False, cap1=False, phase=0.0):
        """Revolve [(radius, y), ...] around the +Y axis."""
        rings = []
        for r, y in profile:
            ring = []
            for s in range(segs):
                a = phase + s / segs * math.tau
                # Winding chosen so normals face outward for profiles running toward +Y.
                ring.append((math.sin(a) * r, y, math.cos(a) * r))
            rings.append(ring)
        self.loft(rings, mat, True, cap0, cap1, M)

    def tube(self, pts, radius, mat, segs=8, M=IDENT, spline=0):
        """Sweep a circular section along a polyline, optionally splined."""
        if spline:
            pts = catmull([tuple(p) for p in pts], spline)
        pts = [Vector(p) for p in pts]
        rings = []
        up = Vector((0.13, 0.27, 0.95))
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            side = d.cross(up).normalized()
            up2 = side.cross(d).normalized()
            up = up2
            rings.append(
                [
                    tuple(p + (side * math.cos(s / segs * math.tau) + up2 * math.sin(s / segs * math.tau)) * radius)
                    for s in range(segs)
                ]
            )
        self.loft(rings, mat, True, True, True, M)

    def sphere(self, center, radius, mat, rings=8, segs=12, M=IDENT, squash=1.0):
        prof = []
        for i in range(rings + 1):
            a = i / rings * math.pi
            prof.append((max(math.sin(a), 1e-4) * radius, -math.cos(a) * radius * squash))
        self.lathe(prof, segs, mat, M @ T(*center))

    def grid_plate(self, grid, r0, c0, r1, c1, height, inset, mat, closed=True):
        """Raised armour plate conforming to a lofted grid, with bevelled skirt."""
        cols = len(grid[0])
        rows = []
        for r in range(r0, r1 + 1):
            row = []
            for c in range(c0, c1 + 1):
                row.append(Vector(grid[r][c % cols]))
            rows.append(row)
        rn, cn = len(rows), len(rows[0])
        normals = [[Vector((0, 0, 0)) for _ in range(cn)] for _ in range(rn)]
        for r in range(rn):
            for c in range(cn):
                du = rows[min(r + 1, rn - 1)][c] - rows[max(r - 1, 0)][c]
                dv = rows[r][min(c + 1, cn - 1)] - rows[r][max(c - 1, 0)]
                normals[r][c] = dv.cross(du).normalized()
        centroid = sum((p for row in rows for p in row), Vector((0, 0, 0))) / (rn * cn)
        inner, outer = [], []
        for r in range(rn):
            for c in range(cn):
                p = rows[r][c]
                pull = (centroid - p)
                edge = r in (0, rn - 1) or c in (0, cn - 1)
                base = p + pull.normalized() * (inset if edge else 0) if pull.length > 1e-6 else p
                top = p + pull.normalized() * (inset + height * 1.4 if edge else 0) if pull.length > 1e-6 else p
                outer.append(base + normals[r][c] * 0.002)
                inner.append(top + normals[r][c] * height)
        v = inner + outer
        f = []
        n = rn * cn
        for r in range(rn - 1):
            for c in range(cn - 1):
                a, b, d, e = r * cn + c, r * cn + c + 1, (r + 1) * cn + c, (r + 1) * cn + c + 1
                f.append((a, b, e, d))
        perimeter = (
            [(0, c) for c in range(cn)]
            + [(r, cn - 1) for r in range(1, rn)]
            + [(rn - 1, c) for c in range(cn - 2, -1, -1)]
            + [(r, 0) for r in range(rn - 2, 0, -1)]
        )
        for i, (r, c) in enumerate(perimeter):
            r2, c2 = perimeter[(i + 1) % len(perimeter)]
            a, b = r * cn + c, r2 * cn + c2
            f.append((a + n, b + n, b, a))
        self.add(v, f, mat)

    def stud_row(self, a, b, count, normal, radius, height, mat):
        """A row of small six-sided rivets from a to b, standing along normal."""
        a, b, normal = Vector(a), Vector(b), Vector(normal).normalized()
        rot = normal.to_track_quat("Y", "Z").to_matrix().to_4x4()
        for i in range(count):
            p = a.lerp(b, i / max(count - 1, 1))
            self.lathe([(radius, 0), (radius, height * 0.6), (radius * 0.55, height)], 6, mat, T(*p) @ rot, cap1=True)

    def text(self, body, M, size, mat, depth=0.006):
        """Real geometry stencil text lying in the local XY plane, facing +Z."""
        curve = bpy.data.curves.new("txt", "FONT")
        curve.body = body
        curve.size = size
        curve.extrude = depth
        curve.align_x = "CENTER"
        curve.align_y = "CENTER"
        curve.fill_mode = "BOTH"
        curve.resolution_u = 2
        ob = bpy.data.objects.new("txt", curve)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        self.add([tuple(v.co) for v in me.vertices], [tuple(p.vertices) for p in me.polygons], mat, M)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(curve)
        bpy.data.meshes.remove(me)

    # ------------------------------------------------------------------ output
    def build(self, parent=None, sharp_deg=32.0):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        for name in self.mats:
            mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
            me.materials.append(mat)
        me.polygons.foreach_set("material_index", self.face_mats)
        recalc_normals(me, self.name)
        box_uv(me, self.uv_scale)
        me.shade_smooth()
        if sharp_deg is not None:
            me.set_sharp_from_angle(angle=math.radians(sharp_deg))
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if parent is not None:
            ob.parent = parent
        print(f"[kit] {self.name}: {self.tris} tris, {len(self.mats)} materials")
        return ob


def recalc_normals(me, name):
    """Makes each separate part's faces point the right way.

    Closed parts get outward normals. An open sheet, like a decal or a glow disk,
    has no inside to measure from, so it is only made self-consistent and keeps
    the side it was authored to show.
    """
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    before = {f: f.normal.copy() for f in bm.faces}
    seen = set()
    closed_parts = open_parts = 0
    for start in bm.faces:
        if start in seen:
            continue
        part = []
        stack = [start]
        seen.add(start)
        while stack:
            face = stack.pop()
            part.append(face)
            for edge in face.edges:
                for other in edge.link_faces:
                    if other not in seen:
                        seen.add(other)
                        stack.append(other)
        closed = all(len(edge.link_faces) == 2 for face in part for edge in face.edges)
        bmesh.ops.recalc_face_normals(bm, faces=part)
        bm.normal_update()
        if closed:
            closed_parts += 1
        else:
            open_parts += 1
            if sum(f.normal.dot(before[f]) * f.calc_area() for f in part) < 0.0:
                bmesh.ops.reverse_faces(bm, faces=part)
                bm.normal_update()
    flipped = sum(1 for f in bm.faces if f.normal.dot(before[f]) < 0.0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    print(f"[normals] {name}: {flipped}/{len(me.polygons)} flipped, {closed_parts} closed parts, {open_parts} open")


def box_uv(me, scale):
    """World-scale box projection so the tiling textures stay uniform."""
    uv = me.uv_layers.new(name="UVMap")
    verts = me.vertices
    data = uv.data
    for poly in me.polygons:
        n = poly.normal
        ax = (abs(n.x), abs(n.y), abs(n.z))
        major = ax.index(max(ax))
        for li in poly.loop_indices:
            co = verts[me.loops[li].vertex_index].co
            if major == 0:
                data[li].uv = (co.y * scale, co.z * scale)
            elif major == 1:
                data[li].uv = (co.x * scale, co.z * scale)
            else:
                data[li].uv = (co.x * scale, co.y * scale)


def empty(name, loc=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, None)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    return ob


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(1337)


def export(filename):
    path = os.path.join(MODELS, filename)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=True,
        export_extras=False,
        export_animations=False,
        export_vertex_color="ACTIVE",
    )
    print(f"[kit] exported {path}")


# ---------------------------------------------------------------------- shared greebles
def thruster_quad(k, center, M=IDENT, size=0.13):
    """Reaction-control block: four tiny nozzles on a bevelled housing."""
    M = M @ T(*center)
    k.cbox((0, 0, 0), (size * 2.3, size * 2.3, size * 1.2), "hull_dark", size * 0.2, M)
    for ang, off in ((0, (size, 0, 0)), (180, (-size, 0, 0)), (90, (0, size, 0)), (-90, (0, -size, 0))):
        rot = T(*off) @ RZ(ang - 90)
        k.lathe(
            [(size * 0.2, 0), (size * 0.34, size * 0.45), (size * 0.28, size * 0.42), (size * 0.08, size * 0.05)],
            10,
            "metal_bare",
            M @ rot,
        )


def nozzle(k, M, radius, length, petals=16, glow="glow_engine"):
    """Convergent engine bell along -Y with articulated petals and glowing core."""
    k.lathe(
        [(radius * 1.02, 0), (radius * 1.04, -length * 0.12), (radius * 0.98, -length * 0.16),
         (radius * 0.98, -length * 0.3), (radius * 1.03, -length * 0.34), (radius * 0.96, -length * 0.45)][::-1],
        32, "hull_dark", M,
    )
    for i in range(petals):
        a = i / petals * 360
        rot = M @ RY(a) @ T(0, -length * 0.45, radius * 0.93) @ RX(9)
        w = math.tau * radius * 0.95 / petals * 0.88
        k.cbox((0, -length * 0.3, 0), (w, length * 0.62, radius * 0.06), "metal_burn", radius * 0.012, rot)
        k.cbox((0, -length * 0.16, radius * 0.05), (w * 0.3, length * 0.26, radius * 0.05), "metal_bare", 0.0, rot)
    # Inner liner: profile runs toward -Y, so its normals face the bore.
    k.lathe([(radius * 0.55, -length * 0.15), (radius * 0.72, -length * 0.5), (radius * 0.74, -length)], 32, "metal_dark", M)
    for r, y in ((0.62, 0.2), (0.46, 0.26)):
        k.lathe([(radius * (r - 0.05), -length * y - 0.01), (radius * r, -length * y)], 28, "metal_bare", M)
    return M @ T(0, -length * 0.14, 0)


def glow_disk(k, M, radius, mat="glow_engine", segs=28):
    """Emissive plate with a raised centre spike, facing -Y."""
    k.lathe([(1e-3, -radius * 0.55), (radius * 0.28, -radius * 0.22), (radius * 0.72, -radius * 0.08), (radius, 0)], segs, mat, M)

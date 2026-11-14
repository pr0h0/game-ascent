"""Exports the shared library of wall details as one GLB, one object per part."""
import os
import sys

from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
from kit import Kit, empty, export, reset_scene  # noqa: E402
from wall_modules import PARTS  # noqa: E402
from ore_parts import PARTS as ORE_PARTS  # noqa: E402

PARTS = dict(PARTS, **ORE_PARTS)

# glTF export undoes this, so a part's local axes come out unchanged in Godot.
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

reset_scene()
root = empty("WallParts")
total = 0
for name, build in PARTS.items():
    k = Kit(name, uv_scale=0.4)
    build(k, G2B)
    k.build(root, sharp_deg=36.0)
    total += k.tris
export("wall_parts.glb")
print(f"[parts] {len(PARTS)} parts, {total} tris")

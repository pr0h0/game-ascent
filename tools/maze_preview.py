"""Draws a generated level from above and from the side: python3 tools/maze_preview.py <id> [out.png]

Colour is the zone (keys split zones), brightness is height. Doors are squares in
their key colour, keys are diamonds, the reactor/boss is white, the escape is green.
"""
import importlib
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "blender"))
level_id = sys.argv[1]
layout = importlib.import_module("layout_" + level_id)
import maze  # noqa: E402
from level_api import cells, S  # noqa: E402

mine = maze.LAST
ZONE = [(90, 160, 230), (230, 200, 70), (230, 90, 80), (150, 230, 120), (200, 140, 230)]
KEYC = {"blue": (60, 120, 255), "yellow": (255, 220, 40), "red": (255, 60, 50), "reactor": (60, 255, 90), "secret": (200, 200, 200)}
P = 8
xs, ys, zs = zip(*cells)
x0, x1, y0, y1, z0, z1 = min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)
W = (x1 - x0 + 1) * P
H_top = (z1 - z0 + 1) * P
H_side = (y1 - y0 + 1) * P
img = Image.new("RGB", (W + 20, H_top + H_side + 50), (12, 14, 18))
d = ImageDraw.Draw(img)


def colour(c):
    if mine and c in mine.owner:
        sp = mine.spaces[mine.owner[c]]
        base = ZONE[sp.zone % len(ZONE)] if sp.kind not in ("escape", "secret") else ((80, 200, 90) if sp.kind == "escape" else (170, 170, 170))
        if sp.kind == "tunnel":
            base = tuple(int(v * 0.75) for v in base)
        return base
    return (150, 150, 150)


top = {}
side = {}
for c in cells:
    k = (c[0], c[2])
    if k not in top or c[1] > top[k][1]:
        top[k] = c
    k2 = (c[0], c[1])
    if k2 not in side or c[2] > side[k2][2]:
        side[k2] = c
for (x, z), c in top.items():
    t = 0.35 + 0.65 * (c[1] - y0) / max(1, y1 - y0)
    col = tuple(int(v * t) for v in colour(c))
    d.rectangle([10 + (x - x0) * P, 10 + (z - z0) * P, 10 + (x - x0) * P + P - 1, 10 + (z - z0) * P + P - 1], fill=col)
oy = H_top + 30
for (x, y), c in side.items():
    t = 0.35 + 0.65 * (c[2] - z0) / max(1, z1 - z0)
    col = tuple(int(v * t) for v in colour(c))
    d.rectangle([10 + (x - x0) * P, oy + (y1 - y) * P, 10 + (x - x0) * P + P - 1, oy + (y1 - y) * P + P - 1], fill=col)


def mark(pos, col, shape):
    x, z = pos[0] / S, pos[2] / S
    cx, cy = 10 + (x - x0) * P + P / 2, 10 + (z - z0) * P + P / 2
    r = P * 1.3
    if shape == "sq":
        d.rectangle([cx - r, cy - r, cx + r, cy + r], outline=col, width=2)
    elif shape == "di":
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=col)
    else:
        d.ellipse([cx - r * 1.5, cy - r * 1.5, cx + r * 1.5, cy + r * 1.5], outline=col, width=3)


for door in layout.DOORS:
    mark([v * S for v in door["cell"]], KEYC.get(door["lock"], (255, 255, 255)), "sq")
for kind, p in layout.PICKUPS:
    if kind.startswith("key_"):
        mark(p, KEYC[kind[4:]], "di")
    elif kind.startswith("upgrade"):
        mark(p, (255, 140, 255), "di")
for kind, p in layout.ROBOTS:
    x, z = p[0] / S, p[2] / S
    d.point((10 + (x - x0) * P + P / 2, 10 + (z - z0) * P + P / 2), fill=(255, 40, 40))
boss = [p for k, p in layout.ROBOTS if k in ("overseer", "crucible", "zero")]
mark(layout.REACTOR or boss[0], (255, 255, 255), "o")
mark([0, 10, 20], (255, 255, 255), "sq")
d.text((10, H_top + 12), f"{level_id}: {len(cells)} cells, top view (N up) / side view (looking north)", fill=(220, 220, 220))
out = sys.argv[2] if len(sys.argv) > 2 else f"/tmp/{level_id}.png"
img.save(out)
print("wrote", out, img.size)

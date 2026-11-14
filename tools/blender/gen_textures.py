"""Generates all tileable PBR texture sets with numpy. Run through Blender:
    blender -b --factory-startup --python tools/blender/gen_textures.py
"""
import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
N = 1024
os.makedirs(OUT, exist_ok=True)


def fnoise(n, beta, seed):
    """Tileable fractal noise, 0..1, shaped in frequency space."""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.normal(size=(n, n)))
    fx = np.fft.fftfreq(n) * n
    r = np.sqrt(fx[:, None] ** 2 + fx[None, :] ** 2)
    r[0, 0] = 1
    f *= r ** (-beta / 2)
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    return (out - out.min()) / (out.max() - out.min())


def normal_from(h, strength):
    dc = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dr = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack((-dc, dr, np.ones_like(h)), -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def write_import(path, normal=False):
    """Pre-seed Godot import settings: materials are built at runtime, so its
    automatic 3D-usage detection would otherwise never enable mipmaps.
    An existing .import is left alone: Godot has added its uid and dest_files to it,
    and rewriting it would churn the UIDs. Delete it to change the settings."""
    if os.path.exists(path + ".import"):
        return
    with open(path + ".import", "w") as f:
        f.write(
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
            f"compress/mode=0\ncompress/normal_map={1 if normal else 2}\n"
            "mipmaps/generate=true\ndetect_3d/compress_to=0\n"
        )


def save(name, arr, normal=False):
    arr = np.clip(arr, 0, 1)
    if arr.ndim == 2:
        arr = np.stack((arr, arr, arr), -1)
    h, w = arr.shape[:2]
    rgba = np.dstack((arr, np.ones((h, w)))) if arr.shape[2] == 3 else arr
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.flipud(rgba).astype(np.float32).ravel())
    path = os.path.join(OUT, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    write_import(path, normal)
    print("[tex]", name)


def srgb(rgb):
    return np.array(rgb, dtype=np.float32)


def split_rects(rng, x, y, w, h, min_size, out):
    """Recursive guillotine split; tiles because the root rect is the whole image."""
    can_w, can_h = w > min_size * 2, h > min_size * 2
    if (can_w or can_h) and (rng.random() < 0.86 or max(w, h) > min_size * 5):
        if can_w and (not can_h or w > h * rng.uniform(0.75, 1.25)):
            cut = int(w * rng.uniform(0.3, 0.7))
            split_rects(rng, x, y, cut, h, min_size, out)
            split_rects(rng, x + cut, y, w - cut, h, min_size, out)
        else:
            cut = int(h * rng.uniform(0.3, 0.7))
            split_rects(rng, x, y, w, cut, min_size, out)
            split_rects(rng, x, y + cut, w, h - cut, min_size, out)
    else:
        out.append((x, y, w, h))


def panel_maps(seed, min_size, groove, bolt_r):
    """Returns height, per-panel tint and seam mask for a panelled surface."""
    rng = np.random.default_rng(seed)
    rects = []
    split_rects(rng, 0, 0, N, N, min_size, rects)
    height = np.zeros((N, N), np.float32)
    tint = np.ones((N, N), np.float32)
    seams = np.zeros((N, N), np.float32)
    for x, y, w, h in rects:
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.minimum.reduce((xx, w - 1 - xx, yy, h - 1 - yy)).astype(np.float32)
        profile = np.clip(d / groove, 0, 1)
        bevel = np.clip((d - groove) / (groove * 2.5), 0, 1)
        level = rng.uniform(0.55, 0.95)
        height[y : y + h, x : x + w] = profile * (0.55 + 0.45 * bevel) * level
        tint[y : y + h, x : x + w] = rng.uniform(0.86, 1.08)
        seams[y : y + h, x : x + w] = 1 - profile
        if min(w, h) > bolt_r * 10:
            inset = bolt_r * 3
            spacing = max(int(min(w, h) / 3), bolt_r * 5)
            for bx in list(range(inset, w - inset, spacing)):
                for by in (inset, h - inset - 1):
                    _bolt(height, x + bx, y + by, bolt_r, level)
            for by in list(range(inset, h - inset, spacing)):
                for bx in (inset, w - inset - 1):
                    _bolt(height, x + bx, y + by, bolt_r, level)
    return height, tint, seams


def _bolt(height, cx, cy, r, level):
    for yy in range(-r, r + 1):
        for xx in range(-r, r + 1):
            d = (xx * xx + yy * yy) ** 0.5
            if d <= r:
                height[(cy + yy) % N, (cx + xx) % N] = level + 0.32 * (1 - d / (r + 1))


def scratches(seed, count, length, thick=1):
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N), np.float32)
    for _ in range(count):
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        a = rng.uniform(0, 6.283)
        ln = int(rng.uniform(0.3, 1) * length)
        strength = rng.uniform(0.2, 1)
        for _s in range(ln):
            a += rng.normal(0, 0.012)
            x += np.cos(a)
            y += np.sin(a)
            ix, iy = int(x) % N, int(y) % N
            out[iy, ix] = max(out[iy, ix], strength)
            if thick > 1:
                out[(iy + 1) % N, ix] = max(out[(iy + 1) % N, ix], strength * 0.6)
    return out


# ---------------------------------------------------------------- hull: small aerospace panels
height, tint, seams = panel_maps(11, 165, 1.7, 2)
scr = scratches(5, 900, 90)
grime = fnoise(N, 2.2, 21)
fine = fnoise(N, 1.0, 22)
h2 = height + fine * 0.012 - scr * 0.03
save("hull_n", normal_from(h2, 8.0), normal=True)
base = (tint * (0.8 + 0.2 * grime))[..., None] * srgb((0.88, 0.89, 0.9))
base *= (1 - seams[..., None] * 0.55)
base *= (1 - (np.clip(grime - 0.58, 0, 1) * 1.3)[..., None])
base = base + scr[..., None] * 0.28
save("hull_a", base)
save("hull_r", np.clip(0.4 + grime * 0.3 + seams * 0.3 + scr * 0.3 - fine * 0.1, 0, 1))

# ---------------------------------------------------------------- wall: large mining-station panels
height, tint, seams = panel_maps(31, 270, 4.5, 7)
rng = np.random.default_rng(7)
grime = fnoise(N, 2.4, 41)
fine = fnoise(N, 0.9, 42)
streak = np.real(np.fft.ifft2(np.fft.fft2(fnoise(N, 0.4, 43)) * np.fft.fft2(np.roll(np.pad(np.ones((90, 2)), ((0, N - 90), (0, N - 2))), -45, 0))))
streak = (streak - streak.min()) / (streak.max() - streak.min())
scr = scratches(9, 500, 150, 2)
save("wall_n", normal_from(height * 2.0 + fine * 0.02 - scr * 0.04, 10.0), normal=True)
base = (tint * (0.62 + 0.38 * grime))[..., None] * srgb((0.60, 0.61, 0.60))
rust = np.clip((streak - 0.6) * 4, 0, 1)[..., None] * np.clip(grime * 1.4, 0, 1)[..., None]
base = base * (1 - rust) + rust * srgb((0.34, 0.17, 0.08))
base *= (1 - seams[..., None] * 0.82)
base += scr[..., None] * 0.18
save("wall_a", base)
save("wall_r", np.clip(0.55 + grime * 0.3 + rust[..., 0] * 0.3 + seams * 0.2 - scr * 0.25, 0, 1))

# ---------------------------------------------------------------- floor: raised-lozenge tread plate
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
cell = N / 16
u = (xx % cell) / cell - 0.5
v = (yy % cell) / cell - 0.5
checker = (np.floor(xx / cell) + np.floor(yy / cell)) % 2
ax, ay = np.where(checker > 0, u, v), np.where(checker > 0, v, u)
ca, sa = np.cos(0.6), np.sin(0.6)
lx, ly = (ax * ca - ay * sa), (ax * sa + ay * ca)
loz = np.clip(1 - (np.abs(lx) / 0.42) ** 2 - (np.abs(ly) / 0.11) ** 2, 0, 1) ** 0.5
grime = fnoise(N, 2.2, 61)
scr = scratches(13, 700, 120, 2)
height = loz * 0.8 + fnoise(N, 1.0, 62) * 0.04
save("floor_n", normal_from(height, 6.0), normal=True)
base = (0.28 + 0.2 * grime + loz * 0.12 + scr * 0.22)[..., None] * srgb((0.8, 0.82, 0.86))
save("floor_a", base)
save("floor_r", np.clip(0.75 - loz * 0.3 + grime * 0.2 - scr * 0.3, 0, 1))

# ---------------------------------------------------------------- rock: fractured basalt with mineral veins
a = fnoise(N, 2.3, 71)
ridged = 1 - np.abs(fnoise(N, 2.0, 72) * 2 - 1)
cracks = np.clip((ridged - 0.962) * 28, 0, 1)
blocky = fnoise(N, 2.7, 73)
detail = fnoise(N, 1.1, 74)
height = a * 0.8 + blocky * 0.55 + detail * 0.09 - cracks * 0.18
save("rock_n", normal_from(height, 15.0), normal=True)
c1, c2, c3 = srgb((0.09, 0.09, 0.105)), srgb((0.24, 0.215, 0.20)), srgb((0.43, 0.34, 0.24))
m = np.clip(a * 1.4 - 0.2, 0, 1)[..., None]
base = c1 * (1 - m) + c2 * m
strata = np.clip(np.sin((yy / N * 6.283 * 9) + a * 16) * 0.5 + 0.5, 0, 1)[..., None]
base = base * (1 - strata * 0.35) + c3 * strata * 0.35
base *= (0.74 + detail[..., None] * 0.5)
base *= (1 - cracks[..., None] * 0.8)
save("rock_a", base)
save("rock_r", np.clip(0.82 + detail * 0.2 - cracks * 0.3, 0, 1))
veins = np.clip((1 - np.abs(fnoise(N, 3.0, 75) * 2 - 1) - 0.982) * 60, 0, 1) * np.clip(fnoise(N, 2.6, 76) * 2.2 - 0.75, 0, 1)
save("rock_e", veins[..., None] * srgb((0.1, 0.86, 0.75)))

# ---------------------------------------------------------------- per-level rock themes
def worley(n, count, seed):
    """Tileable cellular noise: distance to the nearest and second-nearest point, and the cell id."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, n, (count, 2))
    yy_, xx_ = np.mgrid[0:n, 0:n].astype(np.float32)
    f1 = np.full((n, n), 1e9, np.float32)
    f2 = np.full((n, n), 1e9, np.float32)
    cell_id = np.zeros((n, n), np.float32)
    ids = rng.random(count)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx_ - px)
        dy = np.abs(yy_ - py)
        d = np.sqrt(np.minimum(dx, n - dx) ** 2 + np.minimum(dy, n - dy) ** 2)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cell_id = np.where(closer, ids[i], cell_id)
        f1 = np.where(closer, d, f1)
    scale = n / np.sqrt(count)
    return f1 / scale, f2 / scale, cell_id


def rock_theme(theme_id, t, seed):
    """One rock texture set (albedo, normal, roughness, ore emission) in the theme's style."""
    style = t["style"]
    c1, c2, c3, vein = srgb(t["c1"]), srgb(t["c2"]), srgb(t["c3"]), srgb(t["vein"])
    a = fnoise(N, 2.3, seed + 1)
    detail = fnoise(N, 1.1, seed + 2)
    blocky = fnoise(N, 2.7, seed + 3)
    warp = fnoise(N, 2.5, seed + 4)
    ridged = 1 - np.abs(fnoise(N, 2.0, seed + 5) * 2 - 1)
    cracks = np.clip((ridged - 0.962) * 28, 0, 1)
    rough = np.full((N, N), t["rough"], np.float32)
    yy = np.mgrid[0:N, 0:N][0].astype(np.float32)
    if style == "strata":
        layer = (yy / N * 14 + warp * 3.0) % 1.0
        ledges = np.clip(layer * 1.25, 0, 1) ** 0.6
        height = ledges * 0.55 + a * 0.5 + detail * 0.1 - cracks * 0.1
        band = np.clip(np.sin((yy / N * 6.283 * 14) + warp * 18.85) * 0.5 + 0.5, 0, 1)
        m = np.clip(a * 1.3 - 0.15, 0, 1)
        base = c1 * (1 - m[..., None]) + c2 * m[..., None]
        base = base * (1 - band[..., None] * 0.45) + c3 * band[..., None] * 0.45
        strength = 18.0
    elif style == "glassy":
        f1, f2, _ = worley(N, 70, seed + 6)
        scallop = np.clip(f1, 0, 1) ** 2
        height = a * 0.35 + scallop * 0.45 + detail * 0.02 - cracks * 0.12
        m = np.clip(a * 1.5 - 0.3, 0, 1)
        base = c1 * (1 - m[..., None]) + c2 * m[..., None]
        sheen = np.clip(1 - f1 * 1.6, 0, 1) ** 3
        base = base + c3 * sheen[..., None] * 0.5
        rough = rough + (1 - scallop) * 0.15 + cracks * 0.3
        strength = 9.0
    elif style == "crystal":
        f1, f2, cid = worley(N, 110, seed + 6)
        edge = np.clip((f2 - f1) * 6.0, 0, 1)
        height = cid * 0.35 + (1 - f1) * 0.35 + edge * 0.25 + detail * 0.04
        m = np.clip(cid * 1.2 - 0.1, 0, 1)
        base = c1 * (1 - m[..., None]) + c2 * m[..., None]
        base = base * (0.55 + 0.45 * edge[..., None]) + c3 * (np.clip(1 - f1 * 2.2, 0, 1) ** 2)[..., None] * 0.4
        rough = rough + (1 - edge) * 0.25 - cid * 0.12
        strength = 11.0
    elif style == "frost":
        speck = fnoise(N, 0.6, seed + 7)
        frost = np.clip((fnoise(N, 2.1, seed + 8) - 0.42) * 4.0, 0, 1)
        height = a * 0.6 + blocky * 0.3 + speck * 0.04 * frost - cracks * 0.12
        m = np.clip(a * 1.4 - 0.2, 0, 1)
        base = c1 * (1 - m[..., None]) + c2 * m[..., None]
        base = base * (1 - frost[..., None] * 0.8) + c3 * (0.6 + speck[..., None] * 0.25) * frost[..., None] * 0.8
        rough = rough - frost * 0.25 + speck * 0.15
        strength = 10.0
    else:  # fractured
        height = a * 0.8 + blocky * 0.55 + detail * 0.09 - cracks * 0.18
        m = np.clip(a * 1.4 - 0.2, 0, 1)
        base = c1 * (1 - m[..., None]) + c2 * m[..., None]
        strata = np.clip(np.sin((yy / N * 6.283 * 9) + a * 16) * 0.5 + 0.5, 0, 1)[..., None]
        base = base * (1 - strata * 0.35) + c3 * strata * 0.35
        strength = 15.0
    base = base * (0.74 + detail[..., None] * 0.5)
    base = base * (1 - cracks[..., None] * 0.7)

    amt = t["vein_amt"]
    mask = np.clip(fnoise(N, 2.6, seed + 9) * 2.2 - (1.1 - amt * 0.35), 0, 1)
    kind = t["veins"]
    if kind == "bands":
        rings = np.sin(fnoise(N, 3.4, seed + 10) * 38.0) * 0.5 + 0.5
        zone = np.clip((fnoise(N, 3.0, seed + 11) - 0.62) * 5.0, 0, 1)
        veins = np.clip((rings - 0.72) * 5.0, 0, 1) * zone
        glow = veins * 0.9
        base = base * (1 - zone[..., None] * 0.7) + c3 * zone[..., None] * (0.35 + rings[..., None] * 0.65)
    elif kind == "cracks":
        f1, f2, _ = worley(N, 60, seed + 12)
        net = np.clip(1 - (f2 - f1) * 18.0, 0, 1) ** 1.5
        hot = np.clip(fnoise(N, 2.6, seed + 18) * 2.6 - 1.15 + amt * 0.3, 0, 1)
        veins = net * hot
        glow = veins
        height = height - net * 0.2
        base = base * (1 - net[..., None] * 0.7)
    elif kind == "flecks":
        speck = fnoise(N, 0.35, seed + 13)
        veins = np.clip((speck - (0.83 - amt * 0.06)) * 9.0, 0, 1) * np.clip(mask * 1.6, 0, 1)
        lines = np.clip((1 - np.abs(fnoise(N, 3.0, seed + 14) * 2 - 1) - 0.985) * 70, 0, 1) * mask
        veins = np.maximum(veins, lines)
        glow = veins
    elif kind == "seams":
        r1 = 1 - np.abs(fnoise(N, 3.0, seed + 15) * 2 - 1)
        r2 = 1 - np.abs(fnoise(N, 2.6, seed + 16) * 2 - 1)
        veins = np.maximum(np.clip((r1 - 0.955) * 26, 0, 1) * np.clip(mask * 1.5, 0, 1), np.clip((r2 - 0.985) * 70, 0, 1) * mask)
        glow = veins
        height = height + np.clip((r1 - 0.94) * 12, 0, 1) * 0.2
    else:  # lines
        veins = np.clip((1 - np.abs(fnoise(N, 3.0, seed + 17) * 2 - 1) - 0.978) * 55, 0, 1) * np.clip(mask * 1.4, 0, 1)
        glow = veins
    base = base * (1 - veins[..., None]) + vein * 0.55 * veins[..., None]
    rough = rough - veins * 0.3
    save("rock_%s_n" % theme_id, normal_from(height, strength), normal=True)
    save("rock_%s_a" % theme_id, base)
    save("rock_%s_r" % theme_id, np.clip(rough + detail * 0.12 - 0.06, 0.05, 1))
    save("rock_%s_e" % theme_id, np.clip(glow, 0, 1)[..., None] * vein)


def lava_noise():
    """Flow noise in R and G, a cooled-crust crack network in B. Tileable."""
    n0 = N
    globals()["N"] = 512
    r = fnoise(512, 2.2, 501)
    g = fnoise(512, 1.7, 502)
    f1, f2, _ = worley(512, 40, 503)
    b = np.clip(1 - (f2 - f1) * 5.0, 0, 1)
    save("lava_noise", np.stack((r, g, b), -1))
    globals()["N"] = n0


# ---------------------------------------------------------------- hazard stripes with wear
s = ((xx + yy) % (N / 2)) < (N / 4)
grime = fnoise(N, 2.0, 81)
wear = np.clip((fnoise(N, 1.5, 82) - 0.62) * 7, 0, 1)[..., None]
base = np.where(s[..., None], srgb((0.86, 0.6, 0.05)), srgb((0.03, 0.03, 0.035))) * (0.65 + 0.35 * grime[..., None])
base = base * (1 - wear) + srgb((0.3, 0.3, 0.3)) * wear
save("hazard_a", base)

# ---------------------------------------------------------------- particle sprites
M = 256
yy, xx = np.mgrid[-1:1:complex(0, M), -1:1:complex(0, M)]
r = np.sqrt(xx**2 + yy**2)
N_saved, N = N, M
puff_noise = fnoise(M, 2.2, 91)
N = N_saved
puff = np.clip(1 - r, 0, 1) ** 1.4 * np.clip(0.4 + puff_noise * 1.3, 0, 1)
save("fx_puff", np.dstack((np.ones((M, M, 3)), puff)))
soft = np.clip(1 - r, 0, 1) ** 2.2
save("fx_glow", np.dstack((np.ones((M, M, 3)), soft)))
streak = np.exp(-(xx / 0.18) ** 2) * np.clip(1 - np.abs(yy), 0, 1) ** 1.5
save("fx_streak", np.dstack((np.ones((M, M, 3)), streak)))
import json  # noqa: E402
import sys  # noqa: E402

sys.path.insert(0, os.path.dirname(__file__))
from themes import THEMES, runtime  # noqa: E402

only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for i, (theme_id, theme) in enumerate(THEMES.items()):
    if not only or theme_id in only or "rock" in only:
        rock_theme(theme_id, theme, 1000 + i * 37)
lava_noise()
with open(os.path.join(OUT, "themes.json"), "w") as f:
    json.dump({k: runtime(k) for k in THEMES}, f, indent=1)
print("[tex] themes.json")
print("[tex] done")

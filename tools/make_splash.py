"""Boot splash (desktop and the web loading screen): the menu's ship on its pad under the
molten ASCENT title. The ship comes from a home-screen screenshot, so re-run this after
the menu changes: python3 tools/make_splash.py [docs/home_screen.png]
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = __file__.rsplit("/tools/", 1)[0]
SRC = sys.argv[1] if len(sys.argv) > 1 else f"{ROOT}/docs/home_screen.png"
OUT = f"{ROOT}/assets/textures/splash.png"
W, H = 1280, 720
BG = (1, 1, 3)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def molten(t):
    """The title shader's gradient: white-hot at the top, cooling to ember at the base."""
    c = mix((1.0, 0.98, 0.88), (1.0, 0.78, 0.31), smooth(0.12, 0.45, t))
    c = mix(c, (0.94, 0.43, 0.08), smooth(0.45, 0.75, t))
    c = mix(c, (0.59, 0.12, 0.04), smooth(0.75, 1.0, t))
    return tuple(int(v * 255) for v in c)


img = Image.new("RGB", (W, H), BG)

# The ship on its glowing pad, cropped from the home screen and faded at the edges.
src = Image.open(SRC).convert("RGB")
sx, sy = src.width / 1600, src.height / 900
ship = src.crop((int(690 * sx), int(300 * sy), int(1600 * sx), int(830 * sy)))
ship = ship.resize((int(ship.width * 760 / ship.width), int(ship.height * 760 / ship.width)), Image.LANCZOS)
fade = Image.new("L", ship.size, 0)
ImageDraw.Draw(fade).rounded_rectangle((40, 20, ship.width - 40, ship.height - 20), 120, fill=255)
fade = fade.filter(ImageFilter.GaussianBlur(40))
img.paste(ship, ((W - ship.width) // 2, 250), fade)

# ASCENT in Black Ops One with the menu's molten gradient and ember drop shadow.
font = ImageFont.truetype(f"{ROOT}/assets/fonts/BlackOpsOne.ttf", 112)
text, spacing = "ASCENT", 12
widths = [font.getlength(c) for c in text]
x = (W - (sum(widths) + spacing * (len(text) - 1))) / 2
mask = Image.new("L", (W, H))
d = ImageDraw.Draw(mask)
for c, w in zip(text, widths):
    d.text((x, 90), c, font=font, fill=255)
    x += w + spacing
top, bottom = mask.getbbox()[1], mask.getbbox()[3]
fill = Image.new("RGB", (W, H))
fd = ImageDraw.Draw(fill)
for y in range(top, bottom + 1):
    fd.line((0, y, W, y), fill=molten((y - top) / max(bottom - top, 1)))
shadow = Image.new("RGB", (W, H), (41, 8, 3))
img.paste(shadow, (0, 5), mask)
img.paste(fill, (0, 0), mask)

img.save(OUT, optimize=True)
print(OUT)

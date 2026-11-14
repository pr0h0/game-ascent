"""Per-level looks: rock palette, ore, wall style, lava and the asteroid outside.

Shared by gen_textures.py (rock texture sets), level.py (shell, ore details, lights,
lava) and gen_space.py (asteroid shapes). gen_textures.py also writes the runtime
half of each theme to assets/textures/themes.json, which scripts/mats.gd reads, so
every colour is defined only here.

Texture keys:
  style    wall surface: fractured | strata | glassy | crystal | frost
  c1 c2 c3 dark, mid and highlight rock colours (sRGB 0..1)
  veins    ore pattern in the emission map: lines | bands | cracks | flecks | seams
  vein     ore colour baked into the emission map
  vein_amt how much of the wall the ore covers (about 0.5 to 1.5)
Runtime keys (themes.json):
  tint, glow, glow_energy, rock_glow (emission map strength), ambient, fog,
  lava_hot, lava_warm, lava_energy
Level keys:
  bump     multiplier on the shell's rock displacement
  ore      wall details, (part prefix, chance per rock wall, where) where is any|floor|ceiling|wall
  ore_light colour of the small lights some ore clusters carry
  lamp     colour and energy of the rock-zone ceiling lamps
  asteroid shape of the asteroid in the escape and the cutscenes
"""

THEMES = {
    # Warm-up shaft: dusty ochre sandstone, pyrite-gold flecks.
    "first_shift": dict(
        style="strata", c1=(0.13, 0.10, 0.075), c2=(0.36, 0.27, 0.17), c3=(0.55, 0.42, 0.26),
        veins="flecks", vein=(1.0, 0.7, 0.22), vein_amt=0.9, rough=0.85,
        tint=(1.0, 0.97, 0.92), glow=(1.0, 0.66, 0.2), glow_energy=3.2, rock_glow=1.6,
        ambient=(0.62, 0.55, 0.48), fog=(0.86, 0.8, 0.72),
        bump=1.0, ore=[("ore_nodules", 0.06, "wall"), ("ore_veins", 0.08, "wall")],
        ore_light=(1.0, 0.66, 0.25), lamp=((1.0, 0.8, 0.6), 11.0), asteroid="lumpy",
    ),
    # Copper country: grey-green host rock with banded malachite.
    "the_vein": dict(
        style="fractured", c1=(0.06, 0.08, 0.07), c2=(0.17, 0.21, 0.18), c3=(0.12, 0.36, 0.26),
        veins="bands", vein=(0.2, 1.0, 0.45), vein_amt=1.25, rough=0.8,
        tint=(0.92, 1.0, 0.95), glow=(0.22, 1.0, 0.5), glow_energy=3.4, rock_glow=1.9,
        ambient=(0.42, 0.58, 0.5), fog=(0.7, 0.86, 0.78),
        bump=1.05, ore=[("ore_nodules", 0.09, "any"), ("ore_veins", 0.1, "wall")],
        ore_light=(0.3, 1.0, 0.5), lamp=((0.92, 0.95, 0.75), 11.0), asteroid="elongated",
    ),
    # Glassy black obsidian, split by magma cracks. Lava pools at the bottom.
    "black_shaft": dict(
        style="glassy", c1=(0.025, 0.022, 0.03), c2=(0.075, 0.065, 0.08), c3=(0.2, 0.17, 0.2),
        veins="cracks", vein=(1.0, 0.36, 0.06), vein_amt=1.0, rough=0.35,
        tint=(1.0, 1.0, 1.0), glow=(1.0, 0.38, 0.08), glow_energy=4.0, rock_glow=2.4,
        ambient=(0.55, 0.42, 0.42), fog=(0.9, 0.62, 0.5),
        lava_hot=(1.0, 0.62, 0.16), lava_warm=(0.85, 0.12, 0.02), lava_energy=3.2,
        bump=1.15, ore=[("ore_shards", 0.04, "wall"), ("ore_veins", 0.1, "any")],
        ore_light=(1.0, 0.4, 0.12), lamp=((1.0, 0.74, 0.55), 10.0), asteroid="cratered",
    ),
    # Iron foundry: rust-red hematite with hot orange seams, molten channels.
    "smelter_row": dict(
        style="strata", c1=(0.1, 0.035, 0.025), c2=(0.3, 0.11, 0.06), c3=(0.5, 0.24, 0.12),
        veins="lines", vein=(1.0, 0.5, 0.1), vein_amt=1.2, rough=0.8,
        tint=(1.0, 0.95, 0.92), glow=(1.0, 0.5, 0.12), glow_energy=4.0, rock_glow=2.0,
        ambient=(0.62, 0.45, 0.38), fog=(0.95, 0.66, 0.48),
        lava_hot=(1.0, 0.78, 0.3), lava_warm=(1.0, 0.25, 0.03), lava_energy=3.6,
        bump=1.0, ore=[("ore_nodules", 0.05, "wall"), ("ore_veins", 0.12, "wall")],
        ore_light=(1.0, 0.5, 0.15), lamp=((1.0, 0.72, 0.5), 11.0), asteroid="blocky",
    ),
    # Worked-out ice caverns: frost-crusted blue-grey rock, icicles, pale cyan ice.
    "hollow_reach": dict(
        style="frost", c1=(0.16, 0.2, 0.25), c2=(0.42, 0.5, 0.58), c3=(0.78, 0.86, 0.92),
        veins="seams", vein=(0.45, 0.85, 1.0), vein_amt=0.8, rough=0.55,
        tint=(0.95, 0.98, 1.0), glow=(0.5, 0.88, 1.0), glow_energy=2.2, rock_glow=1.4,
        ambient=(0.5, 0.6, 0.75), fog=(0.78, 0.88, 1.0),
        bump=0.8, ore=[("icicles", 0.45, "ceiling"), ("ore_shards", 0.05, "floor"), ("ore_shards", 0.03, "wall")],
        ore_light=(0.5, 0.85, 1.0), lamp=((0.8, 0.9, 1.0), 11.0), asteroid="twin",
    ),
    # Drill galleries in sulphur beds: brown rock crusted with yellow sulphur.
    "deep_cut": dict(
        style="strata", c1=(0.1, 0.085, 0.04), c2=(0.27, 0.23, 0.11), c3=(0.5, 0.44, 0.16),
        veins="flecks", vein=(1.0, 0.9, 0.12), vein_amt=1.4, rough=0.9,
        tint=(1.0, 1.0, 0.9), glow=(1.0, 0.88, 0.15), glow_energy=2.8, rock_glow=1.8,
        ambient=(0.6, 0.58, 0.42), fog=(0.9, 0.88, 0.62),
        bump=1.1, ore=[("ore_nodules", 0.1, "any"), ("ore_veins", 0.06, "wall")],
        ore_light=(1.0, 0.86, 0.25), lamp=((1.0, 0.92, 0.7), 11.0), asteroid="spindle",
    ),
    # The Overseer's den: crimson cinnabar shot through with red veins.
    "overseer_pit": dict(
        style="fractured", c1=(0.07, 0.02, 0.025), c2=(0.22, 0.06, 0.06), c3=(0.42, 0.13, 0.11),
        veins="lines", vein=(1.0, 0.1, 0.12), vein_amt=1.0, rough=0.75,
        tint=(1.0, 0.95, 0.95), glow=(1.0, 0.12, 0.1), glow_energy=4.0, rock_glow=2.0,
        ambient=(0.6, 0.42, 0.45), fog=(0.9, 0.6, 0.6),
        bump=1.1, ore=[("ore_shards", 0.05, "wall"), ("ore_veins", 0.1, "any")],
        ore_light=(1.0, 0.15, 0.12), lamp=((1.0, 0.7, 0.62), 11.0), asteroid="pit",
    ),
    # Below the charts: dark slate split by glowing blue crystal seams.
    "glass_seam": dict(
        style="crystal", c1=(0.035, 0.045, 0.07), c2=(0.1, 0.12, 0.17), c3=(0.22, 0.26, 0.36),
        veins="seams", vein=(0.2, 0.6, 1.0), vein_amt=1.3, rough=0.5,
        tint=(0.95, 0.97, 1.0), glow=(0.25, 0.62, 1.0), glow_energy=4.2, rock_glow=2.4,
        ambient=(0.42, 0.5, 0.72), fog=(0.62, 0.74, 1.0),
        bump=1.0, ore=[("ore_shards", 0.12, "any"), ("crystals", 0.05, "any")],
        ore_light=(0.3, 0.6, 1.0), lamp=((0.82, 0.88, 1.0), 11.0), asteroid="crystalline",
    ),
    # Sector 9: violet-grey rock with amethyst geodes, the last light of the mine.
    "last_light": dict(
        style="crystal", c1=(0.06, 0.045, 0.075), c2=(0.18, 0.14, 0.22), c3=(0.36, 0.28, 0.42),
        veins="lines", vein=(0.75, 0.3, 1.0), vein_amt=0.9, rough=0.65,
        tint=(1.0, 0.97, 1.0), glow=(0.75, 0.3, 1.0), glow_energy=3.6, rock_glow=2.0,
        ambient=(0.55, 0.48, 0.68), fog=(0.82, 0.72, 0.95),
        bump=1.0, ore=[("ore_shards", 0.07, "any"), ("ore_nodules", 0.04, "wall"), ("ore_veins", 0.05, "wall")],
        ore_light=(0.72, 0.35, 1.0), lamp=((0.92, 0.86, 1.0), 11.0), asteroid="disc",
    ),
    # The heart: black basalt, white-hot fissures and open magma.
    "core_zero": dict(
        style="fractured", c1=(0.03, 0.028, 0.03), c2=(0.1, 0.09, 0.09), c3=(0.22, 0.2, 0.19),
        veins="cracks", vein=(1.0, 0.62, 0.2), vein_amt=1.3, rough=0.7,
        tint=(1.0, 1.0, 1.0), glow=(1.0, 0.7, 0.3), glow_energy=4.5, rock_glow=2.6,
        ambient=(0.58, 0.48, 0.44), fog=(0.95, 0.72, 0.55),
        lava_hot=(1.0, 0.92, 0.6), lava_warm=(1.0, 0.36, 0.05), lava_energy=4.0,
        bump=1.15, ore=[("ore_shards", 0.04, "wall"), ("ore_veins", 0.12, "any")],
        ore_light=(1.0, 0.6, 0.25), lamp=((1.0, 0.78, 0.6), 11.0), asteroid="fractured",
    ),
}

DEFAULT_LAVA = dict(lava_hot=(1.0, 0.7, 0.2), lava_warm=(1.0, 0.25, 0.03), lava_energy=3.4)

# Keys copied into themes.json for the game to read.
RUNTIME_KEYS = ("tint", "glow", "glow_energy", "rock_glow", "ambient", "fog", "lava_hot", "lava_warm", "lava_energy", "rough")


def runtime(theme_id):
    t = dict(DEFAULT_LAVA, **THEMES[theme_id])
    return {k: list(t[k]) if isinstance(t[k], tuple) else t[k] for k in RUNTIME_KEYS}

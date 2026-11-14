extends Node
## Gives each mine its own light: the ambient fill, the colour and thickness of the
## haze, how hard bright things bloom, and, in the run-down mines, lamps that flicker.
## It only adjusts the level's Environment and lamps after the level has built them,
## so level geometry, materials and themes stay with level.gd.

## ambient: fill colour, ambient: multiplier on the level's ambient energy,
## fog: haze tint, density: multiplier on fog density, glow: bloom intensity,
## haze: faint light the fog gives off itself, flicker: share of lamps that stutter,
## sat/contrast: a light colour grade.
const MOODS := {
	"First Shift": {"ambient": Color(0.45, 0.52, 0.66), "energy": 1.0, "fog": Color(0.82, 0.84, 0.88), "density": 1.0, "glow": 0.62, "haze": Color(0, 0, 0), "flicker": 0.0, "sat": 1.0, "contrast": 1.0},
	"The Vein": {"ambient": Color(0.62, 0.5, 0.38), "energy": 1.05, "fog": Color(0.9, 0.78, 0.62), "density": 1.1, "glow": 0.66, "haze": Color(0.012, 0.007, 0.002), "flicker": 0.05, "sat": 1.05, "contrast": 1.03},
	"Black Shaft": {"ambient": Color(0.3, 0.38, 0.6), "energy": 0.7, "fog": Color(0.55, 0.62, 0.8), "density": 1.45, "glow": 0.7, "haze": Color(0.0, 0.002, 0.008), "flicker": 0.14, "sat": 0.9, "contrast": 1.08},
	"Smelter Row": {"ambient": Color(0.75, 0.45, 0.28), "energy": 1.15, "fog": Color(1.0, 0.7, 0.45), "density": 1.25, "glow": 0.8, "haze": Color(0.022, 0.008, 0.001), "flicker": 0.04, "sat": 1.1, "contrast": 1.04},
	"Hollow Reach": {"ambient": Color(0.38, 0.58, 0.55), "energy": 0.9, "fog": Color(0.66, 0.86, 0.8), "density": 1.6, "glow": 0.64, "haze": Color(0.002, 0.008, 0.006), "flicker": 0.06, "sat": 0.95, "contrast": 1.0},
	"Deep Cut": {"ambient": Color(0.6, 0.42, 0.36), "energy": 0.85, "fog": Color(0.85, 0.66, 0.55), "density": 1.35, "glow": 0.66, "haze": Color(0.01, 0.004, 0.002), "flicker": 0.12, "sat": 0.95, "contrast": 1.06},
	"The Overseer's Pit": {"ambient": Color(0.62, 0.32, 0.4), "energy": 0.9, "fog": Color(0.85, 0.5, 0.58), "density": 1.3, "glow": 0.82, "haze": Color(0.016, 0.002, 0.005), "flicker": 0.08, "sat": 1.08, "contrast": 1.08},
	"Glass Seam": {"ambient": Color(0.45, 0.6, 0.8), "energy": 1.15, "fog": Color(0.72, 0.86, 1.0), "density": 0.9, "glow": 0.9, "haze": Color(0.004, 0.01, 0.018), "flicker": 0.0, "sat": 1.12, "contrast": 1.02},
	"Last Light": {"ambient": Color(0.36, 0.4, 0.55), "energy": 0.6, "fog": Color(0.6, 0.64, 0.75), "density": 1.2, "glow": 0.72, "haze": Color(0.0, 0.001, 0.004), "flicker": 0.22, "sat": 0.85, "contrast": 1.1},
	"Core Zero": {"ambient": Color(0.55, 0.4, 0.7), "energy": 1.0, "fog": Color(0.78, 0.62, 0.95), "density": 1.15, "glow": 0.95, "haze": Color(0.01, 0.004, 0.02), "flicker": 0.08, "sat": 1.12, "contrast": 1.06},
}
## Only lamps this close to the ship flicker; the rest can't be seen anyway.
const FLICKER_RANGE := 140.0
const FLICKER_STEP := 0.05

var _level_id := 0
var _flickers: Array = []
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	var level: Variant = Game.level
	if not is_instance_valid(level):
		_level_id = 0
		_flickers.clear()
		return
	if level.get_instance_id() != _level_id:
		if not (level.get("_env") is Environment):
			return
		_level_id = level.get_instance_id()
		_apply(level)
	_tick -= delta
	if _tick <= 0.0 and not _flickers.is_empty():
		_tick = FLICKER_STEP
		_flicker()


static func mood_for(level_name: String) -> Dictionary:
	return MOODS.get(level_name, MOODS["First Shift"])


func _apply(level: Node3D) -> void:
	var mood := mood_for(str(Game.current_level().get("name", "")))
	var env: Environment = level.get("_env")
	# Multipliers below must only ever be applied once per level.
	if not env.has_meta("mood"):
		env.set_meta("mood", true)
		# Blended rather than replaced, so a level theme's own fill still shows through.
		env.ambient_light_color = env.ambient_light_color.lerp(mood["ambient"], 0.75)
		env.ambient_light_energy *= float(mood["energy"])
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(mood["fog"], 0.75)
		env.volumetric_fog_density *= float(mood["density"])
		env.volumetric_fog_emission = mood["haze"]
		env.glow_intensity = mood["glow"]
		env.adjustment_enabled = true
		env.adjustment_saturation = mood["sat"]
		env.adjustment_contrast = mood["contrast"]
	_flickers.clear()
	var share: float = mood["flicker"]
	var lights: Array = level.get("lights") if level.get("lights") is Array else []
	_rng.seed = hash(str(Game.current_level().get("name", "")))
	var bases: Variant = level.get("_light_base")
	for i in lights.size():
		var light: OmniLight3D = lights[i]
		if _rng.randf() < share:
			var base: float = float(bases[i]) if bases is Array and i < bases.size() else light.light_energy
			_flickers.append({"light": light, "base": base, "phase": _rng.randf() * 100.0, "rate": _rng.randf_range(0.6, 1.6)})


## Failing lamps: mostly steady, with stutters and brief drop-outs.
func _flicker() -> void:
	# The escape alarm takes over every lamp; leave them to it.
	if Game.reactor_down or not is_instance_valid(Game.player) or not Game.player.is_inside_tree():
		return
	var here: Vector3 = Game.player.global_position
	var t := Time.get_ticks_msec() / 1000.0
	for f: Dictionary in _flickers:
		var light: OmniLight3D = f["light"]
		if not is_instance_valid(light) or light.global_position.distance_squared_to(here) > FLICKER_RANGE * FLICKER_RANGE:
			continue
		var x: float = t * float(f["rate"]) + float(f["phase"])
		var stutter := sin(x * 1.7) * sin(x * 4.3 + 1.0) * sin(x * 0.61 + 2.0)
		var level := 1.0
		if stutter > 0.25:
			level = 0.25 if _rng.randf() < 0.5 else 0.85
		elif stutter > 0.18:
			level = 0.6
		light.light_energy = float(f["base"]) * level

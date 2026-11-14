extends Node
## Player preferences, kept in one config file and applied on change.

const SECTION := "settings"
const BUSES := ["Effects", "Interface", "Ambience", "Music", "Voice"]
const KEYS := ["mouse_sensitivity", "invert_y", "fov", "fullscreen", "vsync", "quality", "master_volume", "effects_volume", "ambience_volume", "music_volume", "voice_volume", "story_subtitles", "unlock_all", "show_story", "show_fps", "render_scale", "screen_shake", "cave_reverb"]

enum Quality { LOW, MEDIUM, HIGH }

signal settings_changed

var path := "user://settings.cfg"
var mouse_sensitivity := 1.0
var invert_y := false
var fov := 80.0
var fullscreen := false
var vsync := true
var quality: int = Quality.HIGH
var master_volume := 1.0
var effects_volume := 1.0
var ambience_volume := 1.0
var music_volume := 0.75
var voice_volume := 1.0
## Spoken story lines are shown as text only if this is on.
var story_subtitles := true
var show_fps := false
var show_story := true
## Fraction of the window resolution the 3D scene renders at.
var render_scale := 1.0
var unlock_all := false
## 0 turns camera shake from blasts and hits off entirely, 1 is full strength.
var screen_shake := 1.0
## How strongly big caverns echo; 0 keeps every room dry.
var cave_reverb := 1.0


func _enter_tree() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_add_bus_effects()
	quality = default_quality()
	load_settings()
	apply.call_deferred()
	# Per-mine lighting is a display setting too; it watches for each level to load.
	add_child(preload("res://scripts/level_mood.gd").new())
	# Draw distances, lamp fades and depth fog follow the graphics quality (after the mood).
	add_child(preload("res://scripts/quality_tuner.gd").new())


## Caves ring a little, explosions push the music back, and nothing ever clips.
func _add_bus_effects() -> void:
	var fx_bus := AudioServer.get_bus_index("Effects")
	if AudioServer.get_bus_effect_count(fx_bus) == 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.55
		room.damping = 0.6
		room.wet = 0.14
		room.dry = 1.0
		room.predelay_msec = 30.0
		AudioServer.add_bus_effect(fx_bus, room)
	var music_bus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music_bus) == 0:
		var duck := AudioEffectCompressor.new()
		duck.threshold = -22.0
		duck.ratio = 3.0
		duck.attack_us = 3000.0
		duck.release_ms = 320.0
		duck.sidechain = &"Effects"
		AudioServer.add_bus_effect(music_bus, duck)
	if AudioServer.get_bus_effect_count(music_bus) == 1:
		var under_voice := AudioEffectCompressor.new()
		under_voice.threshold = -30.0
		under_voice.ratio = 4.0
		under_voice.attack_us = 8000.0
		under_voice.release_ms = 450.0
		under_voice.sidechain = &"Voice"
		AudioServer.add_bus_effect(music_bus, under_voice)
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())


## Volume in decibels for a 0-1 setting, silent at zero.
func bus_db(key: String) -> float:
	return linear_to_db(maxf(float(get(key)), 0.001))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key in KEYS:
		set(key, cfg.get_value(SECTION, key, get(key)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value(SECTION, key, get(key))
	cfg.save(path)


func change(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()
	settings_changed.emit()


## A value that is still being dragged: volumes are heard at once, everything
## else (window, viewport, the disk write, settings_changed) waits for change().
func preview(key: String, value: Variant) -> void:
	set(key, value)
	if key.ends_with("_volume"):
		_apply_volumes()


## The Compatibility renderer (the web build, old GPUs) has neither of these.
static func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Graphics quality for a first run, before the player has picked one: LOW in the browser
## and on software or older integrated GPUs, MEDIUM on other integrated GPUs, HIGH otherwise.
## Tests and Movie Maker recordings keep HIGH so screenshots stay comparable;
## ASCENT_QUALITY=0/1/2 overrides the guess.
func default_quality() -> int:
	var forced := OS.get_environment("ASCENT_QUALITY")
	if forced.is_valid_int():
		return clampi(forced.to_int(), Quality.LOW, Quality.HIGH)
	var args := " ".join(OS.get_cmdline_args())
	if DisplayServer.get_name() == "headless" or args.contains("res://tests/") or args.contains("--write-movie"):
		return Quality.HIGH
	return guess_quality(OS.has_feature("web"), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_type(), is_compatibility())


static func guess_quality(web: bool, adapter: String, device_type: int, compatibility: bool) -> int:
	var name := adapter.to_lower()
	if web or compatibility or device_type == RenderingDevice.DEVICE_TYPE_CPU:
		return Quality.LOW
	for soft in ["llvmpipe", "lavapipe", "softpipe", "swiftshader", "microsoft basic"]:
		if name.contains(soft):
			return Quality.LOW
	if device_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return Quality.HIGH
	# Intel HD/UHD (and other unnamed Intel parts) are the weakest common GPUs; Iris Xe, Arc
	# integrated and recent AMD APUs manage MEDIUM.
	if name.contains("intel") and not (name.contains("iris") or name.contains("arc")):
		return Quality.LOW
	if device_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or name.contains("intel") or name.contains("radeon(tm) graphics") or name.contains("vega") or name.contains("adreno") or name.contains("mali"):
		return Quality.MEDIUM
	return Quality.HIGH


func uses_volumetric_fog() -> bool:
	return quality == Quality.HIGH and not is_compatibility()


func uses_ssao() -> bool:
	return quality != Quality.LOW and not is_compatibility()


func uses_shadows() -> bool:
	return quality != Quality.LOW


func apply() -> void:
	_apply_volumes()
	_apply_quality()
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_volumes() -> void:
	_set_volume("Master", master_volume)
	_set_volume("Effects", effects_volume)
	_set_volume("Interface", effects_volume)
	_set_volume("Ambience", ambience_volume)
	_set_volume("Music", music_volume)
	_set_volume("Voice", voice_volume)


## What the graphics quality changes on the main view; quality_tuner.gd handles the mine itself.
func _apply_quality() -> void:
	var vp := get_viewport()
	var q := clampi(quality, Quality.LOW, Quality.HIGH)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X][q]
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X][q]
	# Higher thresholds switch to the simpler mesh LODs sooner.
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0][q]
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][q]
	# FSR needs the Forward+ renderer; the web build scales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 and not is_compatibility() else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	if is_compatibility():
		return
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if q == Quality.HIGH else RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, true, 0.5, 2 if q == Quality.HIGH else 1, 50.0, 300.0)
	RenderingServer.environment_glow_set_use_bicubic_upscale(q == Quality.HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW][q])


func _set_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))

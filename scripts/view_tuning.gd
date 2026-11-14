class_name ViewTuning
extends Resource
## Where the cockpit and rear cameras sit and how the cabin moves.
## Edited live in tools/cockpit_tuner.tscn; the game reads the saved file.

static var path := "res://assets/view_tuning.tres"
static var _current: ViewTuning

@export_group("Cockpit camera")
@export var cockpit_eye := Vector3(0.0, 0.1, -0.3)
@export_range(-30.0, 30.0, 0.1) var cockpit_pitch := 0.0
## Added to the player's field-of-view setting.
@export_range(-30.0, 30.0, 0.5) var cockpit_fov_offset := 0.0
@export_range(0.02, 0.5, 0.01) var camera_near := 0.06
@export_range(0.0, 0.5, 0.01) var cockpit_shake := 0.1

@export_group("Cabin model")
@export var cabin_offset := Vector3(0.0, 0.1, -0.3)
@export var cabin_rotation := Vector3.ZERO
@export_range(0.5, 1.5, 0.01) var cabin_scale := 1.0

@export_group("Cabin motion")
@export_range(0.0, 0.01, 0.0001) var sway_velocity := 0.0016
@export_range(0.0, 1.0, 0.01) var sway_tilt := 0.35
@export_range(1.0, 30.0, 0.5) var sway_response := 8.0

@export_group("Left screen (stats)")
@export var screen_left_offset := Vector3.ZERO
@export var screen_left_rotation := Vector3.ZERO
@export_range(0.3, 2.0, 0.01) var screen_left_scale := 1.0
@export_range(0.2, 2.0, 0.01) var screen_left_brightness := 1.0

@export_group("Right screen (radar)")
@export var screen_right_offset := Vector3.ZERO
@export var screen_right_rotation := Vector3.ZERO
@export_range(0.3, 2.0, 0.01) var screen_right_scale := 1.0
@export_range(0.2, 2.0, 0.01) var screen_right_brightness := 1.0

@export_group("Rear view")
@export var rear_eye := Vector3(0.0, 1.4, 0.1)
@export_range(-45.0, 45.0, 0.1) var rear_pitch := -6.875
@export_range(-30.0, 30.0, 0.1) var rear_yaw := 0.0
## Added to the player's field-of-view setting.
@export_range(-30.0, 30.0, 0.5) var rear_fov_offset := 0.0
@export var rear_show_ship := true


## The one shared copy, so the tuner's edits reach the ship immediately.
static func current() -> ViewTuning:
	if _current == null:
		_current = _read_file()
	return _current


static func _read_file() -> ViewTuning:
	if ResourceLoader.exists(path):
		var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ViewTuning
		if saved != null:
			return saved
	return ViewTuning.new()


func values() -> Dictionary:
	var out := {}
	for p: Dictionary in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
			out[p["name"]] = get(p["name"])
	return out


func apply_values(from: Dictionary) -> void:
	for key: String in from:
		set(key, from[key])


func save_file() -> Error:
	return ResourceSaver.save(self, path)


func reload_file() -> void:
	apply_values(_read_file().values())


func reset_to_defaults() -> void:
	apply_values(ViewTuning.new().values())

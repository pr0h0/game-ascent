extends Node
## Renders the cockpit with several screen layouts, without saving anything.
## godot --path . --resolution 1920x1080 res://tests/cockpit_variants.tscn -- <dir>

## Height of a screen's bottom edge below its mount, at size 1.
const BOTTOM_EDGE := 0.19
const VARIANTS := [
	{"name": "1_center", "x": 0.78, "depth": -0.98, "tilt": 18.0, "turn": 16.0, "size": 0.9},
	{"name": "2_balanced", "x": 0.95, "depth": -0.97, "tilt": 20.0, "turn": 22.0, "size": 0.92},
	{"name": "3_upright", "x": 1.0, "depth": -1.0, "tilt": 8.0, "turn": 20.0, "size": 0.85},
	{"name": "4_laid_back", "x": 0.92, "depth": -0.95, "tilt": 35.0, "turn": 20.0, "size": 1.0},
]
## Long enough for the start card to fade and the fog to settle.
const SETTLE_FRAMES := 40


var t: Node
var p: Player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(dir)
	t = load("res://tools/cockpit_tuner.tscn").instantiate()
	add_child(t)
	await t.tuner_ready
	p = Game.player
	t._panel.visible = false
	Settings.show_fps = false
	await _frames(SETTLE_FRAMES)
	await _save(dir, "current")
	for v: Dictionary in VARIANTS:
		_apply(v)
		await _frames(SETTLE_FRAMES)
		await _save(dir, v["name"])
	get_tree().paused = false
	get_tree().quit()


func _apply(v: Dictionary) -> void:
	var left := _solve(-1.0, 0, v)
	var right := _solve(1.0, 1, v)
	var view: ViewTuning = t.tuning
	view.screen_left_offset = left["offset"]
	view.screen_left_rotation = left["rotation"]
	view.screen_left_scale = v["size"]
	view.screen_right_offset = right["offset"]
	view.screen_right_rotation = right["rotation"]
	view.screen_right_scale = v["size"]
	p.apply_view_tuning()
	print("VARIANT ", v["name"], " left ", left, " right ", right)


## Finds the tuner values that sit this screen's bottom edge on the dash.
func _solve(side: float, index: int, v: Dictionary) -> Dictionary:
	var basis := Basis(Vector3.UP, -side * deg_to_rad(v["turn"])) * Basis(Vector3.RIGHT, -deg_to_rad(v["tilt"]))
	var x: float = side * v["x"]
	var bottom := Vector3(x, _dash_height(x), v["depth"])
	var origin: Vector3 = bottom + basis.y * BOTTOM_EDGE * float(v["size"])
	var rest: Transform3D = p._screen_rest[index]
	var euler := (rest.basis.orthonormalized().inverse() * basis).get_euler()
	return {"offset": origin - rest.origin, "rotation": Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))}


## The dash top in the cabin model (see cockpit() in tools/blender/props.py).
func _dash_height(x: float) -> float:
	return -0.85 + pow(absf(x) / 2.3, 1.7) * 0.1 + 0.02


func _save(dir: String, shot: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot + ".png"))
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

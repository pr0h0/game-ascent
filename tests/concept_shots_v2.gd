extends Node
## Puts the WREN-9 and each round-2 concept ship on the home-screen plate, from three
## eye-level sides, all at the WREN-9's display scale so their sizes compare honestly.
## xvfb-run -a godot --path . res://tests/concept_shots_v2.tscn -- <dir>

const SHIPS := {
	"wren9": "res://assets/models/wren9.glb",
	"badger": "res://tools/concepts/v2_badger.glb",
	"ferret": "res://tools/concepts/v2_ferret.glb",
	"mole": "res://tools/concepts/v2_mole.glb",
	"swift": "res://tools/concepts/v2_swift.glb",
}
const VIEWS := {"front": PI - 0.6, "side": PI * 0.5, "rear": 0.75}
const DISTANCE := 12.5
const CAMERA_LIFT := 0.55
const PITCH := 0.12

var _title: Node


func _ready() -> void:
	_title = load("res://scenes/title.tscn").instantiate()
	add_child(_title)
	await _wait(10)
	var menu: MainMenu = _title.get_children().filter(func(n): return n is MainMenu)[0]
	menu.show_panel("gallery")
	menu.set_inspecting(true)
	menu._inspect_hint.visible = false
	_title._shown_offset = 0.0
	_title._cam.v_offset = CAMERA_LIFT
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(dir)
	var only := args.slice(1)
	var factor := 0.0
	for ship: String in SHIPS:
		_title.show_entry({"model": SHIPS[ship], "tint": Color.BLACK})
		var sc: Node3D = _title._showcase
		if factor == 0.0:
			factor = sc.scale.x
		else:
			# Same scale as the WREN-9, centred the same way the gallery centres.
			var bounds: AABB = _title._merged_bounds(sc)
			sc.scale = Vector3.ONE * factor
			var center := bounds.get_center() * factor
			_title._showcase_rest_y = maxf(-center.y, _title.SHOWCASE_FLOOR - bounds.position.y * factor)
			sc.position = Vector3(-center.x, _title._showcase_rest_y, -center.z)
		if not only.is_empty() and ship not in only:
			continue
		for view: String in VIEWS:
			_title.yaw = VIEWS[view]
			_title._shown_yaw = VIEWS[view]
			_title.pitch = PITCH
			_title._shown_pitch = PITCH
			_title.distance = DISTANCE
			_title._shown_distance = DISTANCE
			await _wait(4)
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, ship, view])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_title._idle = 0.0
		_title._time = 0.0

extends Node
## Puts the WREN-9 and each concept ship on the home-screen plate, from three sides.
## godot --path . res://tests/concept_shots.tscn -- <dir>

const SHIPS := {
	"wren9": "res://assets/models/wren9.glb",
	"kestrel": "res://tools/concepts/concept_kestrel.glb",
	"mantis": "res://tools/concepts/concept_mantis.glb",
	"atlas": "res://tools/concepts/concept_atlas.glb",
}
const VIEWS := {"front": PI - 0.6, "side": PI * 0.5, "rear": 0.75}
const DISTANCE := 17.5
const CAMERA_LIFT := 1.4
const PITCH := 0.22

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
	var dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(dir)
	for ship: String in SHIPS:
		_title.show_entry({"model": SHIPS[ship], "tint": Color.BLACK})
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

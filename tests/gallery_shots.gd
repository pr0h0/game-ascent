extends Node
## Saves every gallery model at eye level, turned to the angle that shows it best.
## godot --path . res://tests/gallery_shots.tscn -- <dir> [preview]
## "preview" instead saves each model from four sides, for choosing those angles.

const FRONT := PI
const QUARTER := PI - 0.7
const SIDE := PI * 0.5
## One fixed frame for every model, so the plates line up and tall items fit.
const DISTANCE := 17.5
const CAMERA_LIFT := 1.4
const SETTLE_FRAMES := 10
const SHOT_FRAMES := 4
const PREVIEW_YAWS := {"front": PI, "quarter": PI - 0.7, "side": PI * 0.5, "back": 0.0}
## Anything not listed here is shown from the front.
const YAWS := {
	# Long, thin things are only a dot from the front.
	"missile": SIDE, "missile_bunker": SIDE, "missile_cluster": SIDE, "missile_emp": SIDE,
	"cannon": SIDE, "cutter": SIDE, "arc_caster": SIDE, "prism_repeater": SIDE,
	"rail_lance": SIDE, "singularity_launcher": SIDE, "upgrade_dual": SIDE,
	# Three-quarter front shows the body behind the nose.
	"wren9": QUARTER, "drillback": QUARTER, "glint": QUARTER, "hornet": QUARTER, "lancer": QUARTER,
	"longshot": QUARTER, "revenant": QUARTER, "ripper": QUARTER, "shade": QUARTER, "sower": QUARTER,
	"wraith": QUARTER, "mine_seeker": QUARTER, "missile_swarm": QUARTER, "sentry": QUARTER,
}

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
	await _wait(SETTLE_FRAMES)
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var preview: bool = args.size() > 1 and args[1] == "preview"
	for entry: Dictionary in GalleryData.entries():
		if not ResourceLoader.exists(entry["model"]):
			print("no model for ", entry["id"])
			continue
		_title.show_entry(entry)
		if preview:
			for side: String in PREVIEW_YAWS:
				await _shoot(PREVIEW_YAWS[side], "%s/%s__%s.png" % [out, entry["id"], side])
		else:
			await _shoot(float(YAWS.get(entry["id"], FRONT)), "%s/%s.png" % [out, entry["id"]])
	get_tree().quit()


func _shoot(yaw: float, path: String) -> void:
	_pose(yaw)
	await _wait(SHOT_FRAMES)
	get_viewport().get_texture().get_image().save_png(path)


## Level camera, no tilt, and no smoothing to wait for.
func _pose(yaw: float) -> void:
	_title.yaw = yaw
	_title._shown_yaw = yaw
	_title.pitch = 0.0
	_title._shown_pitch = 0.0
	_title.distance = DISTANCE
	_title._shown_distance = DISTANCE
	_title._idle = 0.0


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_title._idle = 0.0
		_title._time = 0.0  # holds the idle bob still

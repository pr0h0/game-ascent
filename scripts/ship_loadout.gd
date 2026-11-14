class_name ShipLoadout
extends Node
## Bolts the equipped gun and missile type onto a ship model's hardpoints.
##
## Any hull works if it names its empties Mount_Gun_* and Mount_Missile_*: each gun
## mount gets the current primary's model, each missile mount a rack whose Slot_*
## empties hold one round each, so the rack shows how many rounds are left. The _L
## mounts are authored mirrored, so the same model fits both sides.
## With a player set, it follows that player's selection every frame; otherwise it
## shows whatever show_loadout() was last given (menus, gallery, cutscenes).

const DIR := "res://assets/models/mounts/"
const GUNS := {
	"laser": "gun_pulse", "cutter": "gun_cutter", "arc": "gun_arc",
	"rail": "gun_rail", "prism": "gun_prism", "singularity": "gun_singularity",
}
const ROUNDS := {
	"homing": "round_homing", "cluster": "round_cluster", "swarm": "round_swarm",
	"bunker": "round_bunker", "emp": "round_emp", "mine": "round_mine",
}
const DEPLOY_TIME := 0.25
const RETRACT_TIME := 0.12
## Where a part starts its deploy from, in the mount's space: tucked back and folded.
const STOW_OFFSET := Vector3(0.0, 0.12, 0.55)
const STOW_TURN := Vector3(-55.0, 0.0, 0.0)

static var _packed: Dictionary = {}

var ship: Node3D
## The Player to follow; null for a static display.
var player: Node
var primary := ""
var secondary := ""
var rounds_shown := 0
var _tier := 0
var _gun_mounts: Array[Node3D] = []
## One stable node per gun mount that sits at the current gun's muzzle.
var muzzles: Array[Node3D] = []
var _guns: Array[Node3D] = []
## Rack slots in firing order: alternating sides, inner slot first.
var _slots: Array[Node3D] = []
var _rounds: Array[Node3D] = []


## Gives a ship model its hardpoint parts. Returns null when the hull has no mounts.
static func attach(model: Node3D, gun := "laser", missile := "homing", count := -1, follow: Node = null) -> ShipLoadout:
	var loadout := ShipLoadout.new()
	loadout.name = "Loadout"
	loadout.player = follow
	model.add_child(loadout)
	loadout._setup(model)
	if loadout._gun_mounts.is_empty() and loadout._slots.is_empty():
		loadout.queue_free()
		return null
	loadout.show_loadout(gun, missile, loadout._slots.size() if count < 0 else count, false)
	return loadout


static func _scene(file: String) -> PackedScene:
	if not _packed.has(file):
		_packed[file] = load(DIR + file + ".glb")
	return _packed[file]


func _setup(model: Node3D) -> void:
	ship = model
	var guns: Array = []
	var racks: Array = []
	for node in model.find_children("Mount_*", "Node3D", true, false):
		if node.name.begins_with("Mount_Gun"):
			guns.append(node)
		elif node.name.begins_with("Mount_Missile"):
			racks.append(node)
	guns.sort_custom(func(a, b): return str(a.name) > str(b.name))  # R before L, as Muzzle_R/L were
	racks.sort_custom(func(a, b): return str(a.name) > str(b.name))
	for mount: Node3D in guns:
		_gun_mounts.append(mount)
		var muzzle := Node3D.new()
		muzzle.name = "LoadoutMuzzle"
		mount.add_child(muzzle)
		muzzles.append(muzzle)
		_guns.append(null)
	var per_rack: Array = []
	for mount: Node3D in racks:
		var rack: Node3D = _scene("rack").instantiate()
		Mats.apply(rack)
		mount.add_child(rack)
		per_rack.append(rack.find_children("Slot_*", "", true, false))
	var depth := 0
	for slots: Array in per_rack:
		depth = maxi(depth, slots.size())
	for i in depth:
		for slots: Array in per_rack:
			if i < slots.size():
				_slots.append(slots[i])
				_rounds.append(null)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	show_loadout(player.current_primary, player.current_secondary, int(player.ammo.get(player.current_secondary, 0)))


## Swaps parts only where something changed, so it is cheap to call every frame.
func show_loadout(gun: String, missile: String, count: int, animate := true) -> void:
	var tier := Game.laser_level() if gun == "laser" else _tier
	if gun != primary or tier != _tier:
		var changed := gun != primary
		primary = gun
		_tier = tier
		for i in _gun_mounts.size():
			_set_gun(i, animate and changed)
	count = clampi(count, 0, _slots.size())
	if missile != secondary:
		secondary = missile
		for i in _slots.size():
			_set_round(i, i < count, animate)
	elif count != rounds_shown:
		for i in _slots.size():
			var r := _rounds[i]
			var want := i < count
			if r != null and r.visible != want:
				r.visible = want
				if want and animate:
					_deploy(r)
	rounds_shown = count


func _set_gun(i: int, animate: bool) -> void:
	var old := _guns[i]
	if old != null:
		if animate:
			_retract(old)
		else:
			old.queue_free()
	var gun: Node3D = _scene(GUNS.get(primary, GUNS["laser"])).instantiate()
	Mats.apply(gun)
	if primary == "laser":
		var glow := Mats.unique_glow(gun, "glow_green")
		glow.emission = Player.LASER_COLORS[clampi(_tier - 1, 0, Player.LASER_COLORS.size() - 1)]
	_gun_mounts[i].add_child(gun)
	_match_cloak(gun)
	_guns[i] = gun
	# Read before the deploy moves the gun, so the muzzle marks where it comes to rest.
	var tip: Node = gun.find_child("Muzzle", true, false)
	var xf := Transform3D.IDENTITY
	while tip is Node3D and tip != gun:
		xf = (tip as Node3D).transform * xf
		tip = tip.get_parent()
	muzzles[i].position = xf.origin
	if animate:
		_deploy(gun)


func _set_round(i: int, shown: bool, animate: bool) -> void:
	if _rounds[i] != null:
		_rounds[i].queue_free()
		_rounds[i] = null
	if not ROUNDS.has(secondary):
		return
	var r: Node3D = _scene(ROUNDS[secondary]).instantiate()
	Mats.apply(r)
	_slots[i].add_child(r)
	_match_cloak(r)
	r.visible = shown
	_rounds[i] = r
	if shown and animate:
		_deploy(r)


func _deploy(part: Node3D) -> void:
	part.position = STOW_OFFSET
	part.rotation_degrees = STOW_TURN
	part.scale = Vector3.ONE * 0.35
	var t := part.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(part, "position", Vector3.ZERO, DEPLOY_TIME)
	t.tween_property(part, "rotation_degrees", Vector3.ZERO, DEPLOY_TIME)
	t.tween_property(part, "scale", Vector3.ONE, DEPLOY_TIME)


func _retract(part: Node3D) -> void:
	var t := part.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(part, "position", STOW_OFFSET, RETRACT_TIME)
	t.tween_property(part, "scale", Vector3.ONE * 0.05, RETRACT_TIME)
	t.chain().tween_callback(part.queue_free)


## New parts fitted while cloaked fade like the rest of the hull.
func _match_cloak(part: Node3D) -> void:
	if player != null and player.has_method("is_cloaked") and player.is_cloaked():
		for mesh in part.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).transparency = 0.65


## The gun model currently on a mount, for tests.
func gun_model(i := 0) -> Node3D:
	return _guns[i] if i < _guns.size() else null


func visible_rounds() -> int:
	var n := 0
	for r in _rounds:
		if r != null and r.visible:
			n += 1
	return n

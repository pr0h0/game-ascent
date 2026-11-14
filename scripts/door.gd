class_name Door
extends StaticBody3D
## Two-leaf security door, unlocked by a coloured key or by the core blowing.

const TRIGGER_RANGE := 26.0
const TRAVEL := 10.6
const OPEN_TIME := 0.9
## Each leaf is half of the 11 m opening.
const LEAF := Vector3(11, 5.5, 0.9)

var lock := "key"
var hidden_door := false
var cell := Vector3i.ZERO
var _upper: Node3D
var _lower: Node3D
## One box per leaf, riding with it, so the gap is passable as soon as it looks it.
var _shape: CollisionShape3D
var _shape_low: CollisionShape3D
var _is_open := false
var _denied_cd := 0.0
var _mat: StandardMaterial3D


func setup(d: Dictionary, cell_size: float) -> void:
	lock = d["lock"]
	cell = Vector3i(int(d["cell"][0]), int(d["cell"][1]), int(d["cell"][2]))
	global_position = Vector3(cell) * cell_size
	if d.has("offset"):
		global_position += Vector3(d["offset"][0], d["offset"][1], d["offset"][2])
	if d["axis"] == "x":
		rotation_degrees.y = 90.0
	Game.level.set_cell_blocked(cell, true)
	# Done here, not in _ready: the door enters the tree before it knows its lock.
	_mat.emission = Game.KEY_COLORS.get(lock, Color(0.25, 0.55, 0.3))
	# Kept low: bright emissive hues wash out to white under the tonemapper.
	_mat.emission_energy_multiplier = 2.2
	# Hidden doors open only when shot, and the entry door never opens: no proximity check.
	if hidden_door or lock == "entry":
		set_process(false)


func _ready() -> void:
	collision_layer = Game.WORLD
	collision_mask = 0
	_shape = _leaf_shape(1.0)
	_shape_low = _leaf_shape(-1.0)
	var model: Node3D = load("res://assets/models/door_secret.glb" if hidden_door else "res://assets/models/door.glb").instantiate()
	Mats.apply(model)
	add_child(model)
	_upper = model.find_child("Upper", true, false)
	_lower = model.find_child("Lower", true, false)
	_mat = Mats.unique_glow(model, "glow_blue")


func _leaf_shape(side: float) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = LEAF
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = side * LEAF.y / 2.0
	add_child(shape)
	return shape


func _unlocked() -> bool:
	if lock == "secret":
		return true
	return Game.reactor_down if lock == "reactor" else Game.has_key(lock)


func _process(delta: float) -> void:
	_denied_cd -= delta
	# The entry door is scenery: the ship arrived through it and it stays shut.
	if _is_open or Game.player == null or hidden_door or lock == "entry":
		return
	if Game.player.global_position.distance_to(global_position) > TRIGGER_RANGE:
		return
	if _unlocked():
		_open()
	else:
		_deny()


## Bolts and missiles call this on anything they hit. Only the player's shots count,
## so robots firing at the player can't open doors for them.
func take_damage(_amount: float, _at: Vector3, source: Object) -> void:
	var from_player: bool = source == Game.player or (source is Missile and source.from_player)
	if not from_player or _is_open:
		return
	if _unlocked():
		_open()
	else:
		_deny()


func is_opening() -> bool:
	return _is_open


func _deny() -> void:
	if _denied_cd > 0.0 or lock == "entry":
		return
	_denied_cd = 4.0
	var text := "SEALED — OPENS ON CORE FAILURE" if lock == "reactor" else "LOCKED — %s KEY REQUIRED" % lock.to_upper()
	Game.say(text, Game.KEY_COLORS.get(lock, Color(1.0, 0.4, 0.25)))
	Sfx.play("denied", global_position, 0.0)


func _open() -> void:
	_is_open = true
	set_process(false)
	if hidden_door:
		Game.on_secret_found()
		Sfx.play("secret", null, -3.0)
	elif lock != "reactor":
		Game.checkpoint()
	_mat.emission = Color(0.2, 1.0, 0.35)
	Game.level.set_cell_blocked(cell, false)
	Sfx.play("door_secret" if hidden_door else "door", global_position, 2.0)
	# Fast start, soft stop: the leaves clear the ship's path early in the move.
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_upper, "position:y", TRAVEL, OPEN_TIME)
	t.tween_property(_lower, "position:y", -TRAVEL, OPEN_TIME)
	t.tween_property(_shape, "position:y", TRAVEL + LEAF.y / 2.0, OPEN_TIME)
	t.tween_property(_shape_low, "position:y", -TRAVEL - LEAF.y / 2.0, OPEN_TIME)
	t.chain().tween_callback(func():
		_shape.disabled = true
		_shape_low.disabled = true)

class_name Astronaut
extends Node3D
## A stranded survivor, drifting and waving. Fly close to bring them aboard.

const RESCUE_RADIUS := 6.0
const SCORE := 1000
const MODEL_SCALE := 2.0
const PICKUP_TIME := 0.35
## Further than this the wave can't be made out, so it isn't animated.
const ANIMATE_RANGE := 160.0

var _model: Node3D
var _arm: Node3D
var _time := 0.0
var _rescued := false


func _ready() -> void:
	add_to_group("astronaut")
	_time = randf() * TAU
	_model = load("res://assets/models/astronaut.glb").instantiate()
	Mats.apply(_model)
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_arm = _model.find_child("ArmR", true, false)


func _process(delta: float) -> void:
	_time += delta
	var p := Game.player
	if _rescued or p == null or p.dead or Game.cinematic:
		_wave()
		return
	var to: Vector3 = p.global_position - global_position
	if to.length_squared() > ANIMATE_RANGE * ANIMATE_RANGE:
		return
	_wave()
	# Turns to keep facing the ship, so the wave reads as a call for help.
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-3.0 * delta))
	if to.length() < RESCUE_RADIUS:
		_rescue()


func _wave() -> void:
	_model.position.y = sin(_time * 1.1) * 0.25
	_model.rotation.z = sin(_time * 0.7) * 0.12
	_arm.rotation.z = sin(_time * 7.0) * 0.45


func _rescue() -> void:
	_rescued = true
	Game.rescue_astronaut()
	Sfx.play("astronaut", null, -3.0)
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, PICKUP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)

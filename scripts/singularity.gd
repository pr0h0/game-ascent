class_name Singularity
extends Node3D
## A slow knot of plasma that drags targets inward, then bursts.

const SPEED := 40.0
const FUSE := 2.5
const PULL_RADIUS := 30.0
const PULL_STRENGTH := 20.0
const BURST_RADIUS := 26.0
const CAPTURE_RANGE := 7.0
const COLOR := Color(0.75, 0.3, 1.0)
## How often the robots in reach are re-listed; the pull itself runs every frame.
const SCAN_INTERVAL := 0.1

var velocity := Vector3.ZERO
var damage := 150.0
var from_player := true
var mask := 1
var _left := FUSE
var _stopped := false
var _query: PhysicsRayQueryParameters3D
var _scan_cd := 0.0
var _in_reach: Array[Robot] = []


static func launch(at: Vector3, direction: Vector3, dmg: float, is_player: bool) -> Singularity:
	var s := Singularity.new()
	s.velocity = direction.normalized() * SPEED
	s.damage = dmg
	s.from_player = is_player
	# It stops at the first thing it meets, so the pull and burst land where aimed.
	s.mask = Game.WORLD | (Game.ENEMY if is_player else Game.PLAYER)
	# Placed before add_child so the launch sound in _ready plays from the right spot.
	s.position = Game.level.to_local(at)
	Game.level.add_child(s)
	return s


func _ready() -> void:
	var core := SphereMesh.new()
	core.radius = 1.3
	core.height = 2.6
	var mi := MeshInstance3D.new()
	mi.mesh = core
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(COLOR.r * 3.0, COLOR.g * 3.0, COLOR.b * 3.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 5.0
	light.omni_range = 34.0
	add_child(light)
	Sfx.play("singularity_fire", global_position, 2.0)
	Sfx.positional_loop("singularity_loop", self, 18.0, -2.0)


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_burst()
		return
	if not _stopped:
		var to := global_position + velocity * delta
		if _query == null:
			_query = PhysicsRayQueryParameters3D.create(global_position, to, mask)
		_query.from = global_position
		_query.to = to
		var hit := get_world_3d().direct_space_state.intersect_ray(_query)
		if hit.is_empty():
			global_position = to
		else:
			_stopped = true
	_pull(delta)


func _pull(delta: float) -> void:
	if from_player:
		_scan_cd -= delta
		if _scan_cd <= 0.0:
			_scan_cd = SCAN_INTERVAL
			_in_reach.clear()
			# A little margin, so a robot that drifts in between scans is still caught.
			var reach := PULL_RADIUS + 15.0
			for e in get_tree().get_nodes_in_group("enemy"):
				if e is Robot and not e is Boss and e.global_position.distance_squared_to(global_position) < reach * reach:
					_in_reach.append(e)
		for e in _in_reach:
			if is_instance_valid(e) and e.is_inside_tree():
				_drag_robot(e, delta)
		return
	var p: Node3D = Game.player
	if p != null and not p.dead:
		var d := p.global_position.distance_to(global_position)
		_stopped = _stopped or d < CAPTURE_RANGE
		if d < PULL_RADIUS:
			p.velocity += (global_position - p.global_position).normalized() * PULL_STRENGTH * 3.0 * delta


func _drag_robot(e: Robot, delta: float) -> void:
	var d := e.global_position.distance_to(global_position)
	# A target pulled onto the orb is inside its own hit ray, so this check does the stopping.
	_stopped = _stopped or d < CAPTURE_RANGE
	if d < PULL_RADIUS:
		# move_and_collide, so the pull can't drag a robot through rock.
		e.move_and_collide((global_position - e.global_position).normalized() * PULL_STRENGTH * delta)


func _burst() -> void:
	Fx.explosion(global_position, 7.0, false)
	Sfx.play("singularity_burst", global_position, 5.0)
	Fx.pulse(global_position, BURST_RADIUS, COLOR)
	if from_player:
		Weapons.splash_enemies(global_position, BURST_RADIUS, damage, Game.player)
	else:
		Weapons.splash_player(global_position, BURST_RADIUS, damage, self)
	queue_free()

class_name Mine
extends StaticBody3D
## Explosive hazards. Each kind triggers differently, and all can be shot from afar.

const TYPES := {
	"prox": {"model": "mine_prox", "hp": 20.0, "range": 11.0, "damage": 30.0, "blast": 14.0, "score": 50},
	"seeker": {"model": "mine_seeker", "hp": 25.0, "range": 7.0, "damage": 35.0, "blast": 13.0, "score": 75, "chase": 55.0, "speed": 15.0},
	"tripwire": {"model": "mine_tripwire", "hp": 30.0, "range": 3.0, "damage": 45.0, "blast": 13.0, "score": 75},
	"pulse": {"model": "mine_pulse", "hp": 30.0, "range": 13.0, "damage": 10.0, "blast": 22.0, "score": 100, "disrupt": 3.0, "drain": 30.0},
	"player": {"model": "missile_mine", "hp": 1.0, "range": 12.0, "damage": 120.0, "blast": 18.0, "score": 0, "life": 45.0},
}
const ARM_DELAY := 0.6
const BEEP_RANGE := 38.0
const TRIPWIRE_AIM_OFFSET := 0.8
## A dropped player mine lives 45 s; it looks for robots this often, not every frame.
const WATCH_INTERVAL := 0.1

var kind := "prox"
var normal := Vector3.UP
var cfg: Dictionary
var hp := 1.0
var life := -1.0
var _armed := ARM_DELAY
var _dead := false
var _beep_cd := 0.0
var _wire_end := Vector3.ZERO
var _model: Node3D
var _watch_cd := 0.0


static func spawn(mine_kind: String, at: Vector3, wall_normal := Vector3.UP) -> Mine:
	var m := Mine.new()
	m.kind = mine_kind
	m.normal = wall_normal.normalized()
	# Placed before add_child so the drop sound in _ready plays from the right spot.
	m.position = Game.level.to_local(at)
	Game.level.add_child(m)
	if mine_kind == "tripwire":
		m.look_at(at + m.normal, Vector3.UP if absf(m.normal.y) < 0.9 else Vector3.BACK)
	return m


func _ready() -> void:
	cfg = TYPES[kind]
	hp = cfg["hp"]
	life = cfg.get("life", -1.0)
	collision_mask = 0
	if kind == "player":
		collision_layer = 0
	else:
		add_to_group("enemy")
		collision_layer = Game.ENEMY
		var shape := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 1.6
		shape.shape = s
		add_child(shape)
	_model = load("res://assets/models/%s.glb" % cfg["model"]).instantiate()
	Mats.apply(_model)
	_model.scale = Vector3.ONE * 2.2
	add_child(_model)
	if kind == "player":
		Sfx.play("mine_drop", global_position, -1.0)


## A tripwire's origin is on the wall, so a line to it would end inside the rock.
func body_center() -> Vector3:
	return global_position + normal * TRIPWIRE_AIM_OFFSET if kind == "tripwire" else global_position


func can_be_locked() -> bool:
	return not _dead


func hp_ratio() -> float:
	return hp / float(cfg["hp"])


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_armed -= delta
	if life >= 0.0:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
	if kind == "player":
		_watch_for_enemies(delta)
		return
	var p: Player = Game.player
	if p == null or p.dead or Game.cinematic or _armed > 0.0:
		return
	if kind == "tripwire":
		_tripwire(p)
		return
	var dist := p.global_position.distance_to(global_position)
	_beep_when_close(dist, delta)
	if cfg.has("chase") and dist < float(cfg["chase"]) and Weapons._clear_line(global_position, p.global_position, self):
		global_position = global_position.move_toward(p.global_position, float(cfg["speed"]) * delta)
	if dist < float(cfg["range"]):
		_detonate()


## Audible early warning: faster and faster as the ship closes in.
func _beep_when_close(dist: float, delta: float) -> void:
	_beep_cd -= delta
	if dist < BEEP_RANGE and _beep_cd <= 0.0:
		_beep_cd = lerpf(0.16, 0.8, dist / BEEP_RANGE)
		Sfx.play("mine_beep", global_position, -3.0, 1.0 if kind == "prox" else 0.8)


func _tripwire(p: Player) -> void:
	if _wire_end == Vector3.ZERO:
		var far := global_position + normal * 60.0
		var q := PhysicsRayQueryParameters3D.create(global_position + normal, far, Game.WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_wire_end = hit.position if not hit.is_empty() else far
		_draw_wire()
	var nearest := Geometry3D.get_closest_point_to_segment(p.global_position, global_position, _wire_end)
	if nearest.distance_to(p.global_position) < float(cfg["range"]):
		_detonate()


func _draw_wire() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, global_position.distance_to(_wire_end))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(4.0, 0.4, 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = global_position.lerp(_wire_end, 0.5)


func _watch_for_enemies(delta: float) -> void:
	if _armed > 0.0:
		return
	_watch_cd -= delta
	if _watch_cd > 0.0:
		return
	_watch_cd = WATCH_INTERVAL
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Robot and e.global_position.distance_to(global_position) < float(cfg["range"]):
			_detonate()
			return


func take_damage(amount: float, _at: Vector3, _source: Object) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		Game.add_kill(cfg["score"])
		_detonate()


func _detonate() -> void:
	_dead = true
	remove_from_group("enemy")
	Fx.explosion(global_position, 4.5)
	if kind == "player":
		# The ship's own mines hit as hard as its other secondaries at this laser level.
		Weapons.splash_enemies(global_position, cfg["blast"], float(cfg["damage"]) * Weapons.missile_mult(), Game.player)
	else:
		Weapons.splash_player(global_position, cfg["blast"], cfg["damage"], self)
		if cfg.has("disrupt") and Game.player != null and Game.player.global_position.distance_to(global_position) < float(cfg["blast"]):
			Game.player.disrupt(cfg["disrupt"], cfg["drain"])
			Sfx.play("pulse_mine", global_position, 3.0)
			Fx.pulse(global_position, cfg["blast"], Weapons.ARC_COLOR)
	queue_free()

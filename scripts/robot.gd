class_name Robot
extends CharacterBody3D
## Flying mine robot: sleeps, fights in the open, calls for help, flanks, dodges,
## falls back when badly hurt and searches where it last saw the ship.
## A type's table entry picks its gun, its movement and any special ability.

const TYPES := {
	"tick": {"model": "tick", "hp": 34.0, "radius": 1.6, "speed": 27.0, "accel": 44.0, "fire": 0.95, "bolt": 55.0, "react": 0.7, "dmg": 10.0, "sight": 130.0, "ideal": 34.0, "score": 100, "turn": 7.0, "boom": 3.0},
	"lancer": {"model": "lancer", "hp": 100.0, "radius": 2.6, "speed": 18.0, "accel": 22.0, "fire": 1.5, "bolt": 95.0, "react": 1.1, "dmg": 16.0, "sight": 190.0, "ideal": 55.0, "score": 350, "turn": 3.2, "boom": 5.5},
	"bulwark": {"model": "bulwark", "hp": 360.0, "radius": 3.9, "speed": 10.0, "accel": 12.0, "fire": 0.38, "bolt": 62.0, "react": 0.9, "dmg": 10.0, "sight": 170.0, "ideal": 36.0, "score": 1200, "turn": 1.7, "boom": 11.0, "missile": 4.6},
	"ripper": {"model": "ripper", "hp": 70.0, "radius": 2.0, "speed": 34.0, "accel": 50.0, "fire": 1.0, "react": 0.3, "sight": 120.0, "ideal": 0.0, "score": 250, "turn": 8.0, "boom": 3.5, "melee": 18.0},
	"drillback": {"model": "drillback", "hp": 300.0, "radius": 3.6, "speed": 22.0, "accel": 26.0, "fire": 1.0, "react": 0.6, "sight": 130.0, "ideal": 0.0, "score": 900, "turn": 2.6, "boom": 8.0, "melee": 40.0},
	"cinder": {"model": "cinder", "hp": 25.0, "radius": 1.6, "speed": 36.0, "accel": 60.0, "fire": 1.0, "react": 0.2, "sight": 130.0, "ideal": 0.0, "score": 150, "turn": 9.0, "boom": 6.0, "explode": 45.0},
	"hornet": {"model": "hornet", "hp": 45.0, "radius": 1.8, "speed": 38.0, "accel": 58.0, "fire": 0.55, "bolt": 70.0, "react": 0.6, "dmg": 10.0, "sight": 140.0, "ideal": 22.0, "score": 200, "turn": 9.0, "boom": 3.5},
	"spark": {"model": "spark", "hp": 80.0, "radius": 2.2, "speed": 20.0, "accel": 30.0, "fire": 2.0, "react": 0.8, "dmg": 12.0, "sight": 110.0, "ideal": 30.0, "score": 400, "turn": 5.0, "boom": 4.5, "weapon": "arc"},
	"longshot": {"model": "longshot", "hp": 70.0, "radius": 2.2, "speed": 12.0, "accel": 16.0, "fire": 3.2, "react": 1.6, "dmg": 40.0, "sight": 230.0, "ideal": 90.0, "score": 500, "turn": 2.4, "boom": 4.5, "weapon": "rail"},
	"glint": {"model": "glint", "hp": 60.0, "radius": 2.0, "speed": 24.0, "accel": 34.0, "fire": 0.5, "react": 0.8, "dmg": 10.0, "sight": 140.0, "ideal": 40.0, "score": 350, "turn": 6.0, "boom": 4.0, "weapon": "prism"},
	"gravitar": {"model": "gravitar", "hp": 220.0, "radius": 3.0, "speed": 9.0, "accel": 12.0, "fire": 7.0, "react": 1.0, "dmg": 40.0, "sight": 150.0, "ideal": 60.0, "score": 900, "turn": 2.0, "boom": 8.0, "weapon": "singularity"},
	"warden": {"model": "warden", "hp": 160.0, "radius": 2.6, "speed": 14.0, "accel": 20.0, "fire": 1.4, "bolt": 70.0, "react": 0.9, "dmg": 10.0, "sight": 140.0, "ideal": 60.0, "score": 700, "turn": 3.0, "boom": 6.0, "heal": 18.0},
	"hive": {"model": "hive", "hp": 420.0, "radius": 4.0, "speed": 6.0, "accel": 10.0, "fire": 2.0, "bolt": 60.0, "react": 1.0, "dmg": 12.0, "sight": 150.0, "ideal": 70.0, "score": 1100, "turn": 1.5, "boom": 11.0, "spawns": 7.0},
	"sower": {"model": "sower", "hp": 110.0, "radius": 2.6, "speed": 16.0, "accel": 22.0, "fire": 2.0, "bolt": 60.0, "react": 1.0, "dmg": 10.0, "sight": 130.0, "ideal": 50.0, "score": 450, "turn": 3.0, "boom": 5.5, "mines": 5.0},
	"wraith": {"model": "wraith", "hp": 65.0, "radius": 2.0, "speed": 30.0, "accel": 44.0, "fire": 1.0, "react": 0.4, "sight": 120.0, "ideal": 0.0, "score": 500, "turn": 7.0, "boom": 4.0, "melee": 26.0, "cloak": true},
	"phase": {"model": "phase", "hp": 75.0, "radius": 2.0, "speed": 18.0, "accel": 28.0, "fire": 0.9, "bolt": 90.0, "react": 0.8, "dmg": 14.0, "sight": 150.0, "ideal": 40.0, "score": 450, "turn": 6.0, "boom": 4.0, "blink": 4.0},
	"siege": {"model": "siege", "hp": 380.0, "radius": 3.8, "speed": 8.0, "accel": 10.0, "fire": 2.5, "bolt": 60.0, "react": 1.2, "dmg": 20.0, "sight": 180.0, "ideal": 70.0, "score": 1300, "turn": 1.6, "boom": 10.0, "missile": 6.0, "salvo": 4},
	"shade": {"model": "shade", "hp": 55.0, "radius": 2.0, "speed": 26.0, "accel": 40.0, "fire": 0.8, "bolt": 75.0, "react": 0.8, "dmg": 12.0, "sight": 140.0, "ideal": 38.0, "score": 300, "turn": 6.0, "boom": 3.5, "fade": 4.0},
	"revenant": {"model": "revenant", "hp": 140.0, "radius": 2.6, "speed": 16.0, "accel": 22.0, "fire": 1.3, "bolt": 100.0, "react": 1.0, "dmg": 18.0, "sight": 190.0, "ideal": 60.0, "score": 600, "turn": 3.2, "boom": 5.5, "fade": 6.0},
	"overseer": {"model": "overseer", "hp": 10000.0, "radius": 9.0, "speed": 8.0, "accel": 8.0, "fire": 0.6, "bolt": 80.0, "react": 1.0, "dmg": 16.0, "sight": 400.0, "ideal": 80.0, "score": 10000, "turn": 1.0, "boom": 30.0},
	"crucible": {"model": "crucible", "hp": 7000.0, "radius": 10.0, "speed": 7.0, "accel": 7.0, "fire": 2.2, "bolt": 46.0, "react": 1.0, "dmg": 18.0, "sight": 400.0, "ideal": 70.0, "score": 8000, "turn": 0.9, "boom": 30.0, "music": "boss_crucible"},
	"zero": {"model": "zero", "hp": 11000.0, "radius": 11.0, "speed": 6.0, "accel": 6.0, "fire": 0.9, "bolt": 90.0, "react": 1.0, "dmg": 16.0, "sight": 450.0, "ideal": 90.0, "score": 20000, "turn": 1.2, "boom": 34.0, "music": "boss_zero"},
}
## Bosses get their own script; everything else is a plain Robot.
const BOSS_SCRIPTS := {
	"overseer": "res://scripts/boss.gd",
	"crucible": "res://scripts/crucible.gd",
	"zero": "res://scripts/zero.gd",
}
const MELEE_INTERVAL := 0.6
## How fast the Spin* part turns, in radians a second.
const SPIN_RATE := 14.0
## The local axis each model's Spin* part turns about (Godot forward is -Z, so the models'
## noses point down -Z). Unlisted models spin about their part's UP: the tick's blade ring
## and the bulwark's gyro rings are flat disks lying in the model's XZ plane. The drillback's
## bit points along the nose and has to bore about Z, not tumble about UP.
const SPIN_AXES := {"drillback": Vector3.FORWARD}
## Models whose Spin* mesh holds several rotors side by side (the ripper's twin saws). The
## mesh is split by side at load so each half turns on its own hub; spinning the whole part
## about the model's centre would swing both saws around the body instead.
const SPLIT_ROTORS := {"ripper": true}
const MELEE_KNOCKBACK := 25.0
const EXPLODE_RANGE := 7.0
const EXPLODE_BLAST := 16.0
const CLOAK_REVEAL_RANGE := 38.0
const CLOAK_REVEAL_TIME := 3.0
const HEAL_RANGE := 40.0
const MAX_BROOD := 4
const BLINK_RANGE := 30.0
const CLOAKED_PLAYER_RANGE := 18.0
const RAIL_WARNING := 0.95
## Aim freezes this long before the shot, so moving off the line dodges it.
const RAIL_LOCK_TIME := 0.3
const SIGHT_COLOR := Color(1.0, 0.15, 0.1)
const BARK_GAP_MS := 450
const DORMANT_RANGE := 240.0
const CINDER_ARM_RANGE := 26.0
static var _last_bark_ms := -1000
## Route searches on a big mine are expensive, so robots take turns.
const PATH_FRAME_GAP := 3
const FORGET_RANGE := 220.0
static var _next_path_frame := 0
const THINK_GAP := 0.14
## Robots hunting out of sight, far from the ship, look around less often.
const FAR_THINK_GAP := 0.26
const FAR_THINK_RANGE := 120.0
## A sleeping robot out of range only checks whether the ship has come close.
const DORMANT_THINK_GAP := 0.4
const SEPARATION_RANGE := 14.0
## Beyond this, a robot out of the ship's sight moves on alternate physics frames.
const HALF_RATE_RANGE := 50.0
const FULL_MASK := Game.WORLD | Game.PLAYER | Game.ENEMY
const HIDDEN_MASK := Game.WORLD | Game.PLAYER

# --- Tactics. Every one of these is scaled by Game.diff("ai"), so Recruit sees far less.
## How far a shout carries: line of sight to an ally, or this close through rock.
const HELP_RANGE := 95.0
const HELP_HEAR_RANGE := 28.0
## A shout goes out a moment after the fight starts, and allies arrive over a few seconds.
const HELP_DELAY := Vector2(0.5, 1.3)
const HELP_RAYS := 10
## Allies that hear a shout pass it on once, over a shorter range.
const RELAY_SHARE := 0.55
## Seconds spent combing the area around the last sighting before giving up.
const SEARCH_TIME := 15.0
const SEARCH_RADIUS := 32.0
## Below this much health a robot may fall back toward friends or out of sight.
const RETREAT_HP := 0.3
const RETREAT_TIME := 7.0
const RETREAT_REGEN := 0.025
const RETREAT_REGEN_CAP := 0.5
const RETREAT_HIDE_SAMPLES := 7
## Share of alerted robots that try to come around the side instead of head-on.
const FLANK_SHARE := 0.6
## Cells on the direct route cost this much more when a flanker plans its approach.
const FLANK_WEIGHT := 9.0
## A flank route this much longer than the direct one isn't worth flying.
const FLANK_DETOUR := 2.4
const PACK_RANGE := 110.0
const DODGE_COOLDOWN := 1.5
const THREAT_RANGE := 60.0
const THREAT_TIME := 0.9
const JINK_UNDER_FIRE := 0.35
const UNDER_FIRE_TIME := 2.0
## Player missiles in flight, so robots can see them coming without searching the tree.
static var _threats: Array = []
static var _watched_level := 0
static var _flank_turn := 0
## Every live robot, so neighbour checks don't search the scene tree.
static var _all: Array[Robot] = []
## Where every robot was, and where the head-on attackers were, refreshed every couple of
## physics frames and shared by all of them.
static var _roster_frame := -100
static var _roster_pos := PackedVector3Array()
static var _pack_pos := PackedVector3Array()
const ROSTER_FRAMES := 2

var kind := "tick"
var cfg: Dictionary
var hp := 1.0
var alerted := false
var has_los := false
var home := Vector3.ZERO
## "idle", "fight", "hunt", "search", "retreat" or "return".
var mode := "idle"
## Where this robot last saw the ship, or was told it was.
var last_seen := Vector3.ZERO
## 0 comes straight at the ship; -1 and 1 swing around opposite sides.
var flank_side := 0

var _model: Node3D
var _spinner: Node3D
## Each rotor the Spin* part was split into, and which way it turns (+1 or -1).
var _rotors: Array[Node3D] = []
var _rotor_dirs: Array[float] = []
var _muzzles: Array[Node3D] = []
var _side := 0
var _fire_cd := 1.0
var _missile_cd := 3.0
var _think_cd := 0.0
var _path_cd := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _phase := 0.0
var _separation := Vector3.ZERO
var _avoid := Vector3.ZERO
var _dead := false
var _returning := false
var _reaction := 0.0
var _stunned := 0.0
var _melee_cd := 0.0
var _ability_cd := 3.0
var _reveal := 0.0
var _brood: Array = []
var _was_cloaked := false
var _armed_sound := false
var _saw: AudioStreamPlayer3D
var _needs_home_path := false
var _rail_charge := 0.0
var _rail_aim := Vector3.FORWARD
var _sight_cd := 0.0
var _rail_muzzle := Vector3.ZERO
var _want_path := false
var _goal := Vector3.ZERO
var _search_left := 0.0
var _retreat_left := 0.0
var _retreats_left := 1
var _help_left := -1.0
var _wake_left := -1.0
var _call_range := HELP_RANGE
var _dodge_cd := 0.0
var _under_fire := 0.0
var _pack_dir := Vector3.ZERO
var _pack_count := 0
## False for robots spawned mid-fight (brood, boss guards): no score, kill or drop.
var bounty := true
var _can_cloak := false
var _heal_time := 0.0
var _idle_bob := 0.0
var _parity := 0


static func make(robot_kind: String) -> Robot:
	if BOSS_SCRIPTS.has(robot_kind):
		return load(BOSS_SCRIPTS[robot_kind]).new()
	return Robot.new()


func _ready() -> void:
	cfg = TYPES[kind]
	hp = max_hp()
	_phase = randf() * TAU
	_think_cd = randf() * 0.2
	_parity = get_instance_id() % 2
	add_to_group("enemy")
	collision_layer = Game.ENEMY
	collision_mask = FULL_MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = cfg["radius"]
	shape.shape = sphere
	add_child(shape)
	_model = load("res://assets/models/%s.glb" % cfg["model"]).instantiate()
	Mats.apply(_model)
	add_child(_model)
	_spinner = _model.find_child("Spin*", true, false)
	if _spinner != null and SPLIT_ROTORS.has(cfg["model"]):
		_split_rotors()
	_can_cloak = cfg.has("fade") or cfg.has("cloak")
	_all.append(self)
	tree_exiting.connect(_all.erase.bind(self))
	Game.player_died.connect(_on_player_died)
	for n in ["Muzzle_R", "Muzzle_L"]:
		var m: Node3D = _model.find_child(n, true, false)
		_muzzles.append(m if m != null else self)
	Sfx.robot_hum(self, kind)
	_watch_threats()


## The local axis this robot's Spin* part turns about.
func spin_axis() -> Vector3:
	return SPIN_AXES.get(cfg["model"], Vector3.UP)


## The nodes that actually turn: the Spin* part itself, or the rotors it was split into.
func spin_parts() -> Array[Node3D]:
	if not _rotors.is_empty():
		return _rotors
	var parts: Array[Node3D] = []
	if _spinner != null:
		parts.append(_spinner)
	return parts


func _spin(delta: float) -> void:
	if _spinner == null:
		return
	if _rotors.is_empty():
		_spinner.rotate_object_local(spin_axis(), SPIN_RATE * delta)
		return
	for i in _rotors.size():
		_rotors[i].rotate_object_local(spin_axis(), SPIN_RATE * delta * _rotor_dirs[i])


## Split per-model meshes, built once and shared by every robot of that model.
static var _rotor_cache := {}


## Cuts the Spin* mesh into its left and right halves, each re-centred on its own hub
## (the middle of its footprint across the spin axis) under a pivot at that hub.
func _split_rotors() -> void:
	var mi := _spinner as MeshInstance3D
	if mi == null:
		var found := _spinner.find_children("*", "MeshInstance3D", true, false)
		mi = found[0] if not found.is_empty() else null
	if mi == null or mi.mesh == null:
		return
	var model: String = cfg["model"]
	if not _rotor_cache.has(model):
		_rotor_cache[model] = Robot._cut_rotors(mi.mesh, spin_axis())
	for half in _rotor_cache[model]:
		var pivot := Node3D.new()
		pivot.name = "Rotor%d" % _rotors.size()
		pivot.position = half["hub"]
		var piece := MeshInstance3D.new()
		piece.mesh = half["mesh"]
		pivot.add_child(piece)
		mi.add_child(pivot)
		Mats.apply(piece)
		_rotors.append(pivot)
		# Mirrored saws counter-rotate, both biting inward.
		_rotor_dirs.append(1.0 if half["hub"].x >= 0.0 else -1.0)
	# The pieces carry all of the original's geometry.
	mi.mesh = null


static func _cut_rotors(mesh: Mesh, axis: Vector3) -> Array:
	var out := []
	for side in [-1.0, 1.0]:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var surfaces := []
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var c := verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]
				if signf(c.x) == side:
					for j in 3:
						keep.append(idx[t + j])
						lo = lo.min(verts[idx[t + j]])
						hi = hi.max(verts[idx[t + j]])
			surfaces.append([si, arrays, keep])
		if lo == Vector3.INF:
			continue
		# The hub sits mid-footprint across the axis; along the axis any point will do.
		var hub := (lo + hi) * 0.5
		hub -= axis * axis.dot(hub)
		var cut := ArrayMesh.new()
		for entry in surfaces:
			var keep: PackedInt32Array = entry[2]
			if keep.is_empty():
				continue
			var arrays := Robot._compact(entry[1], keep)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] -= hub
			arrays[Mesh.ARRAY_VERTEX] = verts
			cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			cut.surface_set_material(cut.get_surface_count() - 1, mesh.surface_get_material(entry[0]))
		out.append({"hub": hub, "mesh": cut})
	return out


## Surface arrays holding only the vertices the kept triangles use, re-indexed.
static func _compact(arrays: Array, keep: PackedInt32Array) -> Array:
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var remap := {}
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	for i in keep:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		idx.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var src = arrays[k]
		if src == null or k == Mesh.ARRAY_INDEX:
			continue
		# Per-vertex arrays; tangents and bone data pack several numbers per vertex.
		var stride: int = src.size() / count
		var dst = src.duplicate()
		dst.resize(order.size() * stride)
		for n in order.size():
			for j in stride:
				dst[n * stride + j] = src[order[n] * stride + j]
		out[k] = dst
	out[Mesh.ARRAY_INDEX] = idx
	return out


## Player missiles are added to the level like everything else; noting them as they
## appear is far cheaper than every robot searching the scene for them.
static func _watch_threats() -> void:
	var world: Node = Game.level
	if world == null or world.get_instance_id() == _watched_level:
		return
	_watched_level = world.get_instance_id()
	_threats.clear()
	world.child_entered_tree.connect(Robot._on_level_child)


static func _on_level_child(n: Node) -> void:
	if n is Missile and n.from_player:
		_threats.append(n)
		if _threats.size() > 24:
			_threats = _threats.filter(func(m): return is_instance_valid(m))


func can_be_locked() -> bool:
	return not _dead and not _is_cloaked()


func hp_ratio() -> float:
	return hp / max_hp()


func max_hp() -> float:
	return float(cfg["hp"]) * Game.diff("hp")


## How much of the clever stuff this difficulty allows, 0..1.
static func tactics() -> float:
	return Game.diff("ai")


## Light, twitchy airframes sidestep; heavy haulers barely can.
func agility() -> float:
	return float(cfg.get("dodge", clampf((float(cfg["accel"]) - 14.0) / 46.0, 0.0, 0.85)))


## Bosses override this: they hold their arena instead of hunting, fleeing or flanking.
func _uses_tactics() -> bool:
	return true


func alert() -> void:
	if not alerted:
		_bark()
		if Game.player != null and last_seen == Vector3.ZERO:
			last_seen = Game.player.global_position
		_pick_role()
		if _uses_tactics() and _call_range > 12.0:
			_help_left = randf_range(HELP_DELAY.x, HELP_DELAY.y)
	alerted = true
	_returning = false
	_wake_left = -1.0
	if mode == "idle" or mode == "return":
		mode = "fight" if has_los else "hunt"
		if not has_los:
			_begin_hunt()


func _pick_role() -> void:
	flank_side = 0
	if _uses_tactics() and randf() < FLANK_SHARE * tactics():
		_flank_turn += 1
		flank_side = 1 if _flank_turn % 2 == 0 else -1


## The chatter that gives away a robot before it's on screen.
func _bark() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_bark_ms < BARK_GAP_MS:
		return
	_last_bark_ms = now
	var radius: float = cfg["radius"]
	var sound := "robot_alert_small" if radius < 2.2 else ("robot_alert_mid" if radius < 3.4 else "robot_alert_big")
	Sfx.play(sound, global_position, 2.0, randf_range(0.9, 1.12))


## An ally shouted. This one wakes a moment later, the further away the later.
func hear_call(at: Vector3, distance: float, relay_range: float) -> void:
	if alerted or _dead or _wake_left > 0.0:
		return
	last_seen = at
	_call_range = relay_range
	_wake_left = 0.25 + distance / 70.0 + randf() * 0.9


## Wakes allies that can see this robot, or are close enough to hear it through rock.
func _call_for_help() -> void:
	var reach := _call_range * lerpf(0.45, 1.0, tactics())
	var space := get_world_3d().direct_space_state
	var rays := 0
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not other is Robot or other.alerted or other._wake_left > 0.0 or other is Boss:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > reach:
			continue
		if d > HELP_HEAR_RANGE:
			if rays >= HELP_RAYS:
				continue
			rays += 1
			var q := PhysicsRayQueryParameters3D.create(global_position, other.global_position, Game.WORLD)
			if not space.intersect_ray(q).is_empty():
				continue
		other.hear_call(last_seen, d, _call_range * RELAY_SHARE)


func stun(seconds: float) -> void:
	_stunned = maxf(_stunned, seconds)
	_rail_charge = 0.0


func _is_cloaked() -> bool:
	if not _can_cloak or _reveal > 0.0 or Game.player == null:
		return false
	if cfg.has("fade"):
		# Spends every other stretch of time fully invisible, while still fighting.
		return fmod(Time.get_ticks_msec() * 0.001 + _phase, float(cfg["fade"]) * 2.0) > float(cfg["fade"])
	return cfg.has("cloak") and global_position.distance_to(Game.player.global_position) > CLOAK_REVEAL_RANGE


## Forget the kill and go back to post, so nothing is waiting at the respawn point.
## Robots still asleep at their post have nowhere to go, so they stay asleep.
func _on_player_died() -> void:
	if alerted or (not _returning and global_position.distance_squared_to(home) > 16.0):
		_stand_down()
	has_los = false
	_wake_left = -1.0
	_help_left = -1.0


func _stand_down() -> void:
	alerted = false
	mode = "return"
	_returning = true
	_path = PackedVector3Array()
	_path_i = 0
	_needs_home_path = true
	_want_path = false
	_call_range = HELP_RANGE
	_separation = Vector3.ZERO
	_avoid = Vector3.ZERO
	_stop_saw()


## At most one route search every few physics ticks, shared by every robot.
static func _claim_path() -> bool:
	var frame := Engine.get_physics_frames()
	if frame < _next_path_frame:
		return false
	_next_path_frame = frame + PATH_FRAME_GAP
	return true


func _think() -> void:
	var p := Game.player
	if p == null or p.dead:
		has_los = false
		return
	var dist: float = global_position.distance_to(p.global_position)
	var space := get_world_3d().direct_space_state
	var had_los := has_los
	if (not alerted and dist > cfg["sight"]) or (p.is_cloaked() and dist > CLOAKED_PLAYER_RANGE):
		has_los = false
	else:
		has_los = space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, p.global_position, Game.WORLD)).is_empty()
	if has_los and not had_los:
		_reaction = float(cfg["react"]) * randf_range(0.85, 1.2) * Game.diff("react")
	elif had_los and not has_los:
		# A half-built rail charge doesn't keep: it would fire the instant the ship reappears.
		_rail_charge = 0.0
		_stop_saw()
	if has_los and dist < cfg["sight"]:
		alert()
	if not alerted:
		return
	if has_los:
		last_seen = p.global_position
	_sense_neighbours()
	_avoid = Vector3.ZERO
	if velocity.length_squared() > 4.0:
		var look := velocity.normalized() * (float(cfg["radius"]) + 8.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + look, Game.WORLD))
		if not hit.is_empty():
			_avoid = hit.normal
	if not _uses_tactics():
		_think_simple(p, dist)
		return
	# Lost the trail: too far to keep hunting, so it heads back to its post.
	if not has_los and dist > FORGET_RANGE and mode != "retreat":
		_stand_down()
		return
	_check_dodge(p)
	_update_mode(p)
	if _want_path and _claim_path():
		_want_path = false
		_path = _route_to(_goal)
		_path_i = 0
		if _path.is_empty() and mode == "hunt":
			_begin_search()


## Bosses keep the old, single-minded chase.
func _think_simple(p: Player, _dist: float) -> void:
	_path_cd -= 1.0
	if not has_los and _path_cd <= 0.0 and _claim_path():
		_path_cd = 4.0
		_path = Game.level.find_path(global_position, p.global_position)
		_path_i = 0


## One pass over the robots: keep some distance, and note where the pack is
## relative to the ship so flankers know which side is already covered.
func _sense_neighbours() -> void:
	_refresh_roster()
	_separation = Vector3.ZERO
	_pack_dir = Vector3.ZERO
	_pack_count = 0
	var here := global_position
	var near_sq := SEPARATION_RANGE * SEPARATION_RANGE
	for other in _roster_pos:
		var away := here - other
		var dsq := away.length_squared()
		# Its own entry is at distance zero and drops out here.
		if dsq > 0.0001 and dsq < near_sq:
			var d := sqrt(dsq)
			_separation += away / d * (1.0 - d / SEPARATION_RANGE)
	# Only flankers use the pack's bearing, and they are never in the pack list themselves.
	if flank_side == 0:
		return
	var at: Vector3 = last_seen
	var pack_sq := PACK_RANGE * PACK_RANGE
	for other in _pack_pos:
		if here.distance_squared_to(other) < pack_sq:
			var from_target := other - at
			if from_target.length_squared() > 1.0:
				_pack_dir += from_target.normalized()
				_pack_count += 1
	if _pack_count > 0:
		_pack_dir = _pack_dir.normalized()


## Rebuilds the shared position lists at most every ROSTER_FRAMES physics frames.
static func _refresh_roster() -> void:
	var frame := Engine.get_physics_frames()
	if frame - _roster_frame < ROSTER_FRAMES and frame >= _roster_frame:
		return
	_roster_frame = frame
	_roster_pos.resize(_all.size())
	var packed := 0
	for r in _all:
		if r.alerted and r.flank_side == 0 and not r._dead:
			packed += 1
	_pack_pos.resize(packed)
	var i := 0
	var j := 0
	for r in _all:
		var at := r.global_position
		_roster_pos[i] = at
		i += 1
		if r.alerted and r.flank_side == 0 and not r._dead:
			_pack_pos[j] = at
			j += 1


func _update_mode(p: Player) -> void:
	if mode == "retreat":
		if _retreat_left <= 0.0 or hp_ratio() > 0.65:
			mode = "fight" if has_los else "hunt"
			_begin_hunt()
		return
	if _should_retreat():
		_begin_retreat(p)
		return
	if has_los:
		mode = "fight"
		_want_path = false
		return
	match mode:
		"fight", "idle":
			mode = "hunt"
			_begin_hunt()
		"hunt":
			if not _want_path and (_path_i >= _path.size() or global_position.distance_to(_goal) < 9.0):
				_begin_search()
		"search":
			if _search_left <= 0.0:
				_stand_down()
			elif not _want_path and _path_i >= _path.size():
				_next_search_spot()


## Head for the last sighting. The search clock starts now.
func _begin_hunt() -> void:
	_goal = last_seen
	_want_path = true
	_search_left = SEARCH_TIME * lerpf(0.35, 1.0, tactics())


func _begin_search() -> void:
	mode = "search"
	_next_search_spot()


## Somewhere near the last sighting that hasn't been looked at yet.
func _next_search_spot() -> void:
	var astar: AStar3D = Game.level.astar
	var offset := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * SEARCH_RADIUS
	var id := astar.get_closest_point(last_seen + offset)
	if id < 0:
		_stand_down()
		return
	_goal = astar.get_point_position(id)
	_want_path = true


func _should_retreat() -> bool:
	if _retreats_left <= 0 or hp_ratio() > RETREAT_HP or cfg.has("explode"):
		return false
	_retreats_left -= 1
	return randf() < tactics() * 0.85


## Falls back to a healer, a healthy friend or somewhere the ship can't see.
func _begin_retreat(p: Player) -> void:
	mode = "retreat"
	# One fall-back per robot, however the retreat was started.
	_retreats_left = 0
	_retreat_left = RETREAT_TIME * randf_range(0.8, 1.25)
	var best: Node3D = null
	var best_score := INF
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not other is Robot or other is Boss:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > 120.0 or other.hp_ratio() < 0.5:
			continue
		# Further from the ship than this robot is, or it's running toward the fight.
		if other.global_position.distance_to(p.global_position) < global_position.distance_to(p.global_position):
			continue
		var score := d - (80.0 if other.cfg.has("heal") else 0.0)
		if score < best_score:
			best_score = score
			best = other
	_goal = best.global_position if best != null else _hiding_spot(p)
	_want_path = true
	Sfx.play("robot_alert_small" if float(cfg["radius"]) < 2.2 else "robot_alert_mid", global_position, -2.0, 0.75)


func _hiding_spot(p: Player) -> Vector3:
	var astar: AStar3D = Game.level.astar
	var space := get_world_3d().direct_space_state
	var best := global_position + (global_position - p.global_position).normalized() * 30.0
	var best_score := -INF
	for i in RETREAT_HIDE_SAMPLES:
		var offset := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized() * randf_range(20.0, 45.0)
		var id := astar.get_closest_point(global_position + offset)
		if id < 0:
			continue
		var spot := astar.get_point_position(id)
		var hidden := not space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, p.global_position, Game.WORLD)).is_empty()
		var score := spot.distance_to(p.global_position) + (60.0 if hidden else 0.0)
		if score > best_score:
			best_score = score
			best = spot
	return best


## Flankers plan around the direct route, so they arrive from another tunnel if there is one.
func _route_to(goal: Vector3) -> PackedVector3Array:
	var level: Node3D = Game.level
	if flank_side == 0 or _pack_count == 0 or mode == "retreat":
		return level.find_path(global_position, goal)
	var astar: AStar3D = level.astar
	var a := astar.get_closest_point(global_position)
	var b := astar.get_closest_point(goal)
	if a < 0 or b < 0:
		return PackedVector3Array()
	var direct := astar.get_id_path(a, b)
	if direct.size() < 6:
		return _points_of(astar, direct)
	# Lava cells already cost more, so restore each cell's own weight afterwards.
	var weights := PackedFloat32Array()
	weights.resize(direct.size())
	for i in range(2, direct.size() - 2):
		weights[i] = astar.get_point_weight_scale(direct[i])
		astar.set_point_weight_scale(direct[i], weights[i] * FLANK_WEIGHT)
	var alt := astar.get_point_path(a, b)
	for i in range(2, direct.size() - 2):
		astar.set_point_weight_scale(direct[i], weights[i])
	if alt.size() > direct.size() * FLANK_DETOUR:
		return _points_of(astar, direct)
	return alt


## The route a search already found, without searching again.
static func _points_of(astar: AStar3D, ids: PackedInt64Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(ids.size())
	for i in ids.size():
		points[i] = astar.get_point_position(ids[i])
	return points


## Sidesteps a missile about to land, or a rail lance being lined up on it.
func _check_dodge(p: Player) -> void:
	if _dodge_cd > 0.0 or _stunned > 0.0:
		return
	var skill := agility() * tactics()
	if skill <= 0.0:
		return
	for m in _threats:
		if not is_instance_valid(m):
			continue
		var to_me: Vector3 = global_position - m.global_position
		var d := to_me.length()
		var speed: float = m.velocity.length()
		if d > THREAT_RANGE or speed < 1.0 or d / speed > THREAT_TIME:
			continue
		if m.velocity.normalized().dot(to_me / maxf(d, 0.01)) < 0.85:
			continue
		_dodge_cd = DODGE_COOLDOWN
		if randf() < skill:
			_jink(m.velocity.normalized())
		return
	if has_los and p.rail_charge > 0.55:
		var aim: Vector3 = (p.aim_point() - p.global_position).normalized()
		var to_robot := (global_position - p.global_position).normalized()
		if aim.dot(to_robot) > 0.995:
			_dodge_cd = DODGE_COOLDOWN
			if randf() < skill * 0.8:
				_jink(to_robot)


## A sharp shove across the line of fire, away from any wall in the way.
func _jink(threat_dir: Vector3) -> void:
	var side := threat_dir.cross(Vector3.UP)
	if side.length_squared() < 0.1:
		side = threat_dir.cross(Vector3.RIGHT)
	side = (side.normalized() * (1.0 if randf() < 0.5 else -1.0) + Vector3(0, randf_range(-0.4, 0.4), 0)).normalized()
	var reach := float(cfg["radius"]) + 7.0
	var space := get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, global_position + side * reach, Game.WORLD)).is_empty():
		side = -side
	velocity += side * float(cfg["speed"]) * 1.15


func _physics_process(delta: float) -> void:
	_reveal -= delta
	if _can_cloak:
		var cloaked := _is_cloaked()
		if cloaked != _was_cloaked:
			_was_cloaked = cloaked
			Sfx.play("cloak" if cloaked else "uncloak", global_position, 0.0)
			_model.visible = not cloaked
	if _wake_left > 0.0:
		_wake_left -= delta
		if _wake_left <= 0.0:
			alert()
	if _dormant():
		_think_cd -= delta
		if _think_cd <= 0.0:
			_think_cd += DORMANT_THINK_GAP
			_think()
		return
	_spin(delta)
	_tick_timers(delta)
	if _stunned > 0.0:
		_stunned -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		move_and_slide()
		return
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = _think_gap()
		_think()
	if _idle_in_place():
		# Hovering at its post: the bob is drawn on the model, so no physics is needed.
		_idle_bob = sin(Time.get_ticks_msec() * 0.001 + _phase) * 1.2
		_model.position.y = _idle_bob
		return
	if _idle_bob != 0.0:
		_idle_bob = 0.0
		_model.position.y = 0.0
	var desired := Vector3.ZERO
	var look_dir := -global_basis.z
	var speed: float = cfg["speed"]
	var p := Game.player
	if alerted and p != null and not p.dead:
		var to: Vector3 = p.global_position - global_position
		if mode == "retreat":
			desired = _follow_path(speed * 1.1) if _path_i < _path.size() else Vector3.ZERO
			if desired.length_squared() > 0.1:
				look_dir = desired.normalized()
			elif has_los:
				look_dir = to.normalized()
			if has_los and to.length() < 30.0:
				_attack(delta, to)
			hp = minf(hp + max_hp() * RETREAT_REGEN * tactics() * delta, maxf(hp, max_hp() * RETREAT_REGEN_CAP))
		elif has_los:
			look_dir = to.normalized()
			desired = _combat_move(to, speed)
			_attack(delta, to)
			_use_ability(delta, to)
		elif _path_i < _path.size():
			desired = _follow_path(speed)
			if desired.length_squared() > 0.1:
				look_dir = desired.normalized()
		elif last_seen != Vector3.ZERO:
			look_dir = (last_seen - global_position).normalized()
	elif _returning and _needs_home_path:
		if _claim_path():
			_needs_home_path = false
			_path = Game.level.find_path(global_position, home)
			_path_i = 0
	elif _returning and _path_i < _path.size():
		desired = _follow_path(speed)
		if desired.length_squared() > 0.1:
			look_dir = desired.normalized()
		if _path_i >= _path.size():
			_returning = false
			mode = "idle"
	elif _returning:
		_returning = false
		mode = "idle"
	desired += (_separation * 0.8 + _avoid * 1.0) * speed
	velocity = velocity.move_toward(desired, float(cfg["accel"]) * delta)
	var step := delta
	var hidden := _half_rate()
	# Unseen robots only steer around each other; pushing through a crowd costs real time.
	var mask := HIDDEN_MASK if hidden else FULL_MASK
	if collision_mask != mask:
		collision_mask = mask
	if hidden:
		# Out of the ship's sight: collide every other frame, covering two frames' travel.
		if (Engine.get_physics_frames() + _parity) % 2 != 0:
			return
		step = delta * 2.0
		velocity *= 2.0
		move_and_slide()
		velocity *= 0.5
	else:
		move_and_slide()
	_turn_to(look_dir, step)


func _tick_timers(delta: float) -> void:
	_dodge_cd -= delta
	_under_fire -= delta
	if mode == "search" or mode == "hunt":
		_search_left -= delta
	if mode == "retreat":
		_retreat_left -= delta
		# Thinking runs on a gap; a robot whose nerve has returned shouldn't wait for it.
		if _retreat_left <= 0.0:
			_think_cd = 0.0
	if _help_left > 0.0:
		_help_left -= delta
		if _help_left <= 0.0 and alerted:
			_call_for_help()


## Out of sight and far from the ship, a robot can look around less often.
func _think_gap() -> float:
	if alerted and not has_los and Game.player != null and global_position.distance_squared_to(Game.player.global_position) > FAR_THINK_RANGE * FAR_THINK_RANGE:
		return FAR_THINK_GAP
	return THINK_GAP


## Movement nobody can see doesn't need every physics frame.
func _half_rate() -> bool:
	if has_los or not _uses_tactics() or Game.player == null:
		return false
	return global_position.distance_squared_to(Game.player.global_position) > HALF_RATE_RANGE * HALF_RATE_RANGE


## Asleep at its post with nothing pushing it: hovering needs no collision checks.
func _idle_in_place() -> bool:
	return not alerted and not _returning and velocity.length_squared() < 0.01


## A sleeping robot far from the ship needs no physics at all, only a periodic look.
func _dormant() -> bool:
	if alerted or _returning or _stunned > 0.0 or _wake_left > 0.0 or Game.player == null:
		return false
	return global_position.distance_squared_to(Game.player.global_position) > DORMANT_RANGE * DORMANT_RANGE


func _combat_move(to: Vector3, speed: float) -> Vector3:
	var around := _flank_push(to)
	if _rushes():
		return (to.normalized() + around * 0.7).normalized() * speed
	var d := to.length()
	var range_err := clampf((d - float(cfg["ideal"])) / maxf(float(cfg["ideal"]), 1.0), -1.0, 1.0)
	var side := to.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	# Weaves harder for a moment after being hit.
	var jitter := 0.65 + (0.45 * agility() * tactics() if _under_fire > 0.0 else 0.0)
	var weave := side * sin(Time.get_ticks_msec() * 0.0011 + _phase) + side.cross(to.normalized()) * cos(Time.get_ticks_msec() * 0.0008 + _phase) * 0.6
	return to.normalized() * range_err * speed + weave * speed * jitter + around * speed * 0.75


## A flanker that's on the same side of the ship as the rest of the pack moves around it.
func _flank_push(to: Vector3) -> Vector3:
	if flank_side == 0 or _pack_count == 0:
		return Vector3.ZERO
	var from_ship := -to.normalized()
	if from_ship.dot(_pack_dir) < 0.35:
		return Vector3.ZERO
	var around := _pack_dir.cross(Vector3.UP)
	if around.length_squared() < 0.1:
		around = _pack_dir.cross(Vector3.RIGHT)
	return around.normalized() * float(flank_side)


func _rushes() -> bool:
	return cfg.has("melee") or cfg.has("explode")


func _follow_path(speed: float) -> Vector3:
	var wp := _path[_path_i]
	if global_position.distance_to(wp) < 7.0:
		_path_i += 1
	return (wp - global_position).normalized() * speed


func _turn_to(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	# Already facing that way (to within about a degree): nothing to turn.
	if global_basis.z.dot(dir) < -0.99985 * dir.length():
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.97 else Vector3.BACK
	var goal := Basis.looking_at(dir, up)
	global_basis = global_basis.orthonormalized().slerp(goal, 1.0 - exp(-float(cfg["turn"]) * delta)).orthonormalized()

func _attack(delta: float, to: Vector3) -> void:
	if cfg.has("melee"):
		_melee(delta, to)
		return
	if cfg.has("explode"):
		if not _armed_sound and to.length() < CINDER_ARM_RANGE:
			_armed_sound = true
			Sfx.play("cinder_arm", global_position, 3.0)
		if to.length() < EXPLODE_RANGE:
			Weapons.splash_player(global_position, EXPLODE_BLAST, cfg["explode"], self)
			# Blowing itself up isn't a kill the player earned.
			_die(false)
		return
	# A beat to react after spotting the player, so peeking a corner is survivable.
	if _reaction > 0.0:
		_reaction -= delta
		return
	_fire_cd -= delta
	_missile_cd -= delta
	if update_rail_charge(delta, cfg.get("dmg", 0.0)):
		return
	var forward := -global_basis.z
	if forward.dot(to.normalized()) < 0.9:
		return
	if _fire_cd <= 0.0:
		_fire_cd = cfg["fire"] * randf_range(0.8, 1.25) * Game.diff("fire")
		_side = 1 - _side
		if cfg.get("weapon", "") == "rail":
			begin_rail_charge()
		else:
			_shoot(_muzzles[_side].global_position)
	if cfg.has("missile") and _missile_cd <= 0.0:
		_missile_cd = cfg["missile"]
		for i in int(cfg.get("salvo", 1)):
			var offset := Vector3(randf_range(-3, 3), 3.0 + randf_range(-1, 1), randf_range(-3, 3))
			Missile.launch(global_position + forward * 5.0 + offset, forward, Game.player, Game.WORLD | Game.PLAYER, false, 42.0, 22.0)


## A rail shot is instant, so it gets a visible sight line and a charge-up first.
func begin_rail_charge() -> void:
	_rail_charge = RAIL_WARNING
	_sight_cd = 0.0
	Sfx.play("rail_charge", global_position, 4.0)


## True while charging. Follows the player until the last moment, then commits.
func update_rail_charge(delta: float, damage: float) -> bool:
	if _rail_charge <= 0.0:
		return false
	_rail_charge -= delta
	_rail_muzzle = _muzzles[_side].global_position
	if _rail_charge > RAIL_LOCK_TIME and Game.player != null:
		_rail_aim = (Game.player.global_position - _rail_muzzle).normalized()
	_sight_cd -= delta
	if _sight_cd <= 0.0:
		_sight_cd = 0.05
		Weapons.beam(_rail_muzzle, _rail_muzzle + _rail_aim * Weapons.RAIL_RANGE * 0.5, SIGHT_COLOR if _rail_charge > RAIL_LOCK_TIME else Color.WHITE, 0.09)
	if _rail_charge <= 0.0:
		Weapons.rail(_rail_muzzle, _rail_aim, damage, Game.WORLD | Game.PLAYER, self)
	return true


func _melee(delta: float, to: Vector3) -> void:
	_melee_cd -= delta
	if _saw == null:
		_saw = Sfx.positional_loop("robot_saw", self, 12.0, -3.0)
		_saw.pitch_scale = randf_range(0.85, 1.15) * (0.7 if float(cfg["radius"]) > 3.0 else 1.0)
	elif not _saw.playing:
		_saw.play()
	if _melee_cd > 0.0 or to.length() > float(cfg["radius"]) + Player.RADIUS + 1.5:
		return
	_melee_cd = MELEE_INTERVAL
	var p: Player = Game.player
	p.take_damage(cfg["melee"], p.global_position, self)
	p.velocity += to.normalized() * MELEE_KNOCKBACK
	Fx.sparks(p.global_position - to.normalized() * Player.RADIUS, -to.normalized(), Weapons.SLASH_COLOR)
	Sfx.play("melee_hit", global_position, 3.0, randf_range(0.9, 1.1))


## The blades spin down once there's nothing to cut.
func _stop_saw() -> void:
	if _saw != null and _saw.playing:
		_saw.stop()


func _shoot(at: Vector3) -> void:
	var p: Player = Game.player
	var aim := (p.global_position - at).normalized()
	var mask := Game.WORLD | Game.PLAYER
	var damage: float = cfg["dmg"]
	match cfg.get("weapon", "laser"):
		"arc":
			Weapons.arc(at, aim, damage, false, self)
		"rail":
			Weapons.rail(at, aim, damage, mask, self)
		"prism":
			var w: Dictionary = Weapons.PRIMARY["prism"]
			Bolt.launch(at, aim, w["speed"], damage, Weapons.PRISM_COLOR, mask, 1.0, self, w["bounces"])
			Sfx.play("prism", at, -2.0, 0.8)
		"singularity":
			Singularity.launch(at, aim, damage, false)
		_:
			var travel := at.distance_to(p.global_position) / float(cfg["bolt"])
			var lead: Vector3 = p.global_position + p.velocity * travel * 0.75
			var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.4
			Bolt.launch(at, (lead + spread - at).normalized(), cfg["bolt"], damage, Bolt.color_for_damage(damage), mask, 1.2, self)
			Sfx.play(Sfx.robot_shot(kind, _shot_sound(damage)), at, -2.0, randf_range(0.9, 1.12))


func _shot_sound(damage: float) -> String:
	if damage >= 20.0:
		return "enemy_shot_heavy"
	return "enemy_shot_fast" if float(cfg["fire"]) <= 0.6 else "enemy_shot"


func _use_ability(delta: float, _to: Vector3) -> void:
	_ability_cd -= delta
	if cfg.has("heal"):
		_heal_allies(delta)
	if _ability_cd > 0.0:
		return
	if cfg.has("spawns"):
		_ability_cd = cfg["spawns"]
		_brood = _brood.filter(func(b): return is_instance_valid(b))
		if _brood.size() < MAX_BROOD:
			# Brood refills forever, so it is worth nothing: no score, kill or drop.
			_brood.append(Game.level.spawn_robot("tick", global_position - global_basis.z * 7.0, true, false))
			Sfx.play("hive_spawn", global_position, 2.0)
	elif cfg.has("mines"):
		_ability_cd = cfg["mines"]
		var dropped := Mine.spawn("prox", global_position + global_basis.z * 5.0)
		dropped.life = 30.0
		Sfx.play("mine_drop", global_position, 2.0)
	elif cfg.has("blink"):
		_ability_cd = cfg["blink"]
		_blink()


## Runs on the think beat rather than every frame; the repair is scaled to the time since.
func _heal_allies(delta: float) -> void:
	_heal_time += delta
	if _heal_time < THINK_GAP:
		return
	var elapsed := _heal_time
	_heal_time = 0.0
	var range_sq := HEAL_RANGE * HEAL_RANGE
	for other in _all:
		if other != self and not other is Boss and not other._dead and other.hp < other.max_hp() and other.global_position.distance_squared_to(global_position) < range_sq:
			other.hp = minf(other.max_hp(), other.hp + float(cfg["heal"]) * elapsed)
			if randf() < minf(1.0, elapsed * 6.0):
				Weapons.beam(global_position, other.global_position, Color(0.3, 1.0, 0.45), 0.14)
				Sfx.play("heal", global_position, -4.0, randf_range(0.95, 1.1))


func _blink() -> void:
	var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * BLINK_RANGE
	var id: int = Game.level.astar.get_closest_point(global_position + offset)
	if id < 0:
		return
	Fx.sparks(global_position, Vector3.UP, Color(0.7, 0.5, 1.0))
	Sfx.play("blink", global_position, 0.0, randf_range(0.9, 1.1))
	global_position = Game.level.astar.get_point_position(id)
	Fx.sparks(global_position, Vector3.UP, Color(0.7, 0.5, 1.0))


func take_damage(amount: float, _at: Vector3, source: Object) -> void:
	if _dead:
		return
	hp -= amount
	_reveal = CLOAK_REVEAL_TIME
	var by_player: bool = source == Game.player or (source is Missile and source.from_player)
	if by_player:
		Game.enemy_hit.emit(hp <= 0.0)
	if by_player and Game.player != null:
		# Being shot gives away roughly where the ship is, even without seeing it.
		if not has_los:
			last_seen = Game.player.global_position
		_under_fire = UNDER_FIRE_TIME
		if _dodge_cd <= 0.0 and _uses_tactics() and not source is Missile and randf() < agility() * tactics() * JINK_UNDER_FIRE:
			_dodge_cd = DODGE_COOLDOWN
			_jink((global_position - Game.player.global_position).normalized())
	if not alerted:
		alert()
		# Anything right beside it hears the hit at once; the rest get the shout.
		for other in get_tree().get_nodes_in_group("enemy"):
			if other is Robot and other != self and not other.alerted and other.global_position.distance_to(global_position) < HELP_HEAR_RANGE:
				other.hear_call(last_seen, 0.0, _call_range * RELAY_SHARE)
	if hp <= 0.0:
		_die()


## credit is false when the player didn't destroy it (a kamikaze blowing itself up).
func _die(credit := true) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemy")
	_all.erase(self)
	_stop_saw()
	credit = credit and bounty
	if credit:
		Game.add_kill(cfg["score"])
	Fx.explosion(global_position, cfg["boom"], cfg["boom"] > 7.0)
	if credit and randf() < (1.0 if cfg["boom"] > 7.0 else 0.28):
		var drop: String = ["energy", "shield", "energy", "ammo"][randi() % 4]
		Game.level.spawn_pickup(drop, global_position)
	queue_free()

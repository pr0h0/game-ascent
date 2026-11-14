class_name Weapons
extends RefCounted
## Every weapon's numbers and hit logic. Robots call the same functions as the
## player, so an enemy's arc or rail shot is exactly the player's.

const ARC_COLOR := Color(0.45, 0.9, 1.0)
const RAIL_COLOR := Color(0.55, 0.65, 1.0)
const PRISM_COLOR := Color(0.6, 1.0, 0.92)
const SLASH_COLOR := Color(1.0, 0.55, 0.2)
const ARC_RANGE := 60.0
const ARC_JUMP_RANGE := 30.0
const ARC_FALLOFF := 0.7
const RAIL_RANGE := 500.0
const RAIL_MIN_DAMAGE := 40.0
const RAIL_MAX_DAMAGE := 140.0
const RAIL_CHARGE_TIME := 1.5
const CUTTER_RANGE := 15.0
const SWARM_COUNT := 8
const SWARM_DAMAGE := 25.0
const CLUSTER_BOMBLETS := 10
const CLUSTER_BOMBLET_DAMAGE := 15.0
const EMP_RADIUS := 35.0
const EMP_STUN := 5.0

const SLOTS := ["laser", "cutter", "arc", "rail", "prism", "singularity"]
const PRIMARY := {
	"laser": {"name": "PULSE CANNONS", "interval": 0.11, "energy": 0.8},
	"cutter": {"name": "PLASMA CUTTER", "interval": 0.4, "energy": 0.0, "damage": 55.0},
	"arc": {"name": "ARC CASTER", "interval": 0.45, "energy": 2.5, "damage": 18.0, "jumps": 4},
	"rail": {"name": "RAIL LANCE", "interval": 0.3, "energy": 12.0},
	"prism": {"name": "PRISM REPEATER", "interval": 0.143, "energy": 0.7, "damage": 10.0, "speed": 200.0, "bounces": 3},
	"singularity": {"name": "SINGULARITY", "interval": 2.5, "energy": 25.0, "damage": 150.0},
}
const ORDER := ["homing", "cluster", "swarm", "bunker", "emp", "mine"]
const SECONDARY := {
	"homing": {"name": "MSL", "cap": 12, "gain": 3, "damage": 90.0},
	"cluster": {"name": "CLUSTER", "cap": 6, "gain": 2, "damage": 20.0},
	"swarm": {"name": "SWARM", "cap": 4, "gain": 1, "damage": 25.0},
	"bunker": {"name": "BUSTER", "cap": 3, "gain": 1, "damage": 320.0, "speed": 55.0},
	"emp": {"name": "EMP", "cap": 4, "gain": 1, "damage": 0.0},
	"mine": {"name": "MINE", "cap": 8, "gain": 3, "damage": 120.0},
}

## Damage grows with the ship's laser level (Game.laser_level(), raised by the
## upgrade_laser_N pickups). The pulse cannon's bolt runs through Player.LASER_DAMAGE (13 / 21 / 30 / 42); every other primary used to stay at its
## level-1 number, so by the late mines the cutter, arc, rail, prism and singularity hit
## like toys next to a magenta cannon. Each primary now gets the same ratio the cannon gets
## (1.00 / 1.62 / 2.31 / 3.23), which keeps the weapons' level-1 balance against each other
## at every laser level.
static func power_mult(level := 0) -> float:
	return float(Player.LASER_DAMAGE[_laser_tier(level)]) / float(Player.LASER_DAMAGE[0])


static func _laser_tier(level: int) -> int:
	return clampi((level if level > 0 else Game.laser_level()) - 1, 0, Player.LASER_DAMAGE.size() - 1)


## Robot armour doesn't grow per level (only the difficulty scales it), but the late
## rosters trade 34 HP ticks for 300-420 HP drillbacks, bulwarks, sieges and hives. Missiles
## are scarce ammo with their own jobs (burst, splash, reach), so they get a gentler curve,
## the square root of the primaries' ratio (1.00 / 1.27 / 1.52 / 1.80): a homing missile
## still takes a real bite out of a late hauler without a rack of them replacing the guns.
static func missile_mult(level := 0) -> float:
	return sqrt(power_mult(level))


## A primary's damage per shot (per bolt, slash, arc strike or burst) at a laser level;
## 0 means the ship's current one. The rail lance's is its full charge.
static func primary_damage(weapon: String, level := 0) -> float:
	match weapon:
		"laser":
			return float(Player.LASER_DAMAGE[_laser_tier(level)])
		"rail":
			return rail_damage(1.0, level)
	return float(PRIMARY[weapon]["damage"]) * power_mult(level)


static func rail_damage(charge: float, level := 0) -> float:
	return lerpf(RAIL_MIN_DAMAGE, RAIL_MAX_DAMAGE, charge) * power_mult(level)


## A secondary's damage per hit at a laser level; 0 means the ship's current one. The swarm's
## is per micro-missile and the cluster's per bomblet, the parts that do the work.
static func secondary_damage(weapon: String, level := 0) -> float:
	match weapon:
		"swarm":
			return SWARM_DAMAGE * missile_mult(level)
		"cluster_bomblet":
			return CLUSTER_BOMBLET_DAMAGE * missile_mult(level)
	return float(SECONDARY[weapon]["damage"]) * missile_mult(level)


static var _box: BoxMesh
static var _beam_mats: Dictionary = {}


static func beam(from: Vector3, to: Vector3, color: Color, width: float) -> void:
	var world: Node3D = Game.level
	var length := from.distance_to(to)
	if world == null or length < 0.05:
		return
	if _box == null:
		_box = BoxMesh.new()
	var key := color.to_html()
	if not _beam_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0)
		_beam_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.material_override = _beam_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = from.lerp(to, 0.5)
	var dir := (to - from) / length
	mi.look_at(mi.global_position + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	mi.scale = Vector3(width, width, length)
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3(0.0, 0.0, length), 0.16)
	t.tween_callback(mi.queue_free)


static func _jagged(from: Vector3, to: Vector3, color: Color) -> void:
	var previous := from
	var side := (to - from).cross(Vector3(0.3, 1.0, 0.2)).normalized()
	var up := side.cross((to - from).normalized())
	for i in range(1, 7):
		var point := from.lerp(to, float(i) / 6.0)
		if i < 6:
			point += side * randf_range(-1.6, 1.6) + up * randf_range(-1.6, 1.6)
		beam(previous, point, color, 0.22)
		previous = point


## Where to aim at something; most targets are simply at their origin.
static func target_point(target: Node3D) -> Vector3:
	return target.body_center() if target.has_method("body_center") else target.global_position


static func _clear_line(a: Vector3, b: Vector3, ignore: Object) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.WORLD)
	if ignore is CollisionObject3D:
		q.exclude = [ignore.get_rid()]
	return Game.level.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


static func _hostiles(from_player: bool) -> Array:
	if not from_player:
		return [Game.player] if Game.player != null and not Game.player.dead else []
	return Game.level.get_tree().get_nodes_in_group("enemy")


## Lightning: strikes the best target ahead, then jumps to whatever is nearest.
static func arc(origin: Vector3, direction: Vector3, damage: float, from_player: bool, shooter: Object) -> void:
	Sfx.play("arc", origin, -2.0, randf_range(0.92, 1.1))
	var struck: Array = []
	var from := origin
	var power := damage
	var hostiles := _hostiles(from_player)
	for jump in int(PRIMARY["arc"]["jumps"]):
		var best: Node3D = null
		var best_score := INF
		for t in hostiles:
			if t in struck or not is_instance_valid(t):
				continue
			var to: Vector3 = t.global_position - from
			var reach := ARC_RANGE if jump == 0 else ARC_JUMP_RANGE
			if to.length() > reach or (jump == 0 and direction.dot(to.normalized()) < 0.75):
				continue
			if to.length() < best_score and _clear_line(from, target_point(t), t):
				best = t
				best_score = to.length()
		if best == null:
			break
		_jagged(from, best.global_position, ARC_COLOR)
		best.take_damage(power, best.global_position, shooter)
		struck.append(best)
		from = best.global_position
		power *= ARC_FALLOFF
	if struck.is_empty():
		_jagged(origin, origin + direction * 30.0, ARC_COLOR)


## A slug through everything in line, stopped only by solid rock.
static func rail(origin: Vector3, direction: Vector3, damage: float, mask: int, shooter: Object) -> void:
	var space: PhysicsDirectSpaceState3D = Game.level.get_world_3d().direct_space_state
	var end := origin + direction * RAIL_RANGE
	var skip: Array[RID] = []
	if shooter is CollisionObject3D:
		skip.append(shooter.get_rid())
	var stop := end
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(origin, end, mask)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if hit.collider.has_method("take_damage"):
			hit.collider.take_damage(damage, hit.position, shooter)
			Fx.sparks(hit.position, hit.normal, RAIL_COLOR)
		if hit.collider.collision_layer & Game.WORLD:
			stop = hit.position
			break
		skip.append(hit.collider.get_rid())
	beam(origin, stop, RAIL_COLOR, 0.42)
	Sfx.play("rail_fire", origin, 1.0, randf_range(0.97, 1.03))


## A close-range cutting sweep across everything in front of the ship.
static func slash(origin: Vector3, forward: Vector3, right: Vector3, damage: float, shooter: Object) -> void:
	Sfx.play("cutter", origin, -1.0, randf_range(0.92, 1.1))
	for i in 7:
		var a := lerpf(-0.7, 0.7, float(i) / 6.0)
		beam(origin + right * sin(a) * 4.0 + forward * 3.0, origin + (forward * cos(a) + right * sin(a)) * CUTTER_RANGE, SLASH_COLOR, 0.3)
	for t in _hostiles(true):
		if not is_instance_valid(t):
			continue
		var to: Vector3 = t.global_position - origin
		if to.length() < CUTTER_RANGE + 2.0 and forward.dot(to.normalized()) > 0.5 and _clear_line(origin, target_point(t), t):
			t.take_damage(damage, t.global_position, shooter)
			Fx.sparks(t.global_position, -to.normalized(), SLASH_COLOR)


static func emp_pulse(at: Vector3) -> void:
	Fx.pulse(at, EMP_RADIUS, ARC_COLOR)
	Sfx.play("emp", at, 3.0)
	for t in _hostiles(true):
		if is_instance_valid(t) and t.has_method("stun") and t.global_position.distance_to(at) < EMP_RADIUS:
			t.stun(EMP_STUN)


## Blast damage to the player's enemies, used by cluster bomblets and mines.
static func splash_enemies(at: Vector3, radius: float, damage: float, source: Object) -> void:
	for t in _hostiles(true):
		if not is_instance_valid(t):
			continue
		var d: float = t.global_position.distance_to(at)
		if d < radius:
			t.take_damage(damage * (1.0 - d / radius), at, source)


static func splash_player(at: Vector3, radius: float, damage: float, source: Object) -> void:
	var p: Node3D = Game.player
	if p != null and not p.dead:
		var d := p.global_position.distance_to(at)
		if d < radius:
			p.take_damage(damage * (1.0 - d / radius * 0.6), at, source)

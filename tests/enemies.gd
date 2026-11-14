extends Node
## Robot tactics (calling for help, hunting, searching, falling back, dodging,
## flanking) and the three bosses (phases, weak points, announced attacks, escape).
## godot --headless --path . res://tests/enemies.tscn

const SHIP := Vector3(0, 10, 38)
## The spine is a straight tunnel north of the launch bay.
const SPINE_A := Vector3(0, 10, -20)
const SPINE_B := Vector3(0, 10, -75)

var failures := 0
var p: Player


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * Engine.physics_ticks_per_second))


func reset_ship(cloaked := true) -> void:
	p.global_position = SHIP
	p.global_basis = Basis.IDENTITY
	p.velocity = Vector3.ZERO
	p.shield = 1e6
	p._invuln = 0.0
	p.invincible_left = 0.0
	p.cloak_left = 1e6 if cloaked else 0.0


func clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.free()


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	p = Game.player
	await _spin_axes()
	await _tactics()
	await _bosses()
	await _boss_levels()
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


## Every vertex of every mesh under a part, in its robot model's frame.
func _part_points(r: Robot, part: Node3D) -> PackedVector3Array:
	var to_model := r._model.global_transform.affine_inverse()
	var meshes: Array = part.find_children("*", "MeshInstance3D", true, false)
	if part is MeshInstance3D:
		meshes.append(part)
	var out := PackedVector3Array()
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var xf: Transform3D = to_model * mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				out.append(xf * v)
	return out


func _centroid(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in pts:
		c += v
	return c / maxf(pts.size(), 1)


func _extent(pts: PackedVector3Array, dir: Vector3) -> float:
	var lo := INF
	var hi := -INF
	for v in pts:
		lo = minf(lo, v.dot(dir))
		hi = maxf(hi, v.dot(dir))
	return hi - lo


func _spin_axes() -> void:
	clear_enemies()
	# Which way each spinning part is meant to turn, in the part's frame (forward is -Z).
	var intended := {"tick": Vector3.UP, "ripper": Vector3.UP, "drillback": Vector3.FORWARD, "bulwark": Vector3.UP}
	var spinners := 0
	var at := SHIP + Vector3(0, 0, 4)
	for kind in Robot.TYPES:
		if Robot.BOSS_SCRIPTS.has(kind):
			continue
		var r: Robot = Game.level.spawn_robot(kind, at)
		var parts := r.spin_parts()
		if parts.is_empty():
			check(not intended.has(kind), "%s has the spinning part it's meant to" % kind)
			r.free()
			continue
		spinners += 1
		var axis := r.spin_axis()
		check(intended.has(kind) and absf(axis.dot(intended[kind])) > 0.999, "%s spins about %s (meant %s)" % [kind, axis, intended.get(kind)])
		var before := []
		var keep := []
		for part in parts:
			before.append(_part_points(r, part))
			keep.append(part.transform)
		r._spin(0.8 / Robot.SPIN_RATE)
		for i in parts.size():
			var part := parts[i]
			var pts: PackedVector3Array = before[i]
			var now := _part_points(r, part)
			part.transform = keep[i]
			var world_axis: Vector3 = (r._model.global_basis.inverse() * part.global_basis * axis).normalized()
			var size := 0.0
			for d in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				size = maxf(size, _extent(pts, d))
			# Turning on its own axle, a rotor's centre stays put and it stays as deep along
			# the axle as it was; about the body's centre it swings away, and about the wrong
			# axis a flat ring tilts and a drill bit tumbles.
			var drift := _centroid(now).distance_to(_centroid(pts))
			var tilt := absf(_extent(now, world_axis) - _extent(pts, world_axis))
			print("      %s %s: axis %s, size %.2f, centre %s, drift %.3f, tilt %.3f" % [kind, part.name, axis, size, _centroid(pts), drift, tilt])
			check(drift < size * 0.03 and tilt < size * 0.03, "%s's %s turns in place about its own axle" % [kind, part.name])
			# The flat rings and saws turn about their thin side, the drill bit about its length.
			var dims := [_extent(pts, Vector3.RIGHT), _extent(pts, Vector3.UP), _extent(pts, Vector3.BACK)]
			var thin := dims.find(dims.min())
			var long := dims.find(dims.max())
			var along := absf(axis[long]) > 0.999 if kind == "drillback" else absf(axis[thin]) > 0.999
			check(along, "%s's %s axle runs along its %s" % [kind, part.name, "length" if kind == "drillback" else "thin side"])
		if kind == "ripper":
			check(parts.size() == 2, "the ripper's two saws each get their own rotor")
			var hubs := parts.map(func(n): return n.position)
			check(hubs.size() == 2 and absf(hubs[0].x + hubs[1].x) < 0.05 and absf(absf(hubs[0].x) - 1.1) < 0.1, "the ripper's saws turn on hubs at either side, not the body centre (%s)" % [hubs])
		r.free()
	check(spinners == intended.size(), "every robot with a spinning part was checked (%d)" % spinners)


func _tactics() -> void:
	var level = Game.level
	clear_enemies()
	reset_ship()
	Game.difficulty = 3

	# Call for help: delayed, and only reaches allies in range.
	var caller: Robot = level.spawn_robot("lancer", SPINE_A)
	var ally: Robot = level.spawn_robot("lancer", SPINE_B)
	var far: Robot = level.spawn_robot("lancer", SPINE_A + Vector3(0, 0, -400))
	await frames(3)
	caller.alert()
	await frames(3)
	check(not ally.alerted, "an ally isn't woken the instant a fight starts")
	await seconds(4.0)
	check(ally.alerted, "a shout wakes an ally in sight down the tunnel")
	check(not far.alerted, "a shout doesn't carry across the mine")
	check(ally.last_seen.distance_to(caller.last_seen) < 1.0, "the ally is told where the ship was seen")
	clear_enemies()
	Game.difficulty = 0
	caller = level.spawn_robot("lancer", SPINE_A)
	ally = level.spawn_robot("lancer", SPINE_A + Vector3(0, 0, -70))
	await frames(3)
	caller.alert()
	await seconds(4.0)
	check(not ally.alerted, "on Recruit a shout carries less far")
	clear_enemies()
	Game.difficulty = 3

	# Hunt then search: go to the last sighting, comb the area, then give up.
	var hunter: Robot = level.spawn_robot("hornet", SPINE_B)
	await frames(3)
	hunter.last_seen = SPINE_A
	hunter.alert()
	await frames(20)
	check(hunter.mode == "hunt", "an alerted robot that can't see the ship hunts (%s)" % hunter.mode)
	var d0: float = hunter.global_position.distance_to(SPINE_A)
	await seconds(3.0)
	check(hunter.global_position.distance_to(SPINE_A) < d0 - 10.0, "the hunter heads for the last sighting")
	await seconds(4.0)
	check(hunter.mode == "search", "it searches once it gets there (%s)" % hunter.mode)
	check(hunter.alerted, "searching robots stay alert")
	hunter._search_left = 0.0
	await frames(20)
	check(hunter.mode == "return" and not hunter.alerted, "it gives up and heads home after searching")
	clear_enemies()

	# Falling back: badly hurt robots run, then come back.
	var trials := [0, 0]
	for d in [0, 3]:
		Game.difficulty = d
		var r: Robot = level.spawn_robot("lancer", SPINE_A)
		await frames(2)
		r.hp = r.max_hp() * 0.2
		for i in 60:
			r._retreats_left = 1
			if r._should_retreat():
				trials[0 if d == 0 else 1] += 1
		r.free()
	check(trials[1] > 35 and trials[0] < trials[1], "hurt robots fall back far more on Nightmare than Recruit (%d vs %d)" % [trials[1], trials[0]])
	Game.difficulty = 3
	reset_ship(false)
	var coward: Robot = level.spawn_robot("hornet", SHIP + Vector3(0, 0, -30))
	var friend: Robot = level.spawn_robot("lancer", SPINE_B)
	await frames(10)
	coward.alert()
	await frames(10)
	coward.hp = coward.max_hp() * 0.2
	coward._begin_retreat(p)
	check(coward.mode == "retreat", "a hurt robot falls back")
	check(coward._goal.distance_to(friend.global_position) < 1.0, "it falls back toward a healthy friend")
	await seconds(1.5)
	check(coward.global_position.distance_to(p.global_position) > 30.0, "it moves away from the ship")
	coward._retreat_left = 0.0
	await frames(10)
	check(coward.mode == "fight" or coward.mode == "hunt", "it comes back to the fight later (%s)" % coward.mode)
	clear_enemies()

	# Dodging: nimble robots sidestep a missile, heavy ones can't.
	reset_ship(false)
	var dodged := 0
	for i in 6:
		var target: Robot = level.spawn_robot("hornet", SHIP + Vector3(0, 0, -45))
		await frames(4)
		target.alert()
		target._reaction = 10.0
		target.set_physics_process(true)
		var at: Vector3 = target.global_position + Vector3(0, 0, 40)
		var start: Vector3 = target.global_position
		Missile.launch(at, Vector3(0, 0, -1), null, Game.WORLD | Game.ENEMY, true, 82.0, 0.0)
		await frames(30)
		if is_instance_valid(target):
			var moved: Vector3 = target.global_position - start
			if Vector2(moved.x, moved.y).length() > 3.0 or target._dodge_cd > 0.0:
				dodged += 1
			target.free()
		await frames(10)
	check(dodged >= 3, "hornets sidestep incoming missiles (%d/6)" % dodged)
	var heavy: Robot = level.spawn_robot("bulwark", SPINE_A)
	await frames(2)
	check(heavy.agility() == 0.0, "a bulwark is too heavy to dodge")
	heavy.free()

	# Flanking: some of a pack take the sides; flank routes leave the graph clean.
	clear_enemies()
	var pack: Array = []
	for i in 8:
		var r: Robot = level.spawn_robot("tick", SPINE_B + Vector3(randf_range(-3, 3), 0, -i * 6.0))
		pack.append(r)
	await frames(3)
	for r in pack:
		r.alert()
	var sides := {}
	for r in pack:
		sides[r.flank_side] = true
	check(sides.has(0) and (sides.has(1) or sides.has(-1)), "a pack splits into head-on and flanking roles %s" % str(sides.keys()))
	var flanker: Robot = pack.filter(func(r): return r.flank_side != 0)[0]
	flanker._pack_count = 3
	flanker._pack_dir = (flanker.global_position - p.global_position).normalized()
	check(flanker._flank_push(p.global_position - flanker.global_position).length() > 0.5, "a flanker bunched with the pack swings round the side")
	var astar: AStar3D = level.astar
	var route: PackedVector3Array = flanker._route_to(level.v3(level.data["start"]))
	var clean := true
	for id in astar.get_point_ids():
		if astar.get_point_weight_scale(id) != 1.0:
			clean = false
			break
	check(not route.is_empty() and clean, "flank routes plan around the direct line and restore the graph")
	clear_enemies()
	Game.difficulty = 1


func _bosses() -> void:
	var level = Game.level
	for kind_name in ["overseer", "crucible", "zero"]:
		clear_enemies()
		reset_ship(false)
		Game.reactor_down = false
		var at := Vector3(0, 10, 0)
		var boss: Boss = level.spawn_robot(kind_name, at, true) as Boss
		await frames(5)
		check(boss is Boss and boss.title() != "", "%s spawns as a boss" % kind_name)
		check(boss.phase() == 1, "%s starts in phase one" % kind_name)
		boss.hp = boss.max_hp() * 0.5
		check(boss.phase() == 2, "%s enters phase two" % kind_name)
		boss.hp = boss.max_hp() * 0.2
		check(boss.phase() == 3, "%s enters phase three" % kind_name)
		boss.hp = boss.max_hp() * 0.9
		await frames(3)
		boss.stun(5.0)
		check(boss._stunned <= Boss.STUN_LIMIT, "EMP only staggers the %s" % kind_name)
		boss._stunned = 0.0

		# A hit on an open weak point does more than one on the plating.
		var weak: Dictionary = boss.weak_points[-1]
		for w in boss.weak_points:
			w["open"] = w == weak
		var weak_at: Vector3 = weak["node"].global_position
		var plate_at: Vector3 = boss.global_position + (boss.global_position - weak_at).normalized() * float(boss.cfg["radius"])
		var hp0: float = boss.hp
		boss.take_damage(100.0, weak_at, p)
		var weak_hit: float = hp0 - boss.hp
		hp0 = boss.hp
		boss.take_damage(100.0, plate_at, p)
		var plate_hit: float = hp0 - boss.hp
		check(weak_hit > 100.0 and plate_hit < 100.0, "%s: weak point %.0f vs plating %.0f" % [kind_name, weak_hit, plate_hit])
		boss.hp = boss.max_hp() * (0.5 if kind_name == "overseer" else 0.9)

		# The special attack is announced before anything is fired.
		var seen_special := ""
		var warned := false
		var shield0 := p.shield
		boss._special_cd = 0.0
		boss._reaction = 0.0
		var vented := false
		var bared := false
		for i in 900:
			await get_tree().physics_frame
			p.global_position = SHIP
			p.velocity = Vector3.ZERO
			if boss.special != "" and seen_special == "":
				seen_special = boss.special
			if boss.special != "" and boss._special_t < boss._warning_time() * 0.8:
				warned = true
			if seen_special != "" and boss.special == "":
				vented = vented or (boss is Crucible and boss.venting())
				bared = bared or (boss is Zero and boss.core_open())
			if seen_special != "" and boss.special == "" and p.shield < shield0:
				break
		check(seen_special != "" and warned, "%s announces a special attack (%s)" % [kind_name, seen_special])
		check(p.shield < shield0, "%s attacks" % kind_name)
		if boss is Crucible:
			check(seen_special != "pour" or vented, "the Crucible vents after a pour, exposing its grates")
		if boss is Zero:
			check(seen_special != "beam" or bared, "Zero's core is bare after it fires its beam")
			# Conduits can be shot off.
			var pod: Dictionary = boss.weak_points[1]
			await frames(1)
			for i in 200:
				if float(pod["hp"]) == 0.0:
					break
				boss.take_damage(200.0, pod["node"].global_position, p)
			check(boss.conduits_lost == 1, "a conduit pod can be shot off")
			boss.hp = boss.max_hp() * 0.2
			await frames(3)
			check(boss._torn, "Zero tears open in its last phase")

		# Death starts the escape, like a reactor.
		boss.hp = 1.0
		boss.take_damage(1000.0, boss.global_position, p)
		check(Game.reactor_down, "killing the %s starts the escape" % kind_name)
		check(Game.escape_left > 0.0, "the escape clock runs after the %s" % kind_name)
		await frames(5)
		Sfx.stop_loop("alarm")
		Game.reactor_down = false
		Game.escape_left = -1.0
	clear_enemies()


## The boss levels carry their boss, with no separate reactor.
func _boss_levels() -> void:
	for pair in [[3, "crucible"], [6, "overseer"], [9, "zero"]]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.levels[pair[0]]["data"]))
		var found: Array = data["robots"].filter(func(r): return r["type"] == pair[1])
		check(found.size() == 1 and data["reactor"] == null, "%s holds the %s instead of a reactor" % [Game.levels[pair[0]]["name"], pair[1]])
	var names: Array = GalleryData.entries().map(func(e): return e["id"])
	check(names.has("crucible") and names.has("zero"), "the gallery lists the new bosses")

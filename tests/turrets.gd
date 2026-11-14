extends Node
## Everything mounted on a wall, in every level, has to be visible, lockable and hittable.
## godot --headless --path . res://tests/turrets.tscn

const STAND_OFF := 12.0

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_turret_saves"
	Game.autopilot = true
	AudioServer.set_bus_mute(0, true)
	for index in Game.levels.size():
		await _check_level(index)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _check_level(index: int) -> void:
	Game.reset_run()
	Game.level_index = index
	Game.start_missiles = Game.levels[index]["base_missiles"]
	Game.start_ammo = Game.base_ammo(index)
	Game.level_start = Game._make_snapshot()
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p: Player = Game.player
	p.invincible_left = 1e9
	var sentries: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Sentry or (e is Mine and e.kind == "tripwire"):
			sentries.append(e)
		elif not e is Reactor:
			e.queue_free()
	await get_tree().physics_frame
	var total := sentries.size()
	var seen := 0
	var locked := 0
	var cut := 0
	var arced := 0
	var bad: Array = []
	var space := level.get_viewport().get_world_3d().direct_space_state
	for s: Node3D in sentries:
		var start: Vector3 = s.body_center()
		var ray := PhysicsRayQueryParameters3D.create(start, start + s.normal * STAND_OFF, Game.WORLD)
		var hit := space.intersect_ray(ray)
		var stand: Vector3 = start + s.normal * STAND_OFF
		if not hit.is_empty():
			stand = hit.position - s.normal * 3.0
		_place(p, stand, s)
		var ok_seen: bool = p.has_line_of_sight(s)
		if ok_seen:
			seen += 1
		p._update_camera(0.0)
		p._update_lock()
		var ok_lock: bool = p.lock_target == s
		if ok_lock:
			locked += 1
		var forward: Vector3 = -p.global_basis.z
		var full: float = s.hp
		Weapons.slash(p.global_position, forward, p.global_basis.x, 1.0, p)
		var ok_cut: bool = s.hp < full
		if ok_cut:
			cut += 1
		s.hp = full
		Weapons.arc(p.global_position, forward, 1.0, true, p)
		var ok_arc: bool = s.hp < full
		if ok_arc:
			arced += 1
		s.hp = full
		if not (ok_seen and ok_lock and ok_cut and ok_arc):
			bad.append([s.get_class() if not s is Mine else "tripwire", s.global_position, s.normal, ok_seen, ok_lock, ok_cut, ok_arc])
	var label: String = Game.levels[index]["name"]
	check(seen == total, "%s: %d/%d wall targets visible" % [label, seen, total])
	check(locked == total, "%s: %d/%d wall targets lockable" % [label, locked, total])
	check(cut == total, "%s: %d/%d wall targets take cutter damage" % [label, cut, total])
	check(arced == total, "%s: %d/%d wall targets take arc damage" % [label, arced, total])
	for row in bad:
		print("   problem: ", row)
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _place(p: Player, at: Vector3, s: Node3D) -> void:
	p.global_position = at
	var dir: Vector3 = (s.body_center() - at).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.BACK
	p.global_basis = Basis.looking_at(dir, up)
	p.velocity = Vector3.ZERO

extends Node
## The equipped gun and missiles are models on the ship's hardpoints, and follow the selection.
## godot --headless --path . res://tests/loadout.tscn

var failures := 0
var p: Player


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func gun_file(i := 0) -> String:
	var g := p.loadout.gun_model(i)
	return g.scene_file_path.get_file().get_basename() if g != null else ""


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	p = Game.player
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	p.shield = 1e6
	var l := p.loadout
	check(l != null, "player has a loadout")
	check(l.muzzles.size() == 2 and l._slots.size() == 6, "two gun mounts and two three-round racks")
	check(gun_file(0) == "gun_pulse" and gun_file(1) == "gun_pulse", "starts with pulse cannons on both wing tips")
	var mount := p.ship.find_child("Mount_Gun_L", true, false) as Node3D
	check(mount != null and mount.basis.determinant() < 0.0, "left gun mount is mirrored")
	check(p._muzzles[0] == l.muzzles[0] and absf(l.muzzles[0].global_position.x - l.muzzles[1].global_position.x) > 5.0, "bolts leave from the wing-tip guns")
	check(l.muzzles[0].position.length() > 1.0, "muzzle sits at the gun's tip")

	# Switching weapons swaps the mounted model, with a short deploy.
	var before := l.gun_model(0)
	var muzzle_before := l.muzzles[0].position
	for weapon in ["cutter", "arc", "rail", "prism", "singularity"]:
		Game.upgrades.append("weapon_" + weapon)
	p.select_primary("rail")
	await frames(2)
	check(gun_file(0) == "gun_rail" and gun_file(1) == "gun_rail", "selecting the rail lance mounts it")
	check(l.gun_model(0) != before, "the old gun model is replaced")
	check(l.gun_model(0).scale.x < 0.99, "the new gun deploys rather than popping in")
	check(l.muzzles[0].position != muzzle_before, "the muzzle moves to the new barrel tip")
	await get_tree().create_timer(ShipLoadout.DEPLOY_TIME + 0.15).timeout
	check(l.gun_model(0).scale.is_equal_approx(Vector3.ONE) and l.gun_model(0).position.is_zero_approx(), "deploy settles on the mount")
	check(not is_instance_valid(before), "the old gun is gone after retracting")
	for weapon in ShipLoadout.GUNS:
		p.select_primary(weapon)
		await frames(2)
		check(gun_file(0) == ShipLoadout.GUNS[weapon], "%s shows %s" % [weapon, ShipLoadout.GUNS[weapon]])
	p.select_primary("laser")
	await frames(1)
	Game.upgrades.append("laser_3")
	await frames(1)
	var glow_ok := false
	for mesh in l.gun_model(0).find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var m := mesh.get_surface_override_material(i) as StandardMaterial3D
			if m != null and m.emission_enabled and m.emission.is_equal_approx(Player.LASER_COLORS[2]):
				glow_ok = true
	check(glow_ok, "pulse cannon glow follows the laser level")

	# The racks show the selected missile type and how many are left.
	p.ammo["homing"] = 4
	await frames(1)
	check(l.secondary == "homing" and l.visible_rounds() == 4, "four homing rounds on the racks")
	p.ammo["swarm"] = 2
	p.select_secondary("swarm")
	await frames(1)
	var r: Node3D = l._rounds[0]
	check(r != null and r.scene_file_path.ends_with("round_swarm.glb") and l.visible_rounds() == 2, "switching to swarm shows two swarm pods")
	p.ammo["swarm"] = 9
	await frames(1)
	check(l.visible_rounds() == 6, "a full rack tops out at six rounds")
	p._missile_cd = 0.0
	p.ammo["swarm"] = 1
	p.fire_missile()
	await frames(1)
	check(l.secondary == "homing" and l.visible_rounds() == 4, "firing the last swarm pod falls back to homing rounds")

	# Static displays get a stock loadout.
	var ship: Node3D = load("res://assets/models/wren9.glb").instantiate()
	add_child(ship)
	var stock := ShipLoadout.attach(ship)
	check(stock != null and stock.primary == "laser" and stock.visible_rounds() == 6, "menu ship shows pulse cannons and a full rack")
	var bare := Node3D.new()
	add_child(bare)
	check(ShipLoadout.attach(bare) == null, "a hull without mounts is left alone")

	Game.upgrades.clear()
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)

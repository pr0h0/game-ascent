extends Node
## Every story shot where robots fly out of a tunnel: steps the whole shot and checks
## each robot stays inside the mine and clear of the others on every frame.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL  " + what)


func _ready() -> void:
	var shots := 0
	for c in StoryData.CHAPTERS.size():
		var chapter: Dictionary = StoryData.CHAPTERS[c]
		for s in chapter["shots"].size():
			if chapter["shots"][s].get("stage", "") != "threat":
				continue
			shots += 1
			await _check_shot(c, s)
	check(shots >= 4, "found the threat shots (%d)" % shots)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _check_shot(c: int, s: int) -> void:
	Game.story_chapter = c
	Game.after_story = "stay"
	var cut: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(cut)
	cut.process_mode = Node.PROCESS_MODE_DISABLED
	cut.shot_index = s
	cut.state = Cutscene.State.HOLD
	cut._build_shot()
	var label := "chapter %d shot %d" % [c, s]
	print("threat shot %d:%d" % [c, s])
	var robots: Array = []
	var radii: Array[float] = []
	var kinds: Array = StoryData.CHAPTERS[c]["shots"][s]["actors"]
	for m: Array in cut._marches:
		robots.append(m[0])
	for k: String in kinds:
		radii.append(cut._actor_radius(k))
	check(robots.size() == kinds.size(), label + ": every actor marches")
	var wall_hits := 0
	var bumps := 0
	var hidden_end := 0
	while cut._shot_t < cut._shot_length:
		cut._animate(1.0 / 30.0)
		for i in robots.size():
			var a: Node3D = robots[i]
			if not a.visible:
				continue
			# The body itself must be in open cells; the tunnel is only just wider than a Bulwark.
			if not cut._fits(a.position, radii[i], 0.3):
				wall_hits += 1
				if wall_hits < 4:
					print("  wall: %s %s t=%.2f at %s" % [label, kinds[i], cut._shot_t, a.position])
			for j in range(i + 1, robots.size()):
				var b: Node3D = robots[j]
				if b.visible and a.position.distance_to(b.position) < radii[i] + radii[j]:
					bumps += 1
					if bumps < 4:
						print("  bump: %s %s/%s t=%.2f %s %s" % [label, kinds[i], kinds[j], cut._shot_t, a.position, b.position])
	for r: Node3D in robots:
		if not r.visible:
			hidden_end += 1
	check(wall_hits == 0, "%s: robots stay out of the walls (%d frames)" % [label, wall_hits])
	check(bumps == 0, "%s: robots never overlap (%d frames)" % [label, bumps])
	check(hidden_end == 0, "%s: every robot is out by the end" % label)
	for i in robots.size():
		check(cut._fits(robots[i].position, radii[i], 0.5), "%s: %s ends clear of the walls at %s" % [label, kinds[i], robots[i].position])
	cut.queue_free()
	await get_tree().process_frame

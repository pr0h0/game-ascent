extends Node
## Plays the finale with no screenshots and reports frame-time spikes.
## godot --path . res://tests/escape_perf.tscn

func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	add_child(load("res://scenes/level.tscn").instantiate())
	for i in 60:
		await get_tree().process_frame
	var p: Player = Game.player
	p.shield = 1e9
	p._invuln = 1e9
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Reactor:
			n.take_damage(1e6, n.global_position, null)
	for i in 30:
		await get_tree().process_frame
	p.global_position = Game.level.v3(Game.level.data["escape_trigger"])
	await get_tree().process_frame
	var run: EscapeRun = Game.level.get_children().filter(func(n): return n is EscapeRun)[0]
	var worst := 0.0
	var worst_at := 0.0
	var spikes := 0
	var frames := 0
	var entered_space := -1
	var last := Time.get_ticks_usec()
	while not Game.finished and frames < 4000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames += 1
		if ms > 34.0:
			spikes += 1
			print("spike %.0f ms at %.2f s (space=%s)" % [ms, run.elapsed(), run._in_space])
		if ms > worst:
			worst = ms
			worst_at = run.elapsed()
		if run._in_space and entered_space < 0:
			entered_space = frames
	print("PERF frames=%d duration=%.2f avg_fps=%.0f worst=%.0fms at %.2fs spikes=%d" % [frames, run.elapsed(), frames / run.elapsed(), worst, worst_at, spikes])
	get_tree().quit()

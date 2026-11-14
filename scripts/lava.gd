class_name Lava
extends Node3D
## Molten floors: burns the ship while it touches or skims a lava pool.
## The pools themselves are part of the level shell (material lava_<theme>); this only
## knows where they are, as 2.5 m floor quads, and checks the ship against them.

const QUAD := 2.5
## Damage per second at the surface, fading to MIN at the edge of the heat.
const BURN_AT_SURFACE := 22.0
const BURN_AT_EDGE := 4.0
const TICK := 0.2
## Quads around the ship's own that still count: its hull is 2 m across.
const REACH := 1

var heat := 3.2
## Vector2i(quad x, quad z) -> Array of surface heights (pools may be stacked).
var _quads: Dictionary = {}
var _tick := 0.0
var _burning := false
var kind := "lava"


func setup(data: Dictionary) -> void:
	heat = float(data.get("lava_heat", heat))
	for q: Array in data.get("lava", []):
		var key := Vector2i(int(q[0]), int(q[1]))
		if not _quads.has(key):
			_quads[key] = []
		_quads[key].append(float(q[2]))
	set_physics_process(not _quads.is_empty())


func has_lava() -> bool:
	return not _quads.is_empty()


## Height of a point over the nearest lava surface below it, or INF if no lava is under it.
func height_above(p: Vector3, reach := REACH) -> float:
	var qx := int(floorf(p.x / QUAD))
	var qz := int(floorf(p.z / QUAD))
	var best := INF
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var surfaces = _quads.get(Vector2i(qx + dx, qz + dz))
			if surfaces == null:
				continue
			for y: float in surfaces:
				var h := p.y - y
				# Only pools under the ship: a floor in a room overhead doesn't count.
				if h > -1.5 and h < best:
					best = h
	return best


func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var p: Player = Game.player
	if p == null or p.dead or Game.cinematic or Game.finished:
		_burning = false
		return
	var h := height_above(p.global_position)
	var burning := h < heat
	if burning:
		var closeness := clampf(1.0 - h / heat, 0.0, 1.0)
		p.take_damage(lerpf(BURN_AT_EDGE, BURN_AT_SURFACE, closeness) * TICK, p.global_position + Vector3.DOWN * 2.0, self)
		if not _burning:
			Game.say("HULL BURNING — CLIMB AWAY FROM THE LAVA", Color(1.0, 0.5, 0.2))
	_burning = burning

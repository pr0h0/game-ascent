class_name WallParts
extends RefCounted
## Places the shared wall details a level lists, one instanced batch per part and chunk.

static var _meshes: Dictionary = {}


static func _library() -> Dictionary:
	if _meshes.is_empty():
		var root: Node = load("res://assets/models/wall_parts.glb").instantiate()
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = node.mesh
			for i in mesh.get_surface_count():
				var source: Material = mesh.surface_get_material(i)
				if source != null:
					mesh.surface_set_material(i, Mats.get_material(source.resource_name))
			_meshes[String(node.name)] = mesh
		root.free()
	return _meshes


## Returns the number of details placed.
static func populate(parent: Node3D, data: Dictionary) -> int:
	var library := _library()
	var placed := 0
	var chunks: Dictionary = data.get("wall_parts", {})
	# A themed level recolours the shared rock and ore parts; one material each, so batching holds.
	var theme_id: String = str(data.get("theme", ""))
	var rock: Material = Mats.theme_rock(theme_id) if theme_id != "" else null
	var ore: Material = Mats.theme_glow(theme_id) if theme_id != "" else null
	for chunk: String in chunks:
		for part: String in chunks[chunk]:
			var flat: Array = chunks[chunk][part]
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.mesh = library[part]
			batch.instance_count = flat.size() / 12
			batch.buffer = PackedFloat32Array(flat)
			var node := MultiMeshInstance3D.new()
			node.multimesh = batch
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if rock != null and part.begins_with("boulder_"):
				node.material_override = rock
			elif ore != null and (part.begins_with("ore_") or part.begins_with("icicles_") or part.begins_with("crystals_")):
				node.material_override = ore
			parent.add_child(node)
			placed += batch.instance_count
	return placed

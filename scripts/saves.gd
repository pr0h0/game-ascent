extends Node
## Level-start snapshots. Each is its own file and is never overwritten, so the
## same level can have any number of saves from different runs.

## Version 2 added First Shift as level one; version 1 saves were all The Vein.
const VERSION := 2

var dir := "user://saves"
## list() parses every file, and menus ask several times per panel switch, so the
## result is kept until a file in the folder is added, removed or touched.
var _cache: Array[Dictionary] = []
var _cache_key := ""


func write(snapshot: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var record := snapshot.duplicate()
	record["version"] = VERSION
	record["created_unix"] = Time.get_unix_time_from_system()
	var id := _new_id()
	record["id"] = id
	var file := FileAccess.open(_path(id), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: " + _path(id))
		return ""
	file.store_string(JSON.stringify(record))
	file.close()
	_cache_key = ""
	return id


## Every readable save for a level that still exists, newest first.
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir)).filter(func(n: String): return n.ends_with(".json"))
	var key := dir
	for file_name: String in files:
		key += "|%s@%d" % [file_name, FileAccess.get_modified_time(dir.path_join(file_name))]
	if key == _cache_key:
		return _cache.duplicate()
	for file_name: String in files:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(dir.path_join(file_name))) != OK:
			continue
		var save: Variant = _migrate(json.data)
		if _is_valid(save):
			out.append(save)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["created_unix"] > b["created_unix"] if a["created_unix"] != b["created_unix"] else a["id"] > b["id"])
	_cache = out
	_cache_key = key
	return out.duplicate()


func latest() -> Dictionary:
	var all := list()
	return all[0] if not all.is_empty() else {}


func has_any() -> bool:
	return not latest().is_empty()


func delete(id: String) -> void:
	DirAccess.remove_absolute(_path(id))
	_cache_key = ""


func _migrate(data: Variant) -> Variant:
	if data is Dictionary and data.get("version") == 1.0 and data.has("level_index"):
		data["level_index"] = int(data["level_index"]) + 1
		data["version"] = float(VERSION)
	return data


func _is_valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != float(VERSION):
		return false
	if not data.get("id") is String:
		return false
	for field in ["created_unix", "level_index", "score", "lives", "kills", "run_time", "shield", "energy", "missiles"]:
		if not (data.get(field) is float or data.get(field) is int):
			return false
	# Older saves have no difficulty and load on the default one.
	if data.has("difficulty"):
		if not (data["difficulty"] is float or data["difficulty"] is int):
			return false
		if int(data["difficulty"]) < 0 or int(data["difficulty"]) >= Game.DIFFICULTIES.size():
			return false
	if data.has("upgrades") and not data["upgrades"] is Array:
		return false
	if data.has("ammo") and not data["ammo"] is Dictionary:
		return false
	return int(data["level_index"]) >= 0 and int(data["level_index"]) < Game.levels.size()


func _path(id: String) -> String:
	return dir.path_join(id + ".json")


func _new_id() -> String:
	var id := ""
	while id.is_empty() or FileAccess.file_exists(_path(id)):
		id = "%d_%06d" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 1000000]
	return id

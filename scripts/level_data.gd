extends RefCounted
class_name LevelData

static func get_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/stages.json"))
	if data is Array:
		for level in data:
			result.append(level)
	return result

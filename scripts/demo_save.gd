class_name DemoSave
extends RefCounted

const PATH := "user://demo_v2.json"
var data := {"version": 2, "unlocked": 0, "credits": 0, "awarded": [], "best": {}, "tutorials": {}, "circuits": {}, "upgrades": {"battery": false, "efficient": false, "storage": false}, "settings": {"fullscreen": true, "reduced_motion": false, "ui_scale": 1.0}}
var warning := ""

func load_data(path := PATH) -> void:
	if not FileAccess.file_exists(path): return
	var parser := JSON.new()
	var parse_result := parser.parse(FileAccess.get_file_as_string(path))
	var candidate = parser.data if parse_result == OK else null
	if not candidate is Dictionary or candidate.get("version") != 2:
		warning = "Save missing or incompatible. Defaults restored; original file retained until next save."
		return
	if not candidate.get("unlocked") is float and not candidate.get("unlocked") is int: return
	data.unlocked = clampi(int(candidate.unlocked), 0, 9)
	if candidate.get("credits", 0) is float or candidate.get("credits", 0) is int:
		data.credits = clampi(int(candidate.get("credits", 0)), 0, 100)
	if candidate.get("best") is Dictionary:
		for key in candidate.best:
			var result = candidate.best[key]
			if str(key) not in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] or not result is Dictionary: continue
			if not (result.get("stars") is float or result.get("stars") is int): continue
			data.best[key] = {"stars": clampi(int(result.stars), 0, 3), "metrics": result.get("metrics", {}) if result.get("metrics", {}) is Dictionary else {}}
	if candidate.get("tutorials") is Dictionary:
		for key in candidate.tutorials:
			if candidate.tutorials[key] is bool: data.tutorials[key] = candidate.tutorials[key]
	if candidate.get("circuits") is Dictionary:
		for key in candidate.circuits:
			if not candidate.circuits[key] is Dictionary: continue
			var board = LogicBoard.new()
			if board.restore(candidate.circuits[key]): data.circuits[key] = board.serialize()
	if candidate.get("awarded") is Array:
		for id in candidate.awarded:
			if (id is int or id is float) and int(id) in range(10) and int(id) not in data.awarded: data.awarded.append(int(id))
	for section in ["upgrades", "settings"]:
		if candidate.get(section) is Dictionary:
			for key in data[section]:
				var v = candidate[section].get(key, data[section][key])
				if key == "ui_scale":
					if v is float or v is int: data.settings.ui_scale = clampf(float(v), 0.85, 1.2)
				elif v is bool: data[section][key] = v
	sync_unlocks()

func is_completed(index: int) -> bool:
	if index < 0 or index >= 10: return false
	var result = data.best.get(str(index), {})
	return result is Dictionary and int(result.get("stars", 0)) > 0

func is_unlocked(index: int) -> bool:
	if index < 0 or index >= 10: return false
	for previous in range(index):
		if not is_completed(previous): return false
	return true

func sync_unlocks() -> void:
	var next := 0
	while next < 9 and is_completed(next): next += 1
	data.unlocked = next

func next_available_stage() -> int:
	sync_unlocks()
	return int(data.unlocked)

func completed_count() -> int:
	var count := 0
	for index in range(10):
		if is_completed(index): count += 1
	return count

func save(path := PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func complete(index: int, stars: int, metrics: Dictionary) -> int:
	if index < 0 or index >= 10 or stars < 1: return 0
	stars = clampi(stars, 1, 3)
	var old = data.best.get(str(index), {})
	if not old is Dictionary or stars >= int(old.get("stars", 0)):
		data.best[str(index)] = {"stars": stars, "metrics": metrics}
	sync_unlocks()
	var reward := 0
	if index not in data.awarded:
		data.awarded.append(index)
		if index >= 3:
			reward = 2
			data.credits += reward
	return reward

func buy(key: String) -> bool:
	if key not in data.upgrades or data.upgrades[key] or int(data.credits) < 2: return false
	data.credits -= 2
	data.upgrades[key] = true
	return true

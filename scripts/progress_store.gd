extends RefCounted
const PATH := "user://sukamaju_progress_v2.save"
const REWARDS := {"NOT":1,"OR":2,"AND":3,"XOR":4,"LATCH":8,"NAND":16,"NOR":17}
var storage_path := PATH
var enabled := true
var data: Dictionary = {"version":3,"completed":{},"circuits":{},"unlocked_stage":1,"components":["WIRE"],"tutorial":{},"settings":{"speed":1.0}}

func load_progress() -> void:
	if not FileAccess.file_exists(storage_path):
		return
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return
	if file.get_length() < 4: return
	var payload_size := file.get_32()
	if payload_size > file.get_length()-4 or payload_size > 16000000: return
	file.seek(0)
	var loaded = file.get_var(false)
	if loaded is Dictionary and int(loaded.get("version", 0)) in [1,2,3]:
		for key in data:
			if loaded.has(key) and typeof(loaded[key]) == typeof(data[key]):
				data[key] = loaded[key]
		# Convert old earned stars to completion without losing unlocked stages.
		for index in loaded.get("stars", {}):
			if int(loaded["stars"][index])>0: data["completed"][index] = true
		# Retire the removed delay module while preserving all saved wires and progress.
		data["components"].erase("TIMER")
		for circuit in data["circuits"].values():
			if circuit is Dictionary:
				for component in circuit.get("nodes", {}).values():
					if component.get("kind", "") == "TIMER":
						component["kind"] = "WIRE"
						component["runtime"] = {}
		data["version"] = 3
		data["unlocked_stage"] = clampi(int(data["unlocked_stage"]), 1, 20)
		for gate in REWARDS:
			if int(data["unlocked_stage"]) > REWARDS[gate] and not gate in data["components"]:
				data["components"].append(gate)

func save_progress() -> void:
	if not enabled: return
	var file := FileAccess.open(storage_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_var(data, false)
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(storage_path+".tmp"), ProjectSettings.globalize_path(storage_path))

func complete(index: int) -> Array:
	data["completed"][index] = true
	data["unlocked_stage"] = maxi(int(data["unlocked_stage"]), mini(20,index+2))
	data["tutorial"][index] = true
	var unlocked: Array = []
	for gate in REWARDS:
		if index+1 == REWARDS[gate] and not gate in data["components"]:
			data["components"].append(gate)
			unlocked.append(gate)
	save_progress()
	return unlocked

extends RefCounted
## Editable graph, compiled into the existing simulator's logic dictionaries.

const LT := preload("res://scripts/logic_tree.gd")
var nodes: Dictionary = {}
var next_id := 1
var last_error := ""


func add_component(kind: String, sensor: String, at: Vector2) -> int:
	var id := next_id
	next_id += 1
	nodes[id] = {"kind": kind, "sensor": sensor, "position": at, "inputs": {}, "runtime": {}}
	return id


func input_count(id: int) -> int:
	match String(nodes[id]["kind"]):
		"SENSOR": return 0
		"AND", "OR", "LATCH": return 2
		_: return 1


func is_actuator(id: int) -> bool:
	return String(nodes[id]["kind"]) in ["DIESEL", "PADAM"]


func import_trees(diesel: Dictionary, shed: Dictionary, has_shed: bool) -> void:
	nodes.clear()
	next_id = 1
	var diesel_id := add_component("DIESEL", "", Vector2(660, 70))
	var source := _import_node(diesel, Vector2(400, 70), maxi(2, LT.get_depth(diesel)))
	if source != 0:
		nodes[diesel_id]["inputs"][0] = source
	if has_shed:
		var shed_id := add_component("PADAM", "", Vector2(660, 330))
		source = _import_node(shed, Vector2(400, 330), maxi(2, LT.get_depth(shed)))
		if source != 0:
			nodes[shed_id]["inputs"][0] = source


func _import_node(tree: Dictionary, at: Vector2, depth: int) -> int:
	if tree.is_empty():
		return 0
	var kind := String(tree.get("type", "SENSOR"))
	# A wire is a connection on this canvas, rather than a separate component.
	if kind == "WIRE":
		return _import_node(tree.get("a", {}), at - Vector2(220, 0), depth - 1)
	if kind == "SENSOR" and String(tree.get("sensor", "NONE")) == "NONE":
		return 0
	var id := add_component(kind, String(tree.get("sensor", "NONE")), at)
	nodes[id]["runtime"] = tree
	if kind != "SENSOR":
		var spread := 62.0 * maxi(1, LT.get_leaf_count(tree)) / 2.0
		for port in range(input_count(id)):
			var child: Dictionary = tree.get("a" if port == 0 else "b", {})
			var offset := 0.0 if input_count(id) == 1 else (-spread if port == 0 else spread)
			var child_id := _import_node(child, at + Vector2(-220, offset), depth - 1)
			if child_id != 0:
				nodes[id]["inputs"][port] = child_id
	return id


func can_connect(source: int, target: int, port: int) -> bool:
	last_error = ""
	if not nodes.has(source) or not nodes.has(target):
		return false
	if source == target or is_actuator(source) or port < 0 or port >= input_count(target):
		last_error = "Hubungkan output ke input komponen lain."
		return false
	if _depends_on(source, target, {}):
		last_error = "Koneksi melingkar tidak bisa dipakai. Gunakan SR latch untuk memori."
		return false
	return true


func connect_nodes(source: int, target: int, port: int) -> bool:
	if not can_connect(source, target, port):
		return false
	nodes[target]["inputs"][port] = source
	return true


func _depends_on(id: int, target: int, visited: Dictionary) -> bool:
	if id == target:
		return true
	if visited.has(id):
		return false
	visited[id] = true
	for source in nodes[id]["inputs"].values():
		if _depends_on(int(source), target, visited):
			return true
	return false


func disconnect_input(target: int, port: int) -> void:
	if nodes.has(target):
		nodes[target]["inputs"].erase(port)


func remove_component(id: int) -> void:
	if not nodes.has(id) or is_actuator(id):
		return
	nodes.erase(id)
	for component in nodes.values():
		for port in component["inputs"].keys():
			if int(component["inputs"][port]) == id:
				component["inputs"].erase(port)


func is_complete(id: int, visited: Dictionary = {}) -> bool:
	if visited.has(id):
		return false
	var path := visited.duplicate()
	path[id] = true
	if String(nodes[id]["kind"]) == "SENSOR":
		return String(nodes[id]["sensor"]) != "NONE"
	for port in range(input_count(id)):
		var source := int(nodes[id]["inputs"].get(port, 0))
		if source == 0 or not nodes.has(source) or not is_complete(source, path):
			return false
	return true


func validation_message() -> String:
	for id in nodes:
		if is_actuator(id) and not is_complete(id):
			return "Lengkapi kabel input menuju %s sebelum Jalankan." % String(nodes[id]["kind"])
	return ""


func compile_trees() -> Dictionary:
	for component in nodes.values():
		component["runtime"] = {}
	var result := {"diesel": {}, "shed": {}}
	var memo: Dictionary = {}
	for id in nodes:
		if not is_actuator(id):
			continue
		var key := "diesel" if nodes[id]["kind"] == "DIESEL" else "shed"
		if is_complete(id):
			result[key] = _compile_node(int(nodes[id]["inputs"][0]), memo)
		else:
			result[key] = LT.make_sensor("NONE")
	return result


func _compile_node(id: int, memo: Dictionary) -> Dictionary:
	if memo.has(id):
		return memo[id]
	var component: Dictionary = nodes[id]
	var kind := String(component["kind"])
	var tree := LT.make_sensor(String(component["sensor"]))
	tree["type"] = kind
	tree["_graph_id"] = id
	memo[id] = tree
	component["runtime"] = tree
	for port in range(input_count(id)):
		tree["a" if port == 0 else "b"] = _compile_node(int(component["inputs"][port]), memo)
	return tree


func value(id: int, sensors: Dictionary, memo: Dictionary) -> bool:
	if memo.has(id):
		return bool(memo[id])
	var component: Dictionary = nodes[id]
	var kind := String(component["kind"])
	var high := false
	if kind == "SENSOR":
		high = bool(sensors.get(String(component["sensor"]), false))
	elif not is_complete(id):
		high = false
	elif kind == "LATCH":
		high = bool(component["runtime"].get("val", false))
	else:
		var a := value(int(component["inputs"][0]), sensors, memo)
		match kind:
			"NOT": high = not a
			"AND": high = a and value(int(component["inputs"][1]), sensors, memo)
			"OR": high = a or value(int(component["inputs"][1]), sensors, memo)
			_: high = a
	memo[id] = high
	return high


func snapshot() -> Dictionary:
	var saved := nodes.duplicate(true)
	for component in saved.values():
		component["runtime"] = {}
	return {"nodes": saved, "next_id": next_id}


func restore(saved: Dictionary) -> void:
	nodes = saved["nodes"].duplicate(true)
	next_id = int(saved["next_id"])

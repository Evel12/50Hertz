extends RefCounted
class_name LogicTree

# Recursive Digital Logic Gate Tree for 50 Hertz — Desa Sukamaju
# Node dictionary structure:
#   { "type": "SENSOR"|"WIRE"|"NOT"|"AND"|"OR"|"LATCH",
#     "sensor": String (when type == "SENSOR"),
#     "a": Dictionary (input A or S),
#     "b": Dictionary (input B or R),
#     "latch_q": bool (internal memory for LATCH),
#     "val": bool (last evaluated output) }


static func make_sensor(sensor_name: String = "NONE") -> Dictionary:
	return {
		"type": "SENSOR",
		"sensor": sensor_name,
		"a": {},
		"b": {},
		"latch_q": false,
		"val": false
	}


static func make_wire(child_a: Dictionary) -> Dictionary:
	return {
		"type": "WIRE",
		"sensor": "NONE",
		"a": child_a,
		"b": {},
		"latch_q": false,
		"val": false
	}


static func make_not(child_a: Dictionary) -> Dictionary:
	return {
		"type": "NOT",
		"sensor": "NONE",
		"a": child_a,
		"b": {},
		"latch_q": false,
		"val": false
	}


static func make_binary(gate_type: String, child_a: Dictionary, child_b: Dictionary) -> Dictionary:
	return {
		"type": gate_type, # "AND", "OR", or "LATCH"
		"sensor": "NONE",
		"a": child_a,
		"b": child_b,
		"latch_q": false,
		"val": false
	}


static func reset_memory(node: Dictionary) -> void:
	if node.is_empty():
		return
	node["latch_q"] = false
	node["val"] = false
	var a_node: Dictionary = node.get("a", {})
	var b_node: Dictionary = node.get("b", {})
	if not a_node.is_empty():
		reset_memory(a_node)
	if not b_node.is_empty():
		reset_memory(b_node)


static func evaluate(node: Dictionary, sensors: Dictionary, update_latches: bool) -> bool:
	if node.is_empty():
		return false

	var ntype: String = String(node.get("type", "SENSOR"))
	var result: bool = false

	match ntype:
		"SENSOR":
			var sname: String = String(node.get("sensor", "NONE"))
			result = bool(sensors.get(sname, false))
		"WIRE":
			var a_node: Dictionary = node.get("a", {})
			result = evaluate(a_node, sensors, update_latches)
		"NOT":
			var a_node: Dictionary = node.get("a", {})
			result = not evaluate(a_node, sensors, update_latches)
		"AND":
			var a_node: Dictionary = node.get("a", {})
			var b_node: Dictionary = node.get("b", {})
			var va: bool = evaluate(a_node, sensors, update_latches)
			var vb: bool = evaluate(b_node, sensors, update_latches)
			result = va and vb
		"OR":
			var a_node: Dictionary = node.get("a", {})
			var b_node: Dictionary = node.get("b", {})
			var va: bool = evaluate(a_node, sensors, update_latches)
			var vb: bool = evaluate(b_node, sensors, update_latches)
			result = va or vb
		"LATCH":
			var s_node: Dictionary = node.get("a", {})
			var r_node: Dictionary = node.get("b", {})
			var vs: bool = evaluate(s_node, sensors, update_latches)
			var vr: bool = evaluate(r_node, sensors, update_latches)
			var q: bool = bool(node.get("latch_q", false))
			if update_latches:
				if vr:
					q = false
				elif vs:
					q = true
				node["latch_q"] = q
			result = q

	node["val"] = result
	return result


static func count_gates(node: Dictionary) -> int:
	return _count_gates(node, {})


static func count_circuit_gates(roots: Array) -> int:
	var visited: Dictionary = {}
	var total := 0
	for root in roots:
		total += _count_gates(root, visited)
	return total


static func _count_gates(node: Dictionary, visited: Dictionary) -> int:
	if node.is_empty():
		return 0
	# A component can drive several inputs on the free canvas; count it once.
	if node.has("_graph_id"):
		var id := int(node["_graph_id"])
		if visited.has(id):
			return 0
		visited[id] = true
	var kind := String(node.get("type", "SENSOR"))
	var total := 1 if kind in ["NOT", "AND", "OR", "LATCH"] else 0
	total += _count_gates(node.get("a", {}), visited)
	total += _count_gates(node.get("b", {}), visited)
	return total


static func get_depth(node: Dictionary) -> int:
	if node.is_empty():
		return 0
	var ntype: String = String(node.get("type", "SENSOR"))
	if ntype == "SENSOR":
		return 1
	var a_node: Dictionary = node.get("a", {})
	var b_node: Dictionary = node.get("b", {})
	var da: int = get_depth(a_node)
	var db: int = get_depth(b_node)
	return 1 + maxi(da, db)


static func get_leaf_count(node: Dictionary) -> int:
	if node.is_empty():
		return 1
	var ntype: String = String(node.get("type", "SENSOR"))
	if ntype == "SENSOR":
		return 1
	var a_node: Dictionary = node.get("a", {})
	var b_node: Dictionary = node.get("b", {})
	if ntype == "WIRE" or ntype == "NOT":
		return maxi(1, get_leaf_count(a_node))
	return maxi(1, get_leaf_count(a_node)) + maxi(1, get_leaf_count(b_node))


static func swap_gate_type(node: Dictionary, new_type: String) -> void:
	# Preserves child A when switching between WIRE, NOT, AND, OR, LATCH
	var old_type: String = String(node.get("type", "WIRE"))
	if old_type == new_type:
		return

	var cur_a: Dictionary = node.get("a", {})
	var cur_b: Dictionary = node.get("b", {})
	if cur_a.is_empty():
		cur_a = make_sensor("NONE")

	node["type"] = new_type
	node["latch_q"] = false
	node["a"] = cur_a

	if new_type == "AND" or new_type == "OR" or new_type == "LATCH":
		if cur_b.is_empty():
			cur_b = make_sensor("NONE")
		node["b"] = cur_b
	else:
		node["b"] = {}


static func wrap_sensor_with_gate(node: Dictionary, gate_type: String) -> void:
	# Wraps a SENSOR node inside a new gate (keeping the sensor on pin A!)
	var old_sensor: String = String(node.get("sensor", "NONE"))
	var child_a: Dictionary = make_sensor(old_sensor)
	node["type"] = gate_type
	node["sensor"] = "NONE"
	node["latch_q"] = false
	node["a"] = child_a
	if gate_type == "AND" or gate_type == "OR" or gate_type == "LATCH":
		node["b"] = make_sensor("NONE")
	else:
		node["b"] = {}


static func replace_with_sensor(node: Dictionary, sensor_name: String) -> void:
	node["type"] = "SENSOR"
	node["sensor"] = sensor_name
	node["a"] = {}
	node["b"] = {}
	node["latch_q"] = false


static func get_sensor_info(sensor_name: String) -> Dictionary:
	match sensor_name:
		"SIANG":
			return {"label": "SIANG", "desc": "Matahari cukup terang untuk PLTS"}
		"MENDUNG":
			return {"label": "MENDUNG", "desc": "Awan tebal menutupi PLTS"}
		"F_RENDAH":
			return {"label": "F_RENDAH", "desc": "Frekuensi < 49.8 Hz (listrik kurang)"}
		"F_TINGGI":
			return {"label": "F_TINGGI", "desc": "Frekuensi > 50.2 Hz (listrik lebih)"}
		"DIESEL_PENUH":
			return {"label": "DIESEL_PENUH", "desc": "Diesel sudah di kapasitas penuh"}
		_:
			return {"label": "+ pilih sensor", "desc": "Slot sensor kosong"}

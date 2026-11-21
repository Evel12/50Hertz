class_name LogicBoard
extends RefCounted

const Program = preload("res://scripts/logic/rule_program.gd")
const KINDS = ["SENSOR", "OUTPUT", "NOT", "AND", "OR", "XOR", "NAND", "NOR", "LATCH", "TIMER", "COMPARE"]
var nodes: Array[Dictionary] = []
var wires: Array[Dictionary] = []
var values: Dictionary = {}
var memories: Dictionary = {}
var timers: Dictionary = {}
var next_id := 1
var error := ""
var script_text := ""
var program = Program.new()
var undo_stack: Array = []
var redo_stack: Array = []

func clear() -> void:
	nodes.clear()
	wires.clear()
	next_id = 1
	reset_runtime()

func reset_runtime() -> void:
	values.clear()
	memories.clear()
	timers.clear()
	error = ""

func checkpoint() -> void:
	undo_stack.append(serialize())
	if undo_stack.size() > 80: undo_stack.pop_front()
	redo_stack.clear()

func undo() -> bool:
	if undo_stack.is_empty(): return false
	redo_stack.append(serialize())
	return restore(undo_stack.pop_back())

func redo() -> bool:
	if redo_stack.is_empty(): return false
	undo_stack.append(serialize())
	return restore(redo_stack.pop_back())

func add(kind: String, pos: Vector2, tag := "") -> int:
	var id := next_id
	next_id += 1
	nodes.append({"id": id, "kind": kind, "tag": tag, "pos": pos, "settings": {}})
	return id

func find(id: int) -> Dictionary:
	for node in nodes:
		if node.id == id: return node
	return {}

func input_count(kind: String) -> int:
	if kind == "SENSOR": return 0
	if kind in ["NOT", "TIMER", "OUTPUT", "COMPARE"]: return 1
	return 2

func remove_node(id: int) -> void:
	var node := find(id)
	if node.is_empty() or node.kind in ["SENSOR", "OUTPUT"]: return
	nodes.erase(node)
	wires = wires.filter(func(w): return w.source != id and w.target != id)

func has_path(start: int, goal: int, visited: Array = []) -> bool:
	if start == goal: return true
	if start in visited: return false
	visited.append(start)
	for w in wires:
		if w.source == start and has_path(w.target, goal, visited): return true
	return false

func connect_nodes(source: int, target: int, port: int, replace := false) -> bool:
	var a := find(source)
	var b := find(target)
	if a.is_empty() or b.is_empty() or a.kind == "OUTPUT" or b.kind == "SENSOR":
		error = "Use a source output and a destination input."
		return false
	if port < 0 or port >= input_count(b.kind):
		error = "Invalid input port."
		return false
	if has_path(target, source):
		error = "Feedback cycles are unsupported. Use explicit LATCH memory."
		return false
	for w in wires:
		if w.target == target and w.port == port and not replace:
			error = "Input occupied. Disconnect its current wire first (undoable)."
			return false
	wires = wires.filter(func(w): return not (w.target == target and w.port == port))
	wires.append({"source": source, "target": target, "port": port})
	error = ""
	return true

func input_value(id: int, port: int, sensors: Dictionary, stack: Array = []):
	for w in wires:
		if w.target == id and w.port == port: return evaluate(w.source, sensors, stack)
	return false

func compare(a: float, b: float, op: String) -> bool:
	match op:
		">": return a > b
		"<": return a < b
		">=": return a >= b
		"<=": return a <= b
		"==": return a == b
		"!=": return a != b
	return false

func evaluate(id: int, sensors: Dictionary, stack: Array = []):
	if values.has(id): return values[id]
	if id in stack: return false
	var node := find(id)
	if node.is_empty(): return false
	var path := stack.duplicate()
	path.append(id)
	var result = false
	var kind: String = node.kind
	if kind == "SENSOR": result = sensors.get(node.tag, false)
	elif kind == "LATCH": result = memories.get(id, false)
	elif kind == "TIMER": result = float(timers.get(id, 0.0)) + 0.000001 >= float(node.settings.get("delay", 1.0))
	else:
		var a = input_value(id, 0, sensors, path)
		var b = input_value(id, 1, sensors, path) if input_count(kind) > 1 else false
		match kind:
			"NOT": result = not bool(a)
			"AND": result = bool(a) and bool(b)
			"OR": result = bool(a) or bool(b)
			"XOR": result = bool(a) != bool(b)
			"NAND": result = not (bool(a) and bool(b))
			"NOR": result = not (bool(a) or bool(b))
			"OUTPUT": result = bool(a)
			"COMPARE": result = compare(float(a), float(node.settings.get("threshold", 75)), str(node.settings.get("op", ">")))
	values[id] = result
	return result

func preview(sensors: Dictionary) -> void:
	values.clear()
	for node in nodes: evaluate(node.id, sensors)

func tick(sensors: Dictionary, dt: float) -> Dictionary:
	preview(sensors)
	if dt > 0:
		var pending := {}
		for node in nodes:
			if node.kind == "LATCH":
				var set_signal := bool(input_value(node.id, 0, sensors))
				var reset_signal := bool(input_value(node.id, 1, sensors))
				pending[node.id] = false if reset_signal else (true if set_signal else memories.get(node.id, false))
			elif node.kind == "TIMER":
				timers[node.id] = float(timers.get(node.id, 0.0)) + dt if bool(input_value(node.id, 0, sensors)) else 0.0
		memories.merge(pending, true)
		preview(sensors)
	var outputs := {}
	for node in nodes:
		if node.kind == "OUTPUT": outputs[node.tag] = bool(values.get(node.id, false))
	outputs.merge(program.execute(sensors), true)
	for node in nodes:
		if node.kind == "OUTPUT" and outputs.has(node.tag): values[node.id] = outputs[node.tag]
	return outputs

func validate(sensors: Array, outputs: Array, allowed_gates: Array = []) -> String:
	program = Program.new()
	for node in nodes:
		if node.kind == "SENSOR" and node.tag not in sensors: return "Sensor unavailable: " + node.tag
		if node.kind == "OUTPUT" and node.tag not in outputs: return "Actuator unavailable: " + node.tag
		if node.kind not in ["SENSOR", "OUTPUT"] and node.kind not in allowed_gates: return "Tool unavailable: " + node.kind
	for tag in sensors + outputs:
		var count := 0
		for node in nodes:
			if node.kind in ["SENSOR", "OUTPUT"] and node.tag == tag: count += 1
		if count != 1: return "Circuit must contain exactly one terminal for " + tag
	if script_text.strip_edges().is_empty(): return ""
	var problem: String = program.compile(script_text, sensors, outputs)
	if not problem.is_empty(): return problem
	for node in nodes:
		if node.kind == "OUTPUT" and program.assignments.has(node.tag):
			for w in wires:
				if w.target == node.id: return "Multiple drivers for %s. Disconnect its gate wire or remove its script assignment." % node.tag
	return ""

func serialize() -> Dictionary:
	var data: Array = []
	for node in nodes: data.append({"id": node.id, "kind": node.kind, "tag": node.tag, "x": node.pos.x, "y": node.pos.y, "settings": node.settings.duplicate(true)})
	return {"version": 2, "nodes": data, "wires": wires.duplicate(true), "script": script_text}

func restore(data: Dictionary) -> bool:
	if not data.get("nodes") is Array or not data.get("wires") is Array: return false
	if data.nodes.size() > 100 or data.wires.size() > 200: return false
	var candidate := LogicBoard.new()
	var ids := []
	for n in data.nodes:
		if not n is Dictionary or n.get("kind", "") not in KINDS: return false
		if not (n.get("id") is float or n.get("id") is int): return false
		var id := int(n.id)
		if id <= 0 or id in ids: return false
		for key in ["x", "y"]:
			if not (n.get(key) is float or n.get(key) is int) or not is_finite(float(n[key])): return false
		var settings = n.get("settings", {})
		if not settings is Dictionary: return false
		if not (settings.get("threshold", 75) is float or settings.get("threshold", 75) is int): return false
		if not (settings.get("delay", 1) is float or settings.get("delay", 1) is int): return false
		if not is_finite(float(settings.get("threshold", 75))) or not is_finite(float(settings.get("delay", 1))): return false
		if float(settings.get("delay", 1)) < 0.05 or float(settings.get("delay", 1)) > 30: return false
		if settings.get("op", ">") not in [">", "<", ">=", "<=", "==", "!="]: return false
		ids.append(id)
		candidate.nodes.append({"id": id, "kind": n.kind, "tag": str(n.get("tag", "")), "pos": Vector2(clampf(float(n.x), -5000, 5000), clampf(float(n.y), -5000, 5000)), "settings": settings.duplicate(true)})
	for w in data.wires:
		if not w is Dictionary or not w.has_all(["source", "target", "port"]): return false
		for key in ["source", "target", "port"]:
			if not (w[key] is int or w[key] is float): return false
			if not is_finite(float(w[key])) or float(w[key]) != float(int(w[key])): return false
		if not candidate.connect_nodes(int(w.source), int(w.target), int(w.port)): return false
	nodes = candidate.nodes
	wires = candidate.wires
	next_id = 1
	for id in ids: next_id = maxi(next_id, id + 1)
	script_text = str(data.get("script", ""))
	reset_runtime()
	return true

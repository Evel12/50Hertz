class_name ToolTutorial
extends RefCounted

var stage := 0
var seen := {}
var skipped := false
var disconnected := false
var step_index := 0
const FIRST = ["Connect TEST_SWITCH output to LAMP input.", "Toggle TEST SWITCH ON and observe LAMP = 1.", "Toggle TEST SWITCH OFF and observe LAMP = 0.", "Disconnect LAMP's input (drag its wire away or use inspector).", "Reconnect TEST_SWITCH to LAMP.", "Press Run, then Pause.", "While paused, press Step.", "Press Reset; circuit is preserved.", "Press Run to finish the training test."]

func reset(index: int) -> void:
	stage = index
	seen.clear()
	skipped = false
	disconnected = false
	step_index = 0

func observe(board, sensors: Dictionary, action := "") -> void:
	if action != "": seen[action] = true
	if stage == 0:
		var connected: bool = not board.wires.is_empty()
		var lamp := false
		for n in board.nodes:
			if n.tag == "LAMP": lamp = bool(board.values.get(n.id, false))
		match step_index:
			0:
				if connected: step_index = 1
			1:
				if connected and sensors.TEST_SWITCH and lamp: step_index = 2
			2:
				if connected and not sensors.TEST_SWITCH and not lamp: step_index = 3
			3:
				if not connected:
					disconnected = true
					step_index = 4
			4:
				if connected: step_index = 5
			5:
				if seen.has("run") and action == "pause": step_index = 6
			6:
				if action == "step": step_index = 7
			7:
				if action == "reset": step_index = 8

func done() -> bool:
	return skipped or (step_index >= 8 if stage == 0 else seen.get("run", false))

func message(board) -> String:
	if skipped: return "Tutorial skipped. Build, predict, test and inspect consequences."
	if stage == 0: return "TOOL %d/9 • %s" % [step_index + 1, FIRST[step_index]]
	if stage == 1:
		var gates = board.nodes.filter(func(n): return n.kind == "NOT")
		if gates.is_empty(): return "1 • Click NOT in the palette to place a gate."
		var inv: Dictionary = gates[0]
		var day_wire := false
		var output_wire := false
		for w in board.wires:
			var a: Dictionary = board.find(w.source)
			var b: Dictionary = board.find(w.target)
			if a.tag == "DAY" and b.id == inv.id: day_wire = true
			if a.id == inv.id and b.tag == "BACKUP": output_wire = true
		if not day_wire: return "2 • Connect DAY's right output to NOT's left input. NOT will invert that signal."
		if not output_wire: return "3 • Connect NOT's right output to BACKUP's left input."
		return "3 • Predict NOT's output at sunset, then Run. Green 1 means backup is requested."
	if stage == 2:
		if board.nodes.filter(func(n): return n.kind == "OR").is_empty(): return "1 • Add OR. Move it by its title bar. It has two separate inputs."
		return "2 • Disconnect the old BACKUP wire. Combine NOT DAY and CLOUD with OR. Watch both events."
	return "Build a rule, predict its consequence, then test. Hints reveal one observation at a time."

extends SceneTree
## Run: godot --headless --path . --script tests/circuit_graph_test.gd
const GraphModel := preload("res://scripts/circuit_graph.gd")
const LT := preload("res://scripts/logic_tree.gd")
const Levels := preload("res://scripts/level_data.gd")
var failures := 0
var checks := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _initialize() -> void:
	for level in Levels.get_levels():
		var imported := GraphModel.new()
		var original: Dictionary = level["initial_diesel_tree"].duplicate(true)
		imported.import_trees(original, level["initial_shed_tree"].duplicate(true), level["has_shed_actuator"])
		var compiled: Dictionary = imported.compile_trees()
		for daylight in [false, true]:
			var sensors := {"SIANG": daylight, "F_RENDAH": daylight, "F_TINGGI": not daylight}
			check(LT.evaluate(original, sensors, false) == LT.evaluate(compiled["diesel"], sensors, false), "Imported graph changes initial preview")

	var graph := GraphModel.new()
	var sensor := graph.add_component("SENSOR", "SIANG", Vector2.ZERO)
	var invert := graph.add_component("NOT", "", Vector2(220, 0))
	var target := graph.add_component("DIESEL", "", Vector2(440, 0))
	check(not graph.validation_message().is_empty(), "Unwired actuator should be incomplete")
	check(graph.connect_nodes(sensor, invert, 0), "Connect sensor to NOT")
	check(graph.connect_nodes(invert, target, 0), "Connect NOT to actuator")
	check(graph.validation_message().is_empty(), "Complete circuit should run")
	var compiled := graph.compile_trees()
	check(LT.evaluate(compiled["diesel"], {"SIANG": false}, false), "NOT should enable diesel at night")
	check(not LT.evaluate(compiled["diesel"], {"SIANG": true}, false), "NOT should disable diesel during daylight")
	check(not graph.connect_nodes(invert, invert, 0), "Self connection must be rejected")
	check(not graph.connect_nodes(target, invert, 0), "Actuator must not be a source")
	check(not graph.connect_nodes(invert, sensor, 0), "Sensor must not accept an input")
	var conjunction := graph.add_component("AND", "", Vector2(300, 200))
	graph.connect_nodes(invert, conjunction, 0)
	check(not graph.connect_nodes(conjunction, invert, 0), "Indirect cycle must be rejected")
	check(graph.nodes[invert]["inputs"][0] == sensor, "Rejected cycle must preserve original cable")
	var saved := graph.snapshot()
	graph.remove_component(sensor)
	check(not graph.nodes[invert]["inputs"].has(0), "Deleting a node must remove its cables")
	check(not graph.validation_message().is_empty(), "Missing upstream input must block simulation")
	graph.restore(saved)
	check(graph.nodes[invert]["inputs"][0] == sensor, "Restoring history must restore cables")
	check(graph.nodes[conjunction]["position"] == Vector2(300, 200), "History must preserve positions")
	graph.connect_nodes(sensor, target, 0)
	check(graph.nodes[target]["inputs"].size() == 1, "Replacing a cable must keep one driver per input")

	# Shared SR memory can drive two actuators and is counted as one gate.
	graph = GraphModel.new()
	var set_sensor := graph.add_component("SENSOR", "F_RENDAH", Vector2.ZERO)
	var reset_sensor := graph.add_component("SENSOR", "F_TINGGI", Vector2(0, 100))
	var latch := graph.add_component("LATCH", "", Vector2(220, 50))
	var diesel := graph.add_component("DIESEL", "", Vector2(440, 0))
	var shed := graph.add_component("PADAM", "", Vector2(440, 100))
	graph.connect_nodes(set_sensor, latch, 0)
	graph.connect_nodes(reset_sensor, latch, 1)
	graph.connect_nodes(latch, diesel, 0)
	graph.connect_nodes(latch, shed, 0)
	compiled = graph.compile_trees()
	check(is_same(compiled["diesel"], compiled["shed"]), "Fan-out must preserve shared memory")
	check(LT.count_circuit_gates([compiled["diesel"], compiled["shed"]]) == 1, "Shared gate must not be counted twice")
	check(LT.evaluate(compiled["diesel"], {"F_RENDAH": true, "F_TINGGI": false}, true), "SR latch must set")
	check(LT.evaluate(compiled["shed"], {"F_RENDAH": false, "F_TINGGI": false}, true), "Shared latch must hold")
	check(not LT.evaluate(compiled["diesel"], {"F_RENDAH": true, "F_TINGGI": true}, true), "Reset must retain priority")
	var memory := bool(compiled["diesel"]["latch_q"])
	graph.value(latch, {"F_RENDAH": true, "F_TINGGI": false}, {})
	check(bool(compiled["diesel"]["latch_q"]) == memory, "Drawing preview must not advance latch memory")
	print("Circuit graph: ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)

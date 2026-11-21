extends SceneTree
const Catalog = preload("res://resources/stages/stage_catalog.gd")
const Sim = preload("res://scripts/grid_sim.gd")
const Board = preload("res://scripts/logic_board.gd")
const Program = preload("res://scripts/logic/rule_program.gd")
const Save = preload("res://scripts/demo_save.gd")
const Tutorial = preload("res://scripts/tool_tutorial.gd")
const Objectives = preload("res://scripts/stage_objectives.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run_sim(index: int, b, rate := 60, speed := 1):
	var s = Sim.new()
	s.reset(index)
	var d = Catalog.get_stage(index)
	var problem: String = b.validate(d.sensors, d.outputs, d.gates)
	check(problem.is_empty(), "Valid circuit %d: %s" % [index + 1, problem])
	var accumulator := 0.0
	var frames := 0
	while not s.failed and not s.completed and frames < 40000:
		frames += 1
		accumulator += (1.0 / rate) * speed
		while accumulator + 0.000001 >= Sim.STEP and not s.failed and not s.completed:
			accumulator -= Sim.STEP
			s.prepare()
			var outputs: Dictionary = b.tick(s.sensors(), Sim.STEP)
			s.trace(b)
			s.step(Sim.STEP, outputs)
	return s

func run() -> void:
	for kind in ["NOT", "AND", "OR", "XOR", "NAND", "NOR"]:
		for a in [false, true]:
			for b in [false, true]:
				var board = Board.new()
				var ai = board.add("SENSOR", Vector2.ZERO, "A")
				var bi = board.add("SENSOR", Vector2.ZERO, "B")
				var gate = board.add(kind, Vector2.ZERO)
				board.connect_nodes(ai, gate, 0)
				if kind != "NOT": board.connect_nodes(bi, gate, 1)
				board.tick({"A": a, "B": b}, Sim.STEP)
				var expected = not a if kind == "NOT" else (a and b) if kind == "AND" else (a or b) if kind == "OR" else (a != b) if kind == "XOR" else not (a and b) if kind == "NAND" else not (a or b)
				check(board.values[gate] == expected, "Truth table " + kind)
	var memory = Board.new()
	var set_id = memory.add("SENSOR", Vector2.ZERO, "SET")
	var reset_id = memory.add("SENSOR", Vector2.ZERO, "RESET")
	var latch = memory.add("LATCH", Vector2.ZERO)
	memory.connect_nodes(set_id, latch, 0)
	memory.connect_nodes(reset_id, latch, 1)
	memory.tick({"SET": true}, Sim.STEP)
	check(memory.values[latch], "Latch sets")
	memory.tick({}, Sim.STEP)
	check(memory.values[latch], "Latch holds")
	memory.tick({"SET": true, "RESET": true}, Sim.STEP)
	check(not memory.values[latch], "Reset wins")
	memory.tick({"SET": true}, 0)
	check(not memory.values[latch], "Paused tick cannot update memory")
	var timer = memory.add("TIMER", Vector2.ZERO)
	memory.find(timer).settings.delay = 1.0
	memory.connect_nodes(set_id, timer, 0)
	for i in range(19): memory.tick({"SET": true}, Sim.STEP)
	check(not memory.values[timer], "Timer below boundary")
	for i in range(100): memory.preview({"SET": true})
	check(not memory.values[timer], "Rendering does not advance timer")
	memory.tick({"SET": true}, Sim.STEP)
	check(memory.values[timer], "Timer exact boundary")
	memory.tick({}, Sim.STEP)
	check(not memory.values[timer], "Timer resets")
	var comparator = memory.add("COMPARE", Vector2.ZERO)
	memory.find(comparator).settings = {"op": ">=", "threshold": 5.0}
	memory.connect_nodes(set_id, comparator, 0)
	memory.tick({"SET": 5.0}, 0)
	check(memory.values[comparator], "Comparator inclusive boundary")
	memory.find(comparator).settings.op = ">"
	memory.tick({"SET": 5.0}, 0)
	check(not memory.values[comparator], "Comparator strict boundary")
	check(not memory.connect_nodes(timer, latch, 0), "Occupied input rejected")
	check(not memory.connect_nodes(timer, set_id, 0), "Sensor input rejected")
	check(not memory.connect_nodes(9999, latch, 0), "Missing source rejected")
	var inv = memory.add("NOT", Vector2.ZERO)
	check(memory.connect_nodes(timer, inv, 0), "Valid wire")
	check(not memory.connect_nodes(inv, timer, 0, true), "Feedback cycle rejected")
	memory.checkpoint()
	var before = memory.serialize()
	memory.add("NOR", Vector2.ZERO)
	check(memory.undo() and memory.serialize() == before, "Undo exact design")
	check(memory.redo() and memory.nodes.size() == before.nodes.size() + 1, "Redo exact design")
	var restored = Board.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(memory.serialize()))), "Versioned JSON circuit round trip")
	check(not restored.restore({"nodes": [{"id": 1, "kind": "OS"}], "wires": []}), "Invalid saved component rejected")
	var program = Program.new()
	check(program.compile("BACKUP = (NOT DAY OR CLOUD) AND SUPPLY <= 75", ["DAY", "CLOUD", "SUPPLY"], ["BACKUP"]).is_empty(), "Program supports logic, comparison, parentheses")
	check(program.execute({"DAY": false, "CLOUD": false, "SUPPLY": 75}).BACKUP, "Program evaluates")
	for text in ["BACKUP = OS.EXECUTE()", "BACKUP = MYSTERY", "BACKUP = (DAY", "BACKUP =", "BACKUP = TRUE\nBACKUP = FALSE", "FILES = TRUE"]:
		check(program.compile(text, ["DAY"], ["BACKUP"]).begins_with("Line"), "Safe parser rejects " + text)
	var multi = Catalog.solution(1)
	multi.script_text = "BACKUP = NOT DAY"
	check(multi.validate(["DAY"], ["BACKUP"], ["NOT"]).contains("Multiple drivers"), "Gate/program multiple driver rejected")
	for index in [1, 2, 3]:
		check(Objectives.commissioning(index, Catalog.solution(index)).is_empty(), "Behavioral commissioning reference " + str(index + 1))
		check(not Objectives.commissioning(index, Catalog.starter(index)).is_empty(), "Commissioning catches missing behavior " + str(index + 1))
	var one_condition = Catalog.starter(3)
	one_condition.connect_nodes(Catalog.terminal(one_condition, "PEAK"), Catalog.terminal(one_condition, "BATTERY"), 0)
	check(Objectives.commissioning(3, one_condition).contains("CHARGED=0"), "AND requires both independent conditions")
	for i in range(10):
		var s = run_sim(i, Catalog.solution(i))
		check(s.completed and not s.failed, "Stage %d reference solution: %s" % [i + 1, s.reason])
		check(s.clinic_outage == 0 and s.water_outage == 0 and s.homes_outage == 0, "Critical services stage %d" % [i + 1])
		check(s.battery >= 0 and s.battery <= s.battery_capacity, "Battery bounds stage %d" % [i + 1])
		if i >= 3:
			var d = Catalog.get_stage(i)
			var gates: int = Catalog.solution(i).nodes.filter(func(n): return n.kind not in ["SENSOR", "OUTPUT"]).size()
			check(s.fuel <= d.fuel_target and s.emissions <= d.emission_target and s.starts <= d.start_limit and gates <= d.gate_target and s.optional_outage <= d.shedding_target, "All optional stars reachable at baseline stage %d" % [i + 1])
		print("STAGE %02d pass=%s time=%.2f freq=%.4f fuel=%.1f starts=%d battery=%.1f shed=%.1f" % [i + 1, s.completed, s.elapsed, s.frequency, s.fuel, s.starts, s.battery, s.optional_outage])
		for schedule in [[30, 1], [144, 4]]:
			var other = run_sim(i, Catalog.solution(i), schedule[0], schedule[1])
			check(other.metrics() == s.metrics(), "Frame/speed invariance stage %d at %dfps %dx" % [i + 1, schedule[0], schedule[1]])
		if i > 0:
			var broken = Catalog.starter(i)
			if i == 3:
				var n = broken.add("NOT", Vector2.ZERO)
				broken.connect_nodes(n, Catalog.terminal(broken, "BATTERY"), 0)
			elif i == 4: broken.connect_nodes(Catalog.terminal(broken, "LOW_FREQ"), Catalog.terminal(broken, "BACKUP"), 0)
			elif i == 5: broken.connect_nodes(Catalog.terminal(broken, "START_WARNING"), Catalog.terminal(broken, "CONNECT_DISTRICT"), 0)
			var fail_sim = run_sim(i, broken)
			check(fail_sim.failed, "Stage %d meaningful failure" % [i + 1])
			check(not fail_sim.reason.is_empty(), "Failure explains cause stage %d" % [i + 1])
	var premature = Catalog.starter(5)
	premature.connect_nodes(Catalog.terminal(premature, "START_WARNING"), Catalog.terminal(premature, "BACKUP"), 0)
	premature.connect_nodes(Catalog.terminal(premature, "GENERATOR_READY"), Catalog.terminal(premature, "CONNECT_DISTRICT"), 0)
	check(run_sim(5, premature).failed, "Ready alone lacks stabilization delay")
	var battery = Sim.new()
	battery.reset(7)
	battery.prepare()
	battery.step(Sim.STEP, {"CHARGE": true})
	check(is_equal_approx(battery.battery, 20 * Sim.STEP * 0.9), "Charge uses surplus and efficiency")
	var energy: float = battery.battery
	battery.step(Sim.STEP, {"BATTERY": true})
	check(is_equal_approx(battery.battery_used, energy) and battery.battery < 0.00001, "Discharge conserves finite energy")
	battery.step(Sim.STEP, {"BATTERY": true, "CHARGE": true})
	check(battery.failed and battery.battery_conflict, "Charge/discharge conflict rejected")
	var save = Save.new()
	for completed in range(3): save.complete(completed, 3, {})
	check(save.complete(3, 2, {}) == 2 and save.complete(3, 3, {}) == 0, "One-time rewards")
	check(save.data.unlocked == 4 and save.data.credits == 2, "Sequential unlock")
	check(save.buy("battery") and not save.buy("battery"), "Upgrade only purchased once")
	save.data.circuits["3"] = Catalog.solution(3).serialize()
	check(save.save("user://test_demo_v2.json"), "Save atomic write")
	var loaded = Save.new()
	loaded.load_data("user://test_demo_v2.json")
	check(loaded.data.unlocked == save.data.unlocked and loaded.data.credits == save.data.credits and loaded.data.upgrades == save.data.upgrades and loaded.data.best["3"].stars == 3 and loaded.data.circuits == save.data.circuits, "Progress and circuits persisted")
	DirAccess.remove_absolute("user://test_demo_v2.json")
	var bad_file := FileAccess.open("user://test_corrupt.json", FileAccess.WRITE)
	bad_file.store_string("{invalid")
	bad_file.close()
	var corrupt = Save.new()
	corrupt.load_data("user://test_corrupt.json")
	check(corrupt.data.unlocked == 0 and not corrupt.warning.is_empty(), "Corrupt save recovers")
	DirAccess.remove_absolute("user://test_corrupt.json")
	var t = Tutorial.new()
	t.reset(0)
	var training = Catalog.starter(0)
	t.observe(training, {"TEST_SWITCH": false})
	check(t.step_index == 0, "Tutorial rejects missing action")
	training.connect_nodes(Catalog.terminal(training, "TEST_SWITCH"), Catalog.terminal(training, "LAMP"), 0)
	training.tick({"TEST_SWITCH": false}, 0)
	t.observe(training, {"TEST_SWITCH": false})
	training.tick({"TEST_SWITCH": true}, 0)
	t.observe(training, {"TEST_SWITCH": true})
	training.tick({"TEST_SWITCH": false}, 0)
	t.observe(training, {"TEST_SWITCH": false})
	training.wires.clear()
	t.observe(training, {"TEST_SWITCH": false})
	check(t.step_index == 4, "Tutorial detects on/off and disconnection")
	training.connect_nodes(Catalog.terminal(training, "TEST_SWITCH"), Catalog.terminal(training, "LAMP"), 0)
	t.observe(training, {"TEST_SWITCH": false})
	for action in ["run", "pause", "step", "reset"]: t.observe(training, {"TEST_SWITCH": false}, action)
	check(t.done(), "Tutorial control sequence completes")
	print("RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

extends RefCounted

# View layouts live in scenes/ui/*.tscn and are instanced by gameplay.tscn.
# This controller binds signals and data; it never constructs UI controls.
var g
var modal: Control
var restore_running := false
var pending_action: Callable
var inspected_id := -1
var views: Control

func _init(game) -> void:
	g = game
	views = g.get_node("UIViews")
	for button in views.find_children("*", "Button", true, false):
		if button.has_meta("menu_action"):
			button.pressed.connect(on_action.bind(str(button.get_meta("menu_action"))))
	for control in views.find_children("*", "Control", true, false):
		if not control.has_meta("value_action"): continue
		var key := str(control.get_meta("value_action"))
		if control is CheckButton: control.toggled.connect(on_value.bind(key))
		elif control is SpinBox: control.value_changed.connect(on_value.bind(key))
		elif control is OptionButton: control.item_selected.connect(on_value.bind(key))

func field(name: String) -> Control:
	return modal.find_child(name, true, false)

func open_modal(view_name: String, title := "") -> Control:
	var was_running: bool = g.running
	if is_instance_valid(modal):
		was_running = restore_running
		modal.hide()
	restore_running = was_running
	g.running = false
	g.editor.set_locked(true)
	modal = views.get_node(view_name)
	if not title.is_empty(): field("Title").text = title
	modal.show()
	var first = modal.find_child("Close", true, false)
	if first: first.grab_focus()
	return modal

func close_modal() -> void:
	if confirmation_open():
		cancel_confirmation()
		return
	if not is_instance_valid(modal): return
	modal.hide()
	modal = null
	g.game_active = true
	g.running = restore_running and not g.sim.failed and not g.sim.completed
	g.editor.set_locked(g.running)

func main_menu() -> void:
	g.game_active = false
	restore_running = false
	open_modal("main_menu")
	restore_running = false

func pause_menu() -> void: open_modal("pause_menu")

func stage_select() -> void:
	open_modal("stage_select")
	for i in range(10):
		var d: Dictionary = g.Catalog.get_stage(i)
		var record = g.save_game.data.best.get(str(i), {})
		var stars := int(record.get("stars", 0)) if record is Dictionary else 0
		var button: Button = field("Stage%02d" % [i + 1])
		var unlocked: bool = g.save_game.is_unlocked(i)
		var cleared: bool = g.save_game.is_completed(i)
		var state := "LOCKED" if not unlocked else "CLEARED" if cleared else "NOT CLEARED"
		button.text = "%02d  %s — %s  %s%s" % [i + 1, d.title, state, "★".repeat(stars), " [saved]" if g.save_game.data.circuits.has(str(i)) else ""]
		button.disabled = not unlocked
		button.modulate = Color("4be0a0") if cleared and unlocked else Color.WHITE
		button.tooltip_text = "Clear Stage %d to unlock. %s" % [i, d.concept] if not unlocked else "Replay this cleared stage. " + d.concept if cleared else "Available to play. " + d.concept
	field("CompletionSummary").text = "%d / 10 stages cleared. Cleared stages remain available for replay." % g.save_game.completed_count()

func settings_panel() -> void:
	open_modal("settings")
	field("Fullscreen").set_pressed_no_signal(g.save_game.data.settings.fullscreen)
	field("ReducedMotion").set_pressed_no_signal(g.save_game.data.settings.reduced_motion)
	field("Scale").select(maxi(0, [0.85, 1.0, 1.1, 1.2].find(float(g.save_game.data.settings.ui_scale))))

func confirm_action(message: String, action: Callable) -> void:
	pending_action = action
	var confirmation: Control = views.get_node("confirmation")
	confirmation.find_child("Message", true, false).text = message
	confirmation.show()
	confirmation.find_child("Cancel", true, false).grab_focus()

func confirmation_open() -> bool:
	return views.get_node("confirmation").visible

func cancel_confirmation() -> void:
	views.get_node("confirmation").hide()
	pending_action = Callable()

func tutorial_options() -> void:
	open_modal("tutorial")
	field("Instructions").text = g.tutorial.message(g.board)
	field("Chatter").visible = g.mission == 4

func board_menu() -> void:
	open_modal("board_menu", "Circuit designs / stage %d" % [g.mission + 1])
	field("Snap").set_pressed_no_signal(g.editor.graph.snapping_enabled)
	field("Feedback").text = ""

func inspect_selected() -> void:
	var n: Dictionary = g.board.find(g.chosen_signal)
	if n.is_empty(): g.notify("Select a component to inspect its inputs and settings."); return
	inspected_id = n.id
	open_modal("component_inspector", "Inspector: %s #%d" % [n.tag if n.kind in ["SENSOR", "OUTPUT"] else n.kind, n.id])
	field("Output").text = "Output: %s. Outgoing path: %s" % [str(g.board.values.get(n.id, false)), str(g.board.wires.filter(func(w): return w.source == n.id))]
	for p in range(2):
		var exists: bool = p < g.board.input_count(n.kind)
		field("Input%d" % p).visible = exists
		field("Disconnect%d" % p).visible = exists
		if exists: field("Input%d" % p).text = "Input %d: %s" % [p, str(g.board.input_value(n.id, p, g.sim.sensors()))]
	for name in ["TimerHelp", "Delay"]: field(name).visible = n.kind == "TIMER"
	for name in ["ComparatorHelp", "Operator", "Threshold"]: field(name).visible = n.kind == "COMPARE"
	field("Delay").set_value_no_signal(float(n.settings.get("delay", 1)))
	field("Operator").select([">", "<", ">=", "<=", "==", "!="].find(n.settings.get("op", ">")))
	field("Threshold").set_value_no_signal(float(n.settings.get("threshold", 75)))
	field("Delete").visible = n.kind not in ["SENSOR", "OUTPUT"]

func script_panel() -> void:
	if g.mission < 8: g.notify("Programming unlocks in Stage 9."); return
	open_modal("script_editor")
	field("Program").text = g.board.script_text
	field("Variables").text = "Live sensor values: " + str(g.sim.sensors())
	field("Validation").text = ""

func show_hint() -> void:
	open_modal("hint", "Observation / hint %d of 3" % [mini(3, g.hint_level + 1)])
	field("Hint").text = g.stage.hints[mini(2, g.hint_level)]
	g.hint_level = mini(2, g.hint_level + 1)

func show_comparison() -> void:
	open_modal("comparison")
	var previous = g.previous_runs.get(str(g.mission), {})
	var has_run: bool = not previous.is_empty()
	field("Empty").visible = not has_run
	for name in ["Frequency", "Fuel", "Outages", "Starts", "Shedding", "Details"]: field(name).visible = has_run
	if not has_run: return
	var now: Dictionary = g.sim.metrics()
	for key in ["frequency", "fuel", "outages", "starts", "shedding"]:
		field(key.capitalize()).text = "%s    previous %.2f → current %.2f" % [key.to_upper(), float(previous.metrics.get(key, 0)), float(now.get(key, 0))]
	field("Details").text = "Previous %.1fs; current %.1fs. Compare complete runs or equal timestamps.\nCircuit changed: %s\nEquipment changed: %s\nWeather and demand timeline: identical." % [previous.metrics.time, now.time, str(previous.circuit != g.board.serialize()), str(previous.upgrades != g.run_equipment)]

func upgrades_panel() -> void:
	open_modal("upgrades", "Between-test equipment / %d credits" % g.save_game.data.credits)
	for pair in [["Battery", "battery"], ["Efficient", "efficient"], ["Storage", "storage"]]:
		var button: Button = field(pair[0])
		button.disabled = g.mission < 3 or g.save_game.data.upgrades[pair[1]] or int(g.save_game.data.credits) < 2
		button.tooltip_text = "Owned" if g.save_game.data.upgrades[pair[1]] else "Costs 2 credits and restarts the test."

func show_help() -> void: open_modal("help")

func show_result() -> void:
	g.result_shown = true
	var stars := 0
	var reward := 0
	if g.sim.completed:
		stars = 3 if g.mission <= 2 else 1
		if g.mission >= 3:
			if g.sim.fuel <= float(g.stage.fuel_target) and g.sim.emissions <= float(g.stage.emission_target): stars += 1
			if g.gate_count() <= int(g.stage.gate_target) and g.sim.starts <= int(g.stage.start_limit) and g.sim.optional_outage <= float(g.stage.shedding_target): stars += 1
		reward = g.save_game.complete(g.mission, stars, g.sim.metrics())
		g.save_game.data.tutorials[str(g.mission)] = g.tutorial.done()
		g.persist()
	open_modal("result_screen", "STAGE %02d CLEARED! / " % [g.mission + 1] + "★".repeat(stars) if g.sim.completed else "TEST FAILED at %.2fs" % g.sim.elapsed)
	restore_running = false
	g.update_stage_status()
	field("ClearBanner").visible = g.sim.completed
	field("ClearBanner").text = "STAGE %02d CLEARED!" % [g.mission + 1]
	field("ProgressionInfo").visible = g.sim.completed
	if g.sim.completed:
		if g.mission == 9:
			field("ProgressionInfo").text = "All ten stages cleared — the demo is complete!" if g.save_game.is_unlocked(9) else "This stage goal is complete. Clear the earlier stages to finish campaign progression."
		elif g.save_game.is_unlocked(g.mission + 1):
			field("ProgressionInfo").text = "Stage %02d is unlocked. Continue to the next stage, or replay to improve your result." % [g.mission + 2]
		else:
			field("ProgressionInfo").text = "This stage goal is complete. Clear the earlier stages to unlock further progression."
		g.notify("Stage %02d CLEARED!" % [g.mission + 1])
	field("Explanation").text = g.sim.explanation()
	field("Metrics").text = "Mandatory: %s\nFuel %.0f / %.0f; emissions %.0f; starts %d / %d\nBattery used %.0f EU; charged %.0f EU; gates %d / %d\nIndustry shed %.1fs / %.1fs; critical outages %.2fs\nCredits earned: %d" % ["PASS" if g.sim.completed else "FAIL", g.sim.fuel, g.stage.fuel_target, g.sim.emissions, g.sim.starts, g.stage.start_limit, g.sim.battery_used, g.sim.battery_stored, g.gate_count(), g.stage.gate_target, g.sim.optional_outage, g.stage.optional_budget, g.sim.clinic_outage + g.sim.homes_outage + g.sim.water_outage, reward] if g.mission >= 3 else "Learning objective: " + ("PASS. Three stars for learning and completion." if g.sim.completed else "Needs another experiment. Your circuit is preserved.")
	field("Optional").visible = g.mission >= 3
	field("Optional").text = "Optional emissions ≤%.0f; shedding ≤%.0fs for engineering star." % [g.stage.emission_target, g.stage.shedding_target]
	field("Prediction").visible = g.mission in [1, 2]
	field("Prediction").text = "Sunset prediction: %d. NOT DAY becomes 1; inspect recorded signals for your controller response." % g.prediction
	field("Next").visible = g.sim.completed
	field("Next").text = "Demo Complete" if g.mission == 9 else "Continue to Stage %02d →" % [g.mission + 2]
	field("Next").disabled = not g.sim.completed or not g.save_game.is_completed(g.mission) or not g.save_game.is_unlocked(mini(9, g.mission + 1))
	field("Retry").text = "Replay Stage — start from the beginning" if g.sim.completed else "Retry test — keep current circuit"
	if not field("Next").disabled: field("Next").grab_focus()

func demo_complete() -> void:
	open_modal("demo_complete")
	for i in range(10):
		var record = g.save_game.data.best.get(str(i), {})
		field("Stage%02d" % [i + 1]).text = "%02d  %s  %s" % [i + 1, g.Catalog.get_stage(i).title, "★".repeat(int(record.get("stars", 0))) if record is Dictionary else ""]

func on_value(value, key: String) -> void:
	match key:
		"fullscreen", "reduced_motion":
			g.save_game.data.settings[key] = bool(value)
			if key == "fullscreen": g.apply_display()
			else: g.village.reduced_motion = bool(value)
			g.persist()
		"ui_scale":
			g.save_game.data.settings.ui_scale = [0.85, 1.0, 1.1, 1.2][int(value)]
			g.apply_display()
			g.persist()
		"snap": g.editor.graph.snapping_enabled = bool(value)
		"delay", "operator", "threshold":
			var node: Dictionary = g.board.find(inspected_id)
			if node.is_empty(): return
			g.board.checkpoint()
			if key == "operator": node.settings.op = [">", "<", ">=", "<=", "==", "!="][int(value)]
			else: node.settings[key] = float(value)
			restore_running = false

func apply_program() -> void:
	var source: String = field("Program").text
	var candidate = g.Board.new()
	candidate.restore(g.board.serialize())
	candidate.script_text = source
	var problem: String = candidate.validate(g.stage.sensors, g.stage.outputs, g.stage.gates)
	if not problem.is_empty(): field("Validation").text = problem; return
	g.board.checkpoint()
	g.board.script_text = source
	g.board.validate(g.stage.sensors, g.stage.outputs, g.stage.gates)
	restore_running = false
	field("Validation").text = "Valid and applied. Reset for a full comparison or resume current state."

func restore_design(kind: String) -> void:
	g.board.checkpoint()
	if kind == "clear":
		g.board.nodes = g.board.nodes.filter(func(n): return n.kind in ["SENSOR", "OUTPUT"])
		g.board.wires.clear()
		g.board.script_text = ""
	else: g.board.restore((g.Catalog.solution(g.mission) if kind == "reference" else g.Catalog.starter(g.mission)).serialize())
	g.editor.rebuild()
	restore_running = false
	close_modal()
	g.restart(false)

func load_design() -> void:
	var data = g.save_game.data.circuits.get(str(g.mission), {})
	var candidate = g.Board.new()
	if not data is Dictionary or not candidate.restore(data): field("Feedback").text = "Missing/invalid circuit. Current design preserved."; return
	var problem: String = candidate.validate(g.stage.sensors, g.stage.outputs, g.stage.gates)
	if not problem.is_empty(): field("Feedback").text = problem; return
	g.board.checkpoint()
	g.board.restore(data)
	g.editor.rebuild()
	restore_running = false
	close_modal()
	g.restart(false)

func on_action(action: String) -> void:
	if action.begins_with("stage:"):
		var index := int(action.trim_prefix("stage:"))
		if not g.save_game.is_unlocked(index):
			g.notify("Stage locked. Clear the previous stage first.")
			return
		g.remember_run()
		g.setup_stage(index)
		restore_running = false
		close_modal()
		return
	if action.begins_with("buy:"):
		if g.save_game.buy(action.trim_prefix("buy:")):
			g.persist()
			restore_running = false
			close_modal()
			g.restart(false)
		return
	if action.begins_with("disconnect:"):
		g.editor.set_locked(false)
		g.editor.disconnect_input(inspected_id, int(action.trim_prefix("disconnect:")))
		restore_running = false
		close_modal()
		return
	match action:
		"close": close_modal()
		"continue":
			g.setup_stage(g.save_game.next_available_stage())
			restore_running = false
			close_modal()
		"stages": stage_select()
		"settings": settings_panel()
		"help": show_help()
		"main": main_menu()
		"hint": show_hint()
		"restart":
			restore_running = false
			close_modal()
			g.replay_stage()
		"retry":
			restore_running = false
			close_modal()
			g.restart()
		"next":
			if not g.sim.completed or g.sim.failed or not g.save_game.is_completed(g.mission):
				g.notify("Complete this stage's goal before continuing.")
				return
			if not g.save_game.is_unlocked(mini(9, g.mission + 1)):
				g.notify("Clear the earlier stages before continuing.")
				return
			if g.mission == 9: demo_complete()
			else:
				g.remember_run()
				g.setup_stage(g.mission + 1)
				restore_running = false
				close_modal()
		"reset_progress": confirm_action("Reset progression, credits, upgrades and circuits?", func():
			g.save_game = g.Save.new()
			g.persist()
			g.setup_stage(0)
			main_menu())
		"skip_tutorial":
			g.tutorial.skipped = true
			g.save_game.data.tutorials[str(g.mission)] = true
			g.persist()
			close_modal()
		"replay_tutorial": confirm_action("Restore starter and restart tutorial?", func():
			g.setup_stage(g.mission)
			restore_running = false
			close_modal())
		"chatter":
			g.board.checkpoint()
			var demo = g.Catalog.starter(4)
			demo.connect_nodes(g.Catalog.terminal(demo, "LOW_FREQ"), g.Catalog.terminal(demo, "BACKUP"), 0)
			g.board.restore(demo.serialize())
			g.editor.rebuild()
			restore_running = false
			close_modal()
			g.restart()
			g.speed = 4
			g.toggle_run()
		"save_circuit":
			g.save_game.data.circuits[str(g.mission)] = g.board.serialize()
			g.persist()
			close_modal()
			g.notify("Circuit saved, including settings and program.")
		"load_circuit": load_design()
		"starter", "clear", "reference": confirm_action("Replace current design with %s? Undo restores it." % action, restore_design.bind(action))
		"delete":
			g.board.checkpoint()
			g.board.remove_node(inspected_id)
			g.editor.rebuild()
			restore_running = false
			close_modal()
		"apply_program": apply_program()
		"confirm":
			var callback := pending_action
			cancel_confirmation()
			if callback.is_valid(): callback.call()
		"cancel": cancel_confirmation()

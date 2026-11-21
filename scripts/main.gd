extends Control

const Catalog = preload("res://resources/stages/stage_catalog.gd")
const Sim = preload("res://scripts/grid_sim.gd")
const Board = preload("res://scripts/logic_board.gd")
const Save = preload("res://scripts/demo_save.gd")
const Tutorial = preload("res://scripts/tool_tutorial.gd")
const Village = preload("res://scripts/ui/village_view.gd")
const Editor = preload("res://scripts/ui/circuit_editor.gd")
const Objectives = preload("res://scripts/stage_objectives.gd")
const Menus = preload("res://scripts/ui/game_menus.gd")
@export var show_main_menu_on_launch := true

var sim = Sim.new()
var board = Board.new()
var save_game = Save.new()
var tutorial = Tutorial.new()
var menus
var stage := {}
var mission := 0
var running := false
var speed := 1
var accumulator := 0.0
var game_active := false
var result_shown := false
var hint_level := 0
var prediction := -1
var previous_runs := {}
var run_equipment := {}
var run_circuit := {}
var editor: CircuitEditor
var village: VillageView
var stage_label: Label
var time_label: Label
var frequency_label: Label
var objective: Label
var tutorial_label: Label
var status_label: Label
var run_button: Button
var event_log: RichTextLabel
var game_root: VBoxContainer
var test_button: Button
var prediction_select: OptionButton
var chosen_signal := -1
var testing := false

func _ready() -> void:
	# An old main.tscn may remain open in Studio after an external scene update.
	# Loading that legacy root must route to the authored scene, not bind absent nodes.
	if not has_node("UIViews") or not has_node("%GameLayout"):
		set_process(false)
		set_process_unhandled_key_input(false)
		call_deferred("recover_legacy_entry")
		return
	testing = "--test-ui" in OS.get_cmdline_user_args()
	if not testing: save_game.load_data()
	menus = Menus.new(self)
	# Theme is authored in resources/ui/control_room.tres.
	apply_display()
	build_ui()
	setup_stage(save_game.next_available_stage() if show_main_menu_on_launch else village.preview_stage)
	if show_main_menu_on_launch: menus.main_menu()
	else: game_active = true
	if not save_game.warning.is_empty(): notify(save_game.warning)

func recover_legacy_entry() -> void:
	if scene_file_path == "res://scenes/gameplay.tscn":
		push_error("Gameplay layout is incomplete. Reload scenes/gameplay.tscn from disk.")
		return
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")

func apply_display(force := false) -> void:
	if testing and not force: return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if save_game.data.settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not save_game.data.settings.fullscreen: DisplayServer.window_set_size(Vector2i(1280, 720))
	get_window().content_scale_factor = float(save_game.data.settings.ui_scale)

func build_ui() -> void:
	# The saved scene is the layout source of truth. Never recreate its controls.
	game_root = %GameLayout
	stage_label = %StageLabel
	time_label = %TimeLabel
	frequency_label = %FrequencyLabel
	objective = %Objective
	tutorial_label = %TutorialLabel
	status_label = %StatusLabel
	run_button = %RunButton
	event_log = %EventLog
	test_button = %TestButton
	prediction_select = %PredictionSelect
	editor = %CircuitEditor
	village = %VillageView
	editor.changed.connect(circuit_changed)
	editor.notice.connect(notify)
	editor.selected.connect(func(id): chosen_signal = id)
	prediction_select.item_selected.connect(func(index): prediction = index - 1)
	for control in find_children("*", "Button", true, false):
		var button: Button = control
		# Scene buttons retain their editable text/style; behavior uses stable action metadata.
		if button.has_meta("action"):
			button.pressed.connect(handle_action.bind(str(button.get_meta("action"))))

func handle_action(action: String) -> void:
	match action:
		"run": toggle_run()
		"reset": restart()
		"step": single_step()
		"speed":
			speed = 1 if speed == 4 else speed * 2
			find_child("SpeedButton", true, false).text = "%dx" % speed
		"help": menus.show_help()
		"stages": menus.stage_select()
		"menu": menus.pause_menu()
		"switch": toggle_switch()
		"hint": menus.show_hint()
		"tutorial": menus.tutorial_options()
		"undo", "redo":
			if running: return
			if action == "undo": board.undo()
			else: board.redo()
			editor.rebuild()
			circuit_changed()
		"fit": editor.fit()
		"board": menus.board_menu()
		"inspect": menus.inspect_selected()
		"program": menus.script_panel()
		"log":
			event_log.visible = not event_log.visible
			editor.call_deferred("fit")
		"compare": menus.show_comparison()
		"upgrades": menus.upgrades_panel()

func setup_stage(index: int) -> void:
	mission = index
	stage = Catalog.get_stage(index)
	board = Catalog.starter(index)
	running = false
	result_shown = false
	hint_level = 0
	prediction = -1
	accumulator = 0
	chosen_signal = -1
	editor.selected_id = -1
	editor.cancel_wire()
	test_button.text = "TEST SWITCH: 0"
	tutorial.reset(index)
	sim.reset(index, save_game.data.upgrades)
	village.set_stage(index)
	village.sim = sim
	village.reduced_motion = save_game.data.settings.reduced_motion
	editor.bind_board(board, stage.gates)
	event_log.clear()
	stage_label.text = "%02d / %s" % [index + 1, stage.title]
	update_stage_status()
	objective.text = "%s\n%s\n%s" % [stage.concept, stage.mandatory, "Three stars for learning and completion; hints have no penalty." if index <= 2 else "* Complete  ** fuel <=%.0f / CO2 <=%.0f  *** gates <=%d / starts <=%d / shed <=%.0fs" % [stage.fuel_target, stage.emission_target, stage.gate_target, stage.start_limit, stage.shedding_target]]
	find_child("ProgramButton", true, false).visible = index >= 8
	find_child("UpgradeButton", true, false).visible = index >= 3
	test_button.visible = index == 0
	prediction_select.visible = index in [1, 2]
	prediction_select.select(0)
	run_equipment = save_game.data.upgrades.duplicate()
	run_circuit = board.serialize()
	circuit_changed()
	notify(stage.story)
	refresh()

func circuit_changed() -> void:
	board.preview(sim.sensors())
	tutorial.observe(board, sim.sensors())
	tutorial_label.text = tutorial.message(board)
	if sim.elapsed > 0: notify("Resume continues current state. Reset for a fair full-run comparison.")

func notify(message: String) -> void:
	status_label.text = message
	status_label.tooltip_text = message

func toggle_switch() -> void:
	if running: notify("Pause to operate the training switch."); return
	sim.test_switch = not sim.test_switch
	test_button.text = "TEST SWITCH: %d" % int(sim.test_switch)
	var problem: String = board.validate(stage.sensors, stage.outputs, stage.gates)
	if problem.is_empty(): sim.commands = board.tick(sim.sensors(), 0)
	sim.record("cause", "TEST_SWITCH -> %d; lamp -> %d" % [int(sim.test_switch), int(sim.commands.get("LAMP", false))])
	sim.trace(board)
	circuit_changed()

func toggle_run() -> void:
	if running:
		running = false
		tutorial.observe(board, sim.sensors(), "pause")
	else:
		if sim.failed or sim.completed: restart()
		var problem: String = board.validate(stage.sensors, stage.outputs, stage.gates)
		if mission == 8 and problem.is_empty() and board.program.assignments.size() < 2: problem = "Stage 9 requires program assignments for BACKUP and BATTERY."
		if not problem.is_empty(): notify(problem); return
		if mission in [1, 2] and prediction == -1 and not tutorial.skipped:
			notify("Choose your sunset prediction before the test.")
			prediction_select.grab_focus()
			return
		running = true
		tutorial.observe(board, sim.sensors(), "run")
		if sim.elapsed == 0:
			run_equipment = save_game.data.upgrades.duplicate()
			run_circuit = board.serialize()
	editor.set_locked(running)
	refresh()

func single_step() -> void:
	if running: notify("Pause before single-stepping."); return
	var problem: String = board.validate(stage.sensors, stage.outputs, stage.gates)
	if mission == 8 and problem.is_empty() and board.program.assignments.size() < 2: problem = "Stage 9 requires program assignments for BACKUP and BATTERY."
	if not problem.is_empty(): notify(problem); return
	if sim.elapsed == 0:
		run_equipment = save_game.data.upgrades.duplicate()
		run_circuit = board.serialize()
	tutorial.observe(board, sim.sensors(), "step")
	advance()
	refresh()

func remember_run() -> void:
	if sim.elapsed <= 0: return
	previous_runs[str(mission)] = {"metrics": sim.metrics(), "circuit": run_circuit.duplicate(true), "upgrades": run_equipment.duplicate()}

func restart(fresh_stage_on_completed := true) -> void:
	if sim.completed and fresh_stage_on_completed:
		replay_stage()
		return
	var was_completed: bool = sim.completed
	remember_run()
	running = false
	accumulator = 0
	result_shown = false
	sim.reset(mission, save_game.data.upgrades)
	board.reset_runtime()
	board.validate(stage.sensors, stage.outputs, stage.gates)
	event_log.clear()
	if was_completed: tutorial.reset(mission)
	tutorial.observe(board, sim.sensors(), "reset")
	test_button.text = "TEST SWITCH: 0"
	run_equipment = save_game.data.upgrades.duplicate()
	run_circuit = board.serialize()
	editor.set_locked(false)
	circuit_changed()
	notify("Reset: same timeline, memory cleared, circuit preserved.")

func replay_stage() -> void:
	# Attempt state belongs to the run; saved clears/unlocks belong to DemoSave.
	remember_run()
	setup_stage(mission)
	village.animation = 0
	notify("Fresh attempt: time, equipment, tutorial and starter circuit reset. Saved clears and unlocked stages are kept.")

func _process(delta: float) -> void:
	if not game_active: return
	if running:
		accumulator += minf(delta, 0.25) * speed
		while accumulator + 0.000001 >= Sim.STEP and running:
			accumulator -= Sim.STEP
			advance()
	else: board.preview(sim.sensors())
	refresh()

func advance() -> void:
	if sim.completed or sim.failed: return
	sim.prepare()
	var output: Dictionary = board.tick(sim.sensors(), Sim.STEP)
	sim.trace(board)
	sim.step(Sim.STEP, output)
	# The safe bench clears as soon as its demonstrated tool sequence is complete.
	if mission == 0 and tutorial.done() and not sim.failed:
		sim.completed = true
		sim.record("result", "Training goal demonstrated: switch, lamp, wiring and simulation controls.")
	if mission == 0 and sim.completed and not tutorial.done():
		sim.completed = false
		sim.elapsed = float(stage.duration) - 1
		notify("Finish the tool checklist or choose Skip Tutorial before completing training.")
	if mission in [1, 2] and not sim.state.DAY and not tutorial.seen.has("prediction_result"):
		tutorial.seen.prediction_result = true
		sim.record("prediction", "Predicted NOT=%d; NOT DAY is now 1. %s" % [prediction, "Prediction matched." if prediction == 1 else "NOT flips DAY=0 into 1."])
	if sim.completed:
		var diagnostic: String = Objectives.commissioning(mission, board)
		if not diagnostic.is_empty():
			sim.completed = false
			sim.fail(diagnostic)
	if sim.failed or sim.completed:
		running = false
		editor.set_locked(false)
		if not result_shown: menus.show_result()

func refresh() -> void:
	time_label.text = "%s · %.0f/%.0fs" % [sim.clock_text(), sim.elapsed, stage.duration]
	frequency_label.text = "%.2f Hz" % sim.frequency
	frequency_label.modulate = Color("ff7185") if sim.danger > 0 else Color("4be0a0")
	run_button.text = "Pause [Space]" if running else "Run [Space]"
	update_stage_status()
	tutorial_label.text = tutorial.message(board)
	highlight_tutorial()
	editor.update_signals(sim.sensors())
	village.preview_commands = board.tick(sim.sensors(), 0)
	village.simulation_running = running
	var selected_node: Dictionary = board.find(chosen_signal)
	village.selected_command = str(selected_node.get("tag", "")) if selected_node.get("kind", "") == "OUTPUT" else ""
	for e in sim.pending_events:
		var color := "#ffce78" if e.kind == "cause" else "#4be0a0" if e.kind in ["action", "logic"] else "#ff7185" if e.kind == "failure" else "#b9cddb"
		event_log.append_text("[color=%s]%.2fs  %s  %s[/color]\n" % [color, e.time, str(e.kind).to_upper(), str(e.message).replace("[", "(")])
	sim.pending_events.clear()

func gate_count() -> int:
	return board.nodes.filter(func(n): return n.kind not in ["SENSOR", "OUTPUT"]).size()

func update_stage_status() -> void:
	var status: Label = find_child("StageStatus", true, false)
	if not status: return
	status.text = "CLEARED" if sim.completed else "REPLAY · NEW RUN" if save_game.is_completed(mission) and sim.elapsed == 0 else "REPLAY · IN PROGRESS" if save_game.is_completed(mission) else "NOT CLEARED"
	status.modulate = Color("4be0a0") if sim.completed else Color("ffce78")

func persist() -> void:
	if not testing and not save_game.save(): notify("Could not write save. Check user data directory permissions.")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F11:
		save_game.data.settings.fullscreen = not save_game.data.settings.fullscreen
		apply_display()
		persist()
	elif event.keycode == KEY_ESCAPE:
		if menus.confirmation_open(): menus.cancel_confirmation()
		elif editor.cancel_wire(): pass
		elif is_instance_valid(menus.modal): menus.close_modal()
		else: menus.pause_menu()
	elif not is_instance_valid(menus.modal) and game_active:
		match event.keycode:
			KEY_SPACE: toggle_run()
			KEY_R: restart()
			KEY_H: menus.show_help()
	get_viewport().set_input_as_handled()

func highlight_tutorial() -> void:
	var gold := Color("ffdf91")
	var normal := Color.WHITE
	var teaching: bool = not tutorial.skipped
	test_button.modulate = gold if teaching and mission == 0 and tutorial.step_index in [1, 2] else normal
	run_button.modulate = gold if teaching and ((mission == 0 and tutorial.step_index in [5, 8]) or (mission in [1, 2] and not running)) else normal
	find_child("StepButton", true, false).modulate = gold if teaching and mission == 0 and tutorial.step_index == 6 else normal
	find_child("ResetButton", true, false).modulate = gold if teaching and mission == 0 and tutorial.step_index == 7 else normal
	for button in editor.palette.get_children():
		var kind: String = str(button.get_meta("gate_kind", ""))
		var missing: bool = board.nodes.filter(func(n): return n.kind == kind).is_empty()
		button.modulate = gold if teaching and ((mission == 1 and kind == "NOT") or (mission == 2 and kind == "OR")) and missing else normal
	for n in board.nodes:
		if editor.controls.has(n.id):
			editor.controls[n.id].modulate = gold if teaching and mission == 0 and tutorial.step_index in [0, 3, 4] else normal

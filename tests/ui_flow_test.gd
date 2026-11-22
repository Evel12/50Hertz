extends SceneTree
## Run with a rendering backend: godot --path . --script tests/ui_flow_test.gd
var view: SubViewport
var game
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 8) -> void:
	for i in range(count):
		await process_frame

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	view.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		view.push_input(event, true)
		await process_frame
	await frames()

func escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		view.push_input(event, true)
	await frames()

func check_screen_bounds(screen: Control, label: String) -> void:
	var frame: Control = screen.get_child(1).get_child(0)
	var rect := frame.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(view.size)).encloses(rect), label + " fits viewport")

func run() -> void:
	view = SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	await click(game.title_screen.buttons[0])
	check(game.current_screen == game.GameScreen.LEVEL_SELECT, "Native title button opens mission selection")
	check_screen_bounds(game.level_select_screen, "Mission selection")
	await click(game.level_select_screen.find_child("Mission1", true, false))
	check(game.current_screen == game.GameScreen.BRIEFING, "Mission card opens briefing")
	check_screen_bounds(game.briefing_screen, "Briefing")
	game._start_playing_current_level()
	await frames()
	var upper_bar: Control = game.playing_hud.get_node("UpperBar")
	check(upper_bar.find_children("*", "ProgressBar", true, false).is_empty(), "Navbar no longer duplicates the simulation progress bar")
	var duplicate_frequency := false
	for label in upper_bar.find_children("*", "Label", true, false):
		if label.text.ends_with(" Hz"):
			duplicate_frequency = true
	check(not duplicate_frequency, "Frequency is displayed only in its own panel")
	check(game.hud_speed_buttons.size() == 3 and game.hud_speed_buttons[0].text == "1x" and game.hud_speed_buttons[1].text == "4x" and game.hud_speed_buttons[2].text == "8x", "Only 1x, 4x and 8x speed controls are offered")
	await click(game.hud_speed_buttons[1])
	check(game.simulator.speed_multiplier == 4.0 and game.hud_speed_buttons[1].button_pressed and not game.hud_speed_buttons[0].button_pressed, "4x control applies and highlights the right multiplier")
	await click(game.hud_speed_buttons[2])
	check(game.simulator.speed_multiplier == 8.0 and game.hud_speed_buttons[2].button_pressed and not game.hud_speed_buttons[1].button_pressed, "8x control applies and updates selection")
	await click(game.hud_speed_buttons[0])
	var expanded_height: float = game.oscilloscope.size.y
	await click(game.oscilloscope.minimize_button)
	check(game.oscilloscope.minimized and game.oscilloscope.size.y < expanded_height, "Frequency panel minimizes to its header")
	var preserved_history: Array = game.oscilloscope.freq_history.duplicate()
	await click(game.oscilloscope.minimize_button)
	check(not game.oscilloscope.minimized and game.oscilloscope.size.y == expanded_height and preserved_history == game.oscilloscope.freq_history, "Restore reopens frequency and objectives without resetting history")
	await click(game.playing_hud.find_child("PauseButton", true, false))
	check(paused and game.is_paused and game.pause_screen.visible, "Pause button opens the modal while editing")
	check_screen_bounds(game.pause_screen, "Pause menu")
	await escape()
	check(not paused and not game.simulator.is_running, "Escape resumes editing without starting simulation")
	game._on_run_pressed()
	check(game.simulator.is_running, "Valid circuit starts simulation")
	await escape()
	var minute: int = game.simulator.current_min
	var frequency: float = game.simulator.frequency
	var history: Array = game.simulator.freq_history.duplicate()
	var starts: int = game.simulator.diesel_starts
	var cost: float = game.simulator.cost_rp
	await create_timer(0.5).timeout
	check(game.simulator.current_min == minute and game.simulator.frequency == frequency, "Pause freezes time and frequency")
	check(game.simulator.freq_history == history and game.simulator.diesel_starts == starts and game.simulator.cost_rp == cost, "Pause preserves history, start count and fuel cost")
	check(not game.world.can_process() and not game.workbench.can_process(), "Village animation and circuit input are paused")
	await click(game.pause_screen.find_child("ResumeButton", true, false))
	check(not paused and game.simulator.is_running, "Resume button continues the running simulation")
	await create_timer(0.3).timeout
	check(game.simulator.current_min > minute, "Clock continues from its paused minute")
	await escape()
	await click(game.pause_screen.find_child("RestartButton", true, false))
	check(not paused and not game.simulator.is_running and game.simulator.current_min == game.simulator.start_min, "Restart resets simulation and leaves the tree unpaused")
	check(game.workbench.can_simulate(), "Restart retains the player's circuit")
	game._set_workbench_expanded(true)
	await frames()
	check(game.oscilloscope.is_visible_in_tree() and game.oscilloscope.z_index > game.workbench_holder.z_index, "Telemetry remains visible over the expanded workbench")
	var old_plot_center: Vector2 = game.oscilloscope.get_global_rect().get_center()
	await click(game.oscilloscope.minimize_button)
	check(game.oscilloscope.minimized and not game.oscilloscope.get_global_rect().has_point(old_plot_center), "Minimize also frees canvas space while workbench is expanded")
	check(game.workbench.graph_view.occlusion == game.oscilloscope, "Circuit input follows the reduced frequency panel bounds")
	await click(game.oscilloscope.minimize_button)
	check(not game.oscilloscope.minimized, "Frequency panel restores above the expanded workbench")
	await escape()
	check(not game.is_workbench_expanded and not paused, "First Escape exits expanded mode")
	await escape()
	check(paused, "Next Escape pauses the game")
	await click(game.pause_screen.find_child("LevelsButton", true, false))
	check(not paused and game.current_screen == game.GameScreen.LEVEL_SELECT and not game.simulator.is_running, "Pause menu returns to missions safely")
	for i in range(4):
		game._enter_level_briefing(i)
		game._start_playing_current_level()
		check(game.oscilloscope.level.id == game.levels[i].id, "Objectives match level %d" % (i + 1))
		game.oscilloscope.update_from_sim({"frequency": 49.0, "cost_rp": 9999999, "diesel_starts": 100, "gate_count": 99, "shed_minutes": 999, "shed_flickers": 99, "dusun2_powered": false})
		var goals: Array[Dictionary] = game.oscilloscope.get_objectives()
		check(not goals[0].okay and not goals[-1].okay, "Violated objectives are marked in level %d" % (i + 1))
		if i == 1:
			check(goals[1].title == "Penggilingan padi" and not goals[1].okay, "Level 2 includes the rice mill objective")
		if i == 3:
			check(goals.size() == 5 and not goals[1].star and goals[3].star, "Level 4 separates required start limits from bonus outage duration")
	game._on_sim_finished(false, "Frekuensi melewati batas aman.", {"end_time_str": "03:15"})
	await frames()
	check_screen_bounds(game.result_screen, "Failure result")
	check(game.result_screen.visible and not game.res_next_btn.visible, "Failure shows repair action without next-level action")
	check(not game.workbench.can_process(), "Result modal blocks underlying circuit keyboard input")
	game._on_sim_finished(true, "", {"end_time_str": "07:00", "stars": 3, "has_shed_actuator": true, "shed_minutes": 100, "target_shed_minutes": 130, "co2_kg": 20, "diesel_starts": 3, "gate_count": 3, "target_gates": 3})
	await frames()
	check_screen_bounds(game.result_screen, "Success result")
	check(game.res_next_btn.visible and game.level_stars[3] == 3, "Success updates earned stars and exposes navigation")
	game._retry_current_level()
	check(game.workbench.can_process() and not game.simulator.is_running, "Repair action re-enables circuit editing")
	game._show_screen(game.GameScreen.RULES)
	await frames()
	check_screen_bounds(game.rules_screen, "Rules")
	print("UI FLOW: ", checks, " checks; ", failures, " failures")
	quit(failures)

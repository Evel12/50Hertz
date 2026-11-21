extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL REPLAY/FLOW: ", message)
func settle() -> void:
	for i in range(4): await process_frame
func flow():
	return game.village.map_root.get_node("PowerFlow")
func route(role: String) -> Dictionary:
	for item in flow().routes:
		if item.role == role: return item
	return {}
func sync_flow() -> void:
	flow().refresh_routes(game.sim, 1.0, false)
func run() -> void:
	game = load("res://scenes/gameplay.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.menus.close_modal()
	game.game_active = true
	# Clear Stage 1, then exercise the actual result Replay button.
	game.tutorial.skipped = true
	game.toggle_run()
	game.advance()
	check(game.sim.completed and game.save_game.is_unlocked(1), "Initial clear opens next stage")
	var saved: Dictionary = game.save_game.data.duplicate(true)
	game.sim.commands = {"LAMP": true}
	game.board.memories[999] = true
	game.board.timers[999] = 8.0
	game.sim.fuel = 999
	game.sim.danger = 3
	game.menus.field("Retry").pressed.emit()
	check(game.sim.elapsed == 0 and not game.sim.completed and not game.sim.failed, "Replay clears run time and result state")
	check(game.tutorial.step_index == 0 and not game.tutorial.skipped and not game.tutorial.done(), "Replay resets finished tutorial evidence")
	check(game.board.serialize() == game.Catalog.starter(0).serialize(), "Replay restores starter circuit")
	check(game.board.memories.is_empty() and game.board.timers.is_empty(), "Replay clears component memory")
	check(game.sim.commands.is_empty() and game.sim.fuel == 0 and game.sim.danger == 0, "Replay clears commands, fuel and stress")
	check(game.save_game.data == saved, "Replay preserves all saved progress, stars, unlocks and rewards")
	check(game.menus.modal == null and not game.menus.views.get_node("result_screen").visible, "Old clear popup stays closed on replay")
	check(game.find_child("StageStatus", true, false).text.contains("REPLAY"), "Saved clear is distinguished from new attempt")
	game.toggle_run()
	game.advance()
	check(not game.sim.completed and game.sim.elapsed > 0, "Replayed tutorial does not instantly clear again")
	game.menus.on_action("next")
	check(game.mission == 0, "Saved best does not complete current attempt")
	game.toggle_run()
	game.menus.stage_select()
	check(game.menus.field("Stage01").text.contains("CLEARED") and not game.menus.field("Stage02").disabled, "Saved clear and next unlock remain after replay")
	game.menus.close_modal()
	game.menus.pause_menu()
	game.menus.on_action("restart")
	check(game.sim.elapsed == 0 and game.tutorial.step_index == 0 and game.save_game.is_unlocked(1), "Pause Restart starts fresh without relocking")
	# Toolbar reset after a completed attempt also starts a fresh stage.
	game.tutorial.skipped = true
	game.toggle_run()
	game.advance()
	game.menus.close_modal()
	game.restart()
	check(not game.tutorial.done() and not game.sim.completed and game.save_game.is_completed(0), "Completed-run Reset does not retain tutorial win state")
	# A later stage resets night/weather/equipment/timeline as well as fuel.
	game.setup_stage(1)
	game.board = game.Catalog.solution(1)
	game.editor.bind_board(game.board, game.stage.gates)
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	while not game.sim.completed and not game.sim.failed: game.advance()
	check(game.sim.completed and not game.sim.state.DAY, "Sunset reference clear reaches night")
	game.save_game.data.circuits["1"] = game.board.serialize()
	game.menus.board_menu()
	game.menus.field("Load").pressed.emit()
	check(game.board.wires.size() == 2 and game.sim.elapsed == 0 and not game.sim.completed, "Loading after clear preserves chosen design and starts a new test")
	check(not game.tutorial.done(), "Load after clear does not retain completed tutorial state")
	while not game.sim.completed and not game.sim.failed: game.advance()
	game.menus.field("Retry").pressed.emit()
	check(game.sim.elapsed == 0 and game.sim.state.DAY and not game.sim.state.CLOUD, "Replay restores morning environment")
	check(game.sim.event_name == "Clear morning" and game.sim.next_event == 0, "Replay resets event label and timeline cursor")
	check(not game.sim.generator_ready and game.sim.startup_clock == 0 and game.sim.starts == 0, "Replay resets generator readiness and starts")
	check(game.board.serialize() == game.Catalog.starter(1).serialize(), "Sunset replay begins with starter design")
	check(game.save_game.is_unlocked(2) and game.save_game.is_completed(1), "Later-stage replay preserves next unlock")
	# Physical flow directions and actual command application.
	sync_flow()
	check(route("HYDRO").active and route("HYDRO").from == "HYDRO" and route("HYDRO").to == "GRID", "Hydro supplies grid")
	check(route("SOLAR").active and route("SOLAR").to == "GRID", "Daylight solar supplies grid")
	check(route("CLINIC").active and route("CLINIC").from == "GRID", "Grid delivers to clinic")
	check(not route("BACKUP").active, "Backup has no ghost flow while off")
	var polyline := PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(100, 100)])
	var sample: Dictionary = flow().point_at(polyline, 150)
	check(sample.position == Vector2(100, 50) and sample.direction == Vector2.DOWN, "Arrows travel complete elbow path in source-to-destination order")
	# Generator startup must not show electricity before readiness.
	game.setup_stage(5)
	game.board = game.Catalog.solution(5)
	game.editor.bind_board(game.board, game.stage.gates)
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	for i in range(162): game.advance()
	sync_flow()
	check(game.sim.commands.get("BACKUP", false) and not route("BACKUP").active, "Starting backup has command but no power flow")
	for i in range(60): game.advance()
	sync_flow()
	check(route("BACKUP").active and route("BACKUP").from == "BACKUP", "Ready backup injects into grid")
	check(not route("DISTRICT").active and route("DISTRICT").state == "DISCONNECTED", "Unconnected district has no animated power")
	for i in range(25): game.advance()
	sync_flow()
	check(route("DISTRICT").active and route("DISTRICT").from == "GRID", "Ready connected district receives grid power")
	# Charging reverses the battery arrow; discharge stops when energy runs out.
	game.setup_stage(7)
	game.sim.prepare()
	game.sim.step(0.05, {"CHARGE": true})
	sync_flow()
	check(route("BATTERY").active and route("BATTERY").from == "GRID" and route("BATTERY").state == "CHARGING", "Charging arrows point into battery")
	game.sim.step(0.05, {"BATTERY": true})
	sync_flow()
	check(route("BATTERY").active and route("BATTERY").from == "BATTERY" and route("BATTERY").to == "GRID", "Discharging arrows point out of battery")
	game.sim.step(0.05, {"BATTERY": true})
	sync_flow()
	check(not route("BATTERY").active, "Empty battery has no flow despite command")
	game.setup_stage(6)
	game.sim.prepare()
	game.sim.step(0.05, {"SHED_FACTORY": true})
	sync_flow()
	check(not route("FACTORY").active and route("FACTORY").state == "DISCONNECTED", "Shedding breaks factory electricity path")
	check(route("CLINIC").active, "Protective shedding leaves clinic path active")
	game.sim.fail("Test grid trip")
	sync_flow()
	check(flow().routes.all(func(item): return not item.active), "Blackout stops every power-flow route")
	check(flow().routes.all(func(item): return item.state == "OUTAGE"), "Fault paths distinct from ordinary off state")
	for stage_index in range(10):
		game.setup_stage(stage_index)
		sync_flow()
		var clear_routes := true
		for item in flow().routes:
			var obstacles: Array[Rect2] = []
			for other in game.village.map_root.get_children():
				if other is VillageBuilding and other.name != item.node and other.role != "GRID":
					obstacles.append(Rect2(other.position - Vector2(53, 61), Vector2(106, 146)))
			for segment in range(item.points.size() - 1):
				if not flow().clear_segment(item.points[segment], item.points[segment+1], obstacles): clear_routes = false
		check(clear_routes, "Routes avoid unrelated buildings stage %d" % [stage_index + 1])
	# Capture a late-stage actual controller with both source and delivery paths.
	game.setup_stage(9)
	game.board = game.Catalog.solution(9)
	game.editor.bind_board(game.board, game.stage.gates)
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	for i in range(650): game.advance()
	game.refresh()
	await settle()
	check(flow().get_index() == 0, "Flow layer precedes buildings and sits above behind-parent roads")
	game.village.reduced_motion = true
	await settle()
	check(flow().reduced_motion, "Reduced motion preserves static directional arrows")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/replay_power_flow.png")
	game.menus.g = null
	game.free()
	await process_frame
	print("REPLAY/FLOW RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

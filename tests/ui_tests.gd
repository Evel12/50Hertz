extends SceneTree
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL UI: " + description)

func settle() -> void:
	for i in range(5): await process_frame

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.menus.close_modal()
	game.game_active = true
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.mode = Window.MODE_WINDOWED
		root.size = resolution
		await settle()
		for stage in [0, 2, 9]:
			game.setup_stage(stage)
			await settle()
			var split = game.game_root.get_node("EqualSplit")
			check(absf(split.get_child(0).size.x - split.get_child(1).size.x) < 2, "Equal split at %s stage %d" % [resolution, stage + 1])
			check(game.editor.graph.size.y >= 180, "Usable board at %s stage %d" % [resolution, stage + 1])
			check(game.status_label.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "Footer within viewport")
			check(game.editor.graph.get_global_rect().position.x >= split.get_child(1).get_global_rect().position.x, "Board confined to right panel")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/ui_%dx%d_stage%d.png" % [resolution.x, resolution.y, stage + 1])
	game.setup_stage(0)
	var switch_id: int = game.Catalog.terminal(game.board, "TEST_SWITCH")
	var lamp_id: int = game.Catalog.terminal(game.board, "LAMP")
	game.editor.connect_wire(str(switch_id), 0, str(lamp_id), 0)
	game.toggle_switch()
	game.toggle_switch()
	game.editor.disconnect_input(lamp_id, 0)
	game.editor.connect_wire(str(switch_id), 0, str(lamp_id), 0)
	game.toggle_run()
	game.toggle_run()
	game.single_step()
	game.restart()
	check(game.tutorial.done(), "Stage 1 complete interactive tool checklist")
	game.toggle_run()
	while not game.sim.completed: game.advance()
	check(game.save_game.data.unlocked == 1 and game.save_game.data.credits == 0, "Training completion unlocks without economy")
	game.menus.close_modal()
	game.setup_stage(1)
	game.board = game.Catalog.solution(1)
	game.editor.bind_board(game.board, game.stage.gates)
	game.prediction = 1
	game.toggle_run()
	check(game.running, "Run starts")
	game.menus.pause_menu()
	check(not game.running, "Menu pauses")
	game.menus.settings_panel()
	game.menus.close_modal()
	check(game.running, "Nested menus preserve running state")
	game.toggle_run()
	game.menus.pause_menu()
	game.menus.close_modal()
	check(not game.running, "Previously paused stays paused")
	var time_before: float = game.sim.elapsed
	game.single_step()
	check(is_equal_approx(game.sim.elapsed - time_before, 0.05), "Step advances fixed tick")
	game.restart()
	check(game.sim.elapsed == 0 and game.board.wires.size() == 2, "Reset preserves circuit")
	# Exercise actual widget callbacks for palette creation and stage progression.
	var old_count: int = game.gate_count()
	game.editor.palette.get_child(0).pressed.emit()
	check(game.gate_count() == old_count + 1, "Palette callback places component")
	game.board.undo()
	game.editor.rebuild()
	game.setup_stage(3)
	game.board = game.Catalog.solution(3)
	game.editor.bind_board(game.board, game.stage.gates)
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	for i in range(500): game.advance()
	game.refresh()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/ui_live_peak.png")
	game.board = game.Catalog.solution(9)
	game.setup_stage(9)
	game.board = game.Catalog.solution(9)
	game.editor.bind_board(game.board, game.stage.gates)
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	while not game.sim.completed and not game.sim.failed: game.advance()
	check(game.sim.completed and game.result_shown, "Stage 10 result reached through game path")
	game.menus.demo_complete()
	check(is_instance_valid(game.menus.modal), "Completion screen opens")
	game.menus.close_modal()
	if DisplayServer.get_name() != "headless":
		game.save_game.data.settings.fullscreen = true
		game.apply_display(true)
		await settle()
		check(root.mode == Window.MODE_FULLSCREEN, "Fullscreen display path")
		game.save_game.data.settings.fullscreen = false
		game.apply_display(true)
		await settle()
		check(root.mode == Window.MODE_WINDOWED, "Windowed display path")
	game.menus.g = null
	game.free()
	await process_frame
	print("UI RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

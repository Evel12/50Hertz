extends SceneTree
const Save = preload("res://scripts/demo_save.gd")
var checks := 0
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL PROGRESSION: ", message)
func settle() -> void:
	for i in range(4): await process_frame
func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var save = Save.new()
	for i in range(10):
		check(not save.is_completed(i), "Fresh stage not completed %d" % [i+1])
		check(save.is_unlocked(i) == (i == 0), "Fresh stage lock %d" % [i+1])
	# A stale/corrupt unlocked number cannot grant access without completed predecessors.
	save.data.unlocked = 9
	check(not save.is_unlocked(1) and save.next_available_stage() == 0, "Locks derive from completion evidence")
	save.complete(0, 3, {"passed": true})
	check(save.is_completed(0) and save.is_unlocked(1) and not save.is_unlocked(2), "First clear unlocks exactly next stage")
	check(save.save("user://test_progression.json"), "Progress saves")
	var loaded = Save.new()
	loaded.load_data("user://test_progression.json")
	check(loaded.is_completed(0) and loaded.is_unlocked(1) and not loaded.is_unlocked(2), "Completion and locks survive reload")
	DirAccess.remove_absolute("user://test_progression.json")
	game = load("res://scenes/gameplay.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		await settle()
	game.menus.close_modal()
	check(game.mission == 0, "Normal startup selects unlocked stage, not editor preview")
	game.menus.stage_select()
	check(game.menus.field("Stage01").text.contains("NOT CLEARED") and not game.menus.field("Stage01").disabled, "Available status visible")
	for i in range(2, 11):
		check(game.menus.field("Stage%02d" % i).disabled and game.menus.field("Stage%02d" % i).text.contains("LOCKED"), "Locked status and disabled button %d" % i)
	game.menus.field("Stage03").pressed.emit()
	check(game.mission == 0, "Programmatic locked button cannot bypass progression")
	game.menus.close_modal()
	game.menus.on_action("next")
	check(game.mission == 0, "Cannot advance before goal completion")
	# Run the real introductory tool sequence, no skips.
	var source: int = game.Catalog.terminal(game.board, "TEST_SWITCH")
	var target: int = game.Catalog.terminal(game.board, "LAMP")
	game.editor.connect_wire(str(source), 0, str(target), 0)
	game.toggle_switch()
	game.toggle_switch()
	game.editor.disconnect_input(target, 0)
	game.editor.connect_wire(str(source), 0, str(target), 0)
	game.toggle_run()
	game.toggle_run()
	game.single_step()
	game.restart()
	check(game.tutorial.done(), "Training goal sequence demonstrated")
	game.toggle_run()
	game.advance()
	check(game.sim.completed and game.sim.elapsed < 1, "Training clears immediately after goal demonstration")
	check(game.menus.modal.name == "result_screen" and game.menus.field("ClearBanner").visible, "Clear popup automatically opens")
	check(game.menus.field("Title").text.contains("CLEARED") and game.menus.field("ClearBanner").text.contains("01"), "Explicit stage clear indication")
	check(game.menus.field("ProgressionInfo").text.contains("02 is unlocked"), "Clear popup announces next unlock")
	check(game.menus.field("Next").visible and not game.menus.field("Next").disabled, "Next action available")
	check(game.find_child("StageStatus", true, false).text == "CLEARED", "Gameplay header records completion")
	await capture("res://tests/progression_clear_popup.png")
	game.menus.stage_select()
	check(game.menus.field("Stage01").text.contains("CLEARED") and not game.menus.field("Stage01").text.contains("NOT CLEARED"), "Cleared stage select indicator")
	check(game.menus.field("Stage02").text.contains("NOT CLEARED") and not game.menus.field("Stage02").disabled, "Next available stage indicator")
	check(game.menus.field("Stage03").disabled, "Later stages remain locked after first clear")
	await capture("res://tests/progression_locked.png")
	game.menus.close_modal()
	game.menus.show_result()
	game.menus.field("Next").pressed.emit()
	check(game.mission == 1 and game.menus.modal == null and not game.sim.completed, "Next starts newly unlocked stage")
	check(game.find_child("StageStatus", true, false).text == "NOT CLEARED", "New stage header indicates not completed")
	# An actual failed sunset run must never grant a clear or next action.
	game.prediction = 1
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	while not game.sim.failed and not game.sim.completed: game.advance()
	check(game.sim.failed and not game.save_game.is_completed(1), "Failure is not recorded as completion")
	check(not game.menus.field("ClearBanner").visible and not game.menus.field("Next").visible, "Failure hides clear banner and next action")
	game.menus.on_action("next")
	check(game.mission == 1 and not game.save_game.is_unlocked(2), "Failure cannot unlock or advance")
	game.menus.close_modal()
	# Complete remaining scenarios through real game orchestration and Next buttons.
	for i in range(1, 10):
		game.setup_stage(i)
		game.board = game.Catalog.solution(i)
		game.editor.bind_board(game.board, game.stage.gates)
		game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
		game.tutorial.skipped = true
		game.prediction = 1
		while not game.sim.failed and not game.sim.completed: game.advance()
		check(game.sim.completed and game.save_game.is_completed(i), "Actual clear saved stage %d" % [i+1])
		check(game.menus.field("Next").visible and not game.menus.field("Next").disabled, "Next enabled after clear %d" % [i+1])
		if i < 9:
			check(game.save_game.is_unlocked(i+1), "Exactly following stage unlocked %d" % [i+2])
			if i < 8: check(not game.save_game.is_unlocked(i+2), "No later stage unlocked early")
			game.menus.field("Next").pressed.emit()
			check(game.mission == i+1, "Next button advances in order")
		else:
			game.menus.field("Next").pressed.emit()
			check(game.menus.modal.name == "demo_complete", "Final clear leads to demo completion")
	check(game.save_game.completed_count() == 10, "All ten completed flags present")
	game.menus.stage_select()
	check(game.menus.field("CompletionSummary").text.contains("10 / 10"), "Completion count displayed")
	for i in range(10):
		var button = game.menus.field("Stage%02d" % [i+1])
		check(button.text.contains("CLEARED") and not button.disabled, "Cleared stages remain replayable")
	if DisplayServer.get_name() != "headless":
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/progression_completed.png")
	game.menus.g = null
	game.free()
	await process_frame
	print("PROGRESSION RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

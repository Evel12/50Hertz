extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL SCENE UI: ", text)
func settle() -> void:
	for i in range(5): await process_frame
func run() -> void:
	# Every form opens independently and has actual editable controls before _ready.
	var files := ["main_menu", "pause_menu", "stage_select", "settings", "tutorial", "board_menu", "component_inspector", "script_editor", "hint", "comparison", "upgrades", "help", "result_screen", "demo_complete", "confirmation"]
	for name in files:
		var packed: PackedScene = load("res://scenes/ui/%s.tscn" % name)
		check(packed != null and packed.get_state().get_node_count() >= 10, "Authored form " + name)
		var view = packed.instantiate()
		check(view.find_child("Title", true, false) is Label, "Editable heading " + name)
		check(view.find_child("Close", true, false) is Button, "Editable close " + name)
		view.free()
	for kind in ["sensor", "output", "not", "and", "or", "xor", "nand", "nor", "latch", "timer", "compare"]:
		var card = load("res://scenes/ui/components/%s.tscn" % kind).instantiate()
		check(card is GraphNode and card.has_node("Signal"), "Authored card " + kind)
		card.free()
	var editor_scene: PackedScene = load("res://scenes/ui/logic_editor.tscn")
	var sample = editor_scene.instantiate()
	check(sample.has_node("Palette") and sample.has_node("CircuitBoard"), "Editable logic editor hierarchy")
	check(sample.get_node("Palette").get_child_count() == 9, "All palette buttons pre-authored")
	root.add_child(sample)
	await settle()
	check(sample.board != null, "Standalone logic editor has a safe preview board")
	sample.place_component("NOT")
	check(sample.board.nodes.filter(func(n): return n.kind == "NOT").size() == 1, "Standalone editor can place an authored card")
	sample.free()
	# Static source audit forbids constructor-based UI and text drawing.
	var forbidden := RegEx.new()
	forbidden.compile("(?:Button|Label|Control|GraphNode|GraphEdit|PanelContainer|VBoxContainer|HBoxContainer|HFlowContainer|SpinBox|CodeEdit|OptionButton|CheckButton|ConfirmationDialog|Theme|StyleBoxFlat)\\.new\\(")
	for path in ["main.gd", "ui/game_menus.gd", "ui/circuit_editor.gd", "ui/village_view.gd", "ui/village_building.gd", "ui/frequency_chart.gd"]:
		var source := FileAccess.get_file_as_string("res://scripts/" + path)
		check(forbidden.search(source) == null and not source.contains("draw_string("), "No constructed UI / text in " + path)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	var count: int = game.get_node("UIViews").get_child_count()
	for name in ["main_menu", "pause_menu", "settings_panel", "stage_select", "show_help", "show_hint", "tutorial_options", "board_menu", "show_comparison", "upgrades_panel", "demo_complete"]:
		game.menus.call(name)
		check(game.menus.modal != null and game.menus.modal.visible, "Open bound view " + name)
		check(game.get_node("UIViews").get_child_count() == count, "No view construction " + name)
		game.menus.close_modal()
	game.setup_stage(0)
	game.menus.stage_select()
	game.menus.field("Stage02").pressed.emit()
	check(game.mission == 0, "Locked stage action is rejected")
	game.menus.field("Stage01").pressed.emit()
	check(game.menus.modal == null, "Stage button is connected")
	game.menus.settings_panel()
	game.menus.field("ReducedMotion").button_pressed = true
	check(game.village.reduced_motion, "Saved settings toggle is bound")
	game.menus.close_modal()
	# Confirmation uses an existing editable view and cancel does not mutate design.
	game.setup_stage(1)
	game.editor.palette.get_child(0).pressed.emit()
	var before: Dictionary = game.board.serialize()
	game.menus.board_menu()
	game.menus.field("Clear").pressed.emit()
	check(game.menus.confirmation_open(), "Pre-authored confirmation opens")
	game.menus.on_action("cancel")
	check(not game.menus.confirmation_open() and game.board.serialize() == before, "Cancel preserves circuit")
	game.menus.field("Clear").pressed.emit()
	game.menus.on_action("confirm")
	check(game.gate_count() == 0 and game.menus.modal == null, "Confirmed clear resets existing board")
	game.board.undo()
	game.editor.rebuild()
	check(game.gate_count() == 1, "Undo after confirmation")
	game.menus.board_menu()
	game.menus.field("Save").pressed.emit()
	game.board.wires.clear()
	game.menus.board_menu()
	game.menus.field("Load").pressed.emit()
	check(game.gate_count() == 1 and game.menus.modal == null, "Authored save/load actions")
	game.setup_stage(5)
	var timer_id: int = game.board.add("TIMER", Vector2(300, 200))
	game.chosen_signal = timer_id
	game.menus.inspect_selected()
	game.menus.field("Delay").value = 2.5
	check(game.board.find(timer_id).settings.delay == 2.5, "Authored timer SpinBox bound")
	check(not game.menus.field("Operator").visible, "Inspector shows relevant controls only")
	game.menus.close_modal()
	game.setup_stage(7)
	var comparator: int = game.board.add("COMPARE", Vector2(300, 200))
	game.chosen_signal = comparator
	game.menus.inspect_selected()
	game.menus.field("Operator").item_selected.emit(1)
	game.menus.field("Threshold").value = 80
	check(game.board.find(comparator).settings.op == "<" and game.board.find(comparator).settings.threshold == 80, "Authored comparator controls bound")
	game.menus.close_modal()
	game.setup_stage(8)
	game.menus.script_panel()
	game.menus.field("Program").text = "BACKUP = OS.EXECUTE()"
	game.menus.field("Apply").pressed.emit()
	check(game.menus.field("Validation").text.begins_with("Line"), "Program syntax errors shown in saved Label")
	check(game.board.script_text == game.stage.script, "Invalid apply preserves valid program")
	game.menus.field("Program").text = game.stage.reference_script
	game.menus.field("Apply").pressed.emit()
	check(game.board.script_text == game.stage.reference_script, "Authored program editor applies rule")
	game.menus.close_modal()
	# Edits to authored captions survive behavior binding.
	var help_button: Button = game.find_child("HelpButton", true, false)
	help_button.text = "My edited help caption"
	help_button.pressed.emit()
	check(game.menus.modal.name == "help" and help_button.text == "My edited help caption", "Metadata binds behavior independently of editable caption")
	# Capture actual pre-authored menus at minimum desktop size.
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		for name in ["main_menu", "settings_panel", "stage_select", "script_panel", "pause_menu"]:
			game.menus.call(name)
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/scene_%s.png" % name)
	game.menus.g = null
	game.free()
	await process_frame
	print("SCENE UI RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

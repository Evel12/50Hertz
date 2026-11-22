extends SceneTree
## Run with a rendering backend: godot --path . --script tests/circuit_editor_input_test.gd
var game
# Isolated viewport keeps native GUI tests independent of desktop mouse input.
var test_view: SubViewport
var board
var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1
func wait_frames() -> void:
	for i in range(7):
		await process_frame
func motion(at: Vector2, buttons: int = 0, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = buttons
	event.relative = relative
	test_view.push_input(event, true)
func button(at: Vector2, held: bool, index: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = index
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE) if held else 0
	event.pressed = held
	test_view.push_input(event, true)
func drag(start: Vector2, finish: Vector2, index: int = MOUSE_BUTTON_LEFT) -> void:
	motion(start)
	await process_frame
	button(start, true, index)
	await process_frame
	var previous := start
	for i in range(1, 9):
		var point := start.lerp(finish, i / 8.0)
		motion(point, MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE, point - previous)
		previous = point
		await process_frame
	button(finish, false, index)
	await wait_frames()
func pin(id: int, output: bool, port: int = 0) -> Vector2:
	var node = board.graph_nodes[id]
	return node.get_global_transform() * (node.get_output_port_position(port) if output else node.get_input_port_position(port))
func key(code: int, held: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = held
	test_view.push_input(event)

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	test_view = SubViewport.new()
	test_view.size = Vector2i(1280, 720)
	test_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(test_view)
	test_view.add_child(game)
	await wait_frames()
	game._enter_level_briefing(0)
	game._start_playing_current_level()
	await wait_frames()
	board = game.workbench
	var original_count: int = board.graph_model.nodes.size()
	var palette = board.palette.get_child(0)
	await drag(palette.get_global_rect().get_center(), (pin(2, true) + pin(1, false)) * 0.5)
	check(board.graph_model.nodes.size() == original_count + 1, "Native palette drag creates one NOT")
	var gate_id := 3
	if not board.graph_model.nodes.has(gate_id):
		quit(1)
		return
	await drag(pin(2, true), pin(gate_id, false))
	check(board.graph_model.nodes[gate_id]["inputs"].get(0, 0) == 2, "Drag output plugs into NOT input")
	await drag(pin(gate_id, true), pin(1, false))
	check(board.graph_model.nodes[1]["inputs"].get(0, 0) == gate_id, "Drag replaces actuator cable")
	check(game.diesel_tree["type"] == "NOT", "Graph drives simulator tree")
	var old_position: Vector2 = board.graph_model.nodes[gate_id]["position"]
	var before_move_tree = game.diesel_tree
	var node = board.graph_nodes[gate_id]
	await drag(node.get_global_rect().get_center(), node.get_global_rect().get_center() + Vector2(55, 40))
	check(board.graph_model.nodes[gate_id]["position"] != old_position, "Gate can be repositioned by dragging body")
	check(is_same(before_move_tree, game.diesel_tree), "Layout drag does not reset simulation")
	var moved_position: Vector2 = board.graph_model.nodes[gate_id]["position"]
	board.undo()
	await wait_frames()
	check(board.graph_model.nodes[gate_id]["position"] == old_position, "Undo node move")
	board.redo()
	await wait_frames()
	check(board.graph_model.nodes[gate_id]["position"] == moved_position, "Redo node move")
	var canvas = board.graph_view
	var pan_start: Vector2 = canvas.global_position + canvas.size - Vector2(70, 50)
	var old_offset: Vector2 = canvas.scroll_offset
	await drag(pan_start, pan_start - Vector2(40, 30), MOUSE_BUTTON_MIDDLE)
	check(canvas.scroll_offset != old_offset, "Docked canvas pans with MMB")
	var space_offset: Vector2 = canvas.scroll_offset
	motion(pan_start)
	key(KEY_SPACE, true)
	await drag(pan_start, pan_start - Vector2(20, 10))
	key(KEY_SPACE, false)
	check(canvas.scroll_offset != space_offset and not game.simulator.is_running, "Space + drag pans without starting simulation")
	var zoom_before: float = canvas.zoom
	motion(pan_start)
	button(pan_start, true, MOUSE_BUTTON_WHEEL_UP)
	button(pan_start, false, MOUSE_BUTTON_WHEEL_UP)
	await wait_frames()
	check(canvas.zoom > zoom_before, "Docked canvas zooms with wheel")
	var dock_zoom: float = canvas.zoom
	var dock_scroll: Vector2 = canvas.scroll_offset
	button(board.expand_button.get_global_rect().get_center(), true)
	button(board.expand_button.get_global_rect().get_center(), false)
	await wait_frames()
	check(game.is_workbench_expanded and board.size.x > 1200, "Expand button opens large canvas")
	check(game.oscilloscope.is_visible_in_tree() and game.oscilloscope.z_index > game.workbench_holder.z_index, "Frequency graph stays visible above canvas")
	check(board.graph_model.nodes[gate_id]["position"] == moved_position, "Expansion preserves node positions")
	var expanded_offset: Vector2 = canvas.scroll_offset
	var empty: Vector2 = canvas.global_position + Vector2(800, 180)
	await drag(empty, empty + Vector2(40, 20), MOUSE_BUTTON_MIDDLE)
	check(canvas.scroll_offset != expanded_offset, "Expanded canvas also pans")
	var expanded_zoom: float = canvas.zoom
	motion(empty)
	button(empty, true, MOUSE_BUTTON_WHEEL_DOWN)
	button(empty, false, MOUSE_BUTTON_WHEEL_DOWN)
	await wait_frames()
	check(canvas.zoom < expanded_zoom, "Expanded canvas also zooms")
	# Pull the old NOT input cable to empty canvas, then reconnect it.
	await drag(pin(gate_id, false), canvas.global_position + Vector2(700, 300))
	check(not board.graph_model.nodes[gate_id]["inputs"].has(0), "Input cable can be unplugged")
	game._on_run_pressed()
	check(not game.simulator.is_running, "Incomplete circuit cannot run")
	await drag(pin(2, true), pin(gate_id, false))
	check(board.can_simulate(), "Reconnected circuit is valid")
	game._on_run_pressed()
	await wait_frames()
	check(game.simulator.is_running and board.is_locked, "Run uses edited graph and locks wiring")
	var locked_offset: Vector2 = canvas.scroll_offset
	await drag(empty, empty + Vector2(25, 15), MOUSE_BUTTON_MIDDLE)
	check(canvas.scroll_offset != locked_offset, "Pan remains available during simulation")
	game._on_run_pressed()
	game._set_workbench_expanded(false)
	await wait_frames()
	check(is_equal_approx(canvas.zoom, dock_zoom) and canvas.scroll_offset.is_equal_approx(dock_scroll), "Docked pan/zoom restored")
	# Build a nested two-actuator circuit, including the second AND input.
	game._enter_level_briefing(3)
	game._start_playing_current_level()
	await wait_frames()
	board._on_component_dropped({"kind": "AND"}, Vector2(280, 330))
	board._on_component_dropped({"kind": "LATCH"}, Vector2(500, 330))
	board._on_component_dropped({"kind": "SENSOR", "sensor": "DIESEL_PENUH"}, Vector2(160, 420))
	await wait_frames()
	board._on_connection_request("Component3", 0, "Component6", 0)
	board._on_connection_request("Component8", 0, "Component6", 1)
	await wait_frames()
	board.fit_view()
	await wait_frames()
	await drag(pin(6, true), pin(7, false, 0))
	check(int(board.graph_model.nodes[7]["inputs"].get(0, 0)) == 6, "Cable plugs into SR latch S beside the new artwork")
	await drag(pin(4, true), pin(7, false, 1))
	check(int(board.graph_model.nodes[7]["inputs"].get(1, 0)) == 4, "Cable plugs into SR latch R beside the new artwork")
	await drag(pin(7, true), pin(5, false))
	check(int(board.graph_model.nodes[5]["inputs"].get(0, 0)) == 7, "SR latch Q cable plugs into the actuator")
	check(board.graph_nodes[6].get_input_port_count() == 2, "AND exposes two cable inputs")
	check(board.can_simulate(), "Nested AND + SR latch circuit validates")
	check(game.simulator.count_total_gates() == 3, "Shared sensor branches retain correct gate score")
	game._on_run_pressed()
	check(game.simulator.is_running, "Two-actuator circuit runs")
	game._on_run_pressed()
	board.graph_nodes[6].selected = true
	board.graph_view.grab_focus()
	key(KEY_DELETE, true)
	key(KEY_DELETE, false)
	await wait_frames()
	check(not board.can_simulate(), "Deleting a connected gate disconnects its cables")
	board.undo()
	await wait_frames()
	check(board.can_simulate(), "Undo restores deleted gate and cables")
	board.redo()
	await wait_frames()
	check(not board.can_simulate(), "Redo repeats gate deletion")
	print("GRAPH INPUT FAILURES: ", failures)
	quit(1 if failures else 0)

extends Control
class_name CircuitWorkbench

const Model := preload("res://scripts/circuit_graph.gd")
const CanvasScript := preload("res://scripts/circuit_canvas.gd")
const NodeScript := preload("res://scripts/circuit_graph_node.gd")
const WiresScript := preload("res://scripts/circuit_wires.gd")
const ExpandButtonScript := preload("res://scripts/circuit_expand_button.gd")
const ToolButtonScript := preload("res://scripts/circuit_tool_button.gd")
const PaletteScript := preload("res://scripts/circuit_palette_item.gd")
const CircuitSkin := preload("res://scripts/circuit_ui_skin.gd")
const UI := preload("res://scripts/upper_hud_skin.gd")

signal circuit_changed()
signal expansion_requested()

var level_dict: Dictionary = {}
var diesel_tree: Dictionary = {}
var shed_tree: Dictionary = {}
var graph_model = Model.new()
var graph_view: GraphEdit
var graph_nodes: Dictionary = {}
var palette: HBoxContainer
var bottom_dock: PanelContainer
var status_label: Label
var expand_button: Button
var undo_button: Button
var redo_button: Button
var delete_button: Button
var is_locked := false
var expanded := false
var latest_sensors: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var _move_before: Dictionary = {}
var _rebuilding := false
var _views: Dictionary = {}
var _status_time := 0.0
var _render_revision := 0
var _rebuild_queued := false


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_controls()
	resized.connect(func(): call_deferred("_refresh_tray_visuals"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		call_deferred("_refresh_tray_visuals")


func _refresh_tray_visuals() -> void:
	if not is_instance_valid(bottom_dock):
		return
	bottom_dock.queue_redraw()
	for item in palette.get_children():
		item.queue_redraw()
	for button in [undo_button, redo_button, delete_button, expand_button]:
		button.queue_redraw()


func _build_controls() -> void:
	var heading := Label.new()
	heading.text = "RANGKAIAN KONTROL"
	heading.position = Vector2(18, 11)
	heading.size = Vector2(195, 24)
	UI.label(heading, 10)
	add_child(heading)
	# Bottom component tray, using the same supplied cream frame as the HUD.
	bottom_dock = PanelContainer.new()
	bottom_dock.name = "ComponentTray"
	bottom_dock.anchor_right = 1
	bottom_dock.anchor_top = 1
	bottom_dock.anchor_bottom = 1
	bottom_dock.offset_left = 16
	bottom_dock.offset_right = -16
	bottom_dock.offset_top = -88
	bottom_dock.offset_bottom = -18
	bottom_dock.add_theme_stylebox_override("panel", UI.frame(UI.PANEL, 8, 6))
	add_child(bottom_dock)
	var tray_row := HBoxContainer.new()
	tray_row.add_theme_constant_override("separation", 8)
	bottom_dock.add_child(tray_row)
	var scroll := ScrollContainer.new()
	scroll.name = "PaletteScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 54
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scroll.scroll_horizontal += -42 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 42
			scroll.accept_event()
	)
	tray_row.add_child(scroll)
	palette = HBoxContainer.new()
	palette.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	palette.add_theme_constant_override("separation", 6)
	scroll.add_child(palette)

	var divider := VSeparator.new()
	var divider_style := StyleBoxLine.new()
	divider_style.vertical = true
	divider_style.color = Color("c3a87c")
	divider_style.thickness = 1
	divider.add_theme_stylebox_override("separator", divider_style)
	tray_row.add_child(divider)
	var tools := HBoxContainer.new()
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_theme_constant_override("separation", 3)
	tray_row.add_child(tools)
	undo_button = _tool(tools, "<", "Undo [Ctrl+Z]", undo)
	redo_button = _tool(tools, ">", "Redo [Ctrl+Y]", redo)
	delete_button = _tool(tools, "Hapus", "Hapus komponen terpilih [Delete]", delete_selected)
	expand_button = _tool(tools, "", "Perbesar panel rangkaian", func(): expansion_requested.emit(), true)
	expand_button.custom_minimum_size.x = 34

	graph_view = CanvasScript.new()
	graph_view.name = "CircuitCanvas"
	graph_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_view.offset_left = 16
	graph_view.offset_top = 47
	graph_view.offset_right = -16
	graph_view.offset_bottom = -98
	graph_view.show_menu = false
	graph_view.minimap_enabled = false
	graph_view.show_grid = true
	graph_view.grid_pattern = 1
	graph_view.snapping_enabled = true
	graph_view.snapping_distance = 20
	graph_view.zoom_min = 0.35
	graph_view.zoom_max = 2
	graph_view.right_disconnects = false
	# Permit pulling a cable off an input; outputs remain available for fan-out.
	graph_view.add_valid_right_disconnect_type(0)
	graph_view.connection_lines_thickness = 0
	graph_view.connection_lines_antialiased = false
	var canvas_background := StyleBoxFlat.new()
	canvas_background.bg_color = Color("0a6455")
	graph_view.add_theme_stylebox_override("panel", canvas_background)
	graph_view.add_theme_color_override("grid_minor", Color(0.45, 0.72, 0.61, 0.25))
	graph_view.add_theme_color_override("grid_major", Color(0.45, 0.72, 0.61, 0.4))
	graph_view.add_theme_color_override("activity", CircuitSkin.SIGNAL_ON)
	add_child(graph_view)
	CircuitSkin.hide_scrollbar_visuals(graph_view)
	var wires = WiresScript.new()
	wires.name = "CableArtwork"
	wires.canvas = graph_view
	wires.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_view.add_child(wires)
	graph_view.component_dropped.connect(_on_component_dropped)
	graph_view.connection_request.connect(_on_connection_request)
	graph_view.disconnection_request.connect(_on_disconnection_request)
	graph_view.delete_nodes_request.connect(_on_delete_nodes)
	graph_view.fit_requested.connect(fit_view)
	graph_view.undo_requested.connect(undo)
	graph_view.redo_requested.connect(redo)
	graph_view.begin_node_move.connect(func(): _move_before = graph_model.snapshot())
	graph_view.end_node_move.connect(_on_end_move)

	status_label = Label.new()
	status_label.anchor_right = 1
	status_label.offset_left = 218
	status_label.offset_right = -18
	status_label.offset_top = 11
	status_label.offset_bottom = 35
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.label(status_label, 7, UI.MUTED)
	add_child(status_label)
	_update_help()


func _tool(parent: HBoxContainer, caption: String, hint: String, callback: Callable, expand_icon: bool = false) -> Button:
	var button: Button = ExpandButtonScript.new() if expand_icon else ToolButtonScript.new()
	button.text = caption
	button.tooltip_text = hint
	button.custom_minimum_size = Vector2(27, 30)
	UI.button(button)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(color, Color.TRANSPARENT)
	button.add_theme_font_size_override("font_size", 7)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxTexture
		style.content_margin_left = 6
		style.content_margin_right = 6
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func setup_workbench(lvl: Dictionary, d_tree: Dictionary, s_tree: Dictionary) -> void:
	var preserve := int(level_dict.get("id", -1)) == int(lvl["id"]) and is_same(diesel_tree, d_tree) and is_same(shed_tree, s_tree)
	level_dict = lvl
	diesel_tree = d_tree
	shed_tree = s_tree
	set_locked(false)
	if preserve:
		return
	graph_model.import_trees(diesel_tree, shed_tree, bool(lvl.get("has_shed_actuator", false)))
	undo_stack.clear()
	redo_stack.clear()
	_views.clear()
	_build_palette()
	_rebuild_graph()
	call_deferred("fit_view")


func _build_palette() -> void:
	for child in palette.get_children():
		palette.remove_child(child)
		child.queue_free()
	for kind in level_dict.get("available_gates", []):
		if kind != "WIRE":
			_palette_button(String(kind), "")
	for sensor in level_dict.get("available_sensors", []):
		_palette_button("SENSOR", String(sensor))


func _palette_button(kind: String, sensor: String) -> void:
	var item = PaletteScript.new()
	item.text = sensor if kind == "SENSOR" else kind
	item.component_data = {"drag_type": "circuit_component", "kind": kind, "sensor": sensor}
	item.tooltip_text = "Tarik ke papan: " + item.text
	UI.button(item)
	var font_size := 7
	item.add_theme_font_size_override("font_size", font_size)
	item.custom_minimum_size = Vector2(maxf(54, UI.FONT.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14), 54)
	# One uninterrupted tray; hover and press still use the user's button states.
	var normal := StyleBoxEmpty.new()
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("disabled", normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		var style := item.get_theme_stylebox(state).duplicate() as StyleBoxTexture
		style.content_margin_left = 6
		style.content_margin_right = 6
		item.add_theme_stylebox_override(state, style)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		item.add_theme_color_override(color, Color.TRANSPARENT)
	item.pressed.connect(func():
		_on_component_dropped(item.component_data, (graph_view.scroll_offset + graph_view.size * 0.5) / graph_view.zoom)
	)
	palette.add_child(item)


func _rebuild_graph() -> void:
	_rebuild_queued = false
	_rebuilding = true
	_render_revision += 1
	graph_view.clear_connections()
	for view in graph_nodes.values():
		graph_view.remove_child(view)
		view.queue_free()
	graph_nodes.clear()
	for id in graph_model.nodes:
		var view = NodeScript.new()
		view.configure(id, graph_model.nodes[id])
		view.draggable = not is_locked
		graph_view.add_child(view)
		graph_nodes[id] = view
		view.position_offset_changed.connect(func():
			if not _rebuilding and graph_model.nodes.has(id):
				graph_model.nodes[id]["position"] = view.position_offset
		)
	_rebuilding = false
	call_deferred("_sync_connections", _render_revision)
	_refresh_signals()
	_update_buttons()


func _sync_connections(revision: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _render_revision:
		return
	graph_view.clear_connections()
	for target in graph_model.nodes:
		for port in graph_model.nodes[target]["inputs"]:
			var source := int(graph_model.nodes[target]["inputs"][port])
			graph_view.connect_node(graph_nodes[source].name, 0, graph_nodes[target].name, int(port))


func _on_component_dropped(data: Dictionary, at: Vector2) -> void:
	if is_locked:
		return
	var kind := String(data.get("kind", ""))
	var sensor := String(data.get("sensor", ""))
	if kind == "SENSOR":
		if not sensor in level_dict.get("available_sensors", []):
			return
	elif kind == "WIRE" or not kind in level_dict.get("available_gates", []):
		return
	_push_undo(graph_model.snapshot())
	graph_model.add_component(kind, sensor, (at - Vector2(70, 35)).snapped(Vector2(10, 10)))
	_commit_graph()
	show_message("Komponen ditambahkan. Tarik output ke pin input untuk menyambung.")


func _id_from_name(node_name: StringName) -> int:
	return String(node_name).trim_prefix("Component").to_int()


func _on_connection_request(from_name: StringName, _from_port: int, to_name: StringName, to_port: int) -> void:
	if is_locked:
		return
	var source := _id_from_name(from_name)
	var target := _id_from_name(to_name)
	if not graph_model.can_connect(source, target, to_port):
		show_message(graph_model.last_error, true)
		return
	if int(graph_model.nodes[target]["inputs"].get(to_port, 0)) == source:
		return
	_push_undo(graph_model.snapshot())
	graph_model.connect_nodes(source, target, to_port)
	_commit_graph(false)
	show_message("Kabel terpasang.")


func _on_disconnection_request(from_name: StringName, _from_port: int, to_name: StringName, to_port: int) -> void:
	if is_locked:
		return
	var target := _id_from_name(to_name)
	if not graph_model.nodes.has(target) or int(graph_model.nodes[target]["inputs"].get(to_port, 0)) != _id_from_name(from_name):
		return
	_push_undo(graph_model.snapshot())
	graph_model.disconnect_input(target, to_port)
	graph_view.disconnect_node(from_name, 0, to_name, to_port)
	_commit_graph(false)
	show_message("Kabel dilepas. Sambungkan ke pin yang baru.")


func _commit_graph(rebuild_nodes: bool = true) -> void:
	var compiled: Dictionary = graph_model.compile_trees()
	diesel_tree = compiled["diesel"]
	shed_tree = compiled["shed"]
	if rebuild_nodes:
		if not _rebuild_queued:
			_rebuild_queued = true
			call_deferred("_run_queued_rebuild")
	else:
		_render_revision += 1
		call_deferred("_sync_connections", _render_revision)
	circuit_changed.emit()


func _run_queued_rebuild() -> void:
	if _rebuild_queued:
		_rebuild_graph()


func delete_selected() -> void:
	var selected: Array[StringName] = []
	for view in graph_nodes.values():
		if view.selected:
			selected.append(view.name)
	_on_delete_nodes(selected)


func _on_delete_nodes(names: Array[StringName]) -> void:
	if is_locked:
		return
	var before: Dictionary = graph_model.snapshot()
	var changed := false
	for node_name in names:
		var id := _id_from_name(node_name)
		if graph_model.nodes.has(id) and not graph_model.is_actuator(id):
			graph_model.remove_component(id)
			changed = true
	if changed:
		_push_undo(before)
		_commit_graph()
	else:
		show_message("Pilih gerbang atau sensor yang ingin dihapus.")


func _on_end_move() -> void:
	if not _move_before.is_empty() and not is_locked:
		_push_undo(_move_before, true)
	_move_before = {}


func _push_undo(saved: Dictionary, layout_only: bool = false) -> void:
	undo_stack.append({"state": saved, "layout_only": layout_only})
	if undo_stack.size() > 50:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_buttons()


func undo() -> void:
	_history_step(undo_stack, redo_stack)


func redo() -> void:
	_history_step(redo_stack, undo_stack)


func _history_step(source: Array[Dictionary], target: Array[Dictionary]) -> void:
	if is_locked or source.is_empty():
		return
	var entry: Dictionary = source.pop_back()
	target.append({"state": graph_model.snapshot(), "layout_only": entry["layout_only"]})
	var runtime: Dictionary = {}
	for id in graph_model.nodes:
		runtime[id] = graph_model.nodes[id]["runtime"]
	graph_model.restore(entry["state"])
	if entry["layout_only"]:
		for id in graph_model.nodes:
			graph_model.nodes[id]["runtime"] = runtime.get(id, {})
		_rebuild_graph()
	else:
		_commit_graph()


func can_simulate() -> bool:
	var problem: String = graph_model.validation_message()
	if not problem.is_empty():
		show_message(problem, true)
		return false
	return true


func set_locked(locked: bool) -> void:
	is_locked = locked
	if graph_view == null:
		return
	graph_view.locked = locked
	graph_view.cancel_connection_drag()
	for view in graph_nodes.values():
		view.draggable = not locked
	for item in palette.get_children():
		item.disabled = locked
	_update_buttons()
	_update_help()


func close_picker() -> void:
	# Called by the main controller when hiding the drawer.
	if graph_view != null:
		graph_view.cancel_connection_drag()


func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	_views[expanded] = {"zoom": graph_view.zoom, "scroll": graph_view.scroll_offset}
	expanded = value
	bottom_dock.offset_left = 548 if expanded else 16
	expand_button.expanded = expanded
	expand_button.tooltip_text = "Kecilkan panel rangkaian" if expanded else "Perbesar panel rangkaian"
	call_deferred("_restore_view")


func _restore_view() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _views.has(expanded):
		graph_view.zoom = _views[expanded]["zoom"]
		await get_tree().process_frame
		graph_view.scroll_offset = _views[expanded]["scroll"]
	else:
		fit_view()
	_refresh_tray_visuals()


func fit_view() -> void:
	await get_tree().process_frame
	if graph_nodes.is_empty():
		return
	var bounds := Rect2()
	var first := true
	for view in graph_nodes.values():
		var rect := Rect2(view.position_offset, view.size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	var available := graph_view.size - Vector2(54, 42)
	# Keep the initial expanded composition above the floating frequency plot.
	if expanded:
		available.y -= 180
	available.y = maxf(100, available.y)
	graph_view.zoom = clampf(minf(available.x / maxf(1, bounds.size.x), available.y / maxf(1, bounds.size.y)), graph_view.zoom_min, 1.25)
	graph_view.scroll_offset = bounds.position * graph_view.zoom - Vector2(26, 20) + Vector2(0, minf(0, bounds.size.y * graph_view.zoom - available.y) * 0.5)


func update_from_sim(state: Dictionary) -> void:
	latest_sensors = state.get("sensors", {})
	_refresh_signals()


func _refresh_signals() -> void:
	if graph_view == null:
		return
	var values: Dictionary = {}
	for id in graph_model.nodes:
		var high: bool = graph_model.value(id, latest_sensors, values)
		var inputs: Array[bool] = []
		var connected: Array[bool] = []
		for port in range(graph_model.input_count(id)):
			var source := int(graph_model.nodes[id]["inputs"].get(port, 0))
			connected.append(source != 0)
			inputs.append(graph_model.value(source, latest_sensors, values) if source != 0 else false)
		if graph_nodes.has(id):
			graph_nodes[id].update_signals(high, inputs, connected)


func _process(delta: float) -> void:
	if graph_view != null:
		_refresh_signals()
	if _status_time > 0:
		_status_time -= delta
		if _status_time <= 0:
			_update_help()


func _update_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = is_locked or undo_stack.is_empty()
		redo_button.disabled = is_locked or redo_stack.is_empty()
		delete_button.disabled = is_locked


func show_message(message: String, error: bool = false) -> void:
	status_label.text = message
	status_label.tooltip_text = message
	status_label.add_theme_color_override("font_color", UI.ALERT if error else UI.MUTED)
	_status_time = 5


func _update_help() -> void:
	if status_label == null:
		return
	status_label.text = "Simulasi aktif - pan & zoom tersedia" if is_locked else "Hubungkan sensor, gerbang, dan keluaran."
	status_label.tooltip_text = "Tarik komponen dari bar bawah. Tarik output ke input untuk memasang kabel. Scroll: zoom. MMB / Spasi+drag: geser. Ctrl+Z / Ctrl+Y: undo / redo."
	status_label.add_theme_color_override("font_color", UI.MUTED)


func _draw() -> void:
	draw_style_box(CircuitSkin.board_frame(), Rect2(Vector2.ZERO, size))


static func draw_gate_symbol(canvas: CanvasItem, rect: Rect2, gate_type: String, is_high: bool, is_hov: bool) -> void:
	CircuitSkin.gate(canvas, rect.grow_individual(12, 0, 12, 0), gate_type, is_high, is_hov)

extends GraphNode

const UI := preload("res://scripts/upper_hud_skin.gd")
const CircuitSkin := preload("res://scripts/circuit_ui_skin.gd")
var component_id := 0
var component: Dictionary = {}
var output_high := false
var input_values: Array[bool] = []
var input_connected: Array[bool] = []
var _last_state := ""
var _face: StyleBoxTexture
var _selected_face: StyleBoxTexture
var _moving := false
var _drag_delta := Vector2.ZERO
var _drag_positions: Dictionary = {}


func configure(id: int, data: Dictionary) -> void:
	component_id = id
	component = data
	name = "Component%d" % id
	position_offset = data["position"]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	var kind := String(data["kind"])
	var actuator := kind in ["DIESEL", "PADAM"]
	var sensor := kind == "SENSOR"
	var binary := kind in ["AND", "OR", "LATCH"]
	custom_minimum_size = Vector2(164 if sensor else 146, 0)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 10
	empty.content_margin_right = 10
	add_theme_stylebox_override("panel", empty)
	# The artwork supplies the selection contour; never surround gates with a box.
	add_theme_stylebox_override("panel_selected", empty.duplicate())
	add_theme_stylebox_override("panel_focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("titlebar", StyleBoxEmpty.new())
	add_theme_stylebox_override("titlebar_selected", StyleBoxEmpty.new())
	get_titlebar_hbox().hide()
	for title_child in get_titlebar_hbox().get_children():
		title_child.hide()
	add_theme_constant_override("separation", 0)
	add_theme_constant_override("port_h_offset", 0)
	_face = UI.frame(UI.PANEL, 8, 4)
	_selected_face = UI.frame(UI.CREAM[1], 8, 4)
	var latch := kind == "LATCH"
	# Align real GraphEdit hit targets to the S/R/Q lettering in the new export.
	# Spacer rows preserve the overall node height and its existing saved positions.
	var latch_heights := [11, 22, 8, 22, 15]
	for row_index in range(5 if latch else (3 if binary else 1)):
		var row := Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size.y = latch_heights[row_index] if latch else (26 if binary else (52 if sensor or actuator else 78))
		add_child(row)
		var left := (binary and row_index != 1) or (not binary and not sensor)
		var right := (row_index == 1 if binary else true) and not actuator
		if latch:
			left = row_index in [1, 3]
			right = row_index == 2
		set_slot(row_index, left, 0, CircuitSkin.SIGNAL_OFF, right, 0, CircuitSkin.SIGNAL_OFF, null, null, false)
	tooltip_text = String(data["sensor"]) if sensor else kind
	if not sensor and not actuator:
		tooltip_text += ": tarik pin untuk memasang kabel"
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	call_deferred("_refresh_after_layout")


func _refresh_after_layout() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_last_state = ""


func _gui_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Port gestures belong to GraphEdit; the rest of the symbol is draggable.
			for port in range(get_input_port_count()):
				if event.position.distance_to(get_input_port_position(port)) < 15:
					return
			for port in range(get_output_port_count()):
				if event.position.distance_to(get_output_port_position(port)) < 15:
					return
			if not selected and not event.shift_pressed and not event.ctrl_pressed:
				for sibling in get_parent().get_children():
					if sibling is GraphNode:
						sibling.selected = false
			selected = not selected if event.shift_pressed or event.ctrl_pressed else true
			if not selected:
				accept_event()
				return
			_moving = true
			get_parent().grab_focus()
			_drag_delta = Vector2.ZERO
			_drag_positions.clear()
			for sibling in get_parent().get_children():
				if sibling is GraphNode and sibling.selected:
					_drag_positions[sibling] = sibling.position_offset
			get_parent().begin_node_move.emit()
			raise_request.emit()
			accept_event()
		elif _moving:
			_moving = false
			get_parent().end_node_move.emit()
			accept_event()
	elif event is InputEventMouseMotion and _moving:
		_drag_delta += event.relative / get_parent().zoom
		for view in _drag_positions:
			var target: Vector2 = _drag_positions[view] + _drag_delta
			view.position_offset = target.snapped(Vector2.ONE * get_parent().snapping_distance)
		accept_event()


func update_signals(high: bool, values: Array[bool], connected: Array[bool]) -> void:
	var signature := str([high, values, connected])
	if signature == _last_state:
		return
	_last_state = signature
	output_high = high
	input_values = values
	input_connected = connected
	for port in range(get_input_port_count()):
		var slot := get_input_port_slot(port)
		var color := Color("e08072") if not connected[port] else (CircuitSkin.SIGNAL_ON if values[port] else CircuitSkin.SIGNAL_OFF)
		if get_slot_color_left(slot) != color:
			set_slot_color_left(slot, color)
	for port in range(get_output_port_count()):
		var slot := get_output_port_slot(port)
		var color := CircuitSkin.SIGNAL_ON if high else CircuitSkin.SIGNAL_OFF
		if get_slot_color_right(slot) != color:
			set_slot_color_right(slot, color)
	queue_redraw()


func _draw() -> void:
	if component.is_empty():
		return
	var kind := String(component["kind"])
	if kind == "SENSOR" or kind in ["DIESEL", "PADAM"]:
		draw_style_box(_selected_face if selected else _face, Rect2(Vector2(3, 1), size - Vector2(6, 2)))
		var caption := String(component["sensor"]) if kind == "SENSOR" else kind
		CircuitSkin.text(self, caption, Rect2(12, 5, size.x - 24, 24), 10, UI.INK, true)
		var subtitle := ("1 / AKTIF" if output_high else "0 / NONAKTIF") if kind == "SENSOR" else (("PLTD " if kind == "DIESEL" else "DUSUN 3 ") + ("ON" if output_high else "OFF"))
		CircuitSkin.text(self, subtitle, Rect2(12, 29, size.x - 24, 17), 8, UI.TEAL if output_high else UI.MUTED, true)
		return
	var bounds := Rect2(20, 2, size.x - 40, size.y - 4)
	var body: Rect2
	if CircuitSkin.GATES.has(kind):
		var highlighted := selected or output_high
		# The yellow state already has the artist's outline, so preserve it exactly.
		var texture := CircuitSkin.outlined_texture(CircuitSkin.GATES[kind][1 if highlighted else 0], not highlighted)
		body = CircuitSkin.fit_rect(texture, bounds)
		for port in range(get_input_port_count()):
			var start := get_input_port_position(port)
			draw_line(start, Vector2(body.position.x + 12, start.y), CircuitSkin.SIGNAL_ON if input_values.size() > port and input_values[port] else CircuitSkin.SIGNAL_OFF, 3)
		if get_output_port_count() > 0:
			var output := get_output_port_position(0)
			draw_line(Vector2(body.end.x - 8, output.y), output, CircuitSkin.SIGNAL_ON if output_high else CircuitSkin.SIGNAL_OFF, 3)
		draw_texture_rect(texture, body, false)


func _draw_port(_slot_index: int, at: Vector2i, _left: bool, color: Color) -> void:
	draw_circle(Vector2(at), 8, Color("17292c"))
	CircuitSkin.port(self, Vector2(at), color == CircuitSkin.SIGNAL_ON, 13)
	if color == Color("e08072"):
		draw_arc(Vector2(at), 6, 0, TAU, 20, color, 2)

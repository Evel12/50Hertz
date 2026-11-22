extends GraphEdit

signal component_dropped(data: Dictionary, at: Vector2)
signal fit_requested()
signal undo_requested()
signal redo_requested()
var locked := false
var space_held := false
var panning := false
var connection_dragging := false
var occlusion: Control
var drag_origin: StringName
var drag_port := 0
var drag_is_output := true


func _ready() -> void:
	connection_drag_started.connect(func(node, port, output):
		connection_dragging = true
		drag_origin = node
		drag_port = port
		drag_is_output = output
	)
	connection_drag_ended.connect(func(): connection_dragging = false)
	# Hide the native wire paint; the model and port interactions remain native.
	var native_wires := get_node_or_null("_connection_layer") as CanvasItem
	if native_wires != null:
		native_wires.modulate.a = 0


func cancel_connection_drag() -> void:
	if connection_dragging:
		force_connection_drag_end()
		connection_dragging = false


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return not locked and data is Dictionary and data.get("drag_type", "") == "circuit_component"


func _drop_data(at: Vector2, data: Variant) -> void:
	component_dropped.emit(data, (at + scroll_offset) / zoom)


func zoom_at(at: Vector2, factor: float) -> void:
	var point := (at + scroll_offset) / zoom
	zoom = clampf(zoom * factor, zoom_min, zoom_max)
	scroll_offset = point * zoom - at


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		panning = false
		space_held = false
		return
	var inside := get_global_rect().has_point(get_global_mouse_position())
	if is_instance_valid(occlusion) and occlusion.is_visible_in_tree() and occlusion.get_global_rect().has_point(get_global_mouse_position()):
		inside = false
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and (inside or space_held):
			space_held = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and not event.echo and (inside or has_focus()):
			if event.ctrl_pressed and event.keycode == KEY_Z:
				if event.shift_pressed:
					redo_requested.emit()
				else:
					undo_requested.emit()
			elif event.ctrl_pressed and event.keycode == KEY_Y:
				redo_requested.emit()
			elif event.keycode == KEY_F:
				fit_requested.emit()
			elif event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
				var selected_nodes: Array[StringName] = []
				for child in get_children():
					if child is GraphNode and child.selected:
						selected_nodes.append(child.name)
				delete_nodes_request.emit(selected_nodes)
			elif event.keycode in [KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
				zoom_at(size * 0.5, 1.15 if event.keycode in [KEY_EQUAL, KEY_KP_ADD] else 1.0 / 1.15)
			else:
				return
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if inside and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(get_local_mouse_position(), 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and (space_held or panning)):
			if inside or panning:
				panning = event.pressed
				mouse_default_cursor_shape = Control.CURSOR_DRAG if panning else Control.CURSOR_ARROW
				get_viewport().set_input_as_handled()
		elif inside and locked and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and panning:
		scroll_offset -= event.relative
		get_viewport().set_input_as_handled()


func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var guides := PackedVector2Array([from_position])
	var stub := 24 * zoom
	if to_position.x - from_position.x < stub * 2:
		# Route backwards connections around the symbols instead of through them.
		var above := minf(from_position.y, to_position.y) - 56 * zoom
		guides.append(Vector2(from_position.x + stub, from_position.y))
		guides.append(Vector2(from_position.x + stub, above))
		guides.append(Vector2(to_position.x - stub, above))
		guides.append(Vector2(to_position.x - stub, to_position.y))
	elif absf(from_position.y - to_position.y) > zoom:
		var middle := (from_position.x + to_position.x) * 0.5
		guides.append(Vector2(middle, from_position.y))
		guides.append(Vector2(middle, to_position.y))
	guides.append(to_position)
	var points := PackedVector2Array([guides[0]])
	for i in range(1, guides.size() - 1):
		var corner := guides[i]
		var incoming := guides[i - 1] - corner
		var outgoing := guides[i + 1] - corner
		var radius := minf(7 * zoom, minf(incoming.length(), outgoing.length()) * 0.45)
		if radius < 0.01:
			continue
		var entry := corner + incoming.normalized() * radius
		var exit := corner + outgoing.normalized() * radius
		points.append(entry)
		for step in range(1, 6):
			var t := step / 5.0
			points.append(entry * (1 - t) * (1 - t) + corner * 2 * (1 - t) * t + exit * t * t)
	points.append(guides[-1])
	return points


func _is_in_input_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	# GraphEdit supplies this mouse position before its canvas zoom transform.
	var origin: Vector2 = in_node.position / in_node.scale
	var point: Vector2 = origin + in_node.get_input_port_position(in_port)
	var distance := mouse_position.distance_to(point)
	if distance * zoom > 16:
		return false
	# Closely spaced S/R pins must remain distinct even when zoomed out.
	for other in range(in_node.get_input_port_count()):
		if other == in_port:
			continue
		var other_distance := mouse_position.distance_to(origin + in_node.get_input_port_position(other))
		if other_distance < distance or (is_equal_approx(other_distance, distance) and other < in_port):
			return false
	return true


func _is_in_output_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	var point: Vector2 = in_node.position / in_node.scale + in_node.get_output_port_position(in_port)
	return mouse_position.distance_to(point) * zoom <= 16

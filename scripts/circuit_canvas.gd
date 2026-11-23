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


func _over_component() -> bool:
	var point := get_global_mouse_position()
	for child in get_children():
		# Include the port hit areas so starting a cable never pans the board.
		if child is GraphNode and child.visible and child.get_global_rect().grow(16).has_point(point):
			return true
	return false


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
		if inside and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not locked:
			var cable := connection_at(get_local_mouse_position())
			if not cable.is_empty():
				disconnection_request.emit(cable["from_node"],int(cable["from_port"]),cable["to_node"],int(cable["to_port"]))
				get_viewport().set_input_as_handled()
				return
		if inside and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(get_local_mouse_position(), 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and (space_held or panning or (event.pressed and inside and not get_viewport().gui_is_dragging() and not connection_dragging and not _over_component()))):
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
	return PackedVector2Array([from_position, to_position])



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

func connection_at(point: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := 9.0
	for cable in get_connection_list():
		var source := get_node_or_null(NodePath(cable["from_node"])) as GraphNode
		var target := get_node_or_null(NodePath(cable["to_node"])) as GraphNode
		if source == null or target == null: continue
		var from_port := int(cable["from_port"])
		var to_port := int(cable["to_port"])
		if from_port >= source.get_output_port_count() or to_port >= target.get_input_port_count(): continue
		var start := source.position + source.get_output_port_position(from_port)*source.scale
		var end := target.position + target.get_input_port_position(to_port)*target.scale
		var points := get_connection_line(start,end)
		for i in range(1,points.size()):
			var hit := Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i])
			var current := hit.distance_to(point)
			if current < distance:
				distance = current
				nearest = cable
	return nearest

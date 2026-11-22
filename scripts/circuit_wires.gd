extends Control
## Draw the user's cable strips along GraphEdit's routes, behind component ports.
const CircuitSkin := preload("res://scripts/circuit_ui_skin.gd")
var canvas: GraphEdit
var animation_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	clip_contents = true


func _process(delta: float) -> void:
	animation_time += delta
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if canvas == null:
		return
	for connection in canvas.get_connection_list():
		var source := canvas.get_node_or_null(NodePath(connection["from_node"])) as GraphNode
		var target := canvas.get_node_or_null(NodePath(connection["to_node"])) as GraphNode
		var input_port := int(connection["to_port"])
		if source == null or target == null or source.get_output_port_count() == 0 or input_port >= target.get_input_port_count():
			continue
		var start := source.position + source.get_output_port_position(0) * source.scale
		var end := target.position + target.get_input_port_position(input_port) * target.scale
		_draw_cable(canvas.get_connection_line(start, end), bool(source.get("output_high")))
	if canvas.connection_dragging:
		var origin := canvas.get_node_or_null(NodePath(canvas.drag_origin)) as GraphNode
		if origin == null:
			return
		var port := int(canvas.drag_port)
		if canvas.drag_is_output and port < origin.get_output_port_count():
			var start := origin.position + origin.get_output_port_position(port) * origin.scale
			_draw_cable(canvas.get_connection_line(start, canvas.get_local_mouse_position()), false, true)
		elif not canvas.drag_is_output and port < origin.get_input_port_count():
			var end := origin.position + origin.get_input_port_position(port) * origin.scale
			_draw_cable(canvas.get_connection_line(canvas.get_local_mouse_position(), end), false, true)


func _draw_cable(points: PackedVector2Array, high: bool, preview: bool = false) -> void:
	if points.size() < 2:
		return
	var width := maxf(1.5, 3.5 * canvas.zoom)
	var alpha := 0.65 if preview else 1.0
	draw_polyline(points, Color(0.04, 0.15, 0.15, alpha), width + 2 * canvas.zoom, false)
	var texture := CircuitSkin.cable_strip(high)
	var texture_scale := width / texture.get_height()
	var phase := -animation_time * 80 if high else 0.0
	var traveled := 0.0
	for i in range(points.size() - 1):
		var segment := points[i + 1] - points[i]
		var length := segment.length()
		if length < 0.01:
			continue
		draw_set_transform(points[i], segment.angle())
		draw_texture_rect_region(texture, Rect2(0, -width * 0.5, length + 0.3, width), Rect2(phase + traveled / texture_scale, 0, length / texture_scale, texture.get_height()), Color(1, 1, 1, alpha), false, false)
		traveled += length
	draw_set_transform(Vector2.ZERO)

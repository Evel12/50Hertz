@tool
extends Control
var sim
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	var green := Color("4be0a0")
	draw_rect(Rect2(0, size.y * 0.1875, size.x, size.y * 0.625), Color("19433a"))
	for hz in [49.5, 50.0, 50.5]:
		var y: float = (50.8 - hz) / 1.6 * size.y
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("52666c"), 1)
	if sim == null or sim.history.size() < 2: return
	var points := PackedVector2Array()
	for i in range(sim.history.size()):
		points.append(Vector2(i * size.x / (float(sim.stage.duration) * 5), (50.8 - clampf(sim.history[i], 49.2, 50.8)) / 1.6 * size.y))
	draw_polyline(points, green, 2, true)

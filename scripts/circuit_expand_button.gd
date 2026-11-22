extends "res://scripts/circuit_tool_button.gd"
## Fullscreen corners drawn in Godot, with the same press offset as the UI frame.
var expanded := false:
	set(value):
		expanded = value
		queue_redraw()


func _draw() -> void:
	super._draw()
	var center := (size * 0.5).round()
	if get_draw_mode() == BaseButton.DRAW_PRESSED:
		center.y += 2
	for x_sign in [-1, 1]:
		for y_sign in [-1, 1]:
			var direction := Vector2(x_sign, y_sign)
			var corner := center + direction * (3 if expanded else 8)
			var inward := -1 if expanded else 1
			var points := PackedVector2Array([
				corner - Vector2(x_sign * 5 * inward, 0), corner,
				corner - Vector2(0, y_sign * 5 * inward)])
			draw_polyline(points, UI.INK, 2, false)

extends "res://scripts/circuit_tool_button.gd"
## Small, framed minimize/restore control that follows the supplied button states.
var minimized := false:
	set(value):
		minimized = value
		queue_redraw()

func _draw() -> void:
	super._draw()
	var pressed_offset := 2 if get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED] else 0
	var center := (size * 0.5 + Vector2(0, pressed_offset - 1)).round()
	draw_line(center + Vector2(-5, 0), center + Vector2(5, 0), UI.INK, 2)
	if minimized:
		draw_line(center + Vector2(0, -5), center + Vector2(0, 5), UI.INK, 2)

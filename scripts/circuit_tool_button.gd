extends Button
## Paint the supplied frame explicitly so it stays intact when the tray moves.
const UI := preload("res://scripts/upper_hud_skin.gd")
const CircuitSkin := preload("res://scripts/circuit_ui_skin.gd")


func _draw() -> void:
	var state := "normal"
	match get_draw_mode():
		BaseButton.DRAW_DISABLED: state = "disabled"
		BaseButton.DRAW_HOVER: state = "hover"
		BaseButton.DRAW_PRESSED: state = "pressed"
		BaseButton.DRAW_HOVER_PRESSED: state = "hover_pressed"
	draw_style_box(get_theme_stylebox(state), Rect2(Vector2.ZERO, size))
	var offset := 2 if state in ["pressed", "hover_pressed"] else 0
	CircuitSkin.text(self, text, Rect2(4, 2 + offset, size.x - 8, size.y - 7), 7, UI.MUTED if disabled else UI.INK, true)

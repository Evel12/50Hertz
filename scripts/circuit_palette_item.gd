extends Button

const UI := preload("res://scripts/upper_hud_skin.gd")
const CircuitSkin := preload("res://scripts/circuit_ui_skin.gd")
var component_data: Dictionary = {}
var _sensor_frame: StyleBoxTexture
var drag_preview := false


func _ready() -> void:
	_sensor_frame = UI.frame(UI.PANEL, 5, 2)


func _draw() -> void:
	if component_data.is_empty():
		return
	var state := "normal"
	match get_draw_mode():
		BaseButton.DRAW_HOVER: state = "hover"
		BaseButton.DRAW_PRESSED: state = "pressed"
		BaseButton.DRAW_HOVER_PRESSED: state = "hover_pressed"
		BaseButton.DRAW_DISABLED: state = "disabled"
	if not drag_preview: draw_style_box(get_theme_stylebox(state), Rect2(Vector2.ZERO, size))
	var offset := Vector2(0, 2) if get_draw_mode() == BaseButton.DRAW_PRESSED else Vector2.ZERO
	var color := Color(1, 1, 1, 0.45) if disabled else Color.WHITE
	var kind := String(component_data["kind"])
	var bounds := Rect2(Vector2(7, 3) + offset, Vector2(size.x - 14, 33))
	if drag_preview: bounds = Rect2(Vector2(7,3),size-Vector2(14,6))
	if CircuitSkin.GROUPS.has(kind):
		var highlighted := not disabled and state in ["hover", "pressed", "hover_pressed"]
		var art: Texture2D = CircuitSkin.GROUPS[kind][1 if highlighted else 0]
		draw_texture_rect(art, CircuitSkin.fit_rect(art, bounds), false, color)
	elif CircuitSkin.GATES.has(kind):
		var highlighted := not disabled and state in ["hover", "pressed", "hover_pressed"]
		var art := CircuitSkin.outlined_texture(CircuitSkin.GATES[kind][1 if highlighted else 0], not highlighted)
		draw_texture_rect(art, CircuitSkin.fit_rect(art, bounds), false, color)
	else:
		# Sensors keep their waveform symbol on the supplied frame.
		var face := Rect2(Vector2(9, 7) + offset, Vector2(size.x - 18, 27))
		if drag_preview: face = Rect2(Vector2.ZERO,size)
		if not drag_preview: draw_style_box(_sensor_frame, face)
		var center := face.get_center()
		var wave := PackedVector2Array([
			center + Vector2(-13, 4), center + Vector2(-6, 4),
			center + Vector2(-6, -4), center + Vector2(5, -4),
			center + Vector2(5, 4), center + Vector2(13, 4)])
		draw_polyline(wave, UI.TEAL * color, 2, false)
	if drag_preview: return
	CircuitSkin.text(self, text, Rect2(Vector2(3, size.y - 16) + offset, Vector2(size.x - 6, 13)), 7, UI.MUTED if disabled else UI.INK, true)


func _get_drag_data(_at: Vector2) -> Variant:
	if disabled:
		return null
	var preview := Button.new()
	preview.set_script(get_script())
	preview.component_data = component_data.duplicate()
	preview.text = text
	preview.drag_preview = true
	for state in ["normal","hover","pressed","focus"]:
		preview.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	preview.custom_minimum_size = Vector2(maxf(size.x,110),maxf(size.y,54))
	preview.size = preview.custom_minimum_size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UI.button(preview)
	for state in ["normal","hover","pressed","focus"]:
		preview.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	preview.modulate.a = 0.92
	var cursor_origin := Control.new()
	cursor_origin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_origin.add_child(preview)
	preview.position = -preview.size * 0.5
	set_drag_preview(cursor_origin)
	return component_data.duplicate()

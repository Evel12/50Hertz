extends RefCounted
## Draws the supplied circuit artwork. Original exports stay untouched.

const UI := preload("res://scripts/upper_hud_skin.gd")
const BOARD := preload("res://assetsui/Rangkaian Tempat Logic/Undetailed Version.png")
const WIRE := [preload("res://assetsui/Logic Gates/Kabel/Group 25.png"), preload("res://assetsui/Logic Gates/Kabel/Group 26.png")]
const PORT := [preload("res://assetsui/Logic Gates/Group 33.png"), preload("res://assetsui/Logic Gates/Group 32.png")]
# Body-only exports let each input connector reflect its own signal value.
const GATES := {
	"AND": [preload("res://assetsui/Logic Gates/39.png"), preload("res://assetsui/Logic Gates/40.png")],
	"OR": [preload("res://assetsui/Logic Gates/41.png"), preload("res://assetsui/Logic Gates/42.png")],
	"NOT": [preload("res://assetsui/Logic Gates/43.png"), preload("res://assetsui/Logic Gates/44.png")],
	# Group 41 is the complete selected export, including the Vector 94 yellow contour.
	"LATCH": [preload("res://assetsui/Group 40.png"), preload("res://assetsui/Group 41.png")],
}
const SIGNAL_ON := Color("ffde54")
const SIGNAL_OFF := Color("a0d2e7")
const BOARD_TEXT := Color("f5e7c6")
static var _board_style: StyleBoxTexture
static var _ports: Array[Texture2D] = []
static var _icons: Dictionary = {}
static var _outlined: Dictionary = {}
static var _cable_strips: Dictionary = {}
static var _invisible_icon: ImageTexture


static func board_frame() -> StyleBoxTexture:
	if _board_style == null:
		var pixels := BOARD.get_image()
		pixels.resize(562, 276, Image.INTERPOLATE_NEAREST)
		_board_style = StyleBoxTexture.new()
		_board_style.texture = ImageTexture.create_from_image(pixels)
		_board_style.texture_margin_left = 12
		_board_style.texture_margin_right = 12
		_board_style.texture_margin_top = 42
		_board_style.texture_margin_bottom = 22
	return _board_style


static func fit_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	var factor := minf(bounds.size.x / texture.get_width(), bounds.size.y / texture.get_height())
	var fitted_size := (texture.get_size() * factor).round()
	return Rect2((bounds.get_center() - fitted_size * 0.5).round(), fitted_size)


static func port(canvas: CanvasItem, center: Vector2, high: bool, diameter: float = 8) -> void:
	if _ports.is_empty():
		for source in PORT:
			var texture := AtlasTexture.new()
			texture.atlas = source
			# These exports include spare transparent space to the right of the ring.
			texture.region = Rect2(0, 0, 40, 40)
			_ports.append(texture)
	canvas.draw_texture_rect(_ports[1 if high else 0], Rect2(center.round() - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false)


static func outlined_texture(source: Texture2D, add_outline: bool = true) -> Texture2D:
	var key := "%d:%s" % [source.get_instance_id(), add_outline]
	if not _outlined.has(key):
		var original := source.get_image()
		original.convert(Image.FORMAT_RGBA8)
		var dimensions := original.get_size() + Vector2i(16, 16)
		var padded := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		padded.blit_rect(original, Rect2i(Vector2i.ZERO, original.get_size()), Vector2i(8, 8))
		if not add_outline:
			_outlined[key] = ImageTexture.create_from_image(padded)
			return _outlined[key]
		var mask := BitMap.new()
		mask.create_from_image_alpha(padded)
		mask.grow_mask(4, Rect2i(Vector2i.ZERO, dimensions))
		var outlined := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				if mask.get_bit(x, y):
					outlined.set_pixel(x, y, Color("13272a"))
		outlined.blend_rect(original, Rect2i(Vector2i.ZERO, original.get_size()), Vector2i(8, 8))
		_outlined[key] = ImageTexture.create_from_image(outlined)
	return _outlined[key]


static func cable_strip(high: bool) -> Texture2D:
	if not _cable_strips.has(high):
		var original: Image = WIRE[1 if high else 0].get_image()
		# Preserve the cream marks already drawn on the user's yellow cable.
		var strip_width := floori(float(original.get_width() - 88) / 32) * 32
		var region := Rect2i(44, original.get_height() / 2 - 7, strip_width, 14)
		_cable_strips[high] = ImageTexture.create_from_image(original.get_region(region))
	return _cable_strips[high]


static func hide_scrollbar_visuals(root: Node) -> void:
	if _invisible_icon == null:
		_invisible_icon = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for child in root.get_children(true):
		if child is ScrollBar:
			# Leave the scroll model enabled, with no painted thumb or reserved strip.
			child.modulate.a = 0
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for style in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
				child.add_theme_stylebox_override(style, StyleBoxEmpty.new())
			for icon_name in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
				child.add_theme_icon_override(icon_name, _invisible_icon)
		else:
			hide_scrollbar_visuals(child)


static func input_pin(rect: Rect2, gate_type: String, second: bool = false) -> Vector2:
	var fraction := 0.5 if gate_type in ["NOT", "WIRE"] else (0.75 if second else 0.25)
	if gate_type == "LATCH":
		fraction = 0.69 if second else 0.26
	return Vector2(rect.position.x + 4, rect.position.y + rect.size.y * fraction).round()


static func output_pin(rect: Rect2) -> Vector2:
	return Vector2(rect.end.x - 4, rect.get_center().y).round()


static func gate(canvas: CanvasItem, rect: Rect2, gate_type: String, high: bool, hovered: bool, input_a: bool = false, input_b: bool = false) -> void:
	if gate_type == "WIRE":
		var texture: Texture2D = WIRE[1 if high else 0]
		canvas.draw_texture_rect(texture, fit_rect(texture, rect), false)
		if hovered:
			canvas.draw_line(input_pin(rect, gate_type), output_pin(rect), SIGNAL_ON, 2)
		return

	var body_bounds := Rect2(rect.position + Vector2(16, 0), rect.size - Vector2(32, 0))
	var a_pin := input_pin(rect, gate_type)
	var b_pin := input_pin(rect, gate_type, true)
	var q_pin := output_pin(rect)
	var a_end := Vector2(body_bounds.position.x + 10, a_pin.y)
	canvas.draw_line(a_pin, a_end, SIGNAL_ON if input_a else SIGNAL_OFF, 2)
	if gate_type not in ["NOT", "WIRE"]:
		canvas.draw_line(b_pin, Vector2(a_end.x, b_pin.y), SIGNAL_ON if input_b else SIGNAL_OFF, 2)
	canvas.draw_line(Vector2(body_bounds.end.x - 8, q_pin.y), q_pin, SIGNAL_ON if high else SIGNAL_OFF, 2)

	if GATES.has(gate_type):
		var highlighted := high or hovered
		var texture := outlined_texture(GATES[gate_type][1 if highlighted else 0], not highlighted)
		canvas.draw_texture_rect(texture, fit_rect(texture, body_bounds), false)
	port(canvas, a_pin, input_a)
	if gate_type != "NOT":
		port(canvas, b_pin, input_b)
	port(canvas, q_pin, high)


static func text(canvas: CanvasItem, value: String, bounds: Rect2, font_size: int = 8, color: Color = BOARD_TEXT, centered: bool = false) -> void:
	var fitted_size := font_size
	while fitted_size > 6 and UI.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x > bounds.size.x:
		fitted_size -= 1
	var baseline := bounds.position.y + (bounds.size.y - UI.FONT.get_height(fitted_size)) * 0.5 + UI.FONT.get_ascent(fitted_size)
	canvas.draw_string(UI.FONT, Vector2(bounds.position.x, roundf(baseline)), value, HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT, bounds.size.x, fitted_size, color)


static func icon(gate_type: String) -> Texture2D:
	if not _icons.has(gate_type):
		var source: Texture2D
		if GATES.has(gate_type):
			source = GATES[gate_type][0]
		elif gate_type == "WIRE":
			source = WIRE[0]
		else:
			return null
		var image := source.get_image()
		var factor := minf(32.0 / image.get_width(), 20.0 / image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		_icons[gate_type] = ImageTexture.create_from_image(image)
	return _icons[gate_type]

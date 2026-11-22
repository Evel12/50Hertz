extends RefCounted
## Skin for the upper gameplay HUD only. Textures are the supplied Figma exports.

const FONT := preload("res://assetsui/PressStart2P-Regular.ttf")
const PANEL := preload("res://assetsui/Button.png")
const CORAL := [preload("res://assetsui/Default.png"), preload("res://assetsui/Hover.png"), preload("res://assetsui/Pressed.png"), preload("res://assetsui/Disabled.png")]
const CREAM := [preload("res://assetsui/Default2.png"), preload("res://assetsui/Hover2.png"), preload("res://assetsui/Pressed2.png"), preload("res://assetsui/Disabled2.png")]
const INK := Color("233c40")
const TEAL := Color("17655d")
const MUTED := Color("586660")
const ALERT := Color("a22f35")
const WARNING := Color("895415")
static var _hud_textures: Dictionary = {}


static func frame(texture: Texture2D = PANEL, horizontal_padding: float = 12.0, vertical_padding: float = 8.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	if not _hud_textures.has(texture):
		# The exports are large templates. Scale a runtime copy with nearest
		# filtering so small controls don't inherit oversized stepped corners.
		var pixels := texture.get_image()
		pixels.resize(pixels.get_width() / 2, pixels.get_height() / 2, Image.INTERPOLATE_NEAREST)
		_hud_textures[texture] = ImageTexture.create_from_image(pixels)
	style.texture = _hud_textures[texture]
	# Preserve the stepped corners and bottom shadow instead of stretching them.
	style.texture_margin_left = 6
	style.texture_margin_right = 6
	style.texture_margin_top = 5
	style.texture_margin_bottom = 7
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding + 3
	return style


static func label(node: Label, font_size: int = 9, color: Color = INK) -> void:
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func depressed_frame(texture: Texture2D, horizontal_padding: float = 10.0) -> StyleBoxTexture:
	var style := frame(texture, horizontal_padding, 6)
	# Sink the face and its text by two pixels while keeping the button's
	# minimum size and hit area fixed. The shorter face also collapses its shadow.
	style.expand_margin_top = -2
	style.content_margin_top += 2
	style.content_margin_bottom -= 2
	style.modulate_color = Color(0.94, 0.94, 0.94)
	return style


static func button(node: Button, primary: bool = false) -> void:
	var textures: Array = CORAL if primary else CREAM
	var states := ["normal", "hover", "pressed", "disabled", "hover_pressed"]
	var indices := [0, 1, 2, 3, 2]
	for i in range(states.size()):
		var style := depressed_frame(textures[indices[i]]) if states[i] in ["pressed", "hover_pressed"] else frame(textures[indices[i]], 10, 6)
		node.add_theme_stylebox_override(states[i], style)
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", 9)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, INK)
	node.add_theme_color_override("font_disabled_color", Color("53635d"))
	# Keyboard focus gets the same yellow outline as the exported hover state.
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("f4c955")
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(-3)
	node.add_theme_stylebox_override("focus", focus)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func select_speed(node: Button, selected: bool) -> void:
	node.set_pressed_no_signal(selected)
	# Keep the selected multiplier distinct after the pointer leaves it.
	node.add_theme_color_override("font_pressed_color", TEAL)
	node.add_theme_stylebox_override("pressed", depressed_frame(CREAM[1], 6))
	node.add_theme_stylebox_override("hover_pressed", depressed_frame(CREAM[1], 6))


static func progress(node: ProgressBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("d1be96")
	track.border_color = Color("a38e6d")
	track.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = TEAL
	node.add_theme_stylebox_override("background", track)
	node.add_theme_stylebox_override("fill", fill)

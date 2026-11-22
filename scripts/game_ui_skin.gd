extends RefCounted
## Shared pixel theme built from the player's Figma artwork.
const HUD := preload("res://scripts/upper_hud_skin.gd")
const FONT := HUD.FONT
const PAPER := Color("ffeac2")
const GREEN := Color("073f3c")
const GOLD := Color("f6cc64")
const MINT := Color("70edbe")
const RED := Color("ff9280")
const PAUSE_PAPER := preload("res://assetsui/Pause Menu/Vector 88.png")
const PAUSE_GREEN := preload("res://assetsui/Pause Menu/Vector 87.png")
static var textures: Dictionary = {}

static func panel(green: bool = false, padding: int = 20) -> StyleBoxTexture:
	var source: Texture2D = PAUSE_GREEN if green else PAUSE_PAPER
	if not textures.has(source):
		var pixels := source.get_image()
		pixels.resize(pixels.get_width() / 4, pixels.get_height() / 4, Image.INTERPOLATE_NEAREST)
		textures[source] = ImageTexture.create_from_image(pixels)
	var style := StyleBoxTexture.new()
	style.texture = textures[source]
	style.texture_margin_left = 14
	style.texture_margin_right = 14
	style.texture_margin_top = 14
	style.texture_margin_bottom = 14
	style.set_content_margin_all(padding)
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 9
	result.set_color("font_color", "Label", PAPER)
	result.set_color("default_color", "RichTextLabel", PAPER)
	for role in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
		result.set_font(role, "RichTextLabel", FONT)
	result.set_stylebox("panel", "TooltipPanel", HUD.frame())
	result.set_color("font_color", "TooltipLabel", HUD.INK)
	result.set_font_size("font_size", "TooltipLabel", 8)
	return result

static func label(value: String, font_size: int = 9, color: Color = PAPER, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = value
	HUD.label(node, font_size, color)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_constant_override("line_spacing", 6)
	return node

static func button(value: String, callback: Callable, primary: bool = false, width: int = 170) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size = Vector2(width, 44)
	HUD.button(node, primary)
	node.pressed.connect(callback)
	return node

static func rich_text() -> RichTextLabel:
	var node := RichTextLabel.new()
	node.add_theme_font_size_override("normal_font_size", 10)
	node.add_theme_color_override("default_color", PAPER)
	node.add_theme_constant_override("line_separation", 8)
	node.add_theme_constant_override("paragraph_separation", 8)
	node.scroll_active = true
	return node

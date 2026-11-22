extends Control
## Reassemble the original menu logo from the player's transparent vector exports.
const BOLT := preload("res://assetsui/Menu Screen/Detailed Version/Vector 63.png")
const LETTERS := [
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 75-1.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 76.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 77.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 78.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 79.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 80.png"),
	preload("res://assetsui/Menu Screen/Detailed Version/Vector 81.png")]
const UI := preload("res://scripts/upper_hud_skin.gd")
const TEXT := preload("res://scripts/circuit_ui_skin.gd")

func _ready() -> void:
	custom_minimum_size = Vector2(184, 38)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

func _draw() -> void:
	var origin := ((size - Vector2(184, 38)) * 0.5).round()
	draw_texture_rect(BOLT, Rect2(origin + Vector2(2, 2), Vector2(23, 34)), false)
	var x := origin.x + 34
	for i in range(LETTERS.size()):
		var texture: Texture2D = LETTERS[i]
		var width := roundf(texture.get_width() * 23.0 / texture.get_height())
		draw_texture_rect(texture, Rect2(x, origin.y + 2, width, 23), false)
		x += width + (7 if i == 1 else 2)
	TEXT.text(self, "DESA SUKAMAJU", Rect2(origin + Vector2(34, 28), Vector2(x - origin.x - 36, 9)), 6, UI.INK, true)

extends Control
## Keep the supplied illustration intact, with real hit targets over its buttons.
signal start_requested
signal rules_requested
signal credits_requested
signal exit_requested
const ART := preload("res://assetsui/Menu Screen/Undetailed Version.png")
const UI := preload("res://scripts/upper_hud_skin.gd")
var buttons: Array[Button] = []

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var captions := ["MULAI BERMAIN", "SETTINGS", "CREDITS", "KELUAR"]
	for i in range(4):
		var button := Button.new()
		button.text = captions[i]
		UI.button(button)
		button.add_theme_font_size_override("font_size", 12)
		button.name = ["StartButton", "RulesButton", "CreditsButton", "ExitButton"][i]
		add_child(button)
		buttons.append(button)
	buttons[0].pressed.connect(func(): start_requested.emit())
	buttons[1].pressed.connect(func(): rules_requested.emit())
	buttons[2].pressed.connect(func(): credits_requested.emit())
	buttons[3].pressed.connect(func(): exit_requested.emit())
	buttons[3].visible = not OS.has_feature("web")
	resized.connect(_layout)
	_layout()

func _art_rect() -> Rect2:
	var factor := maxf(size.x / ART.get_width(), size.y / ART.get_height())
	var extent := ART.get_size() * factor
	# Align to the top so widescreen crops only the empty floor, never the logo.
	return Rect2(Vector2((size.x - extent.x) * 0.5, 0), extent)

func _layout() -> void:
	var rect := _art_rect()
	for i in range(buttons.size()):
		buttons[i].position = rect.position + rect.size * Vector2(0.131, 0.285 + i * (0.370 / 3.0))
		buttons[i].size = rect.size * Vector2(0.210, 0.077)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(ART, _art_rect(), false)
	# Cover the three baked button frames before drawing the evenly spaced controls.
	var rect := _art_rect()
	draw_rect(Rect2(rect.position + rect.size * Vector2(0.120, 0.280), rect.size * Vector2(0.230, 0.350)), Color8(14, 68, 72))

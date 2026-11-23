extends Control
class_name Oscilloscope
## Live telemetry on the player's exported board; the right column is the mission.
const UI := preload("res://scripts/game_ui_skin.gd")
const ART := preload("res://assetsui/Frekuensi jaringan/Undetailed version.png")
const TextLayout := preload("res://scripts/circuit_ui_skin.gd")
const ToggleButton := preload("res://scripts/panel_toggle_button.gd")
const MIN_PLOT_HZ := 49.2
const MAX_PLOT_HZ := 50.8
const EXPANDED_HEIGHT := 222.0
const MINIMIZED_HEIGHT := 44.0
var minimized := false
var restored_height := EXPANDED_HEIGHT
var minimize_button: Button
var _collapsed_frame: StyleBoxTexture
var frequency := 50.0
var supply_kw := 92.0
var demand_kw := 92.0
var shown_supply := 92.0
var shown_demand := 92.0
var freq_history: Array[float] = []
var level: Dictionary = {}
var state: Dictionary = {}
var phase := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Kurva menunjukkan frekuensi simulasi. Hijau: 49.50-50.50 Hz.\nTujuan misi diperbarui selama operasi."
	_collapsed_frame = UI.HUD.frame(UI.HUD.PANEL, 10, 6)
	minimize_button = ToggleButton.new()
	minimize_button.name = "MinimizeFrequency"
	minimize_button.tooltip_text = "Minimalkan frekuensi jaringan"
	minimize_button.custom_minimum_size = Vector2(28, 22)
	UI.HUD.button(minimize_button)
	for state_name in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var style := minimize_button.get_theme_stylebox(state_name).duplicate() as StyleBoxTexture
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 3
		style.content_margin_bottom = 5
		minimize_button.add_theme_stylebox_override(state_name, style)
	minimize_button.pressed.connect(func(): set_minimized(not minimized))
	add_child(minimize_button)
	resized.connect(_layout_controls)
	_layout_controls()

func set_minimized(value: bool) -> void:
	if value == minimized: return
	if value: restored_height = size.y
	minimized = value
	size.y = MINIMIZED_HEIGHT if minimized else restored_height
	var handles := get_node_or_null("PanelHandles")
	if handles != null and handles.grip != null: handles.grip.visible = not minimized
	minimize_button.minimized = minimized
	minimize_button.tooltip_text = "Tampilkan frekuensi jaringan" if minimized else "Minimalkan frekuensi jaringan"
	_layout_controls()
	queue_redraw()

func _layout_controls() -> void:
	minimize_button.position = Vector2(roundf(size.x * 0.5 - 14), 10 if minimized else 17)
	minimize_button.size = Vector2(28, 22)
	queue_redraw()

func setup_level(data: Dictionary) -> void:
	level = data
	state = {}
	freq_history.clear()
	queue_redraw()

func update_from_sim(data: Dictionary) -> void:
	state = data.duplicate()
	frequency = float(data.get("frequency", 50.0))
	supply_kw = float(data.get("supply_kw", 92.0))
	demand_kw = float(data.get("demand_kw", 92.0))
	freq_history.clear()
	for sample in data.get("freq_history", []):
		freq_history.append(float(sample))
	if freq_history.is_empty():
		freq_history.append(frequency)
	queue_redraw()

func _process(delta: float) -> void:
	phase = fmod(phase + delta, 20.0)
	shown_supply = lerpf(shown_supply, supply_kw, 1.0 - exp(-delta * 12.0))
	shown_demand = lerpf(shown_demand, demand_kw, 1.0 - exp(-delta * 12.0))
	if is_visible_in_tree():
		queue_redraw()

func _label(value: String, bounds: Rect2, font_size: int = 7, color: Color = UI.PAPER, centered: bool = false) -> void:
	TextLayout.text(self, value, bounds, font_size, color, centered)

func _hz_to_y(value: float, rect: Rect2) -> float:
	return rect.end.y - clampf((value - MIN_PLOT_HZ) / (MAX_PLOT_HZ - MIN_PLOT_HZ), 0, 1) * rect.size.y

func get_objectives() -> Array[Dictionary]:
	if level.has("outputs"):
		var result: Array[Dictionary] = []
		for objective in level.get("hud_objectives", []):
			var okay := not bool(state.get("control_failed",false))
			if objective["title"]=="Jaringan tetap aman": okay = okay and frequency>=49.5 and frequency<=50.5
			if objective["title"]=="Puskesmas tetap hidup": okay = okay and bool(state.get("puskesmas_powered",true))
			result.append({"title":objective["title"],"value":objective["value"],"okay":okay})
		if result.is_empty(): result.append({"title":"Kendali sesuai misi","value":level.get("mission_summary",""),"okay":true})
		return result
	var safe := frequency >= 49.5 and frequency <= 50.5 and int(state.get("cascade_stage", 0)) == 0
	var end_min := int(level.get("end_min", 1290))
	var goals: Array[Dictionary] = [{"title": "Bertahan s/d %02d:%02d" % [end_min / 60, end_min % 60], "value": "Jaga 49.5-50.5 Hz", "okay": safe}]
	if bool(level.get("has_rice_mill", false)):
		goals.append({"title": "Penggilingan padi", "value": "Jaga tetap menyala", "okay": bool(state.get("dusun2_powered", true))})
	var max_starts := int(level.get("max_diesel_starts", 99))
	if max_starts < 99:
		var starts := int(state.get("diesel_starts", 0))
		goals.append({"title": "Start diesel", "value": "%d / %d kali" % [starts, max_starts], "okay": starts <= max_starts})
	if bool(level.get("has_shed_actuator", false)):
		var flickers := int(state.get("shed_flickers", 0))
		var max_flickers := int(level.get("max_shed_flickers", 3))
		goals.append({"title": "Kedip Dusun 3", "value": "%d / %d kali" % [flickers, max_flickers], "okay": flickers <= max_flickers})
		var minutes := int(state.get("shed_minutes", 0))
		var max_minutes := int(level.get("target_shed_minutes", 130))
		goals.append({"title": "Target padam D3", "value": "%d / %d menit" % [minutes, max_minutes], "okay": minutes <= max_minutes})
	return goals

func _bar(title: String, value: float, shown: float, y: float, color: Color, split: float) -> void:
	_label(title, Rect2(14, y, 56, 11), 7)
	var rect := Rect2(75, y, split - 143, 11)
	var max_kw := maxf(145.0, maxf(supply_kw, demand_kw) * 1.1)
	draw_rect(rect.grow(1), Color("032f2c"))
	draw_rect(rect, Color("1b7466"))
	var fill := Rect2(rect.position, Vector2(rect.size.x * clampf(shown / max_kw, 0, 1), rect.size.y))
	draw_rect(fill, color)
	if fill.size.x > 2:
		draw_line(fill.position, Vector2(fill.end.x, fill.position.y), color.lightened(0.4), 2)
	for i in range(1, 9):
		var x := rect.position.x + rect.size.x * i / 9.0
		draw_line(Vector2(x, y + 2), Vector2(x, y + 9), Color(0.01, 0.18, 0.16, 0.20))
	_label("%d kW" % roundi(value), Rect2(rect.end.x + 7, y, 59, 11), 7, color)

func _draw() -> void:
	if size.x < 100 or size.y < 32:
		return
	if minimized:
		draw_style_box(_collapsed_frame, Rect2(Vector2.ZERO, size))
		_label("FREKUENSI JARINGAN", Rect2(15, 5, size.x * 0.45, 31), 9, UI.HUD.INK)
		_label("%.2f Hz" % frequency, Rect2(size.x - 146, 5, 126, 31), 10, UI.HUD.TEAL if frequency >= 49.5 and frequency <= 50.5 else UI.HUD.ALERT, true)
		return
	draw_texture_rect(ART, Rect2(Vector2.ZERO, size), false)
	var split := size.x * 0.625
	_label("FREKUENSI JARINGAN", Rect2(15, 16, size.x * 0.45, 22), 9, UI.HUD.INK)
	_label("TUJUAN LEVEL", Rect2(size.x * 0.686, 3, size.x * 0.245, 33), 8, UI.HUD.INK, true)
	var safe := frequency >= 49.5 and frequency <= 50.5
	var color := UI.MINT if safe else UI.RED
	var plot := Rect2(size.x * 0.111, size.y * 0.245, size.x * 0.479, size.y * 0.442)
	var safe_top := _hz_to_y(50.5,plot)
	var safe_bottom := _hz_to_y(49.5,plot)
	draw_rect(Rect2(plot.position.x,safe_top,plot.size.x,safe_bottom-safe_top),Color(0.3,1,0.7,0.08))
	for threshold in [49.5,50.5]:
		var boundary := _hz_to_y(threshold,plot)
		draw_line(Vector2(plot.position.x,boundary),Vector2(plot.end.x,boundary),Color(1,0.6,0.45,0.6),1)
	for hz in [50.5, 50.0, 49.5]:
		var y := _hz_to_y(hz, plot)
		_label("%.1f" % hz, Rect2(12, y - 6, 35, 12), 7)
	# Draw only measured history, with a light sweep and a pulsing latest sample.
	var points := PackedVector2Array()
	var count := freq_history.size()
	if count < 2:
		points.append(Vector2(plot.position.x, _hz_to_y(frequency, plot)))
		points.append(Vector2(plot.end.x, _hz_to_y(frequency, plot)))
	else:
		for i in range(count):
			points.append(Vector2(plot.position.x + plot.size.x * float(i) / (count - 1), _hz_to_y(freq_history[i], plot)))
	draw_polyline(points, Color(color, 0.15), 6, true)
	draw_polyline(points, color, 2, true)
	var last: Vector2 = points[-1]
	draw_circle(last, 5 + sin(phase * 4) * 1.5, Color(color, 0.18))
	draw_circle(last, 2.5, UI.PAPER)
	var sweep := plot.position.x + fmod(phase / 6.0, 1.0) * plot.size.x
	draw_line(Vector2(sweep, plot.position.y), Vector2(sweep, plot.end.y), Color(0.6, 1, 0.85, 0.08))
	_label("%.2f Hz" % frequency, Rect2(plot.position + Vector2(7, 4), Vector2(plot.size.x - 14, 18)), 9, color)
	if not safe:
		_label("TURUN" if frequency<49.5 else "NAIK",Rect2(plot.position+Vector2(7,23),Vector2(plot.size.x-14,14)),8,UI.RED)
	_bar("PASOKAN", supply_kw, shown_supply, size.y - 54, UI.MINT, split)
	_bar("BEBAN", demand_kw, shown_demand, size.y - 34, UI.GOLD, split)
	var goals := get_objectives()
	var x := split + 13
	var row_height := minf(43.0, (size.y - 61) / goals.size())
	for i in range(goals.size()):
		var goal: Dictionary = goals[i]
		var y := 49.0 + i * row_height
		var goal_color: Color = UI.PAPER if goal.okay else UI.RED
		draw_rect(Rect2(x, y + 4, 5, 5), UI.MINT if goal.okay else UI.RED)
		var text_width := size.x - x - 24
		_label(goal.title, Rect2(x + 12, y, text_width, 13), 7, goal_color)
		_label(goal.value, Rect2(x + 12, y + 14, text_width, 12), 7, UI.MINT if goal.okay else UI.RED)

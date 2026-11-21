extends Control
class_name Oscilloscope

# Compact Floating SCADA Oscilloscope + Supply/Demand Bars + Control Log Ticker

const MIN_PLOT_HZ := 49.20
const MAX_PLOT_HZ := 50.80

var frequency: float = 50.0
var supply_kw: float = 92.0
var demand_kw: float = 92.0
var pltmh_kw: float = 42.0
var plts_kw: float = 50.0
var diesel_kw: float = 0.0
var cost_rp: float = 0.0
var freq_history: Array[float] = []
var control_log: Array[String] = []
var phase_accum: float = 0.0


func _ready() -> void:
	clip_contents = true
	for i in range(90):
		freq_history.append(50.0)


func update_from_sim(state: Dictionary) -> void:
	frequency = float(state.get("frequency", 50.0))
	supply_kw = float(state.get("supply_kw", 92.0))
	demand_kw = float(state.get("demand_kw", 92.0))
	pltmh_kw = float(state.get("pltmh_kw", 42.0))
	plts_kw = float(state.get("plts_kw", 0.0))
	diesel_kw = float(state.get("diesel_kw", 0.0))
	cost_rp = float(state.get("cost_rp", 0.0))

	var hist: Array = state.get("freq_history", [])
	if not hist.is_empty():
		freq_history.clear()
		for v in hist:
			freq_history.append(float(v))

	var clogs: Array = state.get("control_log", [])
	control_log.clear()
	for entry in clogs:
		control_log.append(String(entry))

	queue_redraw()


func _process(delta: float) -> void:
	var spd: float = maxf(0.5, frequency - 45.0)
	phase_accum += delta * spd * 1.4
	if phase_accum > TAU * 100.0:
		phase_accum = fmod(phase_accum, TAU)
	queue_redraw()


func _hz_to_y(hz: float, rect: Rect2) -> float:
	var t: float = clampf((hz - MIN_PLOT_HZ) / (MAX_PLOT_HZ - MIN_PLOT_HZ), 0.0, 1.0)
	return rect.end.y - t * rect.size.y


func _draw() -> void:
	if size.x < 60.0 or size.y < 60.0:
		return

	var font := ThemeDB.fallback_font

	# Translucent metallic glass HUD backing
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.09, 0.92), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.44, 0.40, 0.90), false, 2.0)

	var is_safe: bool = (frequency >= 49.50 and frequency <= 50.50)
	var is_warn: bool = (frequency < 49.75 or frequency > 50.25)
	var freq_col := Color(0.24, 1.0, 0.60)
	if frequency <= 0.1 or not is_safe:
		freq_col = Color(1.0, 0.25, 0.28)
	elif is_warn:
		freq_col = Color(1.0, 0.78, 0.22)

	# Split horizontally: Left 62% = Frequency Plot + Power Bars | Right 38% = LOG KONTROL
	var split_x: float = size.x * 0.62

	# Header
	draw_string(font, Vector2(12.0, 18.0), "FREKUENSI JARINGAN (Hz)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.58, 0.80, 0.76))
	draw_string(font, Vector2(split_x - 88.0, 18.0), "ZONA BLACKOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.35, 0.35))

	# Plot box
	var plot_rect := Rect2(38.0, 24.0, split_x - 48.0, size.y - 68.0)
	if plot_rect.size.x > 20.0 and plot_rect.size.y > 20.0:
		draw_rect(plot_rect, Color(0.02, 0.04, 0.06), true)

		var y_505: float = _hz_to_y(50.50, plot_rect)
		var y_495: float = _hz_to_y(49.50, plot_rect)
		# Red danger zones above 50.5 and below 49.5
		draw_rect(Rect2(plot_rect.position.x, plot_rect.position.y, plot_rect.size.x, y_505 - plot_rect.position.y), Color(0.60, 0.10, 0.12, 0.22), true)
		draw_rect(Rect2(plot_rect.position.x, y_495, plot_rect.size.x, plot_rect.end.y - y_495), Color(0.60, 0.10, 0.12, 0.22), true)
		# Green safe band
		draw_rect(Rect2(plot_rect.position.x, y_505, plot_rect.size.x, y_495 - y_505), Color(0.10, 0.35, 0.22, 0.14), true)

		# Subtle live AC carrier wave
		if frequency > 1.0:
			var ac_pts := PackedVector2Array()
			var mid_y: float = plot_rect.position.y + plot_rect.size.y * 0.5
			var amp: float = plot_rect.size.y * 0.13
			var cycles: float = 4.5 + (frequency - 50.0) * 3.0
			for i in range(48):
				var u: float = float(i) / 47.0
				ac_pts.append(Vector2(plot_rect.position.x + u * plot_rect.size.x, mid_y + sin(u * TAU * cycles - phase_accum) * amp))
			draw_polyline(ac_pts, Color(freq_col.r, freq_col.g, freq_col.b, 0.15), 1.3, true)

		# Grid lines
		var g_levels: Array[float] = [50.5, 50.2, 50.0, 49.8, 49.5]
		for ghz in g_levels:
			var gy: float = _hz_to_y(ghz, plot_rect)
			var gcol := Color(0.18, 0.34, 0.30, 0.45)
			if is_equal_approx(ghz, 50.5) or is_equal_approx(ghz, 49.5):
				gcol = Color(0.92, 0.30, 0.30, 0.65)
			elif is_equal_approx(ghz, 50.0):
				gcol = Color(0.28, 0.88, 0.58, 0.55)
			draw_line(Vector2(plot_rect.position.x, gy), Vector2(plot_rect.end.x, gy), gcol, 1.0)
			draw_string(font, Vector2(6.0, gy + 3.5), "%.1f" % ghz, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, gcol.lightened(0.25))

		# Frequency curve
		if freq_history.size() >= 2:
			var pts := PackedVector2Array()
			var n: int = freq_history.size()
			for i in range(n):
				var px: float = plot_rect.position.x + (float(i) / float(n - 1)) * plot_rect.size.x
				var py: float = _hz_to_y(freq_history[i], plot_rect)
				pts.append(Vector2(px, py))
			draw_polyline(pts, freq_col, 2.4, true)
			draw_circle(pts[pts.size() - 1], 4.0, freq_col)

		draw_rect(plot_rect, Color(0.18, 0.40, 0.36), false, 1.2)

	# Bottom Supply vs Demand Bars
	var bar_x: float = 68.0
	var bar_w: float = maxf(40.0, split_x - bar_x - 56.0)
	var max_kw: float = 145.0
	var y_sup: float = size.y - 34.0
	var y_dem: float = size.y - 16.0

	draw_string(font, Vector2(10.0, y_sup + 8.0), "PASOKAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.88, 0.72))
	draw_rect(Rect2(bar_x, y_sup, bar_w, 9.0), Color(0.08, 0.12, 0.16), true)
	draw_rect(Rect2(bar_x, y_sup, bar_w * clampf(supply_kw / max_kw, 0.0, 1.0), 9.0), Color(0.24, 0.95, 0.58), true)
	draw_string(font, Vector2(bar_x + bar_w + 6.0, y_sup + 8.0), "%d kW" % int(roundf(supply_kw)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 1.0, 0.80))

	draw_string(font, Vector2(10.0, y_dem + 8.0), "BEBAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.78, 0.42))
	draw_rect(Rect2(bar_x, y_dem, bar_w, 9.0), Color(0.08, 0.12, 0.16), true)
	draw_rect(Rect2(bar_x, y_dem, bar_w * clampf(demand_kw / max_kw, 0.0, 1.0), 9.0), Color(0.98, 0.74, 0.25), true)
	draw_string(font, Vector2(bar_x + bar_w + 6.0, y_dem + 8.0), "%d kW" % int(roundf(demand_kw)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.48))

	# Right Column: LOG KONTROL
	draw_line(Vector2(split_x + 4.0, 8.0), Vector2(split_x + 4.0, size.y - 8.0), Color(0.16, 0.34, 0.36, 0.65), 1.0)
	var log_x: float = split_x + 12.0
	var log_w: float = size.x - log_x - 8.0
	draw_string(font, Vector2(log_x, 18.0), "LOG KONTROL", HORIZONTAL_ALIGNMENT_LEFT, log_w, 10, Color(0.58, 0.82, 0.90))

	var ly: float = 34.0
	var max_lines: int = maxi(1, floori((size.y - 42.0) / 15.0))
	var start_idx: int = maxi(0, control_log.size() - max_lines)
	for i in range(start_idx, control_log.size()):
		var entry: String = control_log[i]
		var lcol := Color(0.75, 0.86, 0.90)
		if entry.contains("BLACKOUT") or entry.contains("RUSAK"):
			lcol = Color(1.0, 0.35, 0.35)
		elif entry.contains("DIESEL ON") or entry.contains("SAHUR") or entry.contains("DIPADAMKAN"):
			lcol = Color(1.0, 0.82, 0.32)
		elif entry.contains("PULIH") or entry.contains("KEMBALI"):
			lcol = Color(0.32, 1.0, 0.62)
		draw_string(font, Vector2(log_x, ly), entry, HORIZONTAL_ALIGNMENT_LEFT, log_w, 10, lcol)
		ly += 15.0

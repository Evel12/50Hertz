extends Control
class_name HudFx

# Lightweight custom-drawn HUD visual widgets (no external assets):
# mode = "SINE_WAVE" | "VIGNETTE" | "GATE_PREVIEW"

const CW := preload("res://scripts/circuit_workbench.gd")

var mode: String = "SINE_WAVE"
var anim_time: float = 0.0
var alarm_intensity: float = 0.0
var preview_gate: String = "NOT"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	anim_time += delta
	if mode == "SINE_WAVE" or (mode == "VIGNETTE" and alarm_intensity > 0.01):
		queue_redraw()


func set_alarm(intensity: float) -> void:
	alarm_intensity = clampf(intensity, 0.0, 1.0)
	queue_redraw()


func set_preview_gate(gate_type: String) -> void:
	preview_gate = gate_type
	queue_redraw()


func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return

	match mode:
		"SINE_WAVE":
			var pts := PackedVector2Array()
			var mid_y: float = size.y * 0.5
			var amp: float = size.y * 0.34
			for i in range(96):
				var u: float = float(i) / 95.0
				var sx: float = u * size.x
				var sy: float = mid_y + sin(u * TAU * 4.0 - anim_time * 3.2) * amp
				pts.append(Vector2(sx, sy))
			draw_polyline(pts, Color(0.22, 1.0, 0.58, 0.22), 7.0, true)
			draw_polyline(pts, Color(0.28, 1.0, 0.62, 0.92), 2.4, true)

		"VIGNETTE":
			if alarm_intensity <= 0.01:
				return
			var pulse: float = 0.55 + 0.45 * sin(anim_time * 9.0)
			var a: float = alarm_intensity * pulse * 0.48
			var col := Color(1.0, 0.14, 0.16, a)
			var t: float = 28.0 + alarm_intensity * 26.0
			draw_rect(Rect2(0.0, 0.0, size.x, t), col, true)
			draw_rect(Rect2(0.0, size.y - t, size.x, t), col, true)
			draw_rect(Rect2(0.0, t, t, size.y - t * 2.0), col, true)
			draw_rect(Rect2(size.x - t, t, t, size.y - t * 2.0), col, true)

		"GATE_PREVIEW":
			var cx: float = size.x * 0.5
			var cy: float = size.y * 0.44
			var gw: float = 58.0
			var gh: float = 40.0
			var r := Rect2(cx - gw * 0.5, cy - gh * 0.5, gw, gh)
			# Input & output leads
			if preview_gate == "NOT":
				draw_line(Vector2(r.position.x - 16.0, cy), Vector2(r.position.x + 4.0, cy), Color(0.45, 0.85, 0.95), 2.0)
			else:
				draw_line(Vector2(r.position.x - 16.0, cy - 10.0), Vector2(r.position.x + 4.0, cy - 10.0), Color(0.45, 0.85, 0.95), 2.0)
				draw_line(Vector2(r.position.x - 16.0, cy + 10.0), Vector2(r.position.x + 4.0, cy + 10.0), Color(0.45, 0.85, 0.95), 2.0)
			draw_line(Vector2(r.end.x, cy), Vector2(r.end.x + 16.0, cy), Color(0.28, 1.0, 0.62), 2.0)
			CW.draw_gate_symbol(self, r, preview_gate, true, false)

extends Control
class_name CircuitWorkbench

const LT := preload("res://scripts/logic_tree.gd")

# Tactile ANSI/IEEE Digital Logic Relay Workbench
# Supports recursive composable logic trees (WIRE, SENSOR, NOT, AND, OR, LATCH),
# curved glowing traces, animated signal packets, spark bursts on edit, and a
# contextual floating component picker matching the reference gameplay.

signal circuit_changed()

var level_dict: Dictionary = {}
var diesel_tree: Dictionary = {}
var shed_tree: Dictionary = {}
var has_shed_actuator: bool = false
var is_locked: bool = false

var anim_time: float = 0.0
var hitboxes: Array[Dictionary] = []
var hovered_node_ref: Dictionary = {}
var edit_sparks: Array[Dictionary] = []

# Contextual floating picker popup (child Control created on demand)
var picker_panel: PanelContainer
var picker_vbox: VBoxContainer
var picker_target_node: Dictionary = {}
var picker_is_root: bool = false


func _ready() -> void:
	clip_contents = true
	_build_picker_popup()


func _build_picker_popup() -> void:
	picker_panel = PanelContainer.new()
	picker_panel.visible = false
	picker_panel.z_index = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.13, 0.97)
	sb.border_color = Color(0.28, 0.95, 0.65, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	picker_panel.add_theme_stylebox_override("panel", sb)
	add_child(picker_panel)

	picker_vbox = VBoxContainer.new()
	picker_vbox.add_theme_constant_override("separation", 4)
	picker_panel.add_child(picker_vbox)


func setup_workbench(lvl: Dictionary, d_tree: Dictionary, s_tree: Dictionary) -> void:
	level_dict = lvl
	diesel_tree = d_tree
	shed_tree = s_tree
	has_shed_actuator = bool(lvl.get("has_shed_actuator", false))
	is_locked = false
	hovered_node_ref = {}
	close_picker()
	queue_redraw()


func set_locked(locked: bool) -> void:
	is_locked = locked
	if locked:
		hovered_node_ref = {}
		close_picker()
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func close_picker() -> void:
	if picker_panel != null:
		picker_panel.visible = false
	picker_target_node = {}


func _process(delta: float) -> void:
	anim_time += delta
	for i in range(edit_sparks.size() - 1, -1, -1):
		var sp: Dictionary = edit_sparks[i]
		var age: float = float(sp["age"]) + delta
		var pos: Vector2 = sp["pos"]
		var vel: Vector2 = sp["vel"]
		pos += vel * delta
		vel *= 0.92
		sp["age"] = age
		sp["pos"] = pos
		sp["vel"] = vel
		if age > 0.45:
			edit_sparks.remove_at(i)
	queue_redraw()


func _spawn_ui_sparks(center: Vector2) -> void:
	for i in range(10):
		var a: float = randf() * TAU
		var s: float = randf_range(40.0, 120.0)
		edit_sparks.append({
			"pos": center,
			"vel": Vector2(cos(a) * s, sin(a) * s),
			"age": 0.0
		})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if picker_panel.visible:
			return
		var mpos: Vector2 = event.position
		var found: Dictionary = {}
		for hb in hitboxes:
			var r: Rect2 = hb["rect"]
			if r.has_point(mpos):
				found = hb["node"]
				break
		if not is_same(found, hovered_node_ref):
			hovered_node_ref = found
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (not found.is_empty() and not is_locked) else Control.CURSOR_ARROW
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_locked:
			return
		var mpos: Vector2 = event.position
		# Clicking outside an open picker closes it
		if picker_panel.visible:
			var pr := Rect2(picker_panel.position, picker_panel.size)
			if not pr.has_point(mpos):
				close_picker()
				accept_event()
				return

		for hb in hitboxes:
			var r: Rect2 = hb["rect"]
			if r.has_point(mpos):
				var node_ref: Dictionary = hb["node"]
				var is_root: bool = bool(hb["is_root"])
				_open_picker_for_node(node_ref, is_root, r)
				accept_event()
				break


func _open_picker_for_node(node_ref: Dictionary, is_root: bool, anchor_rect: Rect2) -> void:
	picker_target_node = node_ref
	picker_is_root = is_root

	for child in picker_vbox.get_children():
		picker_vbox.remove_child(child)
		child.queue_free()

	var ntype: String = String(node_ref.get("type", "SENSOR"))
	var avail_sensors: Array = level_dict.get("available_sensors", ["SIANG"])
	var avail_gates: Array = level_dict.get("available_gates", ["WIRE", "NOT"])
	var center_pt: Vector2 = anchor_rect.get_center()

	if ntype == "SENSOR":
		_add_picker_header("PILIH SENSOR")
		for s in avail_sensors:
			var sname: String = String(s)
			var info: Dictionary = LT.get_sensor_info(sname)
			_add_picker_item(sname, String(info["desc"]), Color(0.32, 0.86, 1.0), func():
				LT.replace_with_sensor(picker_target_node, sname)
				_spawn_ui_sparks(center_pt)
				close_picker()
				circuit_changed.emit()
			)

		# Compact horizontal row for wrapping a sensor inside a gate (prevents popup clipping!)
		var wrap_gates: Array[String] = []
		for g in avail_gates:
			var gs: String = String(g)
			if gs != "WIRE":
				wrap_gates.append(gs)
		if not wrap_gates.is_empty():
			_add_picker_header("SISIPKAN GERBANG")
			var wrow := HBoxContainer.new()
			wrow.add_theme_constant_override("separation", 4)
			picker_vbox.add_child(wrow)
			for wg in wrap_gates:
				var gate_code: String = wg
				var chip := _make_compact_chip(gate_code, Color(1.0, 0.80, 0.30), _gate_short_desc(gate_code))
				chip.pressed.connect(func():
					LT.wrap_sensor_with_gate(picker_target_node, gate_code)
					_spawn_ui_sparks(center_pt)
					close_picker()
					circuit_changed.emit()
				)
				wrow.add_child(chip)

		_add_picker_item("KOSONG", "Lepas sensor", Color(0.65, 0.70, 0.75), func():
			LT.replace_with_sensor(picker_target_node, "NONE")
			_spawn_ui_sparks(center_pt)
			close_picker()
			circuit_changed.emit()
		)
	else:
		_add_picker_header("GANTI GERBANG")
		for g in avail_gates:
			var gate_code: String = String(g)
			var label_txt: String = "KABEL" if gate_code == "WIRE" else gate_code
			_add_picker_item(label_txt, _gate_short_desc(gate_code), Color(0.30, 1.0, 0.62), func():
				LT.swap_gate_type(picker_target_node, gate_code)
				_spawn_ui_sparks(center_pt)
				close_picker()
				circuit_changed.emit()
			)

		if not is_root:
			_add_picker_header("GANTI KE SENSOR")
			var srow := HBoxContainer.new()
			srow.add_theme_constant_override("separation", 4)
			picker_vbox.add_child(srow)
			for s in avail_sensors:
				var sname: String = String(s)
				var schip := _make_compact_chip(sname, Color(0.32, 0.86, 1.0), "Ganti cabang dengan sensor %s" % sname)
				schip.pressed.connect(func():
					LT.replace_with_sensor(picker_target_node, sname)
					_spawn_ui_sparks(center_pt)
					close_picker()
					circuit_changed.emit()
				)
				srow.add_child(schip)

	picker_panel.visible = true
	picker_panel.reset_size()
	var pop_size: Vector2 = picker_panel.get_combined_minimum_size()
	var px: float = clampf(anchor_rect.end.x + 8.0, 8.0, maxf(8.0, size.x - pop_size.x - 10.0))
	var py: float = clampf(anchor_rect.position.y - 10.0, 28.0, maxf(28.0, size.y - pop_size.y - 8.0))
	if anchor_rect.end.x + pop_size.x + 12.0 > size.x:
		px = clampf(anchor_rect.position.x - pop_size.x - 8.0, 8.0, maxf(8.0, size.x - pop_size.x - 10.0))
	picker_panel.position = Vector2(px, py)


func _make_compact_chip(title: String, accent: Color, tip: String) -> Button:
	var btn := Button.new()
	btn.text = title
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(46, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", accent)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.08, 0.13, 0.19)
	sb_n.border_color = Color(0.20, 0.34, 0.42)
	sb_n.set_border_width_all(1)
	sb_n.set_corner_radius_all(4)
	sb_n.content_margin_left = 6
	sb_n.content_margin_right = 6
	var sb_h: StyleBoxFlat = sb_n.duplicate()
	sb_h.bg_color = Color(0.14, 0.24, 0.30)
	sb_h.border_color = accent
	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	return btn


func _add_picker_header(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.80))
	picker_vbox.add_child(lbl)


func _add_picker_item(title: String, desc: String, accent: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = "%s  —  %s" % [title, desc]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(228, 22)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", accent)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.08, 0.13, 0.19)
	sb_n.border_color = Color(0.18, 0.30, 0.38)
	sb_n.set_border_width_all(1)
	sb_n.set_corner_radius_all(4)
	sb_n.content_margin_left = 8
	sb_n.content_margin_right = 8
	var sb_h := sb_n.duplicate()
	sb_h.bg_color = Color(0.12, 0.22, 0.28)
	sb_h.border_color = accent
	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.pressed.connect(cb)
	picker_vbox.add_child(btn)


func _gate_short_desc(code: String) -> String:
	match code:
		"WIRE": return "Teruskan sinyal apa adanya"
		"NOT": return "Balik sinyal: 1→0, 0→1"
		"AND": return "1 kalau DUA-DUANYA 1"
		"OR": return "1 kalau SALAH SATU 1"
		"LATCH": return "Ingatan: S=nyalakan, R=matikan"
		_: return ""


func _draw() -> void:
	hitboxes.clear()
	if size.x < 60.0 or size.y < 60.0:
		return

	var font := ThemeDB.fallback_font

	# Metallic relay cabinet background + corner screw bolts
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.10, 0.96), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.20, 0.48, 0.44), false, 2.0)

	# Blueprint / PCB dot grid
	var step: float = 22.0
	var gx: float = step
	while gx < size.x:
		var gy: float = 30.0
		while gy < size.y - 6.0:
			draw_rect(Rect2(gx, gy, 2.0, 2.0), Color(0.14, 0.26, 0.30, 0.45), true)
			gy += step
		gx += step

	# Corner industrial rivets
	for corner in [Vector2(8, 8), Vector2(size.x - 8, 8), Vector2(8, size.y - 8), Vector2(size.x - 8, size.y - 8)]:
		draw_circle(corner, 3.2, Color(0.25, 0.38, 0.42))
		draw_circle(corner, 1.4, Color(0.08, 0.12, 0.15))

	# Header bar inside cabinet
	draw_string(font, Vector2(18.0, 21.0), "PANEL RANGKAIAN RELAI LOGIKA  •  Klik gerbang atau sensor untuk mengubah", HORIZONTAL_ALIGNMENT_LEFT, size.x - 160.0, 11, Color(0.58, 0.88, 0.84))
	if is_locked:
		draw_string(font, Vector2(size.x - 148.0, 21.0), "[SIMULASI AKTIF]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.80, 0.28))

	# Layout 1 or 2 actuator lanes
	var top_pad: float = 34.0
	var bot_pad: float = 12.0
	var avail_h: float = size.y - top_pad - bot_pad

	if not has_shed_actuator:
		var lane_rect := Rect2(14.0, top_pad, size.x - 28.0, avail_h)
		_draw_actuator_lane(diesel_tree, lane_rect, "DIESEL", "PLTD", true)
	else:
		var h1: float = avail_h * 0.42
		var h2: float = avail_h * 0.54
		var lane1 := Rect2(14.0, top_pad, size.x - 28.0, h1)
		var lane2 := Rect2(14.0, top_pad + h1 + avail_h * 0.04, size.x - 28.0, h2)
		draw_line(Vector2(18.0, lane2.position.y - 4.0), Vector2(size.x - 18.0, lane2.position.y - 4.0), Color(0.16, 0.30, 0.36, 0.6), 1.0)
		_draw_actuator_lane(diesel_tree, lane1, "DIESEL", "PLTD", true)
		_draw_actuator_lane(shed_tree, lane2, "PADAM", "DUSUN 3", false)

	# Spark bursts on edit
	for sp in edit_sparks:
		var pos: Vector2 = sp["pos"]
		var age: float = float(sp["age"])
		var a: float = clampf(1.0 - (age / 0.45), 0.0, 1.0)
		draw_circle(pos, 3.2 * a + 1.0, Color(0.35, 1.0, 0.72, a))


func _draw_actuator_lane(root_node: Dictionary, lane_rect: Rect2, act_title: String, act_sub: String, is_diesel: bool) -> void:
	if root_node.is_empty():
		return

	var act_w: float = 98.0
	var act_h: float = minf(48.0, lane_rect.size.y * 0.62)
	var act_x: float = lane_rect.end.x - act_w
	var act_cy: float = lane_rect.position.y + lane_rect.size.y * 0.5
	var act_rect := Rect2(act_x, act_cy - act_h * 0.5, act_w, act_h)

	var out_high: bool = bool(root_node.get("val", false))
	var tree_area := Rect2(lane_rect.position.x, lane_rect.position.y, act_x - lane_rect.position.x - 26.0, lane_rect.size.y)

	var max_depth: int = maxi(2, LT.get_depth(root_node))
	var root_out_pt: Vector2 = _draw_tree_node(root_node, tree_area, 0, max_depth, true)

	# Connect root output to Actuator box
	_draw_curved_trace(root_out_pt, Vector2(act_rect.position.x, act_cy), out_high)

	# Draw Actuator Box
	var font := ThemeDB.fallback_font
	var active_col := Color(1.0, 0.78, 0.25) if is_diesel else Color(0.98, 0.45, 0.28)
	var bg := Color(0.14, 0.24, 0.16) if (out_high and is_diesel) else (Color(0.26, 0.12, 0.10) if out_high else Color(0.08, 0.11, 0.15))
	var border := active_col if out_high else Color(0.32, 0.42, 0.48)
	draw_rect(act_rect, bg, true)
	draw_rect(act_rect, border, false, 2.2 if out_high else 1.5)
	draw_string(font, Vector2(act_rect.position.x + 10.0, act_rect.position.y + act_h * 0.46), act_title, HORIZONTAL_ALIGNMENT_LEFT, act_w - 16.0, 12, Color(0.95, 0.98, 1.0))
	var sub_txt := act_sub + (" • ON" if out_high else " • OFF")
	draw_string(font, Vector2(act_rect.position.x + 10.0, act_rect.position.y + act_h * 0.80), sub_txt, HORIZONTAL_ALIGNMENT_LEFT, act_w - 16.0, 10, active_col if out_high else Color(0.55, 0.65, 0.72))


func _draw_tree_node(node: Dictionary, area: Rect2, depth_from_right: int, total_depth: int, is_root: bool) -> Vector2:
	var ntype: String = String(node.get("type", "SENSOR"))
	var is_high: bool = bool(node.get("val", false))
	var is_hov: bool = is_same(hovered_node_ref, node) and not is_locked

	# Column x position (right-to-left: depth 0 is rightmost before actuator)
	var col_w: float = area.size.x / float(maxi(1, total_depth))
	var cx: float = area.end.x - (float(depth_from_right) + 0.5) * col_w
	var cy: float = area.position.y + area.size.y * 0.5

	if ntype == "SENSOR":
		# Anchor sensor cleanly in left-most available column
		var sx: float = minf(cx, area.position.x + col_w * 0.52)
		var pill_w: float = minf(114.0, maxf(82.0, col_w - 12.0))
		var pill_h: float = minf(30.0, maxf(24.0, area.size.y * 0.72))
		var rect := Rect2(sx - pill_w * 0.5, cy - pill_h * 0.5, pill_w, pill_h)

		var sname: String = String(node.get("sensor", "NONE"))
		var is_empty: bool = (sname == "NONE")
		var label_txt: String = "+ pilih sensor" if is_empty else sname
		var bg := Color(0.08, 0.24, 0.16) if is_high else (Color(0.06, 0.10, 0.14) if not is_empty else Color(0.05, 0.08, 0.11))
		if is_hov:
			bg = bg.lightened(0.14)
		var border := Color(0.28, 1.0, 0.60) if is_high else (Color(0.28, 0.78, 0.96) if not is_empty else Color(0.45, 0.55, 0.65))
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, 2.0 if (is_hov or is_high) else 1.4)

		var font := ThemeDB.fallback_font
		var dot_col := Color(0.30, 1.0, 0.62) if is_high else Color(0.30, 0.40, 0.48)
		if not is_empty:
			draw_circle(Vector2(rect.position.x + 10.0, cy), 3.5, dot_col)
		var txt_x: float = rect.position.x + (18.0 if not is_empty else 8.0)
		draw_string(font, Vector2(txt_x, cy + 4.0), label_txt, HORIZONTAL_ALIGNMENT_LEFT, pill_w - 22.0, 11, Color(0.94, 0.98, 1.0) if not is_empty else Color(0.60, 0.72, 0.80))

		hitboxes.append({"rect": rect, "node": node, "is_root": is_root})
		return Vector2(rect.end.x, cy)

	# Gate / Wire node
	var gate_w: float = 58.0
	var gate_h: float = 38.0
	if ntype == "LATCH":
		gate_w = 60.0
		gate_h = 44.0
	elif ntype == "WIRE":
		gate_w = 52.0
		gate_h = 26.0

	var g_rect := Rect2(cx - gate_w * 0.5, cy - gate_h * 0.5, gate_w, gate_h)
	var a_node: Dictionary = node.get("a", {})
	var b_node: Dictionary = node.get("b", {})

	if ntype == "WIRE" or ntype == "NOT":
		var child_out: Vector2 = _draw_tree_node(a_node, area, depth_from_right + 1, total_depth, false)
		var a_val: bool = bool(a_node.get("val", false))
		_draw_curved_trace(child_out, Vector2(g_rect.position.x, cy), a_val)
	else:
		# Binary gate (AND, OR, LATCH): split vertical area proportionally by leaf count!
		var la: int = maxi(1, LT.get_leaf_count(a_node))
		var lb: int = maxi(1, LT.get_leaf_count(b_node))
		var ratio_a: float = float(la) / float(la + lb)
		var area_a := Rect2(area.position.x, area.position.y, area.size.x, area.size.y * ratio_a)
		var area_b := Rect2(area.position.x, area.position.y + area.size.y * ratio_a, area.size.x, area.size.y * (1.0 - ratio_a))

		var out_a: Vector2 = _draw_tree_node(a_node, area_a, depth_from_right + 1, total_depth, false)
		var out_b: Vector2 = _draw_tree_node(b_node, area_b, depth_from_right + 1, total_depth, false)
		_draw_curved_trace(out_a, Vector2(g_rect.position.x, cy - gate_h * 0.26), bool(a_node.get("val", false)))
		_draw_curved_trace(out_b, Vector2(g_rect.position.x, cy + gate_h * 0.26), bool(b_node.get("val", false)))

	# Draw the authentic ANSI/IEEE Gate Symbol!
	draw_gate_symbol(self, g_rect, ntype, is_high, is_hov)

	hitboxes.append({"rect": g_rect.grow(4.0), "node": node, "is_root": is_root})
	return Vector2(g_rect.end.x, cy)


func _draw_curved_trace(p1: Vector2, p2: Vector2, high: bool) -> void:
	var segs: int = 12
	var dx: float = maxf(18.0, absf(p2.x - p1.x) * 0.5)
	var c1 := p1 + Vector2(dx, 0.0)
	var c2 := p2 - Vector2(dx, 0.0)
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var u: float = 1.0 - t
		var pt: Vector2 = (u * u * u) * p1 + 3.0 * (u * u * t) * c1 + 3.0 * (u * t * t) * c2 + (t * t * t) * p2
		pts.append(pt)

	var col := Color(0.24, 1.0, 0.60, 0.92) if high else Color(0.24, 0.34, 0.42, 0.80)
	draw_polyline(pts, col, 2.8 if high else 1.8, true)
	draw_circle(p1, 3.0, col)
	draw_circle(p2, 3.0, col)

	# Glowing signal packet zipping along active wire!
	if high:
		var t_p: float = fmod(anim_time * 1.4, 1.0)
		var u_p: float = 1.0 - t_p
		var pkt: Vector2 = (u_p * u_p * u_p) * p1 + 3.0 * (u_p * u_p * t_p) * c1 + 3.0 * (u_p * t_p * t_p) * c2 + (t_p * t_p * t_p) * p2
		draw_circle(pkt, 5.5, Color(0.30, 1.0, 0.65, 0.35))
		draw_circle(pkt, 2.8, Color(0.90, 1.0, 0.95))


static func draw_gate_symbol(canvas: CanvasItem, rect: Rect2, gate_type: String, is_high: bool, is_hov: bool) -> void:
	var font := ThemeDB.fallback_font
	var fill := Color(0.08, 0.24, 0.16) if is_high else Color(0.07, 0.12, 0.18)
	if is_hov:
		fill = fill.lightened(0.16)
	var stroke := Color(0.28, 1.0, 0.62) if is_high else (Color(0.45, 0.92, 1.0) if is_hov else Color(0.55, 0.72, 0.82))
	var sw: float = 2.4 if (is_hov or is_high) else 1.8

	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	var cy: float = (y0 + y1) * 0.5

	match gate_type:
		"WIRE":
			canvas.draw_line(Vector2(x0, cy), Vector2(x1, cy), stroke, 2.2)
			var mid := Vector2((x0 + x1) * 0.5, cy)
			canvas.draw_circle(mid, 5.5 if is_hov else 4.5, fill)
			canvas.draw_arc(mid, 5.5 if is_hov else 4.5, 0.0, TAU, 16, stroke, sw)
			canvas.draw_string(font, Vector2(x0 + 9.0, y1 + 8.0), "KABEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.78, 0.85))

		"NOT":
			var tri := PackedVector2Array([
				Vector2(x0 + 4.0, y0 + 3.0),
				Vector2(x1 - 12.0, cy),
				Vector2(x0 + 4.0, y1 - 3.0)
			])
			canvas.draw_colored_polygon(tri, fill)
			var closed := PackedVector2Array([tri[0], tri[1], tri[2], tri[0]])
			canvas.draw_polyline(closed, stroke, sw, true)
			var bub_c := Vector2(x1 - 6.0, cy)
			canvas.draw_circle(bub_c, 5.0, fill)
			canvas.draw_arc(bub_c, 5.0, 0.0, TAU, 16, stroke, sw)
			canvas.draw_string(font, Vector2(x0 + 16.0, y1 + 11.0), "NOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, stroke)

		"AND":
			var r: float = (y1 - y0) * 0.45
			var arc_cx: float = x1 - r - 3.0
			var pts := PackedVector2Array()
			pts.append(Vector2(x0 + 4.0, y0 + 2.0))
			pts.append(Vector2(arc_cx, y0 + 2.0))
			for i in range(13):
				var a: float = -PI * 0.5 + (float(i) / 12.0) * PI
				pts.append(Vector2(arc_cx + cos(a) * r, cy + sin(a) * r))
			pts.append(Vector2(x0 + 4.0, y1 - 2.0))
			canvas.draw_colored_polygon(pts, fill)
			var outline := PackedVector2Array(pts)
			outline.append(pts[0])
			canvas.draw_polyline(outline, stroke, sw, true)
			canvas.draw_string(font, Vector2(x0 + 16.0, y1 + 11.0), "AND", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, stroke)

		"OR":
			var pts := PackedVector2Array([
				Vector2(x0 + 2.0, y0 + 2.0),
				Vector2(x0 + 24.0, y0 + 2.0),
				Vector2(x0 + 40.0, y0 + 7.0),
				Vector2(x1 - 3.0, cy),
				Vector2(x0 + 40.0, y1 - 7.0),
				Vector2(x0 + 24.0, y1 - 2.0),
				Vector2(x0 + 2.0, y1 - 2.0),
				Vector2(x0 + 11.0, cy)
			])
			canvas.draw_colored_polygon(pts, fill)
			var outline := PackedVector2Array(pts)
			outline.append(pts[0])
			canvas.draw_polyline(outline, stroke, sw, true)
			canvas.draw_string(font, Vector2(x0 + 20.0, y1 + 11.0), "OR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, stroke)

		"LATCH":
			var box := Rect2(x0 + 4.0, y0 + 2.0, (x1 - x0) - 8.0, (y1 - y0) - 4.0)
			canvas.draw_rect(box, fill, true)
			canvas.draw_rect(box, stroke, false, sw)
			canvas.draw_string(font, Vector2(box.position.x + 6.0, y0 + 16.0), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.95, 1.0))
			canvas.draw_string(font, Vector2(box.position.x + 6.0, y1 - 6.0), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.65, 0.45))
			canvas.draw_string(font, Vector2(box.end.x - 15.0, cy + 4.0), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, stroke)
			canvas.draw_circle(Vector2(box.position.x + box.size.x * 0.52, cy), 4.0, Color(0.30, 1.0, 0.62) if is_high else Color(0.22, 0.30, 0.38))
			canvas.draw_string(font, Vector2(x0 + 12.0, y1 + 11.0), "LATCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, stroke)

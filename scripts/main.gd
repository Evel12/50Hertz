extends Node

# Main Game Controller for "50 Hertz — Desa Sukamaju"
# Orchestrates the full-screen 2D VillageWorld + Camera2D, minute-by-minute GridSimulator,
# live Title Screen, Level Select, RPG Briefing Dialogue, Floating SCADA HUD,
# Slide-Up Tactile ANSI CircuitWorkbench, and Post-Level Win/Blackout Modals.

const LevelDataScript := preload("res://scripts/level_data.gd")
const GridSimulatorScript := preload("res://scripts/grid_simulator.gd")
const VillageWorldScript := preload("res://scripts/village_world.gd")
const VillageWorldScene := preload("res://scenes/village_world.tscn")
const OscilloscopeScript := preload("res://scripts/oscilloscope.gd")
const CircuitWorkbenchScript := preload("res://scripts/circuit_workbench.gd")
const HudFxScript := preload("res://scripts/hud_fx.gd")

enum GameScreen { TITLE, RULES, LEVEL_SELECT, BRIEFING, PLAYING, RESULT }

var current_screen: int = GameScreen.TITLE
var levels: Array[Dictionary] = []
var current_level_idx: int = 0
var level_stars: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}

var diesel_tree: Dictionary = {}
var shed_tree: Dictionary = {}

# Core game nodes
var world: VillageWorld
var simulator: GridSimulator
var hud_layer: CanvasLayer
var hud_root: Control
var alarm_vignette: HudFx

# Screen containers
var title_screen: Control
var rules_screen: Control
var level_select_screen: Control
var level_card_star_labels: Array[Label] = []

# RPG Briefing Dialogue Bar
var briefing_screen: Control
var brief_portrait: TextureRect
var brief_speaker_label: Label
var brief_role_label: Label
var brief_story_label: RichTextLabel
var brief_mission_label: Label
var brief_gate_preview: HudFx
var brief_concept_title: Label
var brief_concept_desc: Label
var brief_tt_box: VBoxContainer
var full_story_text: String = ""
var typewriter_chars: float = 0.0
var is_typewriting: bool = false

# Playing HUD (floating over the full-screen 2D village!)
var playing_hud: Control
var hud_level_label: Label
var hud_clock_label: Label
var hud_freq_label: Label
var hud_progress: ProgressBar
var hud_speed_buttons: Array[Button] = []
var hud_run_btn: Button
var hud_workbench_btn: Button
var hud_zoom_label: Label
var hud_mission_chips: HFlowContainer
var oscilloscope: Oscilloscope
var workbench_holder: Control
var workbench: CircuitWorkbench
var is_workbench_open: bool = true
var workbench_tween: Tween

# Result Modal (Win / Blackout)
var result_screen: Control
var res_badge_label: Label
var res_title_label: Label
var res_stars_label: Label
var res_metrics_hbox: HBoxContainer
var res_explain_title: Label
var res_explain_body: RichTextLabel
var res_retry_btn: Button
var res_menu_btn: Button
var res_next_btn: Button


func _ready() -> void:
	levels = LevelDataScript.get_levels()

	# 1. Full-Screen 2D Village World (editable scene scenes/village_world.tscn, always live behind menus & HUD!)
	world = VillageWorldScene.instantiate() as VillageWorld
	add_child(world)
	world.gardu_clicked.connect(_on_gardu_clicked)
	world.zoom_changed.connect(_on_world_zoom_changed)

	# 2. Grid Physics Simulator
	simulator = GridSimulatorScript.new()
	add_child(simulator)
	simulator.tick_updated.connect(_on_sim_tick)
	simulator.world_callout.connect(_on_world_callout)
	simulator.simulation_finished.connect(_on_sim_finished)

	# 3. HUD CanvasLayer
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)

	alarm_vignette = HudFxScript.new()
	alarm_vignette.mode = "VIGNETTE"
	alarm_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(alarm_vignette)

	_build_title_screen()
	_build_rules_screen()
	_build_level_select_screen()
	_build_briefing_screen()
	_build_playing_hud()
	_build_result_screen()

	_show_screen(GameScreen.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if current_screen == GameScreen.PLAYING:
			if event.keycode == KEY_TAB:
				_toggle_workbench()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_SPACE:
				_on_run_pressed()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
				world.zoom_by_step(0.15)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
				world.zoom_by_step(-0.15)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
				world.reset_camera_view()
				get_viewport().set_input_as_handled()
		elif current_screen == GameScreen.BRIEFING and event.keycode == KEY_SPACE:
			if is_typewriting:
				is_typewriting = false
				brief_story_label.text = full_story_text
			else:
				_start_playing_current_level()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if current_screen == GameScreen.BRIEFING and is_typewriting:
		typewriter_chars += delta * 58.0
		var count: int = mini(full_story_text.length(), int(typewriter_chars))
		brief_story_label.text = full_story_text.substr(0, count)
		if count >= full_story_text.length():
			is_typewriting = false


# ==============================================================================
# SCREEN BUILDERS
# ==============================================================================

func _build_title_screen() -> void:
	title_screen = Control.new()
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(title_screen)

	# Translucent vignette so the live twilight village shines through!
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(680, 390)
	card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.07, 0.11, 0.88), Color(0.24, 0.92, 0.58, 0.85), 2, 28, 12))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var tag := Label.new()
	tag.text = "GAME EDUKASI STEM  •  SISTEM DIGITAL & KESEIMBANGAN JARINGAN"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(0.45, 0.85, 0.95))
	vbox.add_child(tag)

	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(title_hbox)

	var t50 := Label.new()
	t50.text = "50"
	t50.add_theme_font_size_override("font_size", 58)
	t50.add_theme_color_override("font_color", Color(0.24, 1.0, 0.58))
	title_hbox.add_child(t50)

	var thz := Label.new()
	thz.text = "HERTZ"
	thz.add_theme_font_size_override("font_size", 58)
	thz.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	title_hbox.add_child(thz)

	var sub := Label.new()
	sub.text = "Jaga listrik Desa Sukamaju tetap 50.00 Hz — rancang otak otomatisnya pakai gerbang logika!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.80, 0.90, 0.94))
	vbox.add_child(sub)

	# Live animated 50 Hz sine wave
	var wave := HudFxScript.new()
	wave.mode = "SINE_WAVE"
	wave.custom_minimum_size = Vector2(560, 44)
	vbox.add_child(wave)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	vbox.add_child(btns)

	var play_btn := Button.new()
	play_btn.text = "▶  MULAI OPERASI DESA"
	play_btn.custom_minimum_size = Vector2(240, 46)
	play_btn.add_theme_font_size_override("font_size", 15)
	_style_button(play_btn, Color(0.10, 0.48, 0.28), Color(0.28, 1.0, 0.60))
	play_btn.pressed.connect(func(): _show_screen(GameScreen.LEVEL_SELECT))
	btns.add_child(play_btn)

	var rules_btn := Button.new()
	rules_btn.text = "📖  ATURAN MAIN"
	rules_btn.custom_minimum_size = Vector2(180, 46)
	rules_btn.add_theme_font_size_override("font_size", 14)
	_style_button(rules_btn, Color(0.08, 0.14, 0.20), Color(0.35, 0.72, 0.90))
	rules_btn.pressed.connect(func(): _show_screen(GameScreen.RULES))
	btns.add_child(rules_btn)


func _build_rules_screen() -> void:
	rules_screen = Control.new()
	rules_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(rules_screen)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_screen.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(780, 380)
	card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.07, 0.11, 0.95), Color(0.28, 0.78, 0.92), 2, 26, 12))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "ATURAN MAIN: PASOKAN LISTRIK HARUS SELALU SAMA DENGAN BEBAN WARGA"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	vbox.add_child(hdr)

	var cards_hbox := HBoxContainer.new()
	cards_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(cards_hbox)

	var rule_items: Array[Dictionary] = [
		{"hz": "50.00 Hz", "title": "Seimbang", "desc": "Pasokan = beban.\nLampu, TV, masjid & Puskesmas aman menyala.", "col": Color(0.26, 1.0, 0.60)},
		{"hz": "49.70 Hz", "title": "Kurang / Lebih", "desc": "Pasokan kurang → frekuensi turun.\nPasokan berlebih → frekuensi naik.", "col": Color(1.0, 0.80, 0.28)},
		{"hz": "0.00 Hz", "title": "BLACKOUT!", "desc": "Keluar dari 49.5–50.5 Hz terlalu lama → gardu trip, satu desa gelap!", "col": Color(1.0, 0.30, 0.32)}
	]
	for item in rule_items:
		var rc := PanelContainer.new()
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c: Color = item["col"]
		rc.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.10, 0.14), c, 1, 14, 8))
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 6)
		rc.add_child(rv)

		var lhz := Label.new()
		lhz.text = String(item["hz"])
		lhz.add_theme_font_size_override("font_size", 26)
		lhz.add_theme_color_override("font_color", c)
		rv.add_child(lhz)

		var lt := Label.new()
		lt.text = String(item["title"])
		lt.add_theme_font_size_override("font_size", 14)
		lt.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		rv.add_child(lt)

		var ld := Label.new()
		ld.text = String(item["desc"])
		ld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ld.add_theme_font_size_override("font_size", 12)
		ld.add_theme_color_override("font_color", Color(0.75, 0.84, 0.90))
		rv.add_child(ld)
		cards_hbox.add_child(rc)

	var note := Label.new()
	note.text = "Pemain TIDAK menekan tombol manual — rancang otak otomatis gardu dari sensor & gerbang logika (NOT, OR, LATCH, AND), lalu uji dalam simulasi satu hari!\nTips: Klik bangunan GARDU INDUK di peta atau tekan [TAB] untuk membuka/menutup Panel Relai."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.84, 0.94, 0.92))
	vbox.add_child(note)

	var btn_h := HBoxContainer.new()
	btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_h.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_h)

	var back_btn := Button.new()
	back_btn.text = "← KEMBALI"
	back_btn.custom_minimum_size = Vector2(150, 40)
	_style_button(back_btn, Color(0.08, 0.12, 0.18), Color(0.40, 0.55, 0.65))
	back_btn.pressed.connect(func(): _show_screen(GameScreen.TITLE))
	btn_h.add_child(back_btn)

	var go_btn := Button.new()
	go_btn.text = "PILIH LEVEL ➔"
	go_btn.custom_minimum_size = Vector2(200, 40)
	_style_button(go_btn, Color(0.10, 0.48, 0.28), Color(0.28, 1.0, 0.60))
	go_btn.pressed.connect(func(): _show_screen(GameScreen.LEVEL_SELECT))
	btn_h.add_child(go_btn)


func _build_level_select_screen() -> void:
	level_select_screen = Control.new()
	level_select_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(level_select_screen)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_select_screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_select_screen.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(780, 440)
	card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.07, 0.11, 0.93), Color(0.24, 0.85, 0.62), 2, 24, 12))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var top_h := HBoxContainer.new()
	vbox.add_child(top_h)

	var hdr := Label.new()
	hdr.text = "PILIH MISI GARDU — DESA SUKAMAJU"
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(0.28, 1.0, 0.62))
	top_h.add_child(hdr)

	var back_b := Button.new()
	back_b.text = "← JUDUL"
	back_b.custom_minimum_size = Vector2(105, 32)
	_style_button(back_b, Color(0.08, 0.12, 0.18), Color(0.35, 0.50, 0.60))
	back_b.pressed.connect(func(): _show_screen(GameScreen.TITLE))
	top_h.add_child(back_b)

	var sub := Label.new()
	sub.text = "Setiap level memperkenalkan satu konsep sistem digital nyata untuk menjaga kestabilan 50.00 Hz."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.75, 0.86, 0.90))
	vbox.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	vbox.add_child(grid)

	level_card_star_labels.clear()
	for i in range(levels.size()):
		var lvl: Dictionary = levels[i]
		var idx: int = i
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(355, 130)
		_style_button(btn, Color(0.06, 0.10, 0.16), Color(0.24, 0.56, 0.68))
		btn.pressed.connect(func(): _enter_level_briefing(idx))
		grid.add_child(btn)

		var bm := MarginContainer.new()
		bm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bm.add_theme_constant_override("margin_left", 14)
		bm.add_theme_constant_override("margin_right", 14)
		bm.add_theme_constant_override("margin_top", 10)
		bm.add_theme_constant_override("margin_bottom", 10)
		btn.add_child(bm)

		var bv := VBoxContainer.new()
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_theme_constant_override("separation", 4)
		bm.add_child(bv)

		var bh := HBoxContainer.new()
		bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(bh)

		var tag_l := Label.new()
		tag_l.text = "LEVEL %d  •  %s" % [i + 1, String(lvl["concept_tag"])]
		tag_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag_l.add_theme_font_size_override("font_size", 11)
		tag_l.add_theme_color_override("font_color", Color(0.32, 0.95, 0.72))
		bh.add_child(tag_l)

		var star_l := Label.new()
		star_l.text = "☆☆☆"
		star_l.add_theme_font_size_override("font_size", 14)
		star_l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
		bh.add_child(star_l)
		level_card_star_labels.append(star_l)

		var title_l := Label.new()
		title_l.text = String(lvl["short_title"])
		title_l.add_theme_font_size_override("font_size", 17)
		title_l.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		bv.add_child(title_l)

		var mis_l := Label.new()
		mis_l.text = String(lvl["mission_summary"])
		mis_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mis_l.add_theme_font_size_override("font_size", 11)
		mis_l.add_theme_color_override("font_color", Color(0.70, 0.80, 0.86))
		bv.add_child(mis_l)

		var spk_l := Label.new()
		spk_l.text = "Laporan: %s (%s)" % [String(lvl["speaker_name"]), String(lvl["speaker_role"])]
		spk_l.add_theme_font_size_override("font_size", 10)
		spk_l.add_theme_color_override("font_color", Color(0.55, 0.75, 0.85))
		bv.add_child(spk_l)


func _build_briefing_screen() -> void:
	# RPG-style bottom-screen dialogue box so the camera-focused village shines above it!
	briefing_screen = Control.new()
	briefing_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(briefing_screen)

	var click_skip := ColorRect.new()
	click_skip.color = Color(0.0, 0.0, 0.0, 0.18)
	click_skip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_skip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and is_typewriting:
			is_typewriting = false
			brief_story_label.text = full_story_text
	)
	briefing_screen.add_child(click_skip)

	var anchor_bot := MarginContainer.new()
	anchor_bot.anchor_left = 0.04
	anchor_bot.anchor_right = 0.96
	anchor_bot.anchor_top = 0.50
	anchor_bot.anchor_bottom = 0.96
	briefing_screen.add_child(anchor_bot)

	var dlg_card := PanelContainer.new()
	dlg_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.08, 0.12, 0.95), Color(0.28, 0.92, 0.62), 3, 18, 10))
	anchor_bot.add_child(dlg_card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	dlg_card.add_child(hbox)

	# Left: Villager RPG Dialogue
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.size_flags_stretch_ratio = 1.2
	left_v.add_theme_constant_override("separation", 8)
	hbox.add_child(left_v)

	var spk_h := HBoxContainer.new()
	spk_h.add_theme_constant_override("separation", 12)
	left_v.add_child(spk_h)

	var port_frame := PanelContainer.new()
	port_frame.add_theme_stylebox_override("panel", _make_stylebox(Color(0.08, 0.14, 0.20), Color(0.45, 0.85, 0.95), 2, 6, 6))
	spk_h.add_child(port_frame)

	brief_portrait = TextureRect.new()
	brief_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	brief_portrait.custom_minimum_size = Vector2(40, 40)
	brief_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port_frame.add_child(brief_portrait)

	var spk_v := VBoxContainer.new()
	spk_v.alignment = BoxContainer.ALIGNMENT_CENTER
	spk_h.add_child(spk_v)

	brief_speaker_label = Label.new()
	brief_speaker_label.add_theme_font_size_override("font_size", 17)
	brief_speaker_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.65))
	spk_v.add_child(brief_speaker_label)

	brief_role_label = Label.new()
	brief_role_label.add_theme_font_size_override("font_size", 11)
	brief_role_label.add_theme_color_override("font_color", Color(0.62, 0.80, 0.88))
	spk_v.add_child(brief_role_label)

	brief_story_label = RichTextLabel.new()
	brief_story_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brief_story_label.scroll_active = false
	brief_story_label.add_theme_font_size_override("normal_font_size", 14)
	brief_story_label.add_theme_color_override("default_color", Color(0.92, 0.96, 1.0))
	left_v.add_child(brief_story_label)

	brief_mission_label = Label.new()
	brief_mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief_mission_label.add_theme_font_size_override("font_size", 12)
	brief_mission_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.30))
	left_v.add_child(brief_mission_label)

	# Right: Visual ANSI Gate Symbol + Truth Table + Action Buttons
	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.size_flags_stretch_ratio = 1.0
	right_v.add_theme_constant_override("separation", 8)
	hbox.add_child(right_v)

	var concept_card := PanelContainer.new()
	concept_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	concept_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.10, 0.15), Color(0.85, 0.68, 0.25), 1, 10, 8))
	right_v.add_child(concept_card)

	var chbox := HBoxContainer.new()
	chbox.add_theme_constant_override("separation", 10)
	concept_card.add_child(chbox)

	brief_gate_preview = HudFxScript.new()
	brief_gate_preview.mode = "GATE_PREVIEW"
	brief_gate_preview.custom_minimum_size = Vector2(96, 76)
	chbox.add_child(brief_gate_preview)

	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 4)
	chbox.add_child(cv)

	brief_concept_title = Label.new()
	brief_concept_title.add_theme_font_size_override("font_size", 13)
	brief_concept_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.32))
	cv.add_child(brief_concept_title)

	brief_concept_desc = Label.new()
	brief_concept_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief_concept_desc.add_theme_font_size_override("font_size", 11)
	brief_concept_desc.add_theme_color_override("font_color", Color(0.80, 0.88, 0.92))
	cv.add_child(brief_concept_desc)

	brief_tt_box = VBoxContainer.new()
	cv.add_child(brief_tt_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	right_v.add_child(btn_row)

	var back_lv := Button.new()
	back_lv.text = "← Pilih Level"
	back_lv.custom_minimum_size = Vector2(130, 38)
	_style_button(back_lv, Color(0.08, 0.12, 0.18), Color(0.36, 0.50, 0.60))
	back_lv.pressed.connect(func(): _show_screen(GameScreen.LEVEL_SELECT))
	btn_row.add_child(back_lv)

	var start_b := Button.new()
	start_b.text = "MULAI MERANCANG ➔"
	start_b.custom_minimum_size = Vector2(210, 38)
	start_b.add_theme_font_size_override("font_size", 13)
	_style_button(start_b, Color(0.10, 0.48, 0.28), Color(0.28, 1.0, 0.60))
	start_b.pressed.connect(_start_playing_current_level)
	btn_row.add_child(start_b)


func _build_playing_hud() -> void:
	playing_hud = Control.new()
	playing_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	playing_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(playing_hud)

	# 1. TOP FLOATING TELEMETRY BAR
	var top_bar := PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 8
	top_bar.offset_bottom = 56
	top_bar.add_theme_stylebox_override("panel", _make_stylebox(Color(0.03, 0.06, 0.09, 0.90), Color(0.18, 0.48, 0.42), 2, 8, 8))
	playing_hud.add_child(top_bar)

	var thbox := HBoxContainer.new()
	thbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(thbox)

	var brand := Label.new()
	brand.text = "⚡ 50 HERTZ"
	brand.add_theme_font_size_override("font_size", 15)
	brand.add_theme_color_override("font_color", Color(0.28, 1.0, 0.62))
	thbox.add_child(brand)

	hud_level_label = Label.new()
	hud_level_label.text = "Level 1 • Senja di Sukamaju"
	hud_level_label.add_theme_font_size_override("font_size", 12)
	hud_level_label.add_theme_color_override("font_color", Color(0.75, 0.88, 0.92))
	thbox.add_child(hud_level_label)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thbox.add_child(sp1)

	hud_clock_label = Label.new()
	hud_clock_label.text = "🕒 15:00"
	hud_clock_label.add_theme_font_size_override("font_size", 15)
	hud_clock_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.36))
	thbox.add_child(hud_clock_label)

	hud_freq_label = Label.new()
	hud_freq_label.text = "50.00 Hz"
	hud_freq_label.custom_minimum_size = Vector2(105, 0)
	hud_freq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_freq_label.add_theme_font_size_override("font_size", 20)
	hud_freq_label.add_theme_color_override("font_color", Color(0.26, 1.0, 0.60))
	thbox.add_child(hud_freq_label)

	hud_progress = ProgressBar.new()
	hud_progress.custom_minimum_size = Vector2(90, 14)
	hud_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud_progress.max_value = 100.0
	hud_progress.show_percentage = false
	thbox.add_child(hud_progress)

	# Speed buttons (1x, 2x, 4x, 8x, 16x)
	var spd_box := HBoxContainer.new()
	spd_box.add_theme_constant_override("separation", 3)
	thbox.add_child(spd_box)
	hud_speed_buttons.clear()
	var speeds: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]
	for sp_val in speeds:
		var sbtn := Button.new()
		sbtn.text = "%dx" % int(sp_val)
		sbtn.custom_minimum_size = Vector2(34, 30)
		sbtn.add_theme_font_size_override("font_size", 11)
		var captured_spd: float = sp_val
		sbtn.pressed.connect(func(): _set_sim_speed(captured_spd))
		spd_box.add_child(sbtn)
		hud_speed_buttons.append(sbtn)

	# Chunky Industrial Jalankan / Hentikan button
	hud_run_btn = Button.new()
	hud_run_btn.text = "▶ Jalankan"
	hud_run_btn.custom_minimum_size = Vector2(118, 32)
	hud_run_btn.add_theme_font_size_override("font_size", 13)
	hud_run_btn.pressed.connect(_on_run_pressed)
	thbox.add_child(hud_run_btn)

	# Slide-up Workbench toggle button
	hud_workbench_btn = Button.new()
	hud_workbench_btn.text = "⚙ Panel [Tab]"
	hud_workbench_btn.custom_minimum_size = Vector2(106, 32)
	hud_workbench_btn.add_theme_font_size_override("font_size", 11)
	_style_button(hud_workbench_btn, Color(0.08, 0.18, 0.24), Color(0.32, 0.82, 0.96))
	hud_workbench_btn.pressed.connect(_toggle_workbench)
	thbox.add_child(hud_workbench_btn)

	var brief_btn := Button.new()
	brief_btn.text = "?"
	brief_btn.tooltip_text = "Lihat Cerita & Tabel Kebenaran"
	brief_btn.custom_minimum_size = Vector2(30, 32)
	_style_button(brief_btn, Color(0.10, 0.14, 0.20), Color(0.92, 0.76, 0.30))
	brief_btn.pressed.connect(func():
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
		_enter_level_briefing(current_level_idx)
	)
	thbox.add_child(brief_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Level"
	menu_btn.custom_minimum_size = Vector2(56, 32)
	menu_btn.add_theme_font_size_override("font_size", 11)
	_style_button(menu_btn, Color(0.08, 0.12, 0.18), Color(0.38, 0.48, 0.56))
	menu_btn.pressed.connect(func():
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
		_show_screen(GameScreen.LEVEL_SELECT)
	)
	thbox.add_child(menu_btn)

	# 2. FLOATING MISSION OBJECTIVE CHIPS (directly below top bar, click-through!)
	hud_mission_chips = HFlowContainer.new()
	hud_mission_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_mission_chips.anchor_left = 0.0
	hud_mission_chips.anchor_right = 1.0
	hud_mission_chips.offset_left = 14
	hud_mission_chips.offset_right = -215
	hud_mission_chips.offset_top = 62
	hud_mission_chips.offset_bottom = 112
	hud_mission_chips.add_theme_constant_override("h_separation", 8)
	hud_mission_chips.add_theme_constant_override("v_separation", 4)
	playing_hud.add_child(hud_mission_chips)

	# 2B. FLOATING MAP ZOOM & CAMERA CONTROLS (Top-Right below header)
	var zoom_panel := PanelContainer.new()
	zoom_panel.anchor_left = 1.0
	zoom_panel.anchor_right = 1.0
	zoom_panel.anchor_top = 0.0
	zoom_panel.anchor_bottom = 0.0
	zoom_panel.offset_left = -196
	zoom_panel.offset_right = -10
	zoom_panel.offset_top = 62
	zoom_panel.offset_bottom = 96
	zoom_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.03, 0.06, 0.09, 0.88), Color(0.22, 0.50, 0.52, 0.90), 1, 4, 8))
	playing_hud.add_child(zoom_panel)

	var zhbox := HBoxContainer.new()
	zhbox.alignment = BoxContainer.ALIGNMENT_CENTER
	zhbox.add_theme_constant_override("separation", 4)
	zoom_panel.add_child(zhbox)

	var z_out_btn := Button.new()
	z_out_btn.text = "−"
	z_out_btn.tooltip_text = "Zoom Out Map (Scroll Bawah / -)"
	z_out_btn.custom_minimum_size = Vector2(28, 24)
	z_out_btn.add_theme_font_size_override("font_size", 14)
	_style_button(z_out_btn, Color(0.07, 0.12, 0.17), Color(0.28, 0.65, 0.78))
	z_out_btn.pressed.connect(func(): world.zoom_by_step(-0.15))
	zhbox.add_child(z_out_btn)

	hud_zoom_label = Label.new()
	hud_zoom_label.text = "68%"
	hud_zoom_label.custom_minimum_size = Vector2(44, 0)
	hud_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_zoom_label.add_theme_font_size_override("font_size", 11)
	hud_zoom_label.add_theme_color_override("font_color", Color(0.78, 0.92, 0.96))
	zhbox.add_child(hud_zoom_label)

	var z_in_btn := Button.new()
	z_in_btn.text = "+"
	z_in_btn.tooltip_text = "Zoom In Map (Scroll Atas / +)"
	z_in_btn.custom_minimum_size = Vector2(28, 24)
	z_in_btn.add_theme_font_size_override("font_size", 14)
	_style_button(z_in_btn, Color(0.07, 0.12, 0.17), Color(0.28, 0.65, 0.78))
	z_in_btn.pressed.connect(func(): world.zoom_by_step(0.15))
	zhbox.add_child(z_in_btn)

	var z_fit_btn := Button.new()
	z_fit_btn.text = "⌖ Fit"
	z_fit_btn.tooltip_text = "Reset Kamera & Zoom Penuh (0) • Drag / WASD untuk geser map"
	z_fit_btn.custom_minimum_size = Vector2(54, 24)
	z_fit_btn.add_theme_font_size_override("font_size", 11)
	_style_button(z_fit_btn, Color(0.08, 0.18, 0.22), Color(0.28, 0.92, 0.62))
	z_fit_btn.pressed.connect(func(): world.reset_camera_view())
	zhbox.add_child(z_fit_btn)

	# 3. BOTTOM-LEFT FLOATING OSCILLOSCOPE + CONTROL LOG
	oscilloscope = OscilloscopeScript.new()
	oscilloscope.anchor_left = 0.0
	oscilloscope.anchor_right = 0.0
	oscilloscope.anchor_top = 1.0
	oscilloscope.anchor_bottom = 1.0
	oscilloscope.offset_left = 10
	oscilloscope.offset_right = 540
	oscilloscope.offset_top = -198
	oscilloscope.offset_bottom = -10
	playing_hud.add_child(oscilloscope)

	# 4. BOTTOM-RIGHT SLIDE-UP TACTILE RELAY WORKBENCH DRAWER
	workbench_holder = Control.new()
	workbench_holder.anchor_left = 1.0
	workbench_holder.anchor_right = 1.0
	workbench_holder.anchor_top = 1.0
	workbench_holder.anchor_bottom = 1.0
	workbench_holder.offset_left = -716
	workbench_holder.offset_right = -10
	workbench_holder.offset_top = -278
	workbench_holder.offset_bottom = -10
	playing_hud.add_child(workbench_holder)

	workbench = CircuitWorkbenchScript.new()
	workbench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workbench.circuit_changed.connect(_on_circuit_changed)
	workbench_holder.add_child(workbench)


func _build_result_screen() -> void:
	result_screen = Control.new()
	result_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(result_screen)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_screen.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(650, 390)
	card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.09, 0.13, 0.96), Color(0.28, 0.92, 0.58), 2, 24, 12))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	res_badge_label = Label.new()
	res_badge_label.add_theme_font_size_override("font_size", 11)
	res_badge_label.add_theme_color_override("font_color", Color(0.45, 0.88, 0.95))
	vbox.add_child(res_badge_label)

	res_title_label = Label.new()
	res_title_label.add_theme_font_size_override("font_size", 26)
	vbox.add_child(res_title_label)

	res_stars_label = Label.new()
	res_stars_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_stars_label.add_theme_font_size_override("font_size", 24)
	res_stars_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	vbox.add_child(res_stars_label)

	res_metrics_hbox = HBoxContainer.new()
	res_metrics_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(res_metrics_hbox)

	var exp_box := PanelContainer.new()
	exp_box.add_theme_stylebox_override("panel", _make_stylebox(Color(0.07, 0.12, 0.17), Color(0.24, 0.55, 0.65), 1, 12, 8))
	vbox.add_child(exp_box)

	var exp_v := VBoxContainer.new()
	exp_v.add_theme_constant_override("separation", 4)
	exp_box.add_child(exp_v)

	res_explain_title = Label.new()
	res_explain_title.add_theme_font_size_override("font_size", 13)
	res_explain_title.add_theme_color_override("font_color", Color(0.42, 0.92, 1.0))
	exp_v.add_child(res_explain_title)

	res_explain_body = RichTextLabel.new()
	res_explain_body.fit_content = true
	res_explain_body.scroll_active = false
	res_explain_body.add_theme_font_size_override("normal_font_size", 13)
	res_explain_body.add_theme_color_override("default_color", Color(0.88, 0.94, 0.98))
	exp_v.add_child(res_explain_body)

	var btn_h := HBoxContainer.new()
	btn_h.alignment = BoxContainer.ALIGNMENT_END
	btn_h.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_h)

	res_menu_btn = Button.new()
	res_menu_btn.text = "Menu"
	res_menu_btn.custom_minimum_size = Vector2(96, 38)
	_style_button(res_menu_btn, Color(0.08, 0.12, 0.18), Color(0.36, 0.48, 0.58))
	res_menu_btn.pressed.connect(func(): _show_screen(GameScreen.LEVEL_SELECT))
	btn_h.add_child(res_menu_btn)

	res_retry_btn = Button.new()
	res_retry_btn.text = "↺ Perbaiki Rangkaian"
	res_retry_btn.custom_minimum_size = Vector2(180, 38)
	_style_button(res_retry_btn, Color(0.10, 0.22, 0.30), Color(0.35, 0.85, 1.0))
	res_retry_btn.pressed.connect(func():
		_show_screen(GameScreen.PLAYING)
		simulator.reset_simulation()
		workbench.set_locked(false)
		_set_workbench_open(true, true)
		_update_run_btn_ui(false)
		world.reset_camera_view()
	)
	btn_h.add_child(res_retry_btn)

	res_next_btn = Button.new()
	res_next_btn.text = "Level Berikutnya ➔"
	res_next_btn.custom_minimum_size = Vector2(190, 38)
	_style_button(res_next_btn, Color(0.10, 0.48, 0.28), Color(0.28, 1.0, 0.60))
	res_next_btn.pressed.connect(func():
		if current_level_idx < levels.size() - 1:
			_enter_level_briefing(current_level_idx + 1)
		else:
			_show_screen(GameScreen.LEVEL_SELECT)
	)
	btn_h.add_child(res_next_btn)


# ==============================================================================
# SCREEN FLOW & LEVEL LOADING
# ==============================================================================

func _show_screen(scr: int) -> void:
	current_screen = scr
	title_screen.visible = (scr == GameScreen.TITLE)
	rules_screen.visible = (scr == GameScreen.RULES)
	level_select_screen.visible = (scr == GameScreen.LEVEL_SELECT)
	briefing_screen.visible = (scr == GameScreen.BRIEFING)
	playing_hud.visible = (scr == GameScreen.PLAYING or scr == GameScreen.RESULT)
	result_screen.visible = (scr == GameScreen.RESULT)

	world.is_interactive = (scr == GameScreen.PLAYING)
	if scr == GameScreen.TITLE or scr == GameScreen.RULES or scr == GameScreen.LEVEL_SELECT:
		world.set_title_ambience()
		alarm_vignette.set_alarm(0.0)
		_refresh_level_select_stars()


func _refresh_level_select_stars() -> void:
	for i in range(level_card_star_labels.size()):
		var st: int = int(level_stars.get(i, 0))
		level_card_star_labels[i].text = "★".repeat(st) + "☆".repeat(3 - st)


func _enter_level_briefing(idx: int) -> void:
	current_level_idx = clampi(idx, 0, levels.size() - 1)
	var lvl: Dictionary = levels[current_level_idx]

	# Initialize level trees fresh when entering a level (keep current if re-opening briefing mid-level!)
	var init_d: Dictionary = lvl["initial_diesel_tree"]
	var init_s: Dictionary = lvl["initial_shed_tree"]
	if diesel_tree.is_empty() or int(simulator.current_level.get("id", -1)) != int(lvl["id"]):
		diesel_tree = init_d.duplicate(true)
		shed_tree = init_s.duplicate(true)
		simulator.setup_level(lvl, diesel_tree, shed_tree)

	# Populate RPG briefing dialogue + ANSI gate preview + truth table
	brief_portrait.texture = VillageWorldScript.load_texture_safe(String(lvl["speaker_tile"]))
	brief_speaker_label.text = "%s  —  %s" % [String(lvl["title"]), String(lvl["speaker_name"])]
	brief_role_label.text = String(lvl["speaker_role"])
	full_story_text = String(lvl["story"])
	typewriter_chars = 0.0
	is_typewriting = true
	brief_story_label.text = ""
	brief_mission_label.text = "🎯 MISI: " + String(lvl["mission_summary"])

	brief_gate_preview.set_preview_gate(String(lvl["gate_symbol"]))
	brief_concept_title.text = String(lvl["concept_title"])
	brief_concept_desc.text = String(lvl["concept_desc"])
	_populate_truth_table(lvl["truth_table"])

	# Focus the 2D Camera smoothly on the village landmark relevant to this level!
	world.focus_zone(String(lvl.get("focus_zone", "overview")), 1.05)
	_show_screen(GameScreen.BRIEFING)


func _start_playing_current_level() -> void:
	var lvl: Dictionary = levels[current_level_idx]
	hud_level_label.text = "%s • %s" % [String(lvl["concept_tag"]), String(lvl["short_title"])]

	workbench.setup_workbench(lvl, diesel_tree, shed_tree)
	simulator.setup_level(lvl, diesel_tree, shed_tree)

	_set_sim_speed(simulator.speed_multiplier)
	_update_run_btn_ui(false)
	_rebuild_mission_chips(lvl)
	_set_workbench_open(true, false)

	world.reset_camera_view()
	_show_screen(GameScreen.PLAYING)


func _populate_truth_table(tt: Dictionary) -> void:
	for c in brief_tt_box.get_children():
		c.queue_free()
	var headers: Array = tt.get("headers", [])
	var rows: Array = tt.get("rows", [])
	if headers.is_empty():
		return
	var g := GridContainer.new()
	g.columns = headers.size()
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 2)
	brief_tt_box.add_child(g)

	for h in headers:
		var hl := Label.new()
		hl.text = String(h)
		hl.add_theme_font_size_override("font_size", 10)
		hl.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0))
		g.add_child(hl)
	for r in rows:
		var row_arr: Array = r
		for cell_val in row_arr:
			var cl := Label.new()
			var ts: String = String(cell_val)
			cl.text = ts
			cl.add_theme_font_size_override("font_size", 10)
			cl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62) if ts.begins_with("1") else Color(0.76, 0.84, 0.88))
			g.add_child(cl)


func _rebuild_mission_chips(lvl: Dictionary) -> void:
	for c in hud_mission_chips.get_children():
		c.queue_free()

	var chips: Array[String] = ["★ Tanpa Blackout"]
	if bool(lvl.get("has_shed_actuator", false)):
		chips.append("⏱ Dusun 3 padam ≤ %d mnt" % int(lvl["target_shed_minutes"]))
		chips.append("⚡ Maks %d× kedip Dusun 3" % int(lvl["max_shed_flickers"]))
	else:
		chips.append("💰 Biaya ≤ %s" % format_rp(int(lvl["target_cost_rp"])))
	if int(lvl.get("max_diesel_starts", 99)) < 20:
		chips.append("🔧 Maks %d× start diesel" % int(lvl["max_diesel_starts"]))
	chips.append("🔌 Target ≤ %d gerbang" % int(lvl["target_gates"]))

	for text_chip in chips:
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_theme_stylebox_override("panel", _make_stylebox(Color(0.03, 0.07, 0.11, 0.82), Color(0.22, 0.50, 0.52, 0.85), 1, 5, 10))
		var lbl := Label.new()
		lbl.text = " %s " % text_chip
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.84, 0.94, 0.96))
		pc.add_child(lbl)
		hud_mission_chips.add_child(pc)


# ==============================================================================
# WORKBENCH SLIDE-UP DRAWER & INTERACTION
# ==============================================================================

func _on_gardu_clicked() -> void:
	_toggle_workbench()


func _on_world_zoom_changed(new_zoom: float) -> void:
	if hud_zoom_label != null:
		hud_zoom_label.text = "%d%%" % int(roundf(new_zoom * 100.0))


func _toggle_workbench() -> void:
	_set_workbench_open(not is_workbench_open, true)


func _set_workbench_open(open: bool, animate: bool) -> void:
	is_workbench_open = open
	if not open:
		workbench.close_picker()
	hud_workbench_btn.text = "▼ Tutup [Tab]" if open else "▲ Panel [Tab]"

	var target_top: float = -278.0 if open else 24.0
	var target_bot: float = -10.0 if open else 292.0

	if workbench_tween != null and workbench_tween.is_valid():
		workbench_tween.kill()

	if animate:
		workbench_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		workbench_tween.tween_property(workbench_holder, "offset_top", target_top, 0.28)
		workbench_tween.tween_property(workbench_holder, "offset_bottom", target_bot, 0.28)
	else:
		workbench_holder.offset_top = target_top
		workbench_holder.offset_bottom = target_bot


func _on_circuit_changed() -> void:
	simulator.setup_level(levels[current_level_idx], diesel_tree, shed_tree)
	workbench.queue_redraw()


func _set_sim_speed(spd: float) -> void:
	simulator.speed_multiplier = spd
	var speeds: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]
	for i in range(hud_speed_buttons.size()):
		var active: bool = is_equal_approx(speeds[i], spd)
		if active:
			_style_button(hud_speed_buttons[i], Color(0.14, 0.44, 0.34), Color(0.32, 1.0, 0.65))
		else:
			_style_button(hud_speed_buttons[i], Color(0.06, 0.10, 0.14), Color(0.22, 0.32, 0.40))


func _on_run_pressed() -> void:
	if simulator.is_running:
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
	else:
		workbench.set_locked(true)
		_update_run_btn_ui(true)
		world.reset_camera_view()
		simulator.start_simulation()


func _update_run_btn_ui(running: bool) -> void:
	if running:
		hud_run_btn.text = "⏹ Hentikan"
		_style_button(hud_run_btn, Color(0.55, 0.16, 0.16), Color(1.0, 0.38, 0.38))
	else:
		hud_run_btn.text = "▶ Jalankan"
		_style_button(hud_run_btn, Color(0.10, 0.50, 0.28), Color(0.28, 1.0, 0.60))


# ==============================================================================
# SIMULATION SIGNALS
# ==============================================================================

func _on_sim_tick(state: Dictionary) -> void:
	hud_clock_label.text = "🕒 " + String(state.get("time_str", "15:00"))
	var freq: float = float(state.get("frequency", 50.0))
	hud_freq_label.text = "%.2f Hz" % freq
	hud_progress.value = float(state.get("progress", 0.0)) * 100.0

	var is_danger: bool = (freq <= 0.1 or freq < 49.50 or freq > 50.50)
	var is_warn: bool = (freq < 49.75 or freq > 50.25)
	if is_danger:
		hud_freq_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.30))
		alarm_vignette.set_alarm(1.0)
	elif is_warn:
		hud_freq_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.25))
		alarm_vignette.set_alarm(0.35)
	else:
		hud_freq_label.add_theme_color_override("font_color", Color(0.26, 1.0, 0.60))
		alarm_vignette.set_alarm(0.0)

	world.update_from_sim(state)
	oscilloscope.update_from_sim(state)
	workbench.queue_redraw()


func _on_world_callout(zone: String, text: String, col: Color) -> void:
	world.spawn_callout(zone, text, col)


func _on_sim_finished(success: bool, reason: String, stats: Dictionary) -> void:
	workbench.set_locked(false)
	_update_run_btn_ui(false)

	var lvl: Dictionary = levels[current_level_idx]
	for c in res_metrics_hbox.get_children():
		c.queue_free()

	if success:
		alarm_vignette.set_alarm(0.0)
		var stars: int = int(stats.get("stars", 3))
		level_stars[current_level_idx] = maxi(int(level_stars.get(current_level_idx, 0)), stars)

		res_badge_label.text = "LEVEL %d SELESAI  •  %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "Desa tetap terang! ⚡"
		res_title_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.62))
		res_stars_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)

		var has_shed: bool = bool(stats.get("has_shed_actuator", false))
		if has_shed:
			_add_metric_card("DUSUN 3 PADAM", "%d menit" % int(stats["shed_minutes"]), "Target ≤ %d menit" % int(stats["target_shed_minutes"]))
		else:
			_add_metric_card("BIAYA SOLAR", format_rp(int(stats["cost_rp"])), "Target ≤ %s" % format_rp(int(stats["target_cost_rp"])))
		_add_metric_card("EMISI CO₂", "%d kg" % int(stats["co2_kg"]), "%d× start diesel" % int(stats["diesel_starts"]))
		_add_metric_card("GERBANG", "%d" % int(stats["gate_count"]), "Target ≤ %d" % int(stats["target_gates"]))

		res_explain_title.text = "💡 Kenapa berhasil?"
		res_explain_body.text = String(lvl["win_explanation"])
		res_retry_btn.text = "↺ Optimasi Lagi"
		res_next_btn.visible = true
		res_next_btn.text = "Selesai! Pilih Level ➔" if current_level_idx == levels.size() - 1 else "Level Berikutnya ➔"
	else:
		world.focus_zone("gardu", 1.05)
		res_badge_label.text = "LEVEL %d  •  GAGAL PUKUL %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "BLACKOUT ✕"
		res_title_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.32))
		res_stars_label.text = "Penyebab: " + reason
		res_stars_label.add_theme_font_size_override("font_size", 13)
		res_stars_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.78))

		res_explain_title.text = "🔍 Petunjuk Teknisi"
		res_explain_body.text = String(lvl["hint_fail"])
		res_retry_btn.text = "↺ Perbaiki Rangkaian"
		res_next_btn.visible = false

	if success:
		res_stars_label.add_theme_font_size_override("font_size", 26)
		res_stars_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))

	_show_screen(GameScreen.RESULT)


func _add_metric_card(title: String, val: String, sub: String) -> void:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.10, 0.15), Color(0.20, 0.38, 0.46), 1, 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)

	var lt := Label.new()
	lt.text = title
	lt.add_theme_font_size_override("font_size", 10)
	lt.add_theme_color_override("font_color", Color(0.55, 0.72, 0.80))
	v.add_child(lt)

	var lv := Label.new()
	lv.text = val
	lv.add_theme_font_size_override("font_size", 18)
	lv.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	v.add_child(lv)

	var ls := Label.new()
	ls.text = sub
	ls.add_theme_font_size_override("font_size", 10)
	ls.add_theme_color_override("font_color", Color(0.35, 0.92, 0.65))
	v.add_child(ls)

	res_metrics_hbox.add_child(pc)


# ==============================================================================
# FORMATTING & STYLING HELPERS
# ==============================================================================

static func format_rp(amount: int) -> String:
	var s: String = str(maxi(0, amount))
	var out: String = ""
	var n: int = s.length()
	for i in range(n):
		if i > 0 and (n - i) % 3 == 0:
			out += "."
		out += s[i]
	return "Rp " + out


func _style_button(btn: Button, bg: Color, border: Color) -> void:
	btn.add_theme_stylebox_override("normal", _make_stylebox(bg, border, 2, 6, 6))
	btn.add_theme_stylebox_override("hover", _make_stylebox(bg.lightened(0.14), border.lightened(0.18), 2, 6, 6))
	btn.add_theme_stylebox_override("pressed", _make_stylebox(bg.darkened(0.12), border, 2, 6, 6))
	btn.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))


func _make_stylebox(bg_col: Color, border_col: Color, border_w: int = 1, pad: int = 8, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

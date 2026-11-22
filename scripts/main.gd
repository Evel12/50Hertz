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
const GameScreens := preload("res://scripts/game_screens.gd")
const GameUiSkin := preload("res://scripts/game_ui_skin.gd")
const HudBrand := preload("res://scripts/hud_brand.gd")
const SIM_SPEEDS: Array[float] = [1.0, 4.0, 8.0]
const UpperHudSkin := preload("res://scripts/upper_hud_skin.gd")
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
var hud_speed_buttons: Array[Button] = []
var hud_run_btn: Button
var hud_workbench_btn: Button
var hud_zoom_label: Label
var oscilloscope: Oscilloscope
var workbench_holder: Control
var workbench: CircuitWorkbench
var is_workbench_open: bool = true
var is_workbench_expanded: bool = false
var workbench_tween: Tween

# Result Modal (Win / Blackout)
var pause_screen: Control
var is_paused := false
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
	process_mode = Node.PROCESS_MODE_ALWAYS
	levels = LevelDataScript.get_levels()

	# 1. Full-Screen 2D Village World (editable scene scenes/village_world.tscn, always live behind menus & HUD!)
	world = VillageWorldScene.instantiate() as VillageWorld
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.gardu_clicked.connect(_on_gardu_clicked)
	world.zoom_changed.connect(_on_world_zoom_changed)

	# 2. Grid Physics Simulator
	simulator = GridSimulatorScript.new()
	simulator.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	hud_root.theme = GameUiSkin.theme()
	hud_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	GameScreens.pause(self)

	_show_screen(GameScreen.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_paused:
			if event.keycode == KEY_ESCAPE:
				_set_paused(false)
			get_viewport().set_input_as_handled()
			return
		if current_screen == GameScreen.PLAYING:
			if event.keycode == KEY_ESCAPE and is_workbench_expanded:
				_set_workbench_expanded(false)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE:
				_set_paused(true)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_TAB:
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
	GameScreens.title(self)


func _build_rules_screen() -> void:
	GameScreens.rules(self)


func _build_level_select_screen() -> void:
	GameScreens.level_select(self)


func _build_briefing_screen() -> void:
	GameScreens.briefing(self)


func _build_playing_hud() -> void:
	playing_hud = Control.new()
	playing_hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	playing_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	playing_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(playing_hud)

	# All screens share the supplied pixel frames and Press Start font.
	var top_bar := PanelContainer.new()
	top_bar.name = "UpperBar"
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 8
	top_bar.offset_bottom = 64
	top_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top_bar.add_theme_stylebox_override("panel", UpperHudSkin.frame())
	playing_hud.add_child(top_bar)

	var thbox := HBoxContainer.new()
	thbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(thbox)

	var brand := HudBrand.new()
	brand.name = "GameLogo"
	brand.custom_minimum_size = Vector2(184, 38)
	thbox.add_child(brand)

	var divider := VSeparator.new()
	var divider_style := StyleBoxLine.new()
	divider_style.color = Color("c4ab80")
	divider_style.thickness = 2
	divider_style.vertical = true
	divider.add_theme_stylebox_override("separator", divider_style)
	thbox.add_child(divider)

	hud_level_label = Label.new()
	hud_level_label.text = "GERBANG NOT\nSenja di Sukamaju"
	hud_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_level_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UpperHudSkin.label(hud_level_label, 9)
	hud_level_label.add_theme_constant_override("line_spacing", 5)
	thbox.add_child(hud_level_label)

	hud_clock_label = Label.new()
	hud_clock_label.name = "SimulationClock"
	hud_clock_label.text = "15:00"
	hud_clock_label.custom_minimum_size.x = 68
	hud_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_clock_label.tooltip_text = "Waktu simulasi"
	UpperHudSkin.label(hud_clock_label, 10, UpperHudSkin.MUTED)
	thbox.add_child(hud_clock_label)

	var spd_box := HBoxContainer.new()
	spd_box.add_theme_constant_override("separation", 2)
	thbox.add_child(spd_box)
	hud_speed_buttons.clear()
	for sp_val in SIM_SPEEDS:
		var sbtn := Button.new()
		sbtn.text = "%dx" % int(sp_val)
		sbtn.custom_minimum_size = Vector2(42, 34)
		sbtn.toggle_mode = true
		sbtn.tooltip_text = "Kecepatan simulasi %dx" % int(sp_val)
		sbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UpperHudSkin.button(sbtn)
		# Narrow multiplier keys still preserve the full exported pixel border.
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			var style := sbtn.get_theme_stylebox(state).duplicate() as StyleBoxTexture
			style.content_margin_left = 6
			style.content_margin_right = 6
			sbtn.add_theme_stylebox_override(state, style)
		var captured_spd: float = sp_val
		sbtn.pressed.connect(func(): _set_sim_speed(captured_spd))
		spd_box.add_child(sbtn)
		hud_speed_buttons.append(sbtn)

	hud_run_btn = Button.new()
	hud_run_btn.text = "Jalankan"
	hud_run_btn.custom_minimum_size = Vector2(106, 34)
	hud_run_btn.tooltip_text = "Jalankan / hentikan simulasi [Spasi]"
	UpperHudSkin.button(hud_run_btn, true)
	hud_run_btn.pressed.connect(_on_run_pressed)
	thbox.add_child(hud_run_btn)

	hud_workbench_btn = Button.new()
	hud_workbench_btn.text = "Tutup [Tab]"
	hud_workbench_btn.custom_minimum_size = Vector2(120, 34)
	UpperHudSkin.button(hud_workbench_btn)
	hud_workbench_btn.pressed.connect(_toggle_workbench)
	thbox.add_child(hud_workbench_btn)

	var brief_btn := Button.new()
	brief_btn.name = "HelpButton"
	brief_btn.text = "?"
	brief_btn.tooltip_text = "Lihat Cerita & Tabel Kebenaran"
	brief_btn.custom_minimum_size = Vector2(34, 34)
	UpperHudSkin.button(brief_btn)
	brief_btn.pressed.connect(func():
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
		_enter_level_briefing(current_level_idx)
	)
	thbox.add_child(brief_btn)

	var pause_btn := Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "II"
	pause_btn.tooltip_text = "Jeda permainan [Esc]"
	pause_btn.custom_minimum_size = Vector2(34, 34)
	UpperHudSkin.button(pause_btn)
	pause_btn.pressed.connect(func(): _set_paused(true))
	thbox.add_child(pause_btn)

	var menu_btn := Button.new()
	menu_btn.name = "LevelButton"
	menu_btn.text = "Level"
	menu_btn.custom_minimum_size = Vector2(66, 34)
	UpperHudSkin.button(menu_btn)
	menu_btn.pressed.connect(func():
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
		_show_screen(GameScreen.LEVEL_SELECT)
	)
	thbox.add_child(menu_btn)
	for control in thbox.get_children():
		if control is Button:
			control.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var zoom_panel := PanelContainer.new()
	zoom_panel.name = "UpperZoom"
	zoom_panel.anchor_left = 1.0
	zoom_panel.anchor_right = 1.0
	zoom_panel.offset_left = -212
	zoom_panel.offset_right = -10
	zoom_panel.offset_top = 72
	zoom_panel.offset_bottom = 116
	zoom_panel.add_theme_stylebox_override("panel", UpperHudSkin.frame(UpperHudSkin.PANEL, 8, 5))
	playing_hud.add_child(zoom_panel)

	var zhbox := HBoxContainer.new()
	zhbox.alignment = BoxContainer.ALIGNMENT_CENTER
	zhbox.add_theme_constant_override("separation", 4)
	zoom_panel.add_child(zhbox)

	var z_out_btn := Button.new()
	z_out_btn.text = "-"
	z_out_btn.tooltip_text = "Zoom Out Map (Scroll Bawah / -)"
	z_out_btn.custom_minimum_size = Vector2(30, 28)
	UpperHudSkin.button(z_out_btn)
	z_out_btn.pressed.connect(func(): world.zoom_by_step(-0.15))
	zhbox.add_child(z_out_btn)

	hud_zoom_label = Label.new()
	hud_zoom_label.text = "68%"
	hud_zoom_label.custom_minimum_size = Vector2(44, 0)
	hud_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UpperHudSkin.label(hud_zoom_label, 9, UpperHudSkin.TEAL)
	zhbox.add_child(hud_zoom_label)

	var z_in_btn := Button.new()
	z_in_btn.text = "+"
	z_in_btn.tooltip_text = "Zoom In Map (Scroll Atas / +)"
	z_in_btn.custom_minimum_size = Vector2(30, 28)
	UpperHudSkin.button(z_in_btn)
	z_in_btn.pressed.connect(func(): world.zoom_by_step(0.15))
	zhbox.add_child(z_in_btn)

	var z_fit_btn := Button.new()
	z_fit_btn.text = "Fit"
	z_fit_btn.tooltip_text = "Reset Kamera & Zoom Penuh (0) - Drag / WASD untuk geser map"
	z_fit_btn.custom_minimum_size = Vector2(48, 28)
	UpperHudSkin.button(z_fit_btn)
	z_fit_btn.pressed.connect(func(): world.reset_camera_view())
	zhbox.add_child(z_fit_btn)

	# 3. BOTTOM-LEFT FREQUENCY BOARD + LEVEL OBJECTIVES
	oscilloscope = OscilloscopeScript.new()
	oscilloscope.anchor_left = 0.0
	oscilloscope.anchor_right = 0.0
	oscilloscope.anchor_top = 1.0
	oscilloscope.anchor_bottom = 1.0
	oscilloscope.offset_left = 10
	oscilloscope.offset_right = 540
	oscilloscope.offset_top = -232
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
	workbench_holder.offset_top = -400
	workbench_holder.offset_bottom = -10
	playing_hud.add_child(workbench_holder)

	workbench = CircuitWorkbenchScript.new()
	workbench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workbench.circuit_changed.connect(_on_circuit_changed)
	workbench.expansion_requested.connect(func(): _set_workbench_expanded(not is_workbench_expanded))
	workbench_holder.add_child(workbench)
	# GUI hit testing follows sibling order, independently of visual z_index.
	# Keep telemetry controls clickable over the expanded GraphEdit.
	playing_hud.move_child(oscilloscope, -1)


func _build_result_screen() -> void:
	GameScreens.result(self)


# ==============================================================================
# SCREEN FLOW & LEVEL LOADING
# ==============================================================================

func _show_screen(scr: int) -> void:
	if is_paused:
		_set_paused(false)
	if is_workbench_expanded and scr not in [GameScreen.PLAYING, GameScreen.RESULT]:
		_set_workbench_expanded(false)
	current_screen = scr
	title_screen.visible = (scr == GameScreen.TITLE)
	rules_screen.visible = (scr == GameScreen.RULES)
	level_select_screen.visible = (scr == GameScreen.LEVEL_SELECT)
	briefing_screen.visible = (scr == GameScreen.BRIEFING)
	playing_hud.visible = (scr == GameScreen.PLAYING or scr == GameScreen.RESULT)
	playing_hud.process_mode = Node.PROCESS_MODE_PAUSABLE if scr == GameScreen.PLAYING else Node.PROCESS_MODE_DISABLED
	result_screen.visible = (scr == GameScreen.RESULT)

	world.is_interactive = (scr == GameScreen.PLAYING and not is_workbench_expanded)
	if scr == GameScreen.TITLE or scr == GameScreen.RULES or scr == GameScreen.LEVEL_SELECT:
		world.set_title_ambience()
		alarm_vignette.set_alarm(0.0)
		_refresh_level_select_stars()


func _refresh_level_select_stars() -> void:
	for i in range(level_card_star_labels.size()):
		var st: int = int(level_stars.get(i, 0))
		level_card_star_labels[i].text = "%d/3" % st


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
	brief_mission_label.text = "MISI: " + String(lvl["mission_summary"])

	brief_gate_preview.set_preview_gate(String(lvl["gate_symbol"]))
	brief_concept_title.text = String(lvl["concept_title"])
	brief_concept_desc.text = String(lvl["concept_desc"])
	_populate_truth_table(lvl["truth_table"])

	# Focus the 2D Camera smoothly on the village landmark relevant to this level!
	world.focus_zone(String(lvl.get("focus_zone", "overview")), 1.05)
	_show_screen(GameScreen.BRIEFING)


func _start_playing_current_level() -> void:
	var lvl: Dictionary = levels[current_level_idx]
	hud_level_label.text = "%s\n%s" % [String(lvl["concept_tag"]), String(lvl["short_title"])]
	hud_level_label.tooltip_text = hud_level_label.text.replace("\n", " - ")

	oscilloscope.setup_level(lvl)
	workbench.setup_workbench(lvl, diesel_tree, shed_tree)
	simulator.setup_level(lvl, diesel_tree, shed_tree)

	_set_sim_speed(simulator.speed_multiplier)
	_update_run_btn_ui(false)
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
	g.add_theme_constant_override("v_separation", 7)
	brief_tt_box.add_child(g)

	for h in headers:
		var hl := Label.new()
		hl.text = String(h)
		hl.add_theme_font_size_override("font_size", 9)
		hl.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0))
		g.add_child(hl)
	for r in rows:
		var row_arr: Array = r
		for cell_val in row_arr:
			var cl := Label.new()
			var ts: String = String(cell_val)
			cl.text = ts
			cl.add_theme_font_size_override("font_size", 9)
			cl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62) if ts.begins_with("1") else Color(0.76, 0.84, 0.88))
			g.add_child(cl)


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
	if not open and is_workbench_expanded:
		_set_workbench_expanded(false)
	is_workbench_open = open
	if not open:
		workbench.close_picker()
	hud_workbench_btn.text = "Tutup [Tab]" if open else "Panel [Tab]"
	if is_workbench_expanded:
		return
	var target_top := -400.0 if open else 24.0
	var target_bottom := -10.0 if open else 414.0
	if workbench_tween != null and workbench_tween.is_valid():
		workbench_tween.kill()
	if animate:
		workbench_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		workbench_tween.tween_property(workbench_holder, "offset_top", target_top, 0.28)
		workbench_tween.tween_property(workbench_holder, "offset_bottom", target_bottom, 0.28)
	else:
		workbench_holder.offset_top = target_top
		workbench_holder.offset_bottom = target_bottom


func _set_workbench_expanded(expand: bool) -> void:
	if workbench_tween != null and workbench_tween.is_valid():
		workbench_tween.kill()
	workbench.set_expanded(expand)
	is_workbench_expanded = expand
	is_workbench_open = true
	hud_workbench_btn.text = "Tutup [Tab]"
	if expand:
		workbench_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		workbench_holder.offset_left = 10
		workbench_holder.offset_right = -10
		workbench_holder.offset_top = 72
		workbench_holder.offset_bottom = -10
	else:
		workbench_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		workbench_holder.offset_left = -716
		workbench_holder.offset_right = -10
		workbench_holder.offset_top = -400
		workbench_holder.offset_bottom = -10
	workbench_holder.z_index = 5
	oscilloscope.z_index = 10
	workbench.graph_view.occlusion = oscilloscope if expand else null
	playing_hud.get_node("UpperZoom").visible = not expand
	world.is_interactive = current_screen == GameScreen.PLAYING and not expand


func _on_circuit_changed() -> void:
	diesel_tree = workbench.diesel_tree
	shed_tree = workbench.shed_tree
	simulator.setup_level(levels[current_level_idx], diesel_tree, shed_tree)
	workbench.update_from_sim({"sensors": simulator.sensors_state})


func _set_sim_speed(spd: float) -> void:
	var selected_speed := spd if spd in SIM_SPEEDS else 1.0
	simulator.speed_multiplier = selected_speed
	for i in range(hud_speed_buttons.size()):
		var active: bool = is_equal_approx(SIM_SPEEDS[i], selected_speed)
		UpperHudSkin.select_speed(hud_speed_buttons[i], active)


func _on_run_pressed() -> void:
	if is_paused:
		return
	if simulator.is_running:
		simulator.stop_simulation()
		workbench.set_locked(false)
		_update_run_btn_ui(false)
	else:
		if not workbench.can_simulate():
			_set_workbench_open(true, false)
			return
		workbench.set_locked(true)
		_update_run_btn_ui(true)
		world.reset_camera_view()
		simulator.start_simulation()


func _update_run_btn_ui(running: bool) -> void:
	hud_run_btn.text = "Hentikan" if running else "Jalankan"
	UpperHudSkin.button(hud_run_btn, true)
	hud_run_btn.add_theme_color_override("font_color", UpperHudSkin.ALERT if running else UpperHudSkin.INK)


# ==============================================================================
# SIMULATION SIGNALS
# ==============================================================================

func _on_sim_tick(state: Dictionary) -> void:
	state["gate_count"] = simulator.count_total_gates()
	hud_clock_label.text = String(state.get("time_str", "15:00"))
	var freq: float = float(state.get("frequency", 50.0))

	var is_danger: bool = (freq <= 0.1 or freq < 49.50 or freq > 50.50)
	var is_warn: bool = (freq < 49.75 or freq > 50.25)
	if is_danger:
		alarm_vignette.set_alarm(1.0)
	elif is_warn:
		alarm_vignette.set_alarm(0.35)
	else:
		alarm_vignette.set_alarm(0.0)

	world.update_from_sim(state)
	oscilloscope.update_from_sim(state)
	workbench.update_from_sim(state)


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

		res_badge_label.text = "LEVEL %d  /  %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "DESA TETAP TERANG!"
		res_title_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.62))
		res_stars_label.text = "%d / 3 BINTANG" % stars

		var has_shed: bool = bool(stats.get("has_shed_actuator", false))
		if has_shed:
			_add_metric_card("DUSUN 3 PADAM", "%d menit" % int(stats["shed_minutes"]), "Target ≤ %d menit" % int(stats["target_shed_minutes"]))
		else:
			_add_metric_card("BIAYA SOLAR", format_rp(int(stats["cost_rp"])), "Target <= %s" % format_rp(int(stats["target_cost_rp"])))
		_add_metric_card("EMISI CO2", "%d kg" % int(stats["co2_kg"]), "%d× start diesel" % int(stats["diesel_starts"]))
		_add_metric_card("GERBANG", "%d" % int(stats["gate_count"]), "Target <= %d" % int(stats["target_gates"]))

		res_explain_title.text = "KENAPA BERHASIL?"
		res_explain_body.text = String(lvl["win_explanation"])
		res_retry_btn.text = "OPTIMASI LAGI"
		res_next_btn.visible = true
		res_next_btn.text = "PILIH LEVEL" if current_level_idx == levels.size() - 1 else "LEVEL BERIKUTNYA"
	else:
		world.focus_zone("gardu", 1.05)
		res_badge_label.text = "LEVEL %d  /  %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "BLACKOUT"
		res_title_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.32))
		res_stars_label.text = "Penyebab: " + reason
		res_stars_label.add_theme_font_size_override("font_size", 9)
		res_stars_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.78))

		res_explain_title.text = "PETUNJUK TEKNISI"
		res_explain_body.text = String(lvl["hint_fail"])
		res_retry_btn.text = "PERBAIKI RANGKAIAN"
		res_next_btn.visible = false

	if success:
		res_stars_label.add_theme_font_size_override("font_size", 12)
		res_stars_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))

	_show_screen(GameScreen.RESULT)


func _add_metric_card(title: String, val: String, sub: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UpperHudSkin.frame(UpperHudSkin.PANEL, 14, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(GameUiSkin.label(title, 8, UpperHudSkin.MUTED))
	box.add_child(GameUiSkin.label(val, 12, UpperHudSkin.INK))
	box.add_child(GameUiSkin.label(sub, 7, UpperHudSkin.TEAL, true))
	res_metrics_hbox.add_child(panel)


func _set_paused(paused: bool) -> void:
	if paused and current_screen != GameScreen.PLAYING:
		return
	is_paused = paused
	get_tree().paused = paused
	pause_screen.visible = paused
	world.is_interactive = not paused and current_screen == GameScreen.PLAYING and not is_workbench_expanded
	if paused:
		pause_screen.find_child("ResumeButton", true, false).grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and pause_screen.is_ancestor_of(focused):
			focused.release_focus()


func _retry_current_level() -> void:
	_set_paused(false)
	simulator.reset_simulation()
	workbench.set_locked(false)
	_update_run_btn_ui(false)
	_set_workbench_expanded(false)
	_set_workbench_open(true, false)
	world.reset_camera_view()
	_show_screen(GameScreen.PLAYING)


func _restart_current_level() -> void:
	# Retain the player's wiring and restart only the simulation clock and memory.
	_retry_current_level()


func _leave_playing(destination: int) -> void:
	_set_paused(false)
	simulator.stop_simulation()
	workbench.set_locked(false)
	_update_run_btn_ui(false)
	_show_screen(destination)



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

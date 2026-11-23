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

enum GameScreen { TITLE, RULES, LEVEL_SELECT, BRIEFING, PLAYING, RESULT, CREDITS }

var audio_enabled := true
var audio
var credits_screen: Control
var is_intro_tutorial := false
var intro_level: Dictionary = {}
var tutorial_guide: Control
var audio_save_delay := -1.0
var progress_store = preload("res://scripts/progress_store.gd").new()
var output_picker: OptionButton
var output_status_label: Label
var reading_modal: Control
var frequency_handles: Control
var workbench_handles: Control
var workbench_normal_rect := Rect2()
var handbook: Control
var manual_panel: Control
var hint_index := 0
var level_buttons: Array[Button] = []

var current_screen: int = GameScreen.TITLE
var levels: Array[Dictionary] = []
var current_level_idx: int = 0
var completed_levels: Dictionary = {}

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
var level_completion_labels: Array[Label] = []

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
var workbench_restored_height := 390.0
var is_workbench_expanded: bool = false
var workbench_tween: Tween

# Result Modal (Win / Blackout)
var pause_screen: Control
var is_paused := false
var result_screen: Control
var res_badge_label: Label
var res_title_label: Label
var res_status_label: Label
var res_metrics_hbox: HBoxContainer
var res_explain_title: Label
var res_explain_body: RichTextLabel
var res_retry_btn: Button
var res_menu_btn: Button
var res_next_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	levels = LevelDataScript.get_levels()
	progress_store.load_progress()
	completed_levels = progress_store.data["completed"]
	intro_level = preload("res://scripts/intro_tutorial_data.gd").build(levels[0])
	audio = preload("res://scripts/game_audio.gd").new()
	audio.enabled = audio_enabled
	add_child(audio)
	audio.configure(progress_store.data["settings"])

	# 1. Full-Screen 2D Village World (editable scene scenes/village_world.tscn, always live behind menus & HUD!)
	world = VillageWorldScene.instantiate() as VillageWorld
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.gardu_clicked.connect(_on_gardu_clicked)
	world.mission_output_selected.connect(_focus_mission_output)
	world.zoom_changed.connect(_on_world_zoom_changed)

	# 2. Grid Physics Simulator
	simulator = GridSimulatorScript.new()
	simulator.speed_multiplier = float(progress_store.data["settings"].get("speed",1.0))
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

	get_tree().node_added.connect(_bind_menu_click)
	_build_title_screen()
	_build_rules_screen()
	GameScreens.credits(self)
	_build_level_select_screen()
	_build_briefing_screen()
	_build_playing_hud()
	_build_result_screen()
	GameScreens.pause(self)
	_build_learning_controls()
	_build_output_controls()
	_install_panel_handles()
	if not OS.has_feature("web") and bool(progress_store.data["settings"].get("fullscreen",false)):
		_set_fullscreen(true)

	_show_screen(GameScreen.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
			_set_fullscreen(get_window().mode != Window.MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(reading_modal):
			if event.keycode == KEY_ESCAPE: reading_modal.close()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(handbook):
			if event.keycode == KEY_ESCAPE:
				handbook.close()
			get_viewport().set_input_as_handled()
			return
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
	if audio!=null: audio.set_ducked(is_paused or is_instance_valid(handbook) or is_instance_valid(reading_modal) or current_screen in [GameScreen.BRIEFING,GameScreen.RESULT])
	if audio_save_delay>=0:
		audio_save_delay -= delta
		if audio_save_delay<0: progress_store.save_progress()
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
	top_bar.anchor_left = 0.5
	top_bar.anchor_right = 0.5
	var layout_top_bar := func():
		var width := minf(800.0, playing_hud.size.x - 20.0)
		top_bar.offset_left = -width * 0.5
		top_bar.offset_right = width * 0.5
	playing_hud.resized.connect(layout_top_bar)
	layout_top_bar.call()
	top_bar.offset_top = 8
	top_bar.offset_bottom = 64
	top_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top_bar.add_theme_stylebox_override("panel", UpperHudSkin.frame())
	playing_hud.add_child(top_bar)

	var thbox := HBoxContainer.new()
	thbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(thbox)

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

	hud_workbench_btn = preload("res://scripts/panel_toggle_button.gd").new()
	hud_workbench_btn.name = "MinimizeWorkbench"
	hud_workbench_btn.custom_minimum_size = Vector2(28, 22)
	hud_workbench_btn.tooltip_text = "Minimalkan rangkaian kontrol [Tab]"
	UpperHudSkin.button(hud_workbench_btn)
	for state in ["normal","hover","pressed","disabled","hover_pressed"]:
		var style := hud_workbench_btn.get_theme_stylebox(state).duplicate() as StyleBoxTexture
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 3
		style.content_margin_bottom = 5
		hud_workbench_btn.add_theme_stylebox_override(state,style)
	hud_workbench_btn.pressed.connect(_toggle_workbench)


	var brief_btn := Button.new()
	brief_btn.name = "HelpButton"
	brief_btn.text = "?"
	brief_btn.tooltip_text = "Baca kembali misi, input, dan output"
	brief_btn.custom_minimum_size = Vector2(34, 34)
	UpperHudSkin.button(brief_btn)
	brief_btn.pressed.connect(_show_mission)
	thbox.add_child(brief_btn)

	for control in thbox.get_children():
		if control is Button:
			control.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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
	hud_workbench_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud_workbench_btn.offset_left = -46
	hud_workbench_btn.offset_right = -18
	hud_workbench_btn.offset_top = 10
	hud_workbench_btn.offset_bottom = 32
	workbench.add_child(hud_workbench_btn)
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
	credits_screen.visible = (scr == GameScreen.CREDITS)
	level_select_screen.visible = (scr == GameScreen.LEVEL_SELECT)
	briefing_screen.visible = (scr == GameScreen.BRIEFING)
	playing_hud.visible = (scr == GameScreen.PLAYING or scr == GameScreen.RESULT)
	playing_hud.process_mode = Node.PROCESS_MODE_PAUSABLE if scr == GameScreen.PLAYING else Node.PROCESS_MODE_DISABLED
	result_screen.visible = (scr == GameScreen.RESULT)

	world.is_interactive = (scr == GameScreen.PLAYING and not is_workbench_expanded)
	if scr in [GameScreen.TITLE,GameScreen.RULES,GameScreen.LEVEL_SELECT,GameScreen.CREDITS]:
		world.set_title_ambience()
		alarm_vignette.set_alarm(0.0)
		_refresh_level_select_status()
	_sync_audio_screen()


func _refresh_level_select_status() -> void:
	for i in range(level_completion_labels.size()):
		var done: bool = bool(completed_levels.get(i, false))
		level_completion_labels[i].text = "SELESAI" if done else "BELUM SELESAI"
		if i < level_buttons.size():
			level_buttons[i].disabled = i+1 > int(progress_store.data["unlocked_stage"])
			level_buttons[i].tooltip_text = "Selesaikan stage sebelumnya" if level_buttons[i].disabled else "Baca misi"


func _enter_level_briefing(idx: int, intro: bool = false) -> void:
	is_intro_tutorial = intro
	if not intro and is_instance_valid(tutorial_guide):
		tutorial_guide.queue_free()
		tutorial_guide = null
	if idx+1 > int(progress_store.data["unlocked_stage"]):
		return
	hint_index = 0
	current_level_idx = clampi(idx, 0, levels.size() - 1)
	var lvl: Dictionary = _active_level()

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
	full_story_text = String(lvl["story"])+"\n\nTUGAS\n"+String(lvl.get("mission_instructions",lvl["mission_summary"]))
	typewriter_chars = 0.0
	is_typewriting = true
	brief_story_label.text = ""
	brief_mission_label.hide()

	brief_gate_preview.set_preview_gate(String(lvl["gate_symbol"]))
	brief_concept_title.text = String(lvl["concept_title"])
	brief_concept_desc.text = String(lvl["concept_desc"])
	_populate_stage_io(lvl)

	world.configure_mission(lvl)
	_populate_output_controls()
	_refresh_output_visuals()
	# Focus the 2D Camera smoothly on the village landmark relevant to this level!
	world.focus_zone(String(lvl.get("focus_zone", "overview")), 1.05)
	_show_screen(GameScreen.BRIEFING)


func _start_playing_current_level() -> void:
	var lvl: Dictionary = _active_level()
	hud_level_label.text = "%s\n%s" % [String(lvl["concept_tag"]), String(lvl["short_title"])]
	hud_level_label.tooltip_text = hud_level_label.text.replace("\n", " - ")

	oscilloscope.setup_level(lvl)
	workbench.setup_workbench(lvl, diesel_tree, shed_tree)
	if is_intro_tutorial:
		for id in workbench.graph_model.nodes:
			if workbench.graph_model.is_actuator(id): workbench.graph_model.nodes[id]["position"] = Vector2(660,80)
		workbench._rebuild_graph()
		workbench.call_deferred("fit_view")
	simulator.output_trees = workbench.output_trees
	var saved: Dictionary = {} if is_intro_tutorial else progress_store.data["circuits"].get(current_level_idx, {})
	if not saved.is_empty():
		workbench.graph_model.restore(saved)
		workbench._commit_graph()
	simulator.setup_level(lvl, diesel_tree, shed_tree)
	_refresh_manual_inputs()
	world.configure_mission(lvl)
	_populate_output_controls()
	_refresh_output_visuals()

	_set_sim_speed(simulator.speed_multiplier)
	_update_run_btn_ui(false)
	_set_workbench_open(true, false)

	world.reset_camera_view()
	_show_screen(GameScreen.PLAYING)
	if is_intro_tutorial:
		if is_instance_valid(tutorial_guide): tutorial_guide.queue_free()
		tutorial_guide = preload("res://scripts/beginner_tutorial.gd").new()
		tutorial_guide.game = self
		hud_root.add_child(tutorial_guide)


func _populate_stage_io(lvl: Dictionary) -> void:
	for child in brief_tt_box.get_children():
		brief_tt_box.remove_child(child)
		child.queue_free()
	for section in [["INPUT",lvl["available_sensors"],Color("80dfff")],["OUTPUT",lvl["outputs"],Color("a4edb0")]]:
		var box := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("103f3c")
		style.border_color = section[2]
		style.set_border_width_all(2)
		style.set_content_margin_all(12)
		box.add_theme_stylebox_override("panel",style)
		brief_tt_box.add_child(box)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation",10)
		box.add_child(stack)
		stack.add_child(GameUiSkin.label(section[0],10,section[2]))
		for key in section[1]:
			stack.add_child(GameUiSkin.label("• "+String(key),8,section[2],true))



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


func _set_workbench_open(open: bool, _animate: bool) -> void:
	if not open and is_workbench_expanded: _set_workbench_expanded(false)
	if not open and is_workbench_open:
		workbench_restored_height = workbench_holder.size.y
	is_workbench_open = open
	workbench_holder.show()
	if not open: workbench.close_picker()
	workbench.set_minimized(not open)
	workbench_holder.size.y = workbench_restored_height if open else 44.0
	if workbench_handles!=null:
		workbench_handles.minimum.y = 330.0 if open else 44.0
	hud_workbench_btn.set("minimized",not open)
	hud_workbench_btn.tooltip_text = "Minimalkan rangkaian kontrol [Tab]" if open else "Tampilkan rangkaian kontrol [Tab]"

func _set_workbench_expanded(expand: bool) -> void:
	if is_workbench_expanded == expand: return
	if not is_workbench_open: _set_workbench_open(true,false)
	workbench.set_expanded(expand)
	if expand:
		workbench_normal_rect = Rect2(workbench_holder.position,workbench_holder.size)
		workbench_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		workbench_holder.offset_left = 10
		workbench_holder.offset_right = -10
		workbench_holder.offset_top = 72
		workbench_holder.offset_bottom = -10
	else:
		workbench_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		workbench_holder.position = workbench_normal_rect.position
		workbench_holder.size = workbench_normal_rect.size
	is_workbench_expanded = expand
	is_workbench_open = true
	workbench_holder.show()
	hud_workbench_btn.set("minimized",false)
	workbench_holder.z_index = 5
	oscilloscope.z_index = 10
	workbench.graph_view.occlusion = oscilloscope
	world.is_interactive = current_screen == GameScreen.PLAYING and not expand
	if workbench_handles != null:
		workbench_handles.set_enabled(not expand)
		if not expand: workbench_handles.apply_rect(workbench_normal_rect)


func _on_circuit_changed() -> void:
	diesel_tree = workbench.diesel_tree
	shed_tree = workbench.shed_tree
	simulator.output_trees = workbench.output_trees
	simulator.setup_level(_active_level(), diesel_tree, shed_tree)
	if not is_intro_tutorial:
		progress_store.data["circuits"][current_level_idx] = workbench.graph_model.snapshot()
		progress_store.save_progress()
	workbench.update_from_sim({"sensors": simulator.sensors_state})


func _set_sim_speed(spd: float) -> void:
	var selected_speed := spd if spd in SIM_SPEEDS else 1.0
	simulator.speed_multiplier = selected_speed
	progress_store.data["settings"]["speed"] = selected_speed
	progress_store.save_progress()
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
	_refresh_output_visuals(state)
	oscilloscope.update_from_sim(state)
	workbench.update_from_sim(state)
	var environment := state.duplicate()
	environment["running"] = simulator.is_running
	audio.update_environment(environment)


func _on_world_callout(zone: String, text: String, col: Color) -> void:
	world.spawn_callout(zone, text, col)


func _on_sim_finished(success: bool, reason: String, stats: Dictionary) -> void:
	workbench.set_locked(false)
	_update_run_btn_ui(false)

	var lvl: Dictionary = _active_level()
	for c in res_metrics_hbox.get_children():
		c.queue_free()

	if success:
		alarm_vignette.set_alarm(0.0)
		if is_intro_tutorial:
			progress_store.data["tutorial"]["intro_completed"] = true
			progress_store.save_progress()
		else:
			progress_store.complete(current_level_idx)

		res_badge_label.text = "LEVEL %d  /  %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "DESA TETAP TERANG!"
		res_title_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.62))
		res_status_label.text = "Semua tujuan wajib misi terpenuhi."

		res_explain_title.text = "KENAPA BERHASIL?"
		res_explain_body.text = String(lvl["win_explanation"])
		if current_level_idx == 19:
			res_explain_body.text += "\nUstadz Hasan: Sahur pertama terlewati. Terima kasih telah menyelesaikan 20 stage!"
		res_retry_btn.text = "COBA LAGI"
		res_next_btn.visible = true
		res_next_btn.text = "PILIH LEVEL" if current_level_idx == levels.size() - 1 else "LEVEL BERIKUTNYA"
	else:
		world.focus_zone("gardu", 1.05)
		res_badge_label.text = "LEVEL %d  /  %s" % [int(lvl["id"]), String(stats["end_time_str"])]
		res_title_label.text = "PENGENDALI PERLU DIPERBAIKI"
		res_title_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.32))
		res_status_label.text = "Rangkaian belum memenuhi tujuan misi."
		res_status_label.add_theme_font_size_override("font_size", 9)
		res_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.78))

		res_explain_title.text = "KENAPA BELUM BERHASIL?"
		res_explain_body.text = reason+"\n\n"+String(lvl["hint_fail"])
		res_retry_btn.text = "PERBAIKI RANGKAIAN"
		res_next_btn.visible = false

	if success:
		res_status_label.add_theme_font_size_override("font_size", 12)
		res_status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))

	if is_intro_tutorial and success:
		res_title_label.text = "LATIHAN SELESAI!"
		res_status_label.text = "Siap mengerjakan misi pertama."
		res_next_btn.text = "MISI PERTAMA"
	_show_screen(GameScreen.RESULT)
	audio.play_result(success)


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
	if audio!=null: audio.set_ducked(paused)
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
	_set_paused(false)
	simulator.stop_simulation()
	if is_instance_valid(reading_modal): reading_modal.close()
	if is_instance_valid(handbook): handbook.close()
	_set_paused(false)
	var lvl := _active_level()
	if not is_intro_tutorial:
		progress_store.data["circuits"].erase(current_level_idx)
		progress_store.save_progress()
	lvl.erase("saved_outputs")
	diesel_tree = lvl["initial_diesel_tree"].duplicate(true)
	shed_tree = lvl["initial_shed_tree"].duplicate(true)
	workbench.level_dict = {}
	hint_index = 0
	_set_workbench_expanded(false)
	_start_playing_current_level()


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

func _build_learning_controls() -> void:
	var hint := GameUiSkin.button("PETUNJUK",_show_hint,false,170)
	hint.name = "HintButton"
	hint.position = Vector2(14,125)
	playing_hud.add_child(hint)
	manual_panel = VBoxContainer.new()
	manual_panel.position = Vector2(14,180)
	manual_panel.size = Vector2(260,220)
	playing_hud.add_child(manual_panel)

func _show_handbook(entry: String = "WIRE") -> void:
	if is_instance_valid(handbook) or is_instance_valid(reading_modal): return
	handbook = preload("res://scripts/component_handbook.gd").new()
	handbook.game = self
	handbook.entry = entry
	hud_root.add_child(handbook)

func _show_mission() -> void:
	if is_instance_valid(reading_modal) or is_instance_valid(handbook): return
	reading_modal = preload("res://scripts/mission_dialog.gd").new()
	reading_modal.game = self
	reading_modal.heading = "MISI — "+str(_active_level()["short_title"])
	reading_modal.mission = _active_level()
	hud_root.add_child(reading_modal)


func _show_hint() -> void:
	# Reopening keeps the last page; the modal owns next/previous navigation.
	_show_hint_page(hint_index)

func _show_hint_page(index: int) -> void:
	var hints: Array = _active_level()["hints"]
	hint_index = clampi(index,0,hints.size()-1)
	_show_text_modal("PETUNJUK %d / %d" % [hint_index+1,hints.size()],str(hints[hint_index]),true)
	if is_instance_valid(reading_modal): reading_modal.update_hint_navigation(hint_index,hints.size())

func _show_text_modal(heading: String, content: String, is_hint: bool) -> void:
	if is_instance_valid(handbook): return
	if is_instance_valid(reading_modal):
		reading_modal.title_label.text = heading
		reading_modal.set_hint_content(content)
		return
	reading_modal = preload("res://scripts/mission_dialog.gd").new()
	reading_modal.game = self
	reading_modal.heading = heading
	reading_modal.content = content
	reading_modal.is_hint = is_hint
	hud_root.add_child(reading_modal)

func _set_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	progress_store.data["settings"]["fullscreen"] = enabled
	progress_store.save_progress()
	var toggle := rules_screen.find_child("FullscreenToggle",true,false) as CheckButton
	if toggle != null: toggle.set_pressed_no_signal(enabled)

func _install_panel_handles() -> void:
	var Handle := preload("res://scripts/floating_panel.gd")
	frequency_handles = Handle.new()
	frequency_handles.name = "PanelHandles"
	frequency_handles.target = oscilloscope
	frequency_handles.minimum = Vector2(420,180)
	oscilloscope.add_child(frequency_handles)
	workbench_handles = Handle.new()
	workbench_handles.name = "PanelHandles"
	workbench_handles.target = workbench_holder
	workbench_handles.minimum = Vector2(560,330)
	workbench_handles.header_width = 200
	workbench_holder.add_child(workbench_handles)
	frequency_handles.rect_changed.connect(func(rect):
		progress_store.data["settings"]["frequency_rect"] = rect
		progress_store.save_progress()
	)
	workbench_handles.rect_changed.connect(func(rect):
		if not is_workbench_open: rect.size.y = workbench_restored_height
		progress_store.data["settings"]["workbench_rect"] = rect
		progress_store.save_progress()
	)
	workbench.graph_view.occlusion = oscilloscope
	call_deferred("_restore_panel_layout")

func _restore_panel_layout() -> void:
	for item in [["frequency_rect",frequency_handles],["workbench_rect",workbench_handles]]:
		var saved = progress_store.data["settings"].get(item[0])
		if saved is Rect2: item[1].apply_rect(saved)

func _reset_panel_layout() -> void:
	if is_workbench_expanded: _set_workbench_expanded(false)
	_set_workbench_open(true,false)
	oscilloscope.set_minimized(false)
	var extent: Vector2 = playing_hud.size
	frequency_handles.apply_rect(Rect2(10,extent.y-232,530,222))
	workbench_handles.apply_rect(Rect2(extent.x-716,extent.y-400,706,390))


func _refresh_manual_inputs() -> void:
	for child in manual_panel.get_children():
		manual_panel.remove_child(child)
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 180)
	manual_panel.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	list.add_child(GameUiSkin.label("Simulasi Switch",8))
	for sensor in _active_level()["available_sensors"]:
		var button := CheckButton.new()
		button.text = sensor
		button.button_pressed = bool(simulator.sensors_state.get(sensor,false))
		button.add_theme_font_size_override("font_size", 7)
		button.toggled.connect(func(on):
			if not simulator.is_running:
				simulator.sensors_state[sensor] = on
				var values: Dictionary = {}
				for output in workbench.output_trees:
					values[output] = preload("res://scripts/logic_tree.gd").evaluate(workbench.output_trees[output], simulator.sensors_state, false)
				workbench.update_from_sim({"sensors":simulator.sensors_state})
				_refresh_output_visuals({"outputs":values,"sensors":simulator.sensors_state,"visual_phase":"latihan"})
		)
		list.add_child(button)

func _build_output_controls() -> void:
	pass


func _populate_output_controls() -> void:
	if output_picker==null or not is_instance_valid(world.mission_map): return
	output_picker.clear()
	for output in _active_level()["outputs"]:
		var marker: Dictionary = world.mission_map.marker_for(output)
		output_picker.add_item(marker.get("name",output))
	if output_picker.item_count>0: output_picker.select(0)

func _refresh_output_visuals(state: Dictionary = {}) -> void:
	if not is_instance_valid(world.mission_map): return
	if int(world.mission_map.level.get("id",-1))!=int(_active_level()["id"]): return
	var context := state.duplicate()
	var sensors: Dictionary = _active_level().get("initial_inputs",{}).duplicate()
	sensors.merge(state.get("sensors",simulator.sensors_state),true)
	context["sensors"] = sensors
	var commands: Dictionary = state.get("outputs",simulator.output_values).duplicate()
	var connected: Dictionary = {}
	for output in _active_level()["outputs"]:
		connected[output] = int(workbench.level_dict.get("id",-1))==int(_active_level()["id"]) and workbench.output_trees.has(output)
		if not commands.has(output):
			commands[output] = preload("res://scripts/logic_tree.gd").evaluate(workbench.output_trees.get(output,{}),sensors,false)
	context["outputs"] = commands
	context["connected_outputs"] = connected
	context["frequency"] = state.get("frequency",simulator.frequency)
	context["cascade_stage"] = state.get("cascade_stage",simulator.cascade_stage)
	context["diesel_ready"] = state.get("diesel_ready",simulator.diesel_warmup>=2 or (simulator.failure_feedback_active and simulator.diesel_kw>0))
	context["pump_running"] = state.get("pump_running",simulator.pump_response>0)
	context["backup_pump_running"] = state.get("backup_pump_running",false)
	context["tank_level"] = state.get("tank_level",simulator.tank_level)
	if not context.has("visual_phase"):
		context["visual_phase"] = ("uji" if not simulator.certification_done and not simulator.failure_feedback_active else "simulasi") if simulator.is_running else "latihan"
	world.update_mission_outputs(context)
	_update_output_status()

func _update_output_status() -> void:
	if output_picker==null or output_picker.selected<0: return
	var output: String = _active_level()["outputs"][output_picker.selected]
	var state: Dictionary = world.mission_map.visual_state(output)
	if state.is_empty(): return
	var phase_label: String = {"latihan":"LATIHAN","uji":"UJI SINYAL","simulasi":"SIMULASI"}.get(state["phase"],"SIMULASI")
	output_status_label.text = "%s | Perintah %d | %s" % [phase_label,int(state["command"]),state["status"]]
	output_status_label.tooltip_text = state["reason"]
	output_picker.tooltip_text = output+"\n"+preload("res://scripts/mission_education.gd").output_description(output)+"\n"+state["reason"]

func _focus_mission_output(output: String) -> void:
	if not is_instance_valid(world.mission_map): return
	var marker: Dictionary = world.mission_map.marker_for(output)
	if marker.is_empty(): return
	world.mission_map.selected_output = output
	var index: int = _active_level()["outputs"].find(output)
	if index>=0 and output_picker!=null: output_picker.select(index)
	world.cam_target_zoom = 1.05
	world.cam.zoom = Vector2.ONE*world.cam_target_zoom
	# Put the facility above the two bottom HUD windows, not behind their center.
	world.cam_target_pos = marker["at"]+Vector2(0,get_viewport().get_visible_rect().size.y*0.22/world.cam_target_zoom)
	world.zoom_changed.emit(world.cam_target_zoom)
	_update_output_status()

func _active_level() -> Dictionary:
	return intro_level if is_intro_tutorial else levels[current_level_idx]

func _on_menu_start() -> void:
	if not bool(progress_store.data["tutorial"].get("intro_completed",false)) and not bool(progress_store.data["tutorial"].get("intro_skipped",false)):
		_start_intro_tutorial()
	else:
		_show_screen(GameScreen.LEVEL_SELECT)

func _start_intro_tutorial() -> void:
	simulator.stop_simulation()
	diesel_tree = {}
	shed_tree = {}
	workbench.level_dict = {}
	_enter_level_briefing(0,true)
	_start_playing_current_level()

func _skip_intro_tutorial() -> void:
	progress_store.data["tutorial"]["intro_skipped"] = true
	progress_store.save_progress()
	simulator.stop_simulation()
	is_intro_tutorial = false
	if is_instance_valid(tutorial_guide): tutorial_guide.queue_free()
	tutorial_guide = null
	_show_screen(GameScreen.LEVEL_SELECT)

func _finish_intro_and_start_mission() -> void:
	_enter_level_briefing(0)

func _bind_menu_click(node: Node) -> void:
	if not node is BaseButton or hud_root==null or not hud_root.is_ancestor_of(node): return
	node.button_down.connect(func():
		if node.name!="ExitButton" and current_screen in [GameScreen.TITLE,GameScreen.RULES,GameScreen.LEVEL_SELECT,GameScreen.CREDITS]: audio.play_click()
	)

func _request_exit() -> void:
	audio.play_click()
	await get_tree().create_timer(0.16).timeout
	get_tree().quit()

func _sync_audio_screen() -> void:
	if audio==null: return
	audio.set_scope("menu" if current_screen in [GameScreen.TITLE,GameScreen.RULES,GameScreen.LEVEL_SELECT,GameScreen.CREDITS] else "stage")
	audio.set_ducked(current_screen in [GameScreen.BRIEFING,GameScreen.RESULT] or is_paused)

func _set_audio_setting(key: String, value: float) -> void:
	progress_store.data["settings"][key] = clampf(value,0,1)
	audio.set_volume(key,value)
	audio_save_delay = 0.3

func _set_stage_ost(id: String) -> void:
	audio.set_stage_ost(id)
	progress_store.data["settings"]["stage_ost"] = audio.preference
	progress_store.save_progress()

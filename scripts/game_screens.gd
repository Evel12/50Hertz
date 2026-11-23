extends RefCounted
## Screens composed from the player's menu, pause and button exports.
const UI := preload("res://scripts/game_ui_skin.gd")
const TitleMenu := preload("res://scripts/title_menu.gd")
const HudFxScript := preload("res://scripts/hud_fx.gd")

static func modal(game: Node, heading: String, subtitle: String, extent: Vector2, opacity: float = 0.58) -> Dictionary:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.z_index = 20
	game.hud_root.add_child(screen)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.07, 0.075, opacity)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = extent
	frame.add_theme_stylebox_override("panel", UI.panel(false, 18))
	center.add_child(frame)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	frame.add_child(stack)
	stack.add_child(UI.label(heading, 17, UI.HUD.INK))
	if not subtitle.is_empty():
		stack.add_child(UI.label(subtitle, 8, UI.HUD.MUTED))
	var board := PanelContainer.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_stylebox_override("panel", UI.panel(true, 20))
	stack.add_child(board)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	board.add_child(body)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	stack.add_child(footer)
	return {"screen": screen, "body": body, "footer": footer, "frame": frame}

static func title(game: Node) -> void:
	var screen := TitleMenu.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start_requested.connect(game._on_menu_start)
	screen.rules_requested.connect(func(): game._show_screen(game.GameScreen.RULES))
	screen.credits_requested.connect(func(): game._show_screen(game.GameScreen.CREDITS))
	screen.exit_requested.connect(game._request_exit)
	screen.z_index = 20
	game.hud_root.add_child(screen)
	game.title_screen = screen

static func rules(game: Node) -> void:
	var view := modal(game,"SETTINGS","TAMPILAN, AUDIO, DAN MUSIK DALAM STAGE.",Vector2(1040,600))
	game.rules_screen = view.screen
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",28)
	view.body.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 390
	left.add_theme_constant_override("separation",14)
	columns.add_child(left)
	left.add_child(UI.label("TAMPILAN",12,UI.GOLD))
	var fullscreen := CheckButton.new()
	fullscreen.name = "FullscreenToggle"
	fullscreen.text = "Fullscreen [F11]"
	fullscreen.add_theme_font_size_override("font_size",10)
	fullscreen.button_pressed = bool(game.progress_store.data["settings"].get("fullscreen",false))
	fullscreen.toggled.connect(game._set_fullscreen)
	left.add_child(fullscreen)
	left.add_child(UI.label("F11: fullscreen | ESC: jeda\nTarik judul panel untuk memindahkan. Gunakan Tab untuk membuka atau menutup rangkaian.",8,UI.PAPER,true))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 490
	right.add_theme_constant_override("separation",9)
	columns.add_child(right)
	right.add_child(UI.label("AUDIO",12,UI.GOLD))
	var captions := {"master_volume":"Volume Utama","music_volume":"Volume Musik / OST","ambience_volume":"Volume Ambience","sfx_volume":"Volume SFX"}
	for key in captions:
		var row := HBoxContainer.new()
		right.add_child(row)
		var caption := UI.label(captions[key],8,UI.PAPER)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var percent := UI.label("",8,UI.GOLD)
		row.add_child(percent)
		var slider := HSlider.new()
		slider.name = "Volume_"+key
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(460,18)
		slider.value = float(game.progress_store.data["settings"].get(key,game.audio.DEFAULTS[key]))*100
		percent.text = "%d%%" % int(slider.value)
		slider.value_changed.connect(func(value):
			percent.text = "%d%%" % int(value)
			game._set_audio_setting(key,value/100.0)
		)
		right.add_child(slider)
	right.add_child(UI.label("OST DALAM STAGE",9,UI.GOLD))
	var ost := OptionButton.new()
	ost.name = "StageOSTPicker"
	ost.custom_minimum_size = Vector2(460,34)
	UI.HUD.button(ost)
	ost.add_theme_font_size_override("font_size",9)
	ost.add_item("Shuffle — semua lagu")
	ost.set_item_metadata(0,"shuffle")
	for id in game.audio.TRACKS:
		ost.add_item(game.audio.TRACKS[id]["name"])
		ost.set_item_metadata(ost.item_count-1,id)
		if game.audio.preference==id: ost.select(ost.item_count-1)
	ost.item_selected.connect(func(index): game._set_stage_ost(ost.get_item_metadata(index)))
	right.add_child(ost)
	right.add_child(UI.label("Pilihan memulai lagu tersebut, lalu lagu lain bergiliran. Menu tetap memakai Games Worldbeat.",7,UI.PAPER,true))
	view.footer.add_child(UI.button("KEMBALI",func(): game._show_screen(game.GameScreen.TITLE),true))

static func credits(game: Node) -> void:
	var view := modal(game,"CREDITS","50 HERTZ — DESA SUKAMAJU",Vector2(1000,550))
	game.credits_screen = view.screen
	var text := UI.rich_text()
	text.custom_minimum_size.y = 325
	text.name = "CreditsText"
	text.selection_enabled = true
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = FileAccess.get_file_as_string("res://data/credits.txt")
	view.body.add_child(text)
	view.footer.add_child(UI.button("KEMBALI",func(): game._show_screen(game.GameScreen.TITLE),true))

static func level_select(game: Node) -> void:
	var view := modal(game, "PILIH MISI GARDU", "DESA SUKAMAJU  /  20 MISI LOGIKA DAN KELISTRIKAN", Vector2(1060, 580))
	game.level_select_screen = view.screen
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 390)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	view.body.add_child(scroll)
	game.level_completion_labels.clear()
	for i in range(game.levels.size()):
		var level: Dictionary = game.levels[i]
		var index := i
		var button := UI.button("", func(): game._enter_level_briefing(index))
		button.name = "Mission%d" % (i + 1)
		button.custom_minimum_size = Vector2(486, 170)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
		game.level_buttons.append(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 18)
		button.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		margin.add_child(box)
		var tag := HBoxContainer.new()
		box.add_child(tag)
		var title := UI.label("%02d  /  %s" % [i + 1, level.concept_tag], 9, UI.HUD.TEAL)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag.add_child(title)
		var status := UI.label("BELUM SELESAI", 7, UI.HUD.WARNING)
		tag.add_child(status)
		game.level_completion_labels.append(status)
		box.add_child(UI.label(level.short_title, 13, UI.HUD.INK))
		box.add_child(UI.label(level.mission_summary, 8, UI.HUD.INK, true))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(spacer)
		var detail := HBoxContainer.new()
		box.add_child(detail)
		_ignore_mouse(margin)
	view.footer.add_child(UI.button("TUTORIAL PEMULA",game._start_intro_tutorial,false,220))
	view.footer.add_child(UI.button("BUKU PANDUAN",func(): game._show_handbook(),false,190))
	view.footer.add_child(UI.button("MENU UTAMA", func(): game._show_screen(game.GameScreen.TITLE), false, 190))

static func briefing(game: Node) -> void:
	var view := modal(game, "LAPORAN DARI DESA", "PAHAMI MISINYA, LALU SUSUN RANGKAIANMU.", Vector2(1110, 540), 0.38)
	game.briefing_screen = view.screen
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.body.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 555
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	var speaker := HBoxContainer.new()
	speaker.add_theme_constant_override("separation", 14)
	left.add_child(speaker)
	game.brief_portrait = TextureRect.new()
	game.brief_portrait.custom_minimum_size = Vector2(48, 48)
	game.brief_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	game.brief_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	speaker.add_child(game.brief_portrait)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 10)
	speaker.add_child(names)
	game.brief_speaker_label = UI.label("", 10, UI.MINT, true)
	game.brief_role_label = UI.label("", 8, UI.PAPER, true)
	names.add_child(game.brief_speaker_label)
	names.add_child(game.brief_role_label)
	game.brief_story_label = UI.rich_text()
	game.brief_story_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(game.brief_story_label)
	game.brief_mission_label = UI.label("", 9, UI.GOLD, true)
	left.add_child(game.brief_mission_label)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	var symbol_row := HBoxContainer.new()
	right.add_child(symbol_row)
	game.brief_gate_preview = HudFxScript.new()
	game.brief_gate_preview.mode = "GATE_PREVIEW"
	game.brief_gate_preview.custom_minimum_size = Vector2(92, 64)
	symbol_row.add_child(game.brief_gate_preview)
	game.brief_concept_title = UI.label("", 11, UI.GOLD, true)
	game.brief_concept_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	symbol_row.add_child(game.brief_concept_title)
	game.brief_concept_desc = UI.label("", 9, UI.PAPER, true)
	right.add_child(game.brief_concept_desc)
	game.brief_tt_box = VBoxContainer.new()
	var io_scroll := ScrollContainer.new()
	io_scroll.name = "BriefingIO"
	io_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	io_scroll.custom_minimum_size.y = 190
	io_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.brief_tt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_scroll.add_child(game.brief_tt_box)
	right.add_child(io_scroll)
	view.footer.add_child(UI.button("PILIH LEVEL", func(): game._show_screen(game.GameScreen.LEVEL_SELECT), false, 175))
	view.footer.add_child(UI.button("MULAI MERANCANG", func(): game._start_playing_current_level(), true, 240))

static func result(game: Node) -> void:
	var view := modal(game, "LAPORAN OPERASI", "DESA SUKAMAJU  /  HASIL SIMULASI", Vector2(1030, 500))
	game.result_screen = view.screen
	game.res_badge_label = UI.label("", 8, UI.PAPER)
	game.res_title_label = UI.label("", 20, UI.MINT)
	game.res_status_label = UI.label("", 10, UI.GOLD, true)
	view.body.add_child(game.res_badge_label)
	view.body.add_child(game.res_title_label)
	view.body.add_child(game.res_status_label)
	game.res_metrics_hbox = HBoxContainer.new()
	game.res_metrics_hbox.add_theme_constant_override("separation", 14)
	view.body.add_child(game.res_metrics_hbox)
	game.res_explain_title = UI.label("", 10, UI.GOLD)
	view.body.add_child(game.res_explain_title)
	game.res_explain_body = UI.rich_text()
	game.res_explain_body.custom_minimum_size.y = 115
	game.res_explain_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.body.add_child(game.res_explain_body)
	game.res_menu_btn = UI.button("PILIH LEVEL", func(): game._show_screen(game.GameScreen.LEVEL_SELECT))
	game.res_retry_btn = UI.button("PERBAIKI RANGKAIAN", func(): game._retry_current_level(), false, 250)
	game.res_next_btn = UI.button("LEVEL BERIKUTNYA", func():
		if game.is_intro_tutorial:
			game._finish_intro_and_start_mission()
		elif game.current_level_idx < game.levels.size() - 1:
			game._enter_level_briefing(game.current_level_idx + 1)
		else:
			game._show_screen(game.GameScreen.LEVEL_SELECT), true, 250)
	view.footer.add_child(game.res_menu_btn)
	view.footer.add_child(game.res_retry_btn)
	view.footer.add_child(game.res_next_btn)

static func pause(game: Node) -> void:
	var view := modal(game, "JEDA SEBENTAR", "DESA MENUNGGU KAMU KEMBALI.", Vector2(480, 574), 0.45)
	game.pause_screen = view.screen
	game.pause_screen.name = "PauseMenu"
	game.pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	game.pause_screen.z_index = 40
	view.body.alignment = BoxContainer.ALIGNMENT_CENTER
	view.body.add_child(UI.label("OPERASI DIJEDA", 12, UI.GOLD))
	view.body.add_child(UI.label("Waktu, frekuensi, dan rangkaian disimpan selama jeda.", 8, UI.PAPER, true))
	var buttons := [
		UI.button("LANJUTKAN", func(): game._set_paused(false), true),
		UI.button("ULANGI LEVEL", func(): game._restart_current_level()),
		UI.button("PILIH LEVEL", func(): game._leave_playing(game.GameScreen.LEVEL_SELECT)),
		UI.button("BUKU PANDUAN", func(): game._show_handbook()),
		UI.button("MENU UTAMA", func(): game._leave_playing(game.GameScreen.TITLE))]
	for i in range(buttons.size()):
		buttons[i].name = ["ResumeButton", "RestartButton", "LevelsButton", "HandbookButton", "TitleButton"][i]
		view.body.add_child(buttons[i])
	view.footer.add_child(UI.label("ESC  KEMBALI KE PERMAINAN", 8, UI.HUD.MUTED))
	game.pause_screen.hide()

static func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_mouse(child)

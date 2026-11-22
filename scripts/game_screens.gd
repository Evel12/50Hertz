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
	screen.start_requested.connect(func(): game._show_screen(game.GameScreen.LEVEL_SELECT))
	screen.rules_requested.connect(func(): game._show_screen(game.GameScreen.RULES))
	screen.exit_requested.connect(func(): game.get_tree().quit())
	screen.z_index = 20
	game.hud_root.add_child(screen)
	game.title_screen = screen

static func rules(game: Node) -> void:
	var view := modal(game, "CARA BERMAIN", "BELAJAR LOGIKA, JAGA LISTRIK DESA.", Vector2(1040, 450))
	game.rules_screen = view.screen
	var body: VBoxContainer = view.body
	body.add_child(UI.label("Tujuanmu: jaga frekuensi di 49.50 - 50.50 Hz.", 12, UI.MINT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var rules_data := [
		["01  SUSUN", "Tarik sensor dan gerbang dari tray bawah ke papan rangkaian."],
		["02  HUBUNGKAN", "Tarik pin keluaran ke pin masukan. Susun logika untuk mengendalikan diesel."],
		["03  UJI", "Jalankan simulasi. Pantau frekuensi dan tujuan level, lalu perbaiki rangkaian."]]
	for item in rules_data:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UI.HUD.frame(UI.HUD.PANEL, 16, 16))
		row.add_child(panel)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 16)
		panel.add_child(text)
		text.add_child(UI.label(item[0], 11, UI.HUD.TEAL))
		text.add_child(UI.label(item[1], 9, UI.HUD.INK, true))
	body.add_child(UI.label("Pasokan kurang: frekuensi turun. Pasokan berlebih: frekuensi naik. Jika terlalu lama di luar batas, gardu akan trip dan desa padam.", 9, UI.PAPER, true))
	body.add_child(UI.label("SCROLL  zoom papan    MMB / SPASI + DRAG  geser\nTAB  panel rangkaian    ESC  jeda permainan", 8, UI.GOLD, true))
	view.footer.add_child(UI.button("KEMBALI", func(): game._show_screen(game.GameScreen.TITLE)))
	view.footer.add_child(UI.button("PILIH LEVEL", func(): game._show_screen(game.GameScreen.LEVEL_SELECT), true, 190))

static func level_select(game: Node) -> void:
	var view := modal(game, "PILIH MISI GARDU", "DESA SUKAMAJU  /  EMPAT MISI MENJAGA 50 HERTZ", Vector2(1060, 580))
	game.level_select_screen = view.screen
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	view.body.add_child(grid)
	game.level_card_star_labels.clear()
	for i in range(game.levels.size()):
		var level: Dictionary = game.levels[i]
		var index := i
		var button := UI.button("", func(): game._enter_level_briefing(index))
		button.name = "Mission%d" % (i + 1)
		button.custom_minimum_size = Vector2(486, 170)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
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
		var stars := UI.label("0/3", 8, UI.HUD.WARNING)
		tag.add_child(stars)
		game.level_card_star_labels.append(stars)
		box.add_child(UI.label(level.short_title, 13, UI.HUD.INK))
		box.add_child(UI.label(level.mission_summary, 8, UI.HUD.INK, true))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(spacer)
		var detail := HBoxContainer.new()
		box.add_child(detail)
		var progress := UI.label("TARGET BINTANG", 7, UI.HUD.MUTED)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(progress)
		var target := "%d GERBANG" % int(level.target_gates)
		if bool(level.has_shed_actuator):
			target += " / PADAM <= %d MNT" % int(level.target_shed_minutes)
		else:
			target += " / BIAYA <= %dRB" % int(level.target_cost_rp / 1000)
		detail.add_child(UI.label(target, 7, UI.HUD.TEAL))
		_ignore_mouse(margin)
	view.footer.add_child(UI.label("Pilih kartu untuk membaca laporan warga.", 8, UI.HUD.MUTED))
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
	right.add_child(game.brief_tt_box)
	view.footer.add_child(UI.button("PILIH LEVEL", func(): game._show_screen(game.GameScreen.LEVEL_SELECT), false, 175))
	view.footer.add_child(UI.button("MULAI MERANCANG", func(): game._start_playing_current_level(), true, 240))

static func result(game: Node) -> void:
	var view := modal(game, "LAPORAN OPERASI", "DESA SUKAMAJU  /  HASIL SIMULASI", Vector2(1030, 500))
	game.result_screen = view.screen
	game.res_badge_label = UI.label("", 8, UI.PAPER)
	game.res_title_label = UI.label("", 20, UI.MINT)
	game.res_stars_label = UI.label("", 10, UI.GOLD, true)
	view.body.add_child(game.res_badge_label)
	view.body.add_child(game.res_title_label)
	view.body.add_child(game.res_stars_label)
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
		if game.current_level_idx < game.levels.size() - 1:
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
		UI.button("MENU UTAMA", func(): game._leave_playing(game.GameScreen.TITLE))]
	for i in range(buttons.size()):
		buttons[i].name = ["ResumeButton", "RestartButton", "LevelsButton", "TitleButton"][i]
		view.body.add_child(buttons[i])
	view.footer.add_child(UI.label("ESC  KEMBALI KE PERMAINAN", 8, UI.HUD.MUTED))
	game.pause_screen.hide()

static func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_mouse(child)

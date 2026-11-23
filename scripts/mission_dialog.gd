extends Control
const UI := preload("res://scripts/game_ui_skin.gd")
var game: Node
var heading := "BACA MISI"
var content := ""
var is_hint := false
var mission: Dictionary = {}
var was_paused := false
var title_label: Label
var text_label: RichTextLabel
var previous_button: Button
var next_button: Button
var hint_frame: PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	was_paused = get_tree().paused
	get_tree().paused = true
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01,0.04,0.04,0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var frame := PanelContainer.new()
	hint_frame = frame
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 120
	frame.offset_right = -120
	frame.offset_top = 65
	frame.offset_bottom = -65
	frame.add_theme_stylebox_override("panel",UI.panel(false,22))
	add_child(frame)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",16)
	frame.add_child(stack)
	title_label = UI.label(heading,16,UI.HUD.INK)
	stack.add_child(title_label)
	var board := PanelContainer.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_stylebox_override("panel",UI.panel(true,20))
	stack.add_child(board)
	if mission.is_empty():
		text_label = UI.rich_text()
		text_label.bbcode_enabled = true
		text_label.add_theme_constant_override("line_separation",3)
		text_label.add_theme_constant_override("paragraph_separation",3)
		text_label.text = _hint_markup(content)
		board.add_child(text_label)
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "MissionScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		board.add_child(scroll)
		var sections := VBoxContainer.new()
		sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sections.add_theme_constant_override("separation",16)
		scroll.add_child(sections)
		_card(sections,"KABAR DESA",String(mission["story"]),Color("c3d7d2"))
		text_label = _card(sections,"TUGASMU",_highlight(String(mission.get("mission_instructions",mission["mission_summary"]))),Color("ffe28a"))
		_card(sections,"CARA MENYELESAIKAN","Hubungkan input melalui gerbang ke semua output yang diminta. Coba Simulasi Switch, lalu tekan Jalankan. Menang jika rangkaian dan skenario memenuhi tugas misi.",Color("d5c1ff"))
		var meanings := preload("res://scripts/mission_education.gd")
		var input_text := ""
		for key in mission["available_sensors"]:
			input_text += "[color=#80dfff]"+key+"[/color]\n"+meanings.input_description(key)+"\n\n"
		_card(sections,"INPUT — informasi yang dibaca",input_text.strip_edges(),Color("80dfff"))
		var output_text := ""
		for key in mission["outputs"]:
			output_text += "[color=#a4edb0]"+key+"[/color]\n"+meanings.output_description(key)+"\n\n"
		_card(sections,"OUTPUT — perintah yang harus dibuat",output_text.strip_edges(),Color("a4edb0"))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation",16)
	stack.add_child(footer)
	if is_hint:
		previous_button = UI.button("SEBELUMNYA",func(): game._show_hint_page(game.hint_index-1),false,190)
		next_button = UI.button("BERIKUTNYA",func(): game._show_hint_page(game.hint_index+1),false,190)
		previous_button.name = "PreviousHint"
		next_button.name = "NextHint"
		footer.add_child(previous_button)
		footer.add_child(next_button)
		update_hint_navigation(game.hint_index,game._active_level()["hints"].size())
	footer.add_child(UI.button("TUTUP",close,true))
	if is_hint: call_deferred("_fit_hint_frame")

func set_hint_content(value: String) -> void:
	text_label.text = _hint_markup(value)
	text_label.scroll_to_line(0)
	call_deferred("_fit_hint_frame")

func _hint_markup(value: String) -> String:
	var lines := value.split("\n")
	for i in range(lines.size()):
		if lines[i].begins_with("LANGKAH ") or lines[i]=="LANGKAH MERANGKAI":
			lines[i] = "[color=#80dfff]"+lines[i]+"[/color]"
		elif lines[i].begins_with("ARTI G"):
			lines[i] = "[color=#a4edb0]"+lines[i]+"[/color]"
	return "[color=#ffe28a]"+"\n".join(lines)+"[/color]"

func _fit_hint_frame() -> void:
	if not is_hint or text_label==null: return
	await get_tree().process_frame
	var height := clampf(text_label.get_content_height()+200.0,230.0,get_viewport_rect().size.y-70.0)
	hint_frame.anchor_top = 0.5
	hint_frame.anchor_bottom = 0.5
	hint_frame.offset_top = -height*0.5
	hint_frame.offset_bottom = height*0.5

func close() -> void:
	get_tree().paused = was_paused
	game.reading_modal = null
	queue_free()

func update_hint_navigation(index: int, count: int) -> void:
	if previous_button == null or next_button == null: return
	previous_button.disabled = index<=0
	next_button.disabled = index>=count-1
	if text_label != null: text_label.scroll_to_line(0)

func _card(parent: VBoxContainer, caption: String, value: String, accent: Color) -> RichTextLabel:
	var panel := PanelContainer.new()
	panel.name = "InputBox" if caption.begins_with("INPUT") else "OutputBox" if caption.begins_with("OUTPUT") else "MissionSection"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("103f3c")
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",12)
	panel.add_child(stack)
	stack.add_child(UI.label(caption,10,accent,true))
	var rich := UI.rich_text()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rich.text = value
	stack.add_child(rich)
	return rich

func _highlight(value: String) -> String:
	var tokens: Array = mission["available_sensors"].duplicate()
	for key in mission["outputs"]:
		if not key in tokens: tokens.append(key)
	tokens.sort_custom(func(a,b): return a.length()>b.length())
	var regex := RegEx.new()
	regex.compile("\\b("+"|".join(tokens)+")\\b")
	var result := ""
	var cursor := 0
	for hit in regex.search_all(value):
		var key := hit.get_string()
		result += value.substr(cursor,hit.get_start()-cursor)
		result += "[color="+("#a4edb0" if key in mission["outputs"] else "#80dfff")+"]"+key+"[/color]"
		cursor = hit.get_end()
	return result+value.substr(cursor)

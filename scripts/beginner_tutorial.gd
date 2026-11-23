extends Control
const UI := preload("res://scripts/game_ui_skin.gd")
const STEPS := [
["Selamat datang di gardu!","Tidak perlu tahu gerbang logika dulu. Kita belajar lewat panel aman. Tujuannya: kirim sinyal dari sakelar ke lampu, lalu coba pembalik NOT.","goals","info"],
["Input adalah informasi","Simulasi Switch mengubah nilai input: 0 berarti mati, 1 berarti aktif. Ini latihan, bukan nilai ujian. Coba klik SAKELAR_UJI hidup lalu mati.","switch","switch"],
["Pasang input di papan","Tray bawah berisi komponen untuk misi ini. Klik atau tarik SAKELAR_UJI ke papan hijau. Kotak lampu adalah output yang sudah disiapkan.","sensor_palette","sensor"],
["Sambungkan kabel pertama","Tarik lingkaran di KANAN sakelar menuju lingkaran di KIRI lampu. Kanan mengirim sinyal; kiri menerima sinyal. Ikuti panah bergerak.","wire_direct","direct"],
["Lihat akibatnya","Klik sakelar hidup lalu mati. Kabel dan lampu mengikuti nilai input. Gunakan OUTPUT MISI → LIHAT untuk menemukan lampu di desa.","switch","lamp"],
["Kenali gerbang NOT","Gerbang mengolah informasi. NOT membalik 0 menjadi 1 dan 1 menjadi 0. Klik atau tarik NOT dari tray ke papan, di antara sakelar dan lampu.","not_palette","not"],
["Putus kabel lama","Klik KANAN pada kabel yang langsung menuju lampu untuk memutusnya. Undo (< atau Ctrl+Z) dapat mengembalikan perubahan; redo memakai > / Ctrl+Y.","wire_direct","disconnected"],
["Input masuk ke NOT","Tarik lingkaran kanan sakelar menuju lingkaran kiri NOT. Satu input menerima satu sumber; satu sumber boleh bercabang.","wire_not_in","not_in"],
["NOT mengirim ke lampu","Tarik lingkaran kanan NOT menuju lingkaran kiri lampu. Gerbang memproses sinyal, bukan menghasilkan daya listrik.","wire_not_out","not_out"],
["Buktikan pembaliknya","Hidupkan lalu matikan sakelar. Sekarang lampu harus berlawanan: sakelar 1 → lampu 0, sakelar 0 → lampu 1. Warna kabel membantu menelusuri sinyal.","switch","inverse"],
["Tujuan dan grafik","Tujuan Level menjelaskan syarat menang. Grafik menunjukkan keseimbangan listrik desa. Tutorial ini aman dan tidak memiliki ancaman blackout.","goals","info"],
["Atur kecepatan","1x, 4x, dan 8x mempercepat jalannya simulasi. Hasil logikanya tetap sama. Jalankan uji resmi untuk memeriksa seluruh kondisi, bukan hanya satu posisi sakelar.","speed","info"],
["Papan yang nyaman","Roda mouse: zoom. Klik kiri lalu tarik area kosong untuk menggeser papan. Tombol tengah / Spasi+drag juga bisa. Tombol sudut tray: perbesar. Tarik judul panel untuk memindahkannya.","expand","info"],
["Perbaiki tanpa takut","Pilih komponen lalu Hapus untuk melepasnya beserta kabel terkait. Undo (< / Ctrl+Z) mengembalikan perubahan; redo (> / Ctrl+Y) mengulanginya. Klik kanan kabel memutus satu sambungan saja.","tools","info"],
["Jelajahi desa","Roda mouse di peta mengubah zoom desa. Tombol 0 mengembalikan pandangan. Klik perangkat di desa untuk melihatnya. Esc membuka menu jeda dan pilihan level.","zoom","info"],
["Bantuan selalu tersedia","Tombol ? di sebelah Jalankan menjelaskan tugas serta fungsi input/output. Petunjuk punya halaman maju/mundur. Buku Panduan ada di menu jeda (Esc), di atas Menu Utama. Tab membuka/menutup papan.","help","info"],
["Siap menjalankan uji","Pastikan jalurnya SAKELAR_UJI → NOT → LAMPU_UJI. Klik Jalankan. Setelah uji dan skenario singkat selesai, kamu siap mengerjakan misi desa.","run","run"]]
var game: Node
var step := 0
var phase := 0.0
var card: PanelContainer
var title_label: Label
var description: Label
var status_label: Label
var previous: Button
var next: Button
var seen_on := false
var seen_off_after_on := false
var last_step := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(440,206)
	card.add_theme_stylebox_override("panel",UI.panel(false,14))
	add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",10)
	card.add_child(stack)
	title_label = UI.label("",10,UI.HUD.TEAL,true)
	stack.add_child(title_label)
	description = UI.label("",9,UI.HUD.INK,true)
	description.custom_minimum_size.x = 410
	stack.add_child(description)
	status_label = UI.label("",7,UI.HUD.MUTED,true)
	stack.add_child(status_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	stack.add_child(row)
	previous = UI.button("SEBELUMNYA",func(): _set_step(step-1),false,128)
	next = UI.button("BERIKUTNYA",advance,true,128)
	var skip := UI.button("LEWATI",func(): game._skip_intro_tutorial(),false,112)
	for button in [previous,next,skip]:
		button.add_theme_font_size_override("font_size",7)
		row.add_child(button)
	_set_step(0)

func _set_step(index: int) -> void:
	step = clampi(index,0,STEPS.size()-1)
	seen_on = false
	seen_off_after_on = false
	title_label.text = "%02d / %02d  %s" % [step+1,STEPS.size(),STEPS[step][0]]
	description.text = STEPS[step][1]
	previous.disabled = step==0
	next.text = "JALANKAN UJI" if STEPS[step][3]=="run" else "BERIKUTNYA"
	card.position = Vector2(760,172) if STEPS[step][2] in ["switch","help"] else Vector2(14,76)
	queue_redraw()

func advance() -> void:
	if not condition_met(): return
	if STEPS[step][3]=="run": game._on_run_pressed()
	else: _set_step(step+1)

func _id(kind: String) -> int:
	for id in game.workbench.graph_model.nodes:
		if game.workbench.graph_model.nodes[id]["kind"]==kind: return id
	return 0

func condition_met() -> bool:
	var model = game.workbench.graph_model
	var sensor := _id("SENSOR")
	var gate := _id("NOT")
	var output := _id("OUTPUT")
	var requirement: String = STEPS[step][3]
	match requirement:
		"info": return true
		"switch", "lamp", "inverse": return seen_on and seen_off_after_on
		"sensor": return sensor!=0
		"not": return gate!=0
		"direct": return sensor!=0 and int(model.nodes[output]["inputs"].get(0,0))==sensor
		"disconnected": return not model.nodes[output]["inputs"].has(0)
		"not_in": return sensor!=0 and gate!=0 and int(model.nodes[gate]["inputs"].get(0,0))==sensor
		"not_out", "run": return gate!=0 and int(model.nodes[output]["inputs"].get(0,0))==gate and model.is_complete(output)
	return false

func _process(delta: float) -> void:
	visible = game.is_intro_tutorial and game.current_screen==game.GameScreen.PLAYING and not game.is_paused and not is_instance_valid(game.handbook) and not is_instance_valid(game.reading_modal) and not game.simulator.is_running
	if not visible: return
	phase += delta
	var active := bool(game.simulator.sensors_state.get("SAKELAR_UJI",false))
	if active: seen_on = true
	elif seen_on: seen_off_after_on = true
	next.disabled = not condition_met()
	status_label.text = "Siap. Klik Berikutnya." if condition_met() else "Coba langkah yang disorot; tombol Berikutnya terbuka setelah berhasil."
	queue_redraw()

func _palette(kind: String) -> Control:
	for item in game.workbench.palette.get_children():
		if item.component_data["kind"]==kind: return item
	return null

func _switch() -> Control:
	return game.manual_panel.find_children("*","CheckButton",true,false)[0] if not game.manual_panel.find_children("*","CheckButton",true,false).is_empty() else null

func _pin(id: int, output: bool) -> Vector2:
	if id==0 or not game.workbench.graph_nodes.has(id): return Vector2.ZERO
	var view = game.workbench.graph_nodes[id]
	return view.get_global_transform()*(view.get_output_port_position(0) if output else view.get_input_port_position(0))

func _draw() -> void:
	if not is_instance_valid(game) or game.workbench==null: return
	var target: String = STEPS[step][2]
	var control: Control
	match target:
		"goals": control = game.oscilloscope
		"switch": control = _switch()
		"sensor_palette": control = _palette("SENSOR")
		"not_palette": control = _palette("NOT")
		"run": control = game.hud_run_btn
		"speed": control = game.hud_speed_buttons[0]
		"expand": control = game.workbench.expand_button
		"tools": control = game.workbench.delete_button
		"zoom": control = game.hud_run_btn
		"help": control = game.playing_hud.find_child("HelpButton",true,false)
	if control!=null:
		var rect := control.get_global_rect().grow(5)
		draw_rect(rect,Color(1,0.85,0.25,0.75+0.2*sin(phase*4)),false,3)
		if target in ["sensor_palette","not_palette"]:
			_arrow(rect.get_center(),game.workbench.graph_view.global_position+Vector2(150,100))
	if target.begins_with("wire"):
		var sensor := _id("SENSOR")
		var gate := _id("NOT")
		var output := _id("OUTPUT")
		var a := _pin(gate,true) if target=="wire_not_out" else _pin(sensor,true)
		var b := _pin(gate,false) if target=="wire_not_in" else _pin(output,false)
		if a!=Vector2.ZERO and b!=Vector2.ZERO:
			if STEPS[step][3]=="disconnected":
				var canvas = game.workbench.graph_view
				var points: PackedVector2Array = canvas.get_connection_line(a-canvas.global_position,b-canvas.global_position)
				for i in range(1,points.size()): draw_dashed_line(points[i-1]+canvas.global_position,points[i]+canvas.global_position,Color("ffcd64"),3,7)
				var at: Vector2 = points[points.size()/2]+canvas.global_position
				draw_circle(at,12,Color(1,0.5,0.3,0.45))
			else: _arrow(a,b)

func _arrow(a: Vector2,b: Vector2) -> void:
	draw_dashed_line(a,b,Color("ffe28a"),3,8)
	var t := fmod(phase*0.55,1.0)
	var at := a.lerp(b,t)
	draw_circle(a,11,Color(1,0.9,0.3,0.45))
	draw_circle(b,11,Color(1,0.9,0.3,0.45))
	draw_colored_polygon(PackedVector2Array([at,at+Vector2(3,16),at+Vector2(8,9),at+Vector2(15,7)]),Color("fff1b9"))

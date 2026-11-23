extends Control
const UI := preload("res://scripts/game_ui_skin.gd")
const LT := preload("res://scripts/logic_tree.gd")
const CircuitArt := preload("res://scripts/circuit_ui_skin.gd")
const INFO := {
"WIRE":["Kabel meneruskan sinyal 0/1; bukan aliran daya pembangkit.","Sakelar uji → lampu uji.","Satu input satu sumber. Satu sumber boleh bercabang.",0],
"NOT":["Q = NOT A. Membalik 0 menjadi 1 dan 1 menjadi 0.","Lampu halaman menyala ketika bukan siang.","SIANG berasal dari waktu, MENDUNG berasal dari awan.",1],
"OR":["Q = A OR B. Satu atau kedua input aktif menyalakan output.","Malam ATAU mendung meminta cadangan.","Kedua input 1 tetap menghasilkan 1.",2],
"AND":["Q = A AND B. Kedua syarat wajib aktif.","Permintaan pompa DAN izin operasi.","Izin saja bukan permintaan operasi.",3],
"XOR":["Q = A XOR B. Output aktif ketika kedua input BERBEDA.","Bandingkan perintah kontaktor dengan status tersambung.","XOR bukan OR: ketika kedua input 1, hasilnya 0.",4],
"LATCH":["Latch menyimpan satu keadaan Q. S (Set) menyalakan Q; R (Reset) mematikan Q. Q adalah output yang disambungkan ke peralatan. Awal Q=0.","Alarm: pulsa S menyalakan alarm. Setelah S kembali 0, Q tetap 1 sampai R diaktifkan.","S=0, R=0: ingat Q sebelumnya. S=1, R=0: Q=1. R=1: Q=0, termasuk ketika S=1. Reset dominan adalah aturan latch game ini. Sakelar S/R di contoh langsung memperbarui Q.",8],
"NAND":["Q = NOT(A AND B). Output mati hanya ketika kedua input aktif.","NAND(POMPA_UTAMA_SEHAT, POMPA_CADANGAN_SEHAT): setidaknya satu tidak sehat.","Bukan NOT A AND B; bukan berarti keduanya rusak. Lingkaran membalik seluruh hasil. NOT A = NAND(A,A). Gerbang universal.",16],
"NOR":["Q = NOT(A OR B). Output aktif hanya ketika kedua input tidak aktif.","NOR(GANGGUAN_POMPA, MODE_PERAWATAN) adalah izin kondisi, bukan perintah menyalakan.","Bukan NOT A OR B. Lingkaran membalik seluruh hasil. NOT A = NOR(A,A). Gerbang universal.",17],
"SENSOR":["Sensor menyatakan fakta: siang, awan, tangki, gangguan, atau status hasil tindakan.","Perintah diesel berbeda dari DIESEL_SIAP: mesin memerlukan waktu respons.","CADANGAN_CUKUP memperhitungkan beban gudang yang akan dipulihkan; bukan hanya frekuensi setelah beban diputus.",0],
"SAKELAR / TOMBOL":["Sakelar adalah permintaan operator yang bertahan. Tombol START, STOP, RESET_ALARM adalah permintaan sesaat.","Permintaan tetap tunduk pada izin dan proteksi.","Latihan sensor manual tidak memengaruhi penilaian resmi.",0],
"AKTUATOR":["Aktuator menerima perintah: lampu, diesel, pompa, kontaktor, alarm.","Perintah → respons peralatan → status kembali sebagai input.","Pengaman peralatan tetap berlaku. Model kelistrikan merupakan penyederhanaan pendidikan.",0],
"RANGKAIAN / MASALAH":["Tarik output ke input. Gabungkan NOT→OR→AND; cabangkan sinyal ke beberapa gerbang. AND/OR/XOR/NAND/NOR selalu dua input.","MMB atau spasi+drag untuk geser, roda untuk zoom, F untuk fit, Ctrl+Z/Y undo/redo.","Pin merah belum terhubung. Lengkapi semua output. Siklus kombinasi ditolak; gunakan latch untuk memori. Baca kasus gagal, cek nilai input lalu telusuri kabel.",0]}
const GATES := ["WIRE","NOT","OR","AND","XOR","LATCH","NAND","NOR"]
const CAPTIONS := {"SAKELAR / TOMBOL":"SAKELAR & TOMBOL", "RANGKAIAN / MASALAH":"MERANGKAI & CEK"}
var game: Node
var entry := "WIRE"
var was_paused := false
var frame: PanelContainer
var body: VBoxContainer
var text: RichTextLabel
var table: RichTextLabel
var preview: Control
var demo_box: VBoxContainer
var toggles: Array[CheckButton] = []
var a := false
var b := false
var demo: Dictionary = {}
var demo_tick := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	was_paused = get_tree().paused
	get_tree().paused = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0.01,0.04,0.04,0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	frame = PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 64
	frame.offset_right = -64
	frame.offset_top = 40
	frame.offset_bottom = -40
	frame.add_theme_stylebox_override("panel",UI.panel(false,20))
	add_child(frame)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",16)
	frame.add_child(stack)
	stack.add_child(UI.label("BUKU PANDUAN KOMPONEN",16,UI.HUD.INK))
	var board := PanelContainer.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_stylebox_override("panel",UI.panel(true,16))
	stack.add_child(board)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",20)
	board.add_child(columns)
	var nav_scroll := ScrollContainer.new()
	nav_scroll.name = "ComponentNavigation"
	nav_scroll.custom_minimum_size.x = 218
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(nav_scroll)
	var nav := VBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation",8)
	nav_scroll.add_child(nav)
	for kind in INFO:
		var caption: String = CAPTIONS.get(kind,kind)
		if int(game.progress_store.data["unlocked_stage"]) <= int(INFO[kind][3]) and not (game.is_intro_tutorial and kind in ["WIRE","NOT"]): caption += " [KUNCI]"
		var button := UI.button(caption,func(): _select(kind),false,200)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size",8)
		button.tooltip_text = kind
		nav.add_child(button)
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "ComponentContent"
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(content_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	content_scroll.add_child(body)
	text = UI.rich_text()
	text.add_theme_constant_override("line_separation",4)
	text.add_theme_constant_override("paragraph_separation",4)
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	demo_box = VBoxContainer.new()
	demo_box.add_theme_constant_override("separation",12)
	body.add_child(demo_box)
	demo_box.add_child(UI.label("COBA KOMPONEN",10,UI.GOLD))
	preview = Control.new()
	preview.custom_minimum_size = Vector2(180,90)
	preview.draw.connect(func():
		if entry in GATES: CircuitArt.connected_preview(preview,Rect2(8,5,190,80),entry,bool(demo.get("val",false)),false,a,b)
	)
	demo_box.add_child(preview)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",14)
	demo_box.add_child(controls)
	for index in range(2):
		var toggle := CheckButton.new()
		toggle.text = "A" if index==0 else "B"
		toggle.add_theme_font_size_override("font_size",10)
		toggle.toggled.connect(func(on):
			if index==0: a=on
			else: b=on
			_update_demo(true)
		)
		controls.add_child(toggle)
		toggles.append(toggle)
	table = UI.rich_text()
	table.bbcode_enabled = true
	table.fit_content = true
	table.scroll_active = false
	demo_box.add_child(table)
	# Keep the example and truth table side by side, in the same scroll viewport.
	var example_row := HBoxContainer.new()
	example_row.add_theme_constant_override("separation",24)
	demo_box.add_child(example_row)
	var example_controls := VBoxContainer.new()
	example_controls.custom_minimum_size.x = 210
	example_row.add_child(example_controls)
	demo_box.remove_child(preview)
	example_controls.add_child(preview)
	demo_box.remove_child(controls)
	example_controls.add_child(controls)
	demo_box.remove_child(table)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	example_row.add_child(table)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	stack.add_child(footer)
	footer.add_child(UI.button("TUTUP",close,true))
	_select(entry)

func _select(kind: String) -> void:
	if not INFO.has(kind): kind = "WIRE"
	entry = kind
	a = false
	b = false
	for toggle in toggles: toggle.set_pressed_no_signal(false)
	demo = LT.make_binary(kind,LT.make_sensor("A"),LT.make_sensor("B"))
	demo_tick = 0
	var info: Array = INFO[kind]
	var unlocked: bool = int(game.progress_store.data["unlocked_stage"]) > int(info[3]) or (game.is_intro_tutorial and kind in ["WIRE","NOT"])
	text.text = kind+"\n\n"
	if unlocked:
		text.text += str(info[0])+"\n\nPORT: "+("S, R → Q" if kind=="LATCH" else ("A → Q" if kind in ["WIRE","NOT"] else "A, B → Q" if kind in GATES else "Sesuai kondisi / perintah peralatan"))
		text.text += "\n\nCONTOH DI DESA\n"+str(info[1])+"\n\nPERHATIKAN\n"+str(info[2])
	else:
		text.text += "Terkunci. Selesaikan Stage %d untuk membuka komponen ini." % int(info[3])
	demo_box.visible = unlocked and kind in GATES
	toggles[0].text = "S" if kind=="LATCH" else "A"
	toggles[1].text = "R" if kind=="LATCH" else "B"
	toggles[1].visible = kind not in ["WIRE","NOT"]
	_update_demo(false)

func _update_demo(advance: bool) -> void:
	if advance: demo_tick += 1
	var q := LT.evaluate(demo,{"A":a,"B":b,"_tick":demo_tick},advance)
	var rows := "A  B  | Q\n"
	if entry == "LATCH":
		rows = "OUTPUT Q = %d (%s)\n\nS  R | Q berikutnya\n0  0 | Q sebelumnya (ingat)\n1  0 | 1 (nyala / set)\n0  1 | 0 (mati / reset)\n1  1 | 0 (reset dominan)\n\nCoba: hidupkan S, lalu matikan S.\nQ tetap 1. Hidupkan R: Q menjadi 0." % [int(q),"NYALA" if q else "MATI"]
	elif entry in ["NOT","WIRE"]:
		rows = "A | Q\n"
		for av in [false,true]:
			var sample := LT.make_binary(entry,LT.make_sensor("A"),{})
			var line := "%d | %d" % [int(av),int(LT.evaluate(sample,{"A":av},false))]
			rows += ("[color=#ffde54]"+line+"[/color]" if a==av else line)+"\n"
	else:
		for av in [false,true]:
			for bv in [false,true]:
				var sample := LT.make_binary(entry,LT.make_sensor("A"),LT.make_sensor("B"))
				var line := "%d  %d  | %d" % [int(av),int(bv),int(LT.evaluate(sample,{"A":av,"B":bv},false))]
				rows += ("[color=#ffde54]"+line+"[/color]" if a==av and b==bv else line)+"\n"
	table.text = rows
	preview.queue_redraw()

func close() -> void:
	get_tree().paused = was_paused
	game.handbook = null
	queue_free()


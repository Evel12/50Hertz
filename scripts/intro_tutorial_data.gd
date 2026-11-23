extends RefCounted
const LT := preload("res://scripts/logic_tree.gd")
static func build(base: Dictionary) -> Dictionary:
	var level := base.duplicate(true)
	level["id"] = 0
	level["title"] = "Tutorial 0: Kenali Panel Gardu"
	level["short_title"] = "Tutorial Pemula"
	level["concept_tag"] = "LATIHAN TERPANDU"
	level["concept_title"] = "Input, kabel, output, dan NOT"
	level["gate_symbol"] = "NOT"
	level["available_gates"] = ["WIRE","NOT"]
	level["available_sensors"] = ["SAKELAR_UJI"]
	level["outputs"] = ["LAMPU_UJI"]
	level["initial_inputs"] = {"SAKELAR_UJI":false}
	level["initial_diesel_tree"] = {}
	level["initial_shed_tree"] = {}
	level["reference_outputs"] = {"LAMPU_UJI":LT.make_not(LT.make_sensor("SAKELAR_UJI"))}
	level["test_episodes"] = [[{"inputs":{"SAKELAR_UJI":false},"expected":{"LAMPU_UJI":true}}],[{"inputs":{"SAKELAR_UJI":true},"expected":{"LAMPU_UJI":false}}]]
	level["scenario_duration"] = 12
	level["timeline"] = [{"step":2,"description":"Sakelar latihan hidup","inputs":{"SAKELAR_UJI":true}},{"step":6,"description":"Sakelar latihan mati","inputs":{"SAKELAR_UJI":false}},{"step":8,"description":"Sakelar latihan hidup lagi","inputs":{"SAKELAR_UJI":true}}]
	level["unlock_reward"] = []
	level["mission_summary"] = "Kenali panel, hubungkan sakelar ke lampu, lalu pasang NOT agar lampu berlawanan dengan sakelar."
	level["mission_instructions"] = level["mission_summary"]
	level["story"] = "Mas Bayu: Mulai dari nol. Kita mencoba panel latihan yang aman. Ikuti sorotan dan panah untuk mengenali input, output, kabel, serta gerbang pembalik."
	level["hud_objectives"] = [{"title":"Ikuti panduan visual","value":"Sakelar → NOT → lampu"},{"title":"Buktikan dua keadaan","value":"Sakelar 0 lampu 1; sebaliknya"}]
	level["hints"] = ["LAMPU_UJI = NOT(SAKELAR_UJI)","1. Pasang SAKELAR_UJI dan NOT di papan.\n2. Tarik output sakelar ke input NOT.\n3. Tarik output NOT ke LAMPU_UJI.\n4. Sakelar mati harus menyalakan lampu; sakelar hidup harus mematikannya.\n5. Tekan Jalankan."]
	level["hint_fail"] = "Ikuti panduan: sambungkan sakelar ke input NOT, lalu output NOT ke lampu. Gunakan tombol Sebelumnya untuk membaca ulang."
	level["win_explanation"] = "Kabel membawa nilai 0/1 dari input. NOT membaliknya sehingga sakelar 0 menghasilkan lampu 1, dan sakelar 1 menghasilkan lampu 0. Kamu sudah memasang komponen, menyambungkan port, membaca sinyal, dan menjalankan uji."
	return level

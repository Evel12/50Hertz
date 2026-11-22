extends RefCounted
class_name LevelData

const LT := preload("res://scripts/logic_tree.gd")

# Defines all 4 levels of "50 Hertz — Desa Sukamaju" with full feature parity
# to the STEM reference specification (NOT, OR, LATCH, AND+LATCH Load Shedding).

static func get_levels() -> Array[Dictionary]:
	return [
		{
			"id": 1,
			"short_title": "Senja di Sukamaju",
			"title": "Level 1: Senja di Sukamaju",
			"concept_tag": "GERBANG NOT",
			"subtitle": "Konsep Baru: NOT (Inverter)",
			"subtheme_badge": "Sebab Akibat • Keseimbangan",
			"speaker_name": "Pak Kades Darto",
			"speaker_role": "Kepala Desa Sukamaju",
			"speaker_tile": "res://Kenney Asset/kenney_tiny-city/Tiles/tile_0120.png",
			"focus_zone": "plts",
			"story": "\"Nak, PLTS kita cuma jalan kalau ada matahari. Begitu magrib, warga nyalain lampu dan TV — listriknya kurang! Tolong atur supaya diesel nyala otomatis waktu sudah TIDAK siang.\"",
			"mission_summary": "Bertahan 15:00–21:30 tanpa blackout",
			"concept_title": "Gerbang NOT (Pembalik Sinyal)",
			"concept_desc": "Membalik sinyal masukan. Kalau input 1 (SIANG), output 0 (Diesel mati). Kalau input 0 (MALAM), output 1 (Diesel nyala).",
			"gate_symbol": "NOT",
			"truth_table": {
				"headers": ["A (SIANG)", "NOT A"],
				"rows": [
					["1 (Siang)", "0 (Mati)"],
					["0 (Malam)", "1 (Nyala)"]
				]
			},
			"available_sensors": ["SIANG"],
			"available_gates": ["WIRE", "NOT"],
			"has_shed_actuator": false,
			"initial_diesel_tree": LT.make_wire(LT.make_sensor("SIANG")),
			"initial_shed_tree": {},
			"start_min": 15 * 60,
			"end_min": 21 * 60 + 30,
			"max_diesel_starts": 99,
			"max_shed_flickers": 99,
			"target_cost_rp": 790000,
			"target_gates": 1,
			"target_shed_minutes": 0,
			"has_rain": false,
			"has_clouds": false,
			"has_rice_mill": false,
			"hint_fail": "Tarik NOT dari tray bawah ke papan. Hubungkan SIANG ke masukan NOT, lalu keluaran NOT ke DIESEL. Diesel harus menyala ketika sudah tidak siang.",
			"win_explanation": "Pasokan harus selalu sama dengan beban (P_pasokan = P_beban → 50.00 Hz). Saat matahari terbenam, PLTS hilang padahal beban malam naik. Gerbang NOT SIANG berarti \"kalau sudah tidak siang\", sehingga diesel menyala menutup kekurangan tepat waktu."
		},
		{
			"id": 2,
			"short_title": "Awan Lewat",
			"title": "Level 2: Awan Lewat",
			"concept_tag": "GERBANG OR",
			"subtitle": "Konsep Baru: OR (Disjungsi)",
			"subtheme_badge": "Sebab Akibat • Keseimbangan",
			"speaker_name": "Bu Sari",
			"speaker_role": "Pemilik Penggilingan Padi",
			"speaker_tile": "res://Kenney Asset/kenney_tiny-city/Tiles/tile_0108.png",
			"focus_zone": "dusun2",
			"story": "\"Mesin giling saya jalan jam 9 pagi sampai jam 4 sore. Kemarin waktu awan tebal lewat, listrik PLTS drop dan mesin saya mati semua! Diesel harus nyala kalau malam ATAU kalau sedang mendung.\"",
			"mission_summary": "Bertahan 07:00–19:00, penggilingan padi tidak boleh mati",
			"concept_title": "Gerbang OR (ATAU)",
			"concept_desc": "Output bernilai 1 kalau SALAH SATU atau KEDUA inputnya bernilai 1. Gabungkan NOT(SIANG) dan MENDUNG ke gerbang OR.",
			"gate_symbol": "OR",
			"truth_table": {
				"headers": ["A", "B", "A OR B"],
				"rows": [
					["0", "0", "0"],
					["0", "1", "1"],
					["1", "0", "1"],
					["1", "1", "1"]
				]
			},
			"available_sensors": ["SIANG", "MENDUNG"],
			"available_gates": ["WIRE", "NOT", "AND", "OR"],
			"has_shed_actuator": false,
			"initial_diesel_tree": LT.make_not(LT.make_sensor("SIANG")),
			"initial_shed_tree": {},
			"start_min": 7 * 60,
			"end_min": 19 * 60,
			"max_diesel_starts": 99,
			"max_shed_flickers": 99,
			"target_cost_rp": 450000,
			"target_gates": 2,
			"target_shed_minutes": 0,
			"has_rain": false,
			"has_clouds": true,
			"has_rice_mill": true,
			"hint_fail": "Gunakan NOT untuk membalik SIANG. Hubungkan NOT(SIANG) dan MENDUNG ke dua masukan OR, lalu keluaran OR ke DIESEL.",
			"win_explanation": "Energi surya bersifat intermiten: daya PLTS bisa turun 85% dalam beberapa menit saat awan lewat. Persamaan Boole (NOT SIANG) OR MENDUNG memastikan pembangkit cadangan langsung mengambil alih baik saat cuaca mendung siang hari maupun saat malam."
		},
		{
			"id": 3,
			"short_title": "Malam Hujan",
			"title": "Level 3: Malam Hujan",
			"concept_tag": "SR LATCH",
			"subtitle": "Konsep Baru: LATCH (SR Flip-Flop)",
			"subtheme_badge": "Satu Langkah Kecil • Keseimbangan",
			"speaker_name": "Mas Bayu",
			"speaker_role": "Teknisi Gardu Desa",
			"speaker_tile": "res://Kenney Asset/kenney_tiny-factory/Tiles/tile_0120.png",
			"focus_zone": "pltd",
			"story": "\"Hujan seharian, PLTS nol. Mesin diesel kita cuma kuat 3 kali start semalam! Kalau kamu sambung langsung ke sensor F_RENDAH, begitu diesel nyala frekuensi naik sedikit, diesel langsung mati lagi — cetak-cetek terus sampai rusak!\"",
			"mission_summary": "Bertahan 16:00–23:30, maksimal 3× start diesel",
			"concept_title": "LATCH (SR Flip-Flop / Histeresis)",
			"concept_desc": "Gerbang yang punya ingatan 1-bit! S = 1 (SET) mengunci output jadi 1. R = 1 (RESET) mengembalikan ke 0. Saat S = 0 dan R = 0, output tetap seperti sebelumnya.",
			"gate_symbol": "LATCH",
			"truth_table": {
				"headers": ["S (Set)", "R (Reset)", "Q (Output)"],
				"rows": [
					["0", "0", "tetap (ingat)"],
					["1", "0", "1 (kunci nyala)"],
					["0", "1", "0 (reset mati)"]
				]
			},
			"available_sensors": ["F_RENDAH", "F_TINGGI"],
			"available_gates": ["WIRE", "NOT", "AND", "OR", "LATCH"],
			"has_shed_actuator": false,
			"initial_diesel_tree": LT.make_wire(LT.make_sensor("F_RENDAH")),
			"initial_shed_tree": {},
			"start_min": 16 * 60,
			"end_min": 23 * 60 + 30,
			"max_diesel_starts": 3,
			"max_shed_flickers": 99,
			"target_cost_rp": 900000,
			"target_gates": 1,
			"target_shed_minutes": 0,
			"has_rain": true,
			"has_clouds": true,
			"has_rice_mill": false,
			"hint_fail": "Gunakan LATCH agar diesel tidak berkedip mengikuti sensor. Hubungkan F_RENDAH ke pin S, F_TINGGI ke pin R, dan keluaran Q ke DIESEL.",
			"win_explanation": "Ini disebut Histeresis: batas menyalakan (49.8 Hz) dibuat berbeda dari batas mematikan (50.2 Hz) menggunakan memori SR LATCH. Prinsip yang sama dipakai pada termostat AC, kulkas, dan relai proteksi PLN supaya mesin tidak rusak karena on-off setiap detik."
		},
		{
			"id": 4,
			"short_title": "Sahur Pertama",
			"title": "Level 4: Sahur Pertama",
			"concept_tag": "AND + LATCH",
			"subtitle": "Konsep Baru: AND di dalam LATCH (Load Shedding)",
			"subtheme_badge": "Sebab Akibat • Satu Langkah Kecil • Keseimbangan",
			"speaker_name": "Ustadz Hasan",
			"speaker_role": "Takmir Masjid Sukamaju",
			"speaker_tile": "res://Kenney Asset/kenney_tiny-city/Tiles/tile_0121.png",
			"focus_zone": "dusun3",
			"story": "\"Malam pertama Ramadhan! Jam 3 pagi semua warga bangun sahur — rice cooker, lampu, pompa air nyala bersamaan. Bebannya melebihi PLTMH + diesel! Lebih baik Dusun 3 padam sebentar daripada satu desa gelap. Padamkan HANYA kalau frekuensi rendah DAN diesel sudah penuh — lalu nyalakan lagi setelah sahur!\"",
			"mission_summary": "Bertahan 02:00–07:00 • Dusun 3 boleh padam (≤ 130 mnt, maks 3× kedip)",
			"concept_title": "AND di dalam LATCH (Load Shedding)",
			"concept_desc": "Gerbang AND memastikan Dusun 3 hanya dipadamkan jika F_RENDAH = 1 DAN DIESEL_PENUH = 1. LATCH mengunci pemadaman agar tidak berkedip sampai F_TINGGI meresetnya setelah sahur.",
			"gate_symbol": "AND",
			"truth_table": {
				"headers": ["F_RENDAH", "DIESEL_PENUH", "A AND B"],
				"rows": [
					["0", "0", "0"],
					["0", "1", "0"],
					["1", "0", "0"],
					["1", "1", "1 (Set Latch!)"]
				]
			},
			"available_sensors": ["F_RENDAH", "F_TINGGI", "DIESEL_PENUH"],
			"available_gates": ["WIRE", "NOT", "AND", "OR", "LATCH"],
			"has_shed_actuator": true,
			"initial_diesel_tree": LT.make_binary("LATCH", LT.make_sensor("F_RENDAH"), LT.make_sensor("F_TINGGI")),
			"initial_shed_tree": LT.make_wire(LT.make_sensor("NONE")),
			"start_min": 2 * 60,
			"end_min": 7 * 60,
			"max_diesel_starts": 6,
			"max_shed_flickers": 3,
			"target_cost_rp": 650000,
			"target_gates": 3,
			"target_shed_minutes": 130,
			"has_rain": false,
			"has_clouds": false,
			"has_rice_mill": false,
			"hint_fail": "Pada jalur PADAM Dusun 3, gunakan LATCH. Pin S diisi keluaran AND(F_RENDAH, DIESEL_PENUH), pin R diisi F_TINGGI. Hubungkan Q ke PADAM agar relai tidak berkedip dan Dusun 3 menyala kembali setelah sahur.",
			"win_explanation": "Ini disebut Under-Frequency Load Shedding (UFLS) — prosedur nyata yang digunakan PLN! Satu langkah kecil melepas sebagian beban non-kritis (Dusun 3) menyelamatkan seluruh desa, Puskesmas, dan Masjid dari pemadaman total (cascading blackout)."
		}
	]

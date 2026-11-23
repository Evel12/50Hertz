extends RefCounted
## View-only state: never advances equipment, logic memory, timers, or scoring.
const OFF := Color("476261")
const ON := Color("70ed9d")
const WARN := Color("ffcd64")
const FAULT := Color("ff7874")

static func resolve(output: String, context: Dictionary) -> Dictionary:
	var connected := bool(context.get("connected_outputs",{}).get(output,false))
	var command := bool(context.get("outputs",{}).get(output,false))
	var sensors: Dictionary = context.get("sensors",{})
	var phase := String(context.get("visual_phase","latihan"))
	var grid := float(context.get("frequency",50.0))>0.1 and int(context.get("cascade_stage",0))<3
	var result := {"connected":connected,"command":command,"running":false,"cable_active":false,"alert":false,"color":OFF,"status":"BELUM TERHUBUNG","reason":"Lengkapi semua pin menuju output ini.","phase":phase}
	if not connected: return result
	var run := command and grid
	var status := "HIDUP" if run else "MATI"
	var reason := "Peralatan mengikuti perintah rangkaian."
	var warning := false
	match output:
		"PERINTAH_DIESEL":
			var admitted := bool(sensors.get("IZIN_OPERASI",true)) and bool(sensors.get("DIESEL_SEHAT",true))
			var ready := bool(context.get("diesel_ready",false))
			run = command and admitted and ready and grid
			if command and not admitted:
				status = "TERTAHAN"
				reason = "Perintah start ada, tetapi izin / kondisi diesel tidak memenuhi proteksi."
				warning = true
			elif command and not ready:
				status = "START / BELUM SIAP"
				reason = "Perintah sudah aktif. Kabel daya menunggu diesel siap memasok."
				warning = true
			else:
				status = "SIAP MENYUPLAI" if run else "BERHENTI"
				reason = "Diesel sudah siap; kabel menunjukkan sambungan dayanya." if run else "Tidak ada perintah start dari rangkaian."
		"PERINTAH_POMPA", "PERINTAH_POMPA_CADANGAN":
			var admitted := bool(sensors.get("IZIN_OPERASI",true)) and bool(sensors.get("SUMBER_AIR_ADA",true)) and not bool(sensors.get("MODE_PERAWATAN",false))
			if output=="PERINTAH_POMPA": admitted = admitted and not bool(sensors.get("GANGGUAN_POMPA",false))
			var actual := bool(context.get("pump_running" if output=="PERINTAH_POMPA" else "backup_pump_running",false))
			run = command and admitted and grid and (actual or phase in ["latihan","uji"])
			if command and not admitted:
				status = "TERTAHAN PROTEKSI"
				reason = "Periksa izin, sumber air, perawatan, dan gangguan pompa."
				warning = true
			else:
				status = "MENGALIR" if run else ("MENUNGGU RESPONS" if command else "BERHENTI")
				reason = "Motor dan aliran air aktif; tangki berubah hanya pada langkah simulasi." if run else ("Perintah aktif, tetapi operasi belum terkonfirmasi." if command else "Pompa tidak sedang menerima perintah operasi.")
				warning = command and not run
		"PUTUS_GUDANG":
			run = not command and grid and int(context.get("cascade_stage",0))<1
			status = "TERSAMBUNG" if run else "DIPUTUS"
			reason = "Perintah PUTUS=1 membuka kontaktor: kabel dan beban gudang mati." if command else "Perintah PUTUS=0 menutup kontaktor dan menyambungkan gudang."
			warning = command
			if not command and not run:
				status = "TANPA DAYA"
				reason = "Proteksi feeder gudang memutus suplai."
				warning = true
		"SAMBUNG_PENGGILINGAN":
			var admitted := bool(sensors.get("DIESEL_SIAP",false)) and bool(sensors.get("JARINGAN_AMAN",false))
			run = command and admitted and grid and bool(context.get("dusun2_powered",true))
			warning = command and not admitted
			status = "TERTAHAN" if warning else ("BERPUTAR" if run else "TERPUTUS")
			reason = "Kontaktor menunggu diesel siap dan jaringan aman." if warning else "Kontaktor dan roda penggilingan mengikuti kondisi sambungan."
		"ALARM":
			run = command
			status = "ALARM AKTIF" if run else "TENANG"
			reason = "Beacon mengikuti output alarm, termasuk memori latch jika dipasang."
			result["alert"] = run
		"INDIKATOR":
			run = command
			status = "BERBEDA" if run else "SESUAI"
			reason = "Bandingkan lampu kecil perintah dan status; indikator mengikuti output pembanding."
		"Q":
			status = "TERSAMBUNG" if run else "TERBUKA"
			reason = "Q mengendalikan kontaktor uji panel NAND/NOR."
	if command and not grid and output not in ["ALARM","INDIKATOR"]:
		status = "TANPA DAYA"
		reason = "Perintah aktif, tetapi suplai terputus oleh proteksi jaringan."
		warning = true
	result["running"] = run
	result["cable_active"] = run
	result["status"] = status
	result["reason"] = reason
	result["color"] = FAULT if result["alert"] else (WARN if warning else (ON if run else OFF))
	return result

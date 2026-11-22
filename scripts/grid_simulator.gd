extends Node
class_name GridSimulator

const LT := preload("res://scripts/logic_tree.gd")

signal tick_updated(state: Dictionary)
signal world_callout(zone: String, text: String, color: Color)
signal simulation_finished(success: bool, reason: String, stats: Dictionary)

const NOMINAL_FREQ := 50.0
const MIN_SAFE_FREQ := 49.50
const MAX_SAFE_FREQ := 50.50
const F_RENDAH_THRESH := 49.80
const F_TINGGI_THRESH := 50.20

# Base sim speed: 4 game-minutes per real second at 1x (up to 16x = 64 min/sec)
const BASE_MINS_PER_SEC := 4.0

var current_level: Dictionary = {}
var diesel_tree: Dictionary = {}
var shed_tree: Dictionary = {}

var is_running: bool = false
var speed_multiplier: float = 1.0
var sim_accum: float = 0.0

var current_min: int = 900
var start_min: int = 900
var end_min: int = 1290

# Physical grid state
var frequency: float = NOMINAL_FREQ
var sun_factor: float = 1.0
var cloud_cover: float = 0.0
var rain_intensity: float = 0.0
var is_rice_mill_active: bool = false
var is_sahur_surge: bool = false

var pltmh_kw: float = 42.0
var plts_kw: float = 50.0
var diesel_kw: float = 0.0
var diesel_cap_kw: float = 75.0
var diesel_min_kw: float = 22.0
var supply_kw: float = 92.0
var demand_kw: float = 92.0
var d1_kw: float = 30.0
var d2_kw: float = 26.0
var d3_kw: float = 24.0
var puskesmas_kw: float = 12.0

# Actuators & metrics
var diesel_on: bool = false
var prev_diesel_on: bool = false
var shed_d3_on: bool = false
var prev_shed_d3_on: bool = false

var diesel_starts: int = 0
var shed_flickers: int = 0
var shed_minutes: int = 0
var cost_rp: float = 0.0
var co2_kg: float = 0.0
var out_of_bounds_mins: int = 0

var dusun1_powered: bool = true
var dusun2_powered: bool = true
var dusun3_powered: bool = true
var puskesmas_powered: bool = true
var cascade_stage: int = 0

var sensors_state: Dictionary = {}
var freq_history: Array[float] = []
var control_log: Array[String] = []

# Event flags so world callouts fire once per transition
var announced_sunset: bool = false
var announced_cloud: bool = false
var announced_sahur: bool = false
var announced_imsak: bool = false
var announced_mill: bool = false


func setup_level(level_dict: Dictionary, d_tree: Dictionary, s_tree: Dictionary) -> void:
	current_level = level_dict
	diesel_tree = d_tree
	shed_tree = s_tree
	start_min = int(level_dict.get("start_min", 900))
	end_min = int(level_dict.get("end_min", 1290))
	reset_simulation()


func reset_simulation() -> void:
	is_running = false
	sim_accum = 0.0
	current_min = start_min
	frequency = NOMINAL_FREQ
	diesel_on = false
	prev_diesel_on = false
	shed_d3_on = false
	prev_shed_d3_on = false
	diesel_starts = 0
	shed_flickers = 0
	shed_minutes = 0
	cost_rp = 0.0
	co2_kg = 0.0
	out_of_bounds_mins = 0
	dusun1_powered = true
	dusun2_powered = true
	dusun3_powered = true
	puskesmas_powered = true
	cascade_stage = 0
	announced_sunset = false
	announced_cloud = false
	announced_sahur = false
	announced_imsak = false
	announced_mill = false

	LT.reset_memory(diesel_tree)
	if not shed_tree.is_empty():
		LT.reset_memory(shed_tree)

	freq_history.clear()
	for i in range(90):
		freq_history.append(NOMINAL_FREQ)

	control_log.clear()

	if not current_level.is_empty():
		_sample_environment(current_min)
		_update_sensors()
		diesel_on = LT.evaluate(diesel_tree, sensors_state, false)
		shed_d3_on = LT.evaluate(shed_tree, sensors_state, false) if bool(current_level.get("has_shed_actuator", false)) else false
		_compute_power_preview()
		_emit_state()


func start_simulation() -> void:
	reset_simulation()
	is_running = true
	_add_log("Simulasi dimulai")


func stop_simulation() -> void:
	is_running = false


func _process(delta: float) -> void:
	if not is_running or current_level.is_empty():
		return

	sim_accum += delta * BASE_MINS_PER_SEC * speed_multiplier
	var max_steps_per_frame: int = 8
	var steps_done: int = 0
	while sim_accum >= 1.0 and steps_done < max_steps_per_frame and is_running:
		sim_accum -= 1.0
		steps_done += 1
		_step_one_minute()


func _step_one_minute() -> void:
	if current_min >= end_min:
		_finish_simulation(true, "Desa Sukamaju berhasil menjaga kesetimbangan 50.00 Hz sepanjang jadwal operasi!")
		return

	# 1. Sample weather, solar, and village loads for this minute
	_sample_environment(current_min)

	# 2. Update sensors & evaluate recursive logic trees
	_update_sensors()
	diesel_on = LT.evaluate(diesel_tree, sensors_state, true)
	var has_shed: bool = bool(current_level.get("has_shed_actuator", false))
	shed_d3_on = LT.evaluate(shed_tree, sensors_state, true) if has_shed else false

	# 3. Track diesel starts & chattering damage
	if diesel_on and not prev_diesel_on:
		diesel_starts += 1
		_add_log("DIESEL ON — start #%d" % diesel_starts)
		world_callout.emit("pltd", "⚡ DIESEL START #%d" % diesel_starts, Color(1.0, 0.85, 0.30))
		var max_starts: int = int(current_level.get("max_diesel_starts", 99))
		if diesel_starts > max_starts:
			_add_log("MESIN DIESEL RUSAK (terlalu sering start!)")
			dusun1_powered = false
			dusun2_powered = false
			dusun3_powered = false
			puskesmas_powered = false
			cascade_stage = 3
			frequency = 0.0
			world_callout.emit("pltd", "🔥 KONTAKTOR JEBOL!", Color(1.0, 0.25, 0.25))
			_emit_state()
			_finish_simulation(false, "Mesin diesel rusak karena terlalu sering nyala-mati (chattering — %d× start, batas maks %d×)!" % [diesel_starts, max_starts])
			return
	elif not diesel_on and prev_diesel_on:
		_add_log("DIESEL OFF")
	prev_diesel_on = diesel_on

	# 4. Track Dusun 3 Load Shedding flickers & duration
	if has_shed:
		if shed_d3_on and not prev_shed_d3_on:
			shed_flickers += 1
			_add_log("DUSUN 3 DIPADAMKAN (lepas beban #%d)" % shed_flickers)
			world_callout.emit("dusun3", "⚠ LEPAS BEBAN #%d" % shed_flickers, Color(1.0, 0.72, 0.22))
			var max_flick: int = int(current_level.get("max_shed_flickers", 99))
			if shed_flickers > max_flick:
				_add_log("GARDU DUSUN 3 RUSAK (kedip > %d×)" % max_flick)
				dusun1_powered = false
				dusun2_powered = false
				dusun3_powered = false
				puskesmas_powered = false
				cascade_stage = 3
				frequency = 0.0
				world_callout.emit("dusun3", "💥 RELAI FLICKER!", Color(1.0, 0.25, 0.25))
				_emit_state()
				_finish_simulation(false, "Relai Dusun 3 terlalu sering berkedip on-off (%d× kedip, batas maks %d×)! Kunci pemadaman menggunakan LATCH." % [shed_flickers, max_flick])
				return
		elif not shed_d3_on and prev_shed_d3_on:
			_add_log("DUSUN 3 MENYALA KEMBALI")
			world_callout.emit("dusun3", "💡 DUSUN 3 PULIH!", Color(0.30, 1.0, 0.62))
		prev_shed_d3_on = shed_d3_on
		if shed_d3_on:
			shed_minutes += 1

	# 5. Compute demand & supply with realistic PLTS curtailment + diesel governor droop
	var active_d3: float = 0.0 if shed_d3_on else d3_kw
	demand_kw = d1_kw + d2_kw + active_d3 + puskesmas_kw

	# Grid-tied PLTS inverter automatically curtails surplus solar above (demand - pltmh)
	var effective_plts: float = minf(plts_kw, maxf(0.0, demand_kw - pltmh_kw))
	plts_kw = effective_plts

	var base_supply: float = pltmh_kw + plts_kw
	if diesel_on:
		var deficit: float = maxf(0.0, demand_kw - base_supply)
		# Governor aims to meet deficit (+ slight headroom so freq recovers above 49.80 Hz smoothly),
		# bounded by minimum idle output (diesel_min_kw) and maximum engine capacity (diesel_cap_kw)
		var target_diesel: float = deficit
		if frequency < 49.96:
			target_diesel += 6.0
		diesel_kw = clampf(target_diesel, diesel_min_kw, diesel_cap_kw)
		# Fuel cost & CO2 per minute of diesel operation
		var kwh_step: float = diesel_kw / 60.0
		cost_rp += kwh_step * 2650.0 # ~Rp 2.650 / kWh diesel solar
		co2_kg += kwh_step * 0.62
	else:
		diesel_kw = 0.0

	supply_kw = base_supply + diesel_kw

	# 6. Frequency response physics
	var power_balance: float = supply_kw - demand_kw
	var k_inertia: float = 0.0022

	if absf(power_balance) <= 3.5:
		# Primary governor gently pulls frequency back toward 50.00 Hz when balanced
		frequency = move_toward(frequency, NOMINAL_FREQ, 0.018) + power_balance * 0.0005
	else:
		frequency += power_balance * k_inertia

	frequency = clampf(frequency, 48.60, 51.40)

	# Record rolling history (keep ~90 points across window)
	if (current_min - start_min) % 2 == 0:
		freq_history.append(frequency)
		if freq_history.size() > 90:
			freq_history.pop_front()

	# 7. Check safe frequency limits (49.50 - 50.50 Hz) & Cascading Blackout
	if frequency < MIN_SAFE_FREQ or frequency > MAX_SAFE_FREQ:
		out_of_bounds_mins += 1
		if out_of_bounds_mins >= 2:
			cascade_stage = 1
		if out_of_bounds_mins >= 5:
			cascade_stage = 2
		if out_of_bounds_mins >= 8 or frequency <= 49.15 or frequency >= 50.85:
			cascade_stage = 3

		dusun3_powered = (not shed_d3_on) and (cascade_stage < 1)
		dusun2_powered = (cascade_stage < 2)
		dusun1_powered = (cascade_stage < 3)
		puskesmas_powered = (cascade_stage < 3)

		if cascade_stage >= 3:
			var kind_str: String = "TERLALU RENDAH (pasokan kurang dari beban)" if frequency < MIN_SAFE_FREQ else "TERLALU TINGGI (kelebihan pasokan daya)"
			_add_log("BLACKOUT — %.2f Hz!" % frequency)
			world_callout.emit("gardu", "⚡ BLACKOUT!", Color(1.0, 0.22, 0.22))
			frequency = 0.0
			_emit_state()
			_finish_simulation(false, "Frekuensi %s pada pukul %s sehingga proteksi gardu memutus seluruh listrik desa!" % [kind_str, format_time(current_min)])
			return
	else:
		out_of_bounds_mins = 0
		cascade_stage = 0
		dusun3_powered = not shed_d3_on
		dusun2_powered = true
		dusun1_powered = true
		puskesmas_powered = true

	# 8. Advance minute & emit UI state
	current_min += 1
	_emit_state()

	if current_min >= end_min:
		_finish_simulation(true, "Desa Sukamaju tetap terang & stabil 50.00 Hz sampai pukul %s!" % format_time(end_min))


func _sample_environment(minute: int) -> void:
	var lvl_id: int = int(current_level.get("id", 1))
	var hr: float = float(minute) / 60.0

	# Natural daylight curve (sun rises 05:30..07:00, sets sharply around Magrib 17:15..17:50)
	if hr < 5.5 or hr >= 17.85:
		sun_factor = 0.0
	elif hr < 6.8:
		sun_factor = clampf((hr - 5.5) / 1.3, 0.0, 1.0)
	elif hr <= 17.25:
		sun_factor = 1.0
	else:
		sun_factor = clampf((17.85 - hr) / 0.60, 0.0, 1.0)

	cloud_cover = 0.0
	rain_intensity = 0.0
	is_rice_mill_active = false
	is_sahur_surge = false

	match lvl_id:
		1:
			# Level 1: Senja di Sukamaju (15:00 - 21:30)
			pltmh_kw = 42.0
			diesel_cap_kw = 75.0
			diesel_min_kw = 24.0
			plts_kw = 60.0 * clampf(sun_factor * 1.45, 0.0, 1.0)
			# Evening peak rises smoothly after 17:30
			var eve_ramp: float = clampf((hr - 17.35) / 1.0, 0.0, 1.0)
			d1_kw = 30.0 + 12.0 * eve_ramp
			d2_kw = 26.0 + 8.0 * eve_ramp
			d3_kw = 24.0 + 5.0 * eve_ramp
			puskesmas_kw = 12.0
			if not announced_sunset and sun_factor < 0.28 and is_running:
				announced_sunset = true
				_add_log("Matahari terbenam — PLTS padam")
				world_callout.emit("plts", "🌇 MAGRIB! PLTS 0 kW", Color(1.0, 0.65, 0.28))

		2:
			# Level 2: Awan Lewat (07:00 - 19:00)
			pltmh_kw = 45.0
			diesel_cap_kw = 80.0
			diesel_min_kw = 22.0
			# Two cloud windows: 10:15-11:15 and 14:30-15:05
			if (hr >= 10.25 and hr <= 11.25) or (hr >= 14.50 and hr <= 15.08):
				cloud_cover = 0.90
				if not announced_cloud and is_running:
					announced_cloud = true
					_add_log("Awan tebal lewat — PLTS drop 85%!")
					world_callout.emit("plts", "☁️ AWAN TEBAL! PLTS DROP", Color(0.65, 0.82, 1.0))
			else:
				cloud_cover = 0.10
				if hr > 11.5 and hr < 14.0:
					announced_cloud = false

			plts_kw = 65.0 * clampf(sun_factor * 1.45, 0.0, 1.0) * (1.0 - cloud_cover * 0.85)
			is_rice_mill_active = (hr >= 9.0 and hr <= 16.0)
			if is_rice_mill_active and not announced_mill and is_running:
				announced_mill = true
				_add_log("Penggilingan padi mulai beroperasi (+24 kW)")
				world_callout.emit("dusun2", "🌾 GILINGAN PADI AKTIF!", Color(0.95, 0.85, 0.35))

			var mill_kw: float = 24.0 if is_rice_mill_active else 0.0
			var eve_boost: float = 18.0 if hr >= 17.5 else 0.0
			d1_kw = 26.0 + eve_boost * 0.5
			d2_kw = 18.0 + mill_kw + eve_boost * 0.25
			d3_kw = 20.0 + eve_boost * 0.25
			puskesmas_kw = 12.0

		3:
			# Level 3: Malam Hujan (16:00 - 23:30)
			pltmh_kw = 45.0
			diesel_cap_kw = 65.0
			diesel_min_kw = 24.0
			cloud_cover = 0.95
			rain_intensity = 1.0
			plts_kw = 0.0 # Hujan seharian, PLTS nol!
			# Load starts ~45 kW at 16:00, surges to ~96 kW during 17:00-22:15, then drops back to ~45 kW after 22:15
			var peak_factor: float = 0.0
			if hr >= 16.8 and hr < 17.3:
				peak_factor = (hr - 16.8) / 0.5
			elif hr >= 17.3 and hr <= 22.1:
				peak_factor = 1.0
			elif hr > 22.1 and hr < 22.35:
				peak_factor = 1.0 - (hr - 22.1) / 0.25
			d1_kw = 14.0 + 20.0 * peak_factor
			d2_kw = 11.0 + 16.0 * peak_factor
			d3_kw = 10.0 + 15.0 * peak_factor
			puskesmas_kw = 10.0

		4:
			# Level 4: Sahur Pertama (02:00 - 07:00)
			pltmh_kw = 45.0
			diesel_cap_kw = 55.0 # PLTMH (45) + Diesel (55) = 100 kW max night capacity
			diesel_min_kw = 24.0
			plts_kw = 48.0 * sun_factor
			is_sahur_surge = (hr >= 2.75 and hr <= 4.30)

			if is_sahur_surge:
				if not announced_sahur and is_running:
					announced_sahur = true
					_add_log("LONJAKAN SAHUR! Beban 128 kW > Kapasitas 100 kW")
					world_callout.emit("masjid", "🌙 SAHUR! BEBAN +45 kW", Color(1.0, 0.82, 0.30))
				d1_kw = 46.0
				d2_kw = 35.0
				d3_kw = 33.0
				puskesmas_kw = 14.0 # Total = 128 kW; without D3 = 95 kW (fits 100 kW!)
			elif hr > 4.30 and hr < 4.75:
				if not announced_imsak and is_running:
					announced_imsak = true
					_add_log("Imsak — beban warga turun")
					world_callout.emit("masjid", "🕌 IMSAK — BEBAN TURUN", Color(0.45, 0.90, 1.0))
				# Right after Sahur, residential load dips so freq rises > 50.20 Hz to reset SHED LATCH!
				d1_kw = 20.0
				d2_kw = 16.0
				d3_kw = 22.0
				puskesmas_kw = 12.0 # Without D3 = 48 kW vs 45+24 = 69 kW -> freq > 50.20 Hz!
			else:
				# Normal pre-sahur (02:00-02:45) and post-subuh (04:45-07:00)
				d1_kw = 28.0
				d2_kw = 22.0
				d3_kw = 22.0
				puskesmas_kw = 12.0 # Total = 84 kW (covered by PLTMH + Diesel, or PLTMH + PLTS after 06:15)


func _update_sensors() -> void:
	sensors_state = {
		"NONE": false,
		"SIANG": sun_factor >= 0.28,
		"MENDUNG": cloud_cover >= 0.55,
		"F_RENDAH": frequency < F_RENDAH_THRESH,
		"F_TINGGI": frequency > F_TINGGI_THRESH,
		"DIESEL_PENUH": diesel_on and (diesel_kw >= diesel_cap_kw * 0.92)
	}


func _compute_power_preview() -> void:
	var active_d3: float = 0.0 if shed_d3_on else d3_kw
	demand_kw = d1_kw + d2_kw + active_d3 + puskesmas_kw
	plts_kw = minf(plts_kw, maxf(0.0, demand_kw - pltmh_kw))
	var base_supply: float = pltmh_kw + plts_kw
	if diesel_on:
		var deficit: float = maxf(0.0, demand_kw - base_supply)
		diesel_kw = clampf(deficit, diesel_min_kw, diesel_cap_kw)
	else:
		diesel_kw = 0.0
	supply_kw = base_supply + diesel_kw
	dusun3_powered = not shed_d3_on


func _add_log(msg: String) -> void:
	control_log.append("%s  %s" % [format_time(current_min), msg])
	if control_log.size() > 14:
		control_log.pop_front()


static func format_time(total_mins: int) -> String:
	var m_wrap: int = total_mins % (24 * 60)
	var hh: int = floori(float(m_wrap) / 60.0)
	var mm: int = m_wrap % 60
	return "%02d:%02d" % [hh, mm]


func count_total_gates() -> int:
	var roots: Array = [diesel_tree]
	if bool(current_level.get("has_shed_actuator", false)):
		roots.append(shed_tree)
	return LT.count_circuit_gates(roots)


func _emit_state() -> void:
	var progress: float = clampf(float(current_min - start_min) / float(maxi(1, end_min - start_min)), 0.0, 1.0)
	tick_updated.emit({
		"time_str": format_time(current_min),
		"current_min": current_min,
		"progress": progress,
		"frequency": frequency,
		"sun_factor": sun_factor,
		"cloud_cover": cloud_cover,
		"rain_intensity": rain_intensity,
		"is_rice_mill_active": is_rice_mill_active,
		"is_sahur_surge": is_sahur_surge,
		"pltmh_kw": pltmh_kw,
		"plts_kw": plts_kw,
		"diesel_kw": diesel_kw,
		"supply_kw": supply_kw,
		"demand_kw": demand_kw,
		"diesel_on": diesel_on,
		"shed_d3_on": shed_d3_on,
		"diesel_starts": diesel_starts,
		"shed_flickers": shed_flickers,
		"shed_minutes": shed_minutes,
		"cost_rp": cost_rp,
		"co2_kg": co2_kg,
		"dusun1_powered": dusun1_powered,
		"dusun2_powered": dusun2_powered,
		"dusun3_powered": dusun3_powered,
		"puskesmas_powered": puskesmas_powered,
		"cascade_stage": cascade_stage,
		"sensors": sensors_state,
		"freq_history": freq_history,
		"control_log": control_log
	})


func _finish_simulation(success: bool, reason: String) -> void:
	is_running = false
	var gate_cnt: int = count_total_gates()
	var target_g: int = int(current_level.get("target_gates", 1))
	var target_cost: float = float(current_level.get("target_cost_rp", 790000))
	var target_shed: int = int(current_level.get("target_shed_minutes", 0))
	var has_shed: bool = bool(current_level.get("has_shed_actuator", false))

	var stars: int = 0
	if success:
		stars = 3
		if has_shed:
			if shed_minutes > target_shed:
				stars -= 1
		else:
			if cost_rp > target_cost:
				stars -= 1
		if gate_cnt > target_g:
			stars -= 1
		stars = clampi(stars, 1, 3)

	simulation_finished.emit(success, reason, {
		"stars": stars,
		"cost_rp": int(roundf(cost_rp)),
		"target_cost_rp": int(target_cost),
		"co2_kg": int(roundf(co2_kg)),
		"gate_count": gate_cnt,
		"target_gates": target_g,
		"diesel_starts": diesel_starts,
		"shed_minutes": shed_minutes,
		"target_shed_minutes": target_shed,
		"has_shed_actuator": has_shed,
		"end_time_str": format_time(current_min)
	})

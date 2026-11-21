class_name GridSimulation
extends RefCounted

const Catalog = preload("res://resources/stages/stage_catalog.gd")
const STEP := 0.05
const SAFE_LOW := 49.5
const SAFE_HIGH := 50.5
const TRIP_SECONDS := 5.0
const EFFICIENCY := 0.9
var stage := {}
var mission := 0
var elapsed := 0.0
var frequency := 50.0
var supply := 0.0
var demand := 0.0
var available := 0.0
var solar := 0.0
var hydro := 45.0
var diesel := 0.0
var battery := 0.0
var battery_capacity := 1800.0
var battery_flow := 0.0
var battery_used := 0.0
var battery_stored := 0.0
var fuel := 0.0
var emissions := 0.0
var danger := 0.0
var starts := 0
var startup_clock := 0.0
var ready_clock := 0.0
var generator_ready := false
var district_connected := false
var failed := false
var completed := false
var reason := ""
var event_name := "Clear morning"
var state := {}
var commands := {}
var history: Array[float] = []
var events: Array[Dictionary] = []
var pending_events: Array[Dictionary] = []
var next_event := 0
var sample_clock := 0.0
var optional_outage := 0.0
var clinic_outage := 0.0
var water_outage := 0.0
var homes_outage := 0.0
var premature := false
var battery_conflict := false
var outside_peak := 0.0
var efficient := false
var battery_efficiency := EFFICIENCY
var test_switch := false
var previous_sensors := {}
var previous_signals := {}

func reset(index: int, upgrades: Dictionary = {}) -> void:
	mission = index
	stage = Catalog.get_stage(index)
	elapsed = 0
	frequency = 50
	fuel = 0
	emissions = 0
	danger = 0
	starts = 0
	startup_clock = 0
	ready_clock = 0
	generator_ready = false
	district_connected = false
	failed = false
	completed = false
	reason = ""
	event_name = "Training bench ready" if index == 0 else "Clear morning"
	state = stage.initial.duplicate(true)
	commands = {}
	history.clear()
	events.clear()
	pending_events.clear()
	next_event = 0
	sample_clock = 0
	optional_outage = 0
	clinic_outage = 0
	water_outage = 0
	homes_outage = 0
	premature = false
	battery_conflict = false
	outside_peak = 0
	battery_used = 0
	battery_stored = 0
	battery_flow = 0
	diesel = 0
	efficient = upgrades.get("efficient", false) and index >= 3
	battery_efficiency = 0.95 if upgrades.get("storage", false) and index >= 3 else EFFICIENCY
	battery_capacity = stage.battery_capacity + (600 if upgrades.get("battery", false) and index >= 3 else 0)
	battery = stage.battery_start
	test_switch = false
	previous_signals = {}
	update_environment()
	supply = hydro + solar
	previous_sensors = sensors()
	record("setup", "Controller ready. Same timeline on every restart.")

func update_environment() -> void:
	solar = (7.0 if state.CLOUD else float(stage.solar_capacity)) if state.DAY else 0.0
	hydro = 15.0 if state.HYDRO_FAULT else 45.0
	demand = 75.0 + (20.0 if state.PEAK else 0.0)
	if mission == 0: demand = 45; solar = 0
	if mission == 4: demand = 45.0 if state.get("QUIET", false) else 70.0
	if mission == 5: demand = 75.0 if district_connected else 45.0
	if commands.get("SHED_FACTORY", false): demand -= 18
	if commands.get("SHED_MILL", false): demand -= 12
	available = hydro + solar + diesel

func prepare() -> void:
	while next_event < stage.events.size() and elapsed + 0.000001 >= float(stage.events[next_event].time):
		var event: Dictionary = stage.events[next_event]
		next_event += 1
		state.merge(event.changes, true)
		event_name = event.title
		record("cause", event.title)
	update_environment()
	var current := sensors()
	for name in current:
		if current[name] is bool and previous_sensors.get(name, false) != current[name]:
			record("sensor", "%s: %d -> %d" % [name, int(previous_sensors.get(name, false)), int(current[name])])
	previous_sensors = current.duplicate()

func sensors() -> Dictionary:
	return {"TEST_SWITCH": test_switch, "DAY": state.get("DAY", true), "CLOUD": state.get("CLOUD", false), "PEAK": state.get("PEAK", false), "CHARGED": battery > 0.5, "LOW_FREQ": frequency < 49.9, "HIGH_FREQ": frequency > 50.4, "HYDRO_FAULT": state.get("HYDRO_FAULT", false), "START_WARNING": state.get("START_WARNING", false), "GENERATOR_READY": generator_ready, "SUPPLY": available, "DEMAND": demand, "BATTERY_LEVEL": battery, "TRUE": true}

func trace(board) -> void:
	for node in board.nodes:
		if node.kind == "SENSOR": continue
		var current = board.values.get(node.id, false)
		if previous_signals.get(node.id, false) != current:
			record("logic", "%s #%d output -> %d" % [node.tag if node.kind == "OUTPUT" else node.kind, node.id, int(bool(current))])
		previous_signals[node.id] = current

func step(dt: float, outputs: Dictionary) -> void:
	if failed or completed: return
	var old_commands := commands.duplicate()
	commands = outputs.duplicate()
	for key in commands:
		if commands[key] != old_commands.get(key, false):
			record("action", "%s command -> %d" % [key, int(bool(commands[key]))])
	var on := bool(commands.get("BACKUP", false))
	if on and not old_commands.get("BACKUP", false):
		starts += 1
		record("equipment", "Backup start requested; startup %.1fs" % stage.startup)
	startup_clock = startup_clock + dt if on else 0.0
	var was_ready := generator_ready
	generator_ready = on and startup_clock + 0.000001 >= float(stage.startup)
	ready_clock = ready_clock + dt if generator_ready else 0.0
	if generator_ready != was_ready: record("equipment", "Backup " + ("READY: producing 30 kW" if generator_ready else "OFFLINE"))
	diesel = 30.0 if generator_ready else 0.0
	if mission == 5:
		district_connected = commands.get("CONNECT_DISTRICT", false)
		if district_connected and (not generator_ready or ready_clock < 1.0 - 0.000001):
			premature = true
			fail("District reconnected before backup was ready and stable for 1s. The command added 30 kW demand before safe supply existed.")
	update_environment()
	var discharge := bool(commands.get("BATTERY", false))
	var charge := bool(commands.get("CHARGE", false))
	if discharge and charge:
		battery_conflict = true
		fail("CHARGE and BATTERY were both 1. Conflicting commands were rejected; neither energy flow was applied.")
		charge = false
		discharge = false
	battery_flow = 0
	if discharge:
		battery_flow = minf(float(stage.battery_rate), battery * battery_efficiency / dt)
		var spent := battery_flow * dt / battery_efficiency
		battery -= spent
		battery_used += spent
		if mission == 3 and not state.PEAK: outside_peak += dt
	elif charge:
		var charging := minf(20.0, minf(maxf(0, available - demand), (battery_capacity - battery) / (dt * battery_efficiency)))
		battery_flow = -charging
		var stored := charging * dt * battery_efficiency
		battery += stored
		battery_stored += stored
	battery = clampf(battery, 0, battery_capacity)
	supply = available + battery_flow
	fuel += diesel * dt * (0.7 if efficient else 1.0)
	emissions += diesel * dt * (0.455 if efficient else 0.65)
	if mission != 0:
		var was_stressed := danger > 0
		var target := 50.0 + (supply - demand) * 0.025
		frequency = lerpf(frequency, target, minf(1, dt * 1.8))
		if frequency < SAFE_LOW or frequency > SAFE_HIGH: danger += dt
		else: danger = maxf(0, danger - dt * 0.6)
		if was_stressed and danger == 0: record("consequence", "Supply recovered; frequency stabilized.")
		if commands.get("SHED_FACTORY", false): optional_outage += dt
		if commands.get("SHED_MILL", false): optional_outage += dt
		if danger >= TRIP_SECONDS:
			clinic_outage += dt
			water_outage += dt
			homes_outage += dt
			fail("%s Supply %.0f kW versus demand %.0f kW drove frequency to %.2f Hz for 5s of stress. Clinic, water and homes lost supply. BACKUP=%d, BATTERY=%d, SHED_FACTORY=%d." % [event_name, supply, demand, frequency, int(on), int(discharge), int(commands.get("SHED_FACTORY", false))])
	elapsed = minf(float(stage.duration), elapsed + dt)
	sample_clock += dt
	if sample_clock >= 0.2:
		sample_clock -= 0.2
		history.append(frequency)
	if mission == 3 and outside_peak > 0.1: fail("Battery discharged outside PEAK. That decision wastes stored energy reserved for the factory surge.")
	if mission == 4 and starts > int(stage.start_limit): fail("Backup exceeded %d starts. LOW_FREQ switched off during recovery and repeatedly restarted; use memory until HIGH_FREQ resets it." % stage.start_limit)
	if mission in [6, 9] and optional_outage > float(stage.optional_budget) + 0.001: fail("Optional industry interruption budget exceeded: %.1fs. Protective shedding must be released when its cause clears." % optional_outage)
	if elapsed + 0.000001 >= float(stage.duration) and not failed:
		if mission == 5 and not district_connected: fail("The district was never restored. A safe controller must finish the readiness and delay sequence.")
		else:
			completed = true
			record("result", "Scenario complete: critical services remained supplied.")

func fail(message: String) -> void:
	if failed: return
	failed = true
	reason = message
	record("failure", message)

func record(kind: String, message: String) -> void:
	var event := {"time": elapsed, "kind": kind, "message": message}
	events.append(event)
	pending_events.append(event)

func forecast() -> String:
	if next_event >= stage.events.size(): return "No further scheduled changes"
	var e: Dictionary = stage.events[next_event]
	return "%ds: %s (in %.0fs)" % [e.time, e.title, maxf(0, float(e.time) - elapsed)]

func clock_text() -> String:
	var minutes := int(420 + elapsed / float(stage.duration) * 960)
	return "%02d:%02d" % [floori(float(minutes) / 60.0), minutes % 60]

func metrics() -> Dictionary:
	return {"frequency": frequency, "fuel": fuel, "emissions": emissions, "outages": clinic_outage + water_outage + homes_outage, "shedding": optional_outage, "starts": starts, "battery_used": battery_used, "battery_stored": battery_stored, "time": elapsed, "passed": completed and not failed}

func explanation() -> String:
	var causes := []
	var actions := []
	for e in events:
		if e.kind == "cause" and e.message not in causes: causes.append(e.message)
		if e.kind in ["logic", "action", "equipment"] and e.message not in actions: actions.append(e.message)
	return "CAUSE: %s\nLOGIC / ACTION: %s\nCONSEQUENCE: %s" % ["; ".join(causes) if not causes.is_empty() else "Training switch / demand at start", "; ".join(actions).left(900) if not actions.is_empty() else "No actuator changed", reason if failed else "Clinic, homes and water remained supplied; final frequency %.2f Hz." % frequency]

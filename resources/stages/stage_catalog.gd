class_name StageCatalog
extends RefCounted

const ALL_GATES = ["NOT", "AND", "OR", "XOR", "NAND", "NOR", "LATCH", "TIMER", "COMPARE"]

static func get_stage(index: int) -> Dictionary:
	var names = ["First Connection", "After Sunset", "Two Reasons to Act", "Use the Battery Wisely", "Stop the Chatter", "Ready Before Reconnecting", "Keep the Clinic On", "Save the Surplus", "From Wires to Code", "The Long Night"]
	var concepts = ["Ports and signals", "NOT", "OR", "AND", "Memory / hysteresis", "Readiness / on-delay", "Priority shedding", "Numeric comparisons / storage", "Safe rule programming", "Independent engineering"]
	var stories = ["Commission a safe training lamp before connecting the village.", "Daylight ends. Build an automatic backup controller.", "Clouds and sunset have the same consequence: less solar power.", "A factory peak needs support only while stored energy is available.", "A direct frequency switch chatters. Remember the request until recovery.", "Start the generator, wait for readiness, then stabilize before reconnecting.", "A river fault threatens the clinic. Deliberate interruption can protect essential service.", "Store midday surplus. Earlier decisions determine evening resources.", "Translate familiar gates into a small, safe controller program.", "A storm, festival and hydro fault interact. Use the forecast to protect Sukamaju."]
	var d = {"id": index, "title": names[index], "concept": concepts[index], "story": stories[index], "duration": [12, 40, 50, 65, 75, 65, 105, 100, 90, 125][index], "sensors": [], "outputs": [], "gates": [], "events": [], "initial": {"DAY": true, "CLOUD": false, "PEAK": false, "HYDRO_FAULT": false, "START_WARNING": false}, "startup": 0.0, "battery_start": 1200.0, "battery_capacity": 1800.0, "solar_capacity": 30.0, "battery_rate": 24.0, "optional_budget": 0.0, "emission_target": 1500.0, "shedding_target": 70.0, "fuel_target": 2000.0, "gate_target": 8, "start_limit": 99, "hints": [], "mandatory": "Finish without a blackout; clinic and homes remain supplied.", "script": "", "reference_script": "", "failure": "Leave BACKUP disconnected: sunset causes a supply deficit."}
	match index:
		0:
			d.sensors = ["TEST_SWITCH"]
			d.outputs = ["LAMP"]
			d.mandatory = "Demonstrate lamp ON and OFF, disconnect/reconnect, then Run, Pause, Step and Reset."
			d.hints = ["Find the cyan TEST_SWITCH output on its right edge.", "Drag its right port to LAMP's left input. Toggle TEST SWITCH.", "Observe ON and OFF, disconnect the lamp input and reconnect. Follow the tool checklist."]
			d.failure = "A disconnected lamp cannot follow the switch. No village blackout is possible."
		1:
			d.sensors = ["DAY"]
			d.outputs = ["BACKUP"]
			d.gates = ["NOT"]
			d.events = [event(18, "Sunset: solar goes offline", {"DAY": false})]
			d.hints = ["DAY becomes 0 after sunset.", "NOT inverts 0 into 1.", "Wire DAY -> NOT -> BACKUP."]
			d.gate_target = 1
		2:
			d.sensors = ["DAY", "CLOUD"]
			d.outputs = ["BACKUP"]
			d.gates = ["NOT", "OR"]
			d.events = [event(10, "Cloud arrived", {"CLOUD": true}), event(22, "Cloud cleared", {"CLOUD": false}), event(32, "Sunset", {"DAY": false})]
			d.hints = ["There are two independent reasons to start backup.", "Keep the NOT DAY branch. Combine it with CLOUD using OR.", "BACKUP = NOT DAY OR CLOUD. Replace the old BACKUP wire explicitly."]
			d.failure = "Use only NOT DAY: backup ignores the cloud and the grid trips before sunset."
			d.gate_target = 2
		3:
			d.sensors = ["DAY", "CLOUD", "PEAK", "CHARGED"]
			d.outputs = ["BACKUP", "BATTERY"]
			d.gates = ["NOT", "OR", "AND"]
			d.events = [event(20, "Factory peak begins", {"PEAK": true}), event(35, "Factory peak ends", {"PEAK": false}), event(45, "Sunset", {"DAY": false})]
			d.hints = ["The backup circuit is already working. Focus on BATTERY.", "Discharge requires both a peak and remaining energy.", "PEAK -> AND A; CHARGED -> AND B; AND -> BATTERY."]
			d.mandatory += " Never discharge outside PEAK; commissioning must pass all PEAK / CHARGED cases."
			d.failure = "Connect TRUE to BATTERY: discharge outside PEAK violates the energy rule."
		4:
			d.sensors = ["LOW_FREQ", "HIGH_FREQ"]
			d.outputs = ["BACKUP"]
			d.gates = ["LATCH", "NOT", "AND", "OR"]
			d.initial.DAY = false
			d.events = [event(20, "Demand relaxes", {"QUIET": true}), event(30, "Demand returns", {"QUIET": false}), event(45, "Demand relaxes", {"QUIET": true}), event(55, "Demand returns", {"QUIET": false}), event(68, "Demand relaxes", {"QUIET": true})]
			d.start_limit = 4
			d.hints = ["Try LOW_FREQ directly to BACKUP and inspect repeated starts.", "LOW_FREQ should SET memory. HIGH_FREQ should RESET memory.", "LOW_FREQ -> LATCH SET, HIGH_FREQ -> RESET, LATCH -> BACKUP. RESET wins."]
			d.mandatory += " Maximum 4 generator starts."
			d.failure = "LOW_FREQ directly drives BACKUP: frequency recovery switches it off too soon and creates repeated starts."
		5:
			d.sensors = ["START_WARNING", "GENERATOR_READY"]
			d.outputs = ["BACKUP", "CONNECT_DISTRICT"]
			d.gates = ["TIMER", "AND", "LATCH", "NOT", "OR"]
			d.initial.DAY = false
			d.startup = 3.0
			d.events = [event(8, "District requests reconnection", {"START_WARNING": true})]
			d.hints = ["START_WARNING starts backup. Its startup takes 3 game seconds.", "Use GENERATOR_READY as the timer input, not the start command.", "START_WARNING -> BACKUP; GENERATOR_READY -> TIMER (1s) -> CONNECT_DISTRICT."]
			d.mandatory = "Restore the district after generator readiness plus 1s stabilization; no premature connection."
			d.failure = "START_WARNING -> CONNECT_DISTRICT reconnects demand before the generator is ready."
		6:
			d.sensors = ["DAY", "CLOUD", "HYDRO_FAULT", "LOW_FREQ", "CHARGED"]
			d.outputs = ["BACKUP", "BATTERY", "SHED_FACTORY", "SHED_MILL"]
			d.gates = ALL_GATES.slice(0, 8)
			d.events = [event(25, "Hydro fault: output falls to 15 kW", {"HYDRO_FAULT": true}), event(65, "Hydro repaired", {"HYDRO_FAULT": false}), event(75, "Sunset", {"DAY": false})]
			d.optional_budget = 70.0
			d.fuel_target = 2250.0
			d.hints = ["Protect the clinic. Factory and mill are optional loads.", "During the fault, shed the factory and request backup.", "BACKUP = NOT DAY OR HYDRO_FAULT; SHED_FACTORY = HYDRO_FAULT."]
			d.mandatory += " Optional interruptions combined <=70s."
			d.failure = "No fault response: lost hydro supply destabilizes the clinic supply."
		7:
			d.sensors = ["SUPPLY", "DEMAND", "BATTERY_LEVEL", "CHARGED", "DAY"]
			d.outputs = ["CHARGE", "BATTERY"]
			d.gates = ["COMPARE", "AND", "OR", "NOT"]
			d.solar_capacity = 50.0
			d.battery_start = 0.0
			d.battery_rate = 30.0
			d.events = [event(65, "Sunset: stored energy is now needed", {"DAY": false})]
			d.hints = ["SUPPLY is available generation before battery flow; demand is 75 kW.", "Compare SUPPLY >75 to charge and SUPPLY <75 to discharge.", "Two comparators: >75 -> CHARGE and <75 -> BATTERY. Set thresholds in the inspector."]
			d.mandatory += " No simultaneous charge/discharge."
			d.failure = "Discharge without charging first: the empty battery cannot support evening demand."
		8:
			d.sensors = ["DAY", "CLOUD", "PEAK", "CHARGED", "SUPPLY", "DEMAND", "BATTERY_LEVEL"]
			d.outputs = ["BACKUP", "BATTERY"]
			d.gates = ["NOT", "OR", "AND"]
			d.events = [event(15, "Cloud arrived", {"CLOUD": true}), event(28, "Cloud cleared", {"CLOUD": false}), event(48, "Sunset", {"DAY": false}), event(60, "Factory peak", {"PEAK": true}), event(75, "Peak ends", {"PEAK": false})]
			d.script = "# Replace FALSE with the matching gate expression.\nBACKUP = FALSE\nBATTERY = FALSE"
			d.reference_script = "BACKUP = NOT DAY OR CLOUD\nBATTERY = PEAK AND CHARGED"
			d.hints = ["Equivalent gates: BACKUP = (NOT DAY) OR CLOUD.", "AND requires both PEAK and CHARGED for battery support.", "BACKUP = NOT DAY OR CLOUD\nBATTERY = PEAK AND CHARGED"]
			d.mandatory += " Use a valid program to drive both outputs."
			d.failure = "Starter FALSE outputs do not respond to clouds or the evening peak."
		9:
			d.sensors = ["DAY", "CLOUD", "PEAK", "HYDRO_FAULT", "START_WARNING", "GENERATOR_READY", "CHARGED", "SUPPLY", "DEMAND", "BATTERY_LEVEL", "LOW_FREQ", "HIGH_FREQ"]
			d.outputs = ["BACKUP", "BATTERY", "CHARGE", "SHED_FACTORY", "SHED_MILL"]
			d.gates = ALL_GATES
			d.startup = 2.0
			d.events = [event(25, "Storm warning: start reserves", {"START_WARNING": true}), event(30, "Storm clouds arrive", {"CLOUD": true}), event(50, "Festival demand rises", {"PEAK": true}), event(55, "Hydro fault: output falls to 15 kW", {"HYDRO_FAULT": true}), event(85, "Hydro repaired; festival ends", {"HYDRO_FAULT": false, "PEAK": false}), event(95, "Sunset", {"DAY": false})]
			d.optional_budget = 170.0
			d.start_limit = 4
			d.fuel_target = 3300.0
			d.emission_target = 2200.0
			d.shedding_target = 80.0
			d.hints = ["Forecast: warning 25s, storm 30s, festival 50s, fault 55s, repair 85s, sunset 95s.", "Start reserves on warning. Shed industry during festival/fault; battery can cover the worst overlap.", "BACKUP=START_WARNING; SHED_FACTORY=PEAK OR HYDRO_FAULT; SHED_MILL=HYDRO_FAULT; BATTERY=PEAK AND HYDRO_FAULT."]
			d.mandatory += " Water interruption <=2s; industry interruptions combined <=170s."
			d.failure = "Leave backup and shedding disconnected: the storm/festival/fault combination overwhelms reserves."
	return d

static func event(time: float, title: String, changes: Dictionary) -> Dictionary:
	return {"time": time, "title": title, "changes": changes}

static func starter(index: int):
	var b = LogicBoard.new()
	var d = get_stage(index)
	for i in range(d.sensors.size()): b.add("SENSOR", Vector2(40 + floori(float(i) / 6.0) * 220, 65 + (i % 6) * 95), d.sensors[i])
	for i in range(d.outputs.size()): b.add("OUTPUT", Vector2(800, 65 + i * 110), d.outputs[i])
	b.script_text = d.script
	if index in [2, 3]:
		var inv = b.add("NOT", Vector2(310, 50))
		b.connect_nodes(terminal(b, "DAY"), inv, 0)
		b.connect_nodes(inv, terminal(b, "BACKUP"), 0)
		if index == 3:
			var either = b.add("OR", Vector2(550, 100))
			b.connect_nodes(inv, either, 0)
			b.connect_nodes(terminal(b, "CLOUD"), either, 1)
			b.connect_nodes(either, terminal(b, "BACKUP"), 0, true)
	return b

static func terminal(b, tag: String) -> int:
	for n in b.nodes:
		if n.tag == tag: return n.id
	return -1

static func gate(b, kind: String, sources: Array, settings: Dictionary = {}) -> int:
	var id = b.add(kind, Vector2(300 + (b.nodes.size() % 3) * 190, 60 + (b.nodes.size() % 6) * 100))
	b.find(id).settings = settings
	for p in range(sources.size()): b.connect_nodes(sources[p], id, p)
	return id

static func solution(index: int):
	var b = starter(index)
	# Reference circuits are for verification and an explicitly requested solution reveal.
	b.wires.clear()
	b.nodes = b.nodes.filter(func(n): return n.kind in ["SENSOR", "OUTPUT"])
	var t = func(tag): return terminal(b, tag)
	var backup = -1
	match index:
		0: b.connect_nodes(t.call("TEST_SWITCH"), t.call("LAMP"), 0)
		1: backup = gate(b, "NOT", [t.call("DAY")])
		2, 3:
			backup = gate(b, "OR", [gate(b, "NOT", [t.call("DAY")]), t.call("CLOUD")])
			if index == 3: b.connect_nodes(gate(b, "AND", [t.call("PEAK"), t.call("CHARGED")]), t.call("BATTERY"), 0)
		4: backup = gate(b, "LATCH", [t.call("LOW_FREQ"), t.call("HIGH_FREQ")])
		5:
			backup = t.call("START_WARNING")
			b.connect_nodes(gate(b, "TIMER", [t.call("GENERATOR_READY")], {"delay": 1.0}), t.call("CONNECT_DISTRICT"), 0)
		6:
			backup = gate(b, "OR", [gate(b, "NOT", [t.call("DAY")]), t.call("HYDRO_FAULT")])
			b.connect_nodes(t.call("HYDRO_FAULT"), t.call("SHED_FACTORY"), 0)
		7:
			b.connect_nodes(gate(b, "COMPARE", [t.call("SUPPLY")], {"op": ">", "threshold": 75.0}), t.call("CHARGE"), 0)
			b.connect_nodes(gate(b, "COMPARE", [t.call("SUPPLY")], {"op": "<", "threshold": 75.0}), t.call("BATTERY"), 0)
		8: b.script_text = get_stage(index).reference_script
		9:
			backup = t.call("START_WARNING")
			b.connect_nodes(gate(b, "OR", [t.call("PEAK"), t.call("HYDRO_FAULT")]), t.call("SHED_FACTORY"), 0)
			b.connect_nodes(t.call("HYDRO_FAULT"), t.call("SHED_MILL"), 0)
			b.connect_nodes(gate(b, "AND", [t.call("PEAK"), t.call("HYDRO_FAULT")]), t.call("BATTERY"), 0)
	if backup != -1: b.connect_nodes(backup, t.call("BACKUP"), 0)
	return b

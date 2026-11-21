@tool
class_name VillageView
extends Control

@export_enum("01 Training Yard", "02 Riverside Hamlet", "03 Cloudbank Terrace", "04 Mill Road", "05 Hilltop Relay", "06 East District", "07 Clinic Quarter", "08 Solar Fields", "09 Control Campus", "10 Festival Village") var preview_stage := 1:
	set(value):
		preview_stage = clampi(value, 0, 9)
		if is_inside_tree():
			load_map()
			if Engine.is_editor_hint(): make_preview()
@export var map_scene_override: PackedScene:
	set(value):
		map_scene_override = value
		if is_inside_tree(): load_map()
var sim
var map_root: Node2D
var preview_commands := {}
var simulation_running := false
var selected_command := ""
var reduced_motion := false
var animation := 0.0
const GREEN = Color("4be0a0")
const CYAN = Color("74d7f2")
const AMBER = Color("ffce78")
const RED = Color("ff7185")
const WHITE = Color("e8f1f5")

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_map()
	if Engine.is_editor_hint(): make_preview()

func set_stage(index: int) -> void:
	if preview_stage != index: preview_stage = index
	elif not is_instance_valid(map_root): load_map()

func load_map() -> void:
	if is_instance_valid(map_root):
		remove_child(map_root)
		map_root.queue_free()
	var resource: PackedScene = map_scene_override if map_scene_override else load("res://scenes/stages/stage_%02d.tscn" % [preview_stage + 1])
	if resource:
		map_root = resource.instantiate()
		map_root.name = "StageMap"
		add_child(map_root)
		map_root.scale = size / Vector2(900, 790)
	queue_redraw()

func make_preview() -> void:
	if Engine.is_editor_hint():
		var data: Dictionary = preload("res://resources/stages/stage_catalog.gd").get_stage(preview_stage)
		var edited_root = get_tree().edited_scene_root
		var heading = edited_root.find_child("StageLabel", true, false) if edited_root else null
		var objective = edited_root.find_child("Objective", true, false) if edited_root else null
		if heading: heading.text = "%02d / %s" % [preview_stage + 1, data.title]
		if objective: objective.text = data.concept + "\n" + data.mandatory
	sim = {"state": {"DAY": true, "CLOUD": false, "HYDRO_FAULT": false}, "commands": {}, "failed": false, "danger": 0.0, "solar": 30.0, "hydro": 45.0, "generator_ready": false, "diesel": 0.0, "startup_clock": 0.0, "battery_flow": 0.0, "battery": 1200.0, "battery_capacity": 1800.0, "mission": preview_stage, "history": [], "event_name": "EDITOR PREVIEW / open scenes/stages/stage_%02d.tscn to move buildings" % [preview_stage + 1], "supply": 75.0, "demand": 75.0, "fuel": 0.0, "emissions": 0.0, "starts": 0, "optional_outage": 0.0}

func _process(delta: float) -> void:
	if not reduced_motion and not Engine.is_editor_hint(): animation += delta
	if is_instance_valid(map_root):
		map_root.scale = size / Vector2(900, 790)
		if sim != null:
			for site in map_root.get_children():
				if site is VillageBuilding: update_site(site)
			if map_root.has_node("PowerFlow"):
				map_root.get_node("PowerFlow").refresh_routes(sim, animation, reduced_motion or Engine.is_editor_hint(), selected_command)
	sync_monitor()
	queue_redraw()

func update_site(site: VillageBuilding) -> void:
	var tag := ""
	site.intentional = false
	site.fault = false
	site.stressed = false
	site.night = not sim.state.get("DAY", true)
	site.powered = not sim.failed
	site.status = "OUTAGE" if sim.failed else "ONLINE"
	match site.role:
		"HYDRO":
			site.fault = sim.state.get("HYDRO_FAULT", false)
			site.status = "HYDRO FAULT / 15 kW" if site.fault else "45 kW"
		"SOLAR":
			site.powered = sim.solar > 0
			site.status = "%.0f kW / %s" % [sim.solar, "CLOUD" if sim.state.get("CLOUD", false) else "SUN" if not site.night else "NIGHT"]
		"BACKUP":
			tag = "BACKUP"
			site.powered = sim.generator_ready
			site.status = "READY / 30 kW" if site.powered else "STARTING %.1fs" % sim.startup_clock if sim.commands.get(tag, false) else "OFF / NO START COMMAND"
		"BATTERY":
			tag = "BATTERY"
			site.powered = absf(sim.battery_flow) > 0.01
			site.energy_fraction = clampf(sim.battery / sim.battery_capacity, 0, 1)
			site.status = "%s / %.0f EU" % ["DISCHARGE" if sim.battery_flow > 0 else "CHARGING" if sim.battery_flow < 0 else "IDLE", sim.battery]
			if sim.commands.get("CHARGE", false) or preview_commands.get("CHARGE", false): tag = "CHARGE"
		"FACTORY", "MILL":
			tag = "SHED_FACTORY" if site.role == "FACTORY" else "SHED_MILL"
			site.intentional = sim.commands.get(tag, false)
			site.powered = not sim.failed and not site.intentional
			site.status = "INTENTIONAL SHED" if site.intentional else "PEAK DEMAND +20 kW" if site.role == "FACTORY" and sim.state.get("PEAK", false) else site.status
		"DISTRICT":
			tag = "CONNECT_DISTRICT"
			site.powered = not sim.failed and sim.commands.get(tag, false)
			site.intentional = not site.powered and not sim.failed
			site.status = "CONNECTED" if site.powered else "WAITING / DISCONNECTED" if not sim.failed else "EARLY CONNECT / OUTAGE"
		"LAMP":
			tag = "LAMP"
			site.powered = sim.commands.get(tag, false)
			site.status = "ON / SIGNAL 1" if site.powered else "OFF / SIGNAL 0"
	if sim.mission == 0 and site.role == "HOME":
		site.powered = sim.commands.get("LAMP", false)
		site.status = "TRAINING LOAD ON" if site.powered else "TRAINING LOAD OFF"
	if site.role in ["HOME", "CLINIC", "WATER", "GRID", "FACTORY", "MILL"] and not sim.failed and not site.intentional:
		site.stressed = sim.danger > 0.05
		if site.stressed: site.status = "GRID UNSTABLE / %.2f Hz" % sim.frequency
	if sim.failed and site.role in ["HOME", "CLINIC", "WATER", "GRID", "FACTORY", "MILL", "DISTRICT"]: site.fault = true
	site.command = int(bool(sim.commands.get(tag, false))) if tag != "" else -1
	site.preview_command = int(bool(preview_commands.get(tag, false))) if tag != "" else -1
	site.animation = animation
	site.reduced_motion = reduced_motion or Engine.is_editor_hint()
	site.queue_redraw()

func _draw() -> void:
	if sim == null: return
	var scale_by := size / Vector2(900, 790)
	draw_set_transform(Vector2.ZERO, 0, scale_by)
	var night: bool = not sim.state.get("DAY", true)
	draw_rect(Rect2(0, 0, 900, 790), Color("10222d"))
	draw_rect(Rect2(12, 12, 876, 480), Color("172c3b") if night else [Color("284b43"), Color("354d39"), Color("29484e"), Color("484735")][preview_stage % 4])
	for i in range(12):
		var p = Vector2(55 + sin(i * 0.5) * 15, 60 + i * 34)
		draw_line(p, Vector2(55 + sin((i + 1) * 0.5) * 15, p.y + 34), Color("34738b"), 27, true)
	# PowerFlow is an authored map layer above roads and below buildings.
	if sim.state.get("CLOUD", false):
		for i in range(4): draw_circle(Vector2(420 + i * 25 + sin(animation * 0.2) * 60, 72 - (i % 2) * 8), 22, Color("9baeb9"))
	else: draw_circle(Vector2(845, 65), 17, Color("bed6ea") if night else AMBER)

func grid_position() -> Vector2:
	if is_instance_valid(map_root):
		for site in map_root.get_children():
			if site is VillageBuilding and site.role == "GRID": return site.position
	return Vector2(450, 260)

func sync_monitor() -> void:
	if sim == null or not has_node("VillageTitle"): return
	$VillageTitle.text = "DESA SUKAMAJU / STAGE %02d / SEBAB AKIBAT" % [preview_stage + 1]
	$CurrentEvent.text = sim.event_name
	$SupplyDemand.text = "SUPPLY %.0f kW   DEMAND %.0f kW   STRESS %.1f / 5s" % [sim.supply, sim.demand, sim.danger]
	$SupplyDemand.modulate = RED if sim.danger > 0 else GREEN
	$Resources.text = "Observe: condition → signal → equipment → village." if sim.mission <= 2 else "Fuel %.0f   CO2 %.0f   Starts %d   Industry shed %.1fs" % [sim.fuel, sim.emissions, sim.starts, sim.optional_outage]
	$Forecast.text = "NEXT: " + ("Change Preview Stage in the Inspector" if sim is Dictionary else sim.forecast())
	$FrequencyChart.sim = sim

@tool
class_name VillagePowerFlow
extends Node2D

@export var generation_color := Color("74d7f2")
@export var delivery_color := Color("4be0a0")
@export var charging_color := Color("ffce78")
@export var disconnected_color := Color("627582")
@export var fault_color := Color("ff7185")
@export_range(2, 10) var line_width := 5.0
@export_range(35, 120) var arrow_spacing := 70.0
@export_range(15, 150) var flow_speed := 55.0
var routes: Array[Dictionary] = []
var clock := 0.0
var reduced_motion := false
var geometry_signature := ""
var route_cache := {}

func _ready() -> void:
	if Engine.is_editor_hint():
		refresh_routes({"failed": false, "hydro": 45.0, "solar": 30.0, "diesel": 0.0, "battery_flow": 0.0, "commands": {}, "mission": int(get_parent().get_meta("stage_number", 1)) - 1}, 0, true)

func refresh_routes(sim, animation_time: float, reduced := false, selected_command := "") -> void:
	routes.clear()
	clock = animation_time
	reduced_motion = reduced
	var map = get_parent()
	if not map: return
	var signature := ""
	for node in map.get_children():
		if node is VillageBuilding: signature += str(node.name) + str(node.role) + str(node.position)
	if signature != geometry_signature:
		geometry_signature = signature
		route_cache.clear()
	var hub := Vector2(450, 260)
	for node in map.get_children():
		if node is VillageBuilding and node.role == "GRID": hub = node.position
	for site in map.get_children():
		if not site is VillageBuilding or site.role == "GRID": continue
		var role: String = site.role
		var generation: bool = role in ["HYDRO", "SOLAR", "BACKUP"] or (role == "BATTERY" and sim.battery_flow > 0)
		var active := false
		var shed := false
		var tag := ""
		var charging: bool = role == "BATTERY" and sim.battery_flow < -0.001
		var state := "OFF"
		match role:
			"HYDRO": active = sim.hydro > 0
			"SOLAR": active = sim.solar > 0
			"BACKUP":
				tag = "BACKUP"
				active = sim.diesel > 0
			"BATTERY":
				tag = "CHARGE" if charging else "BATTERY"
				active = absf(sim.battery_flow) > 0.001
			"FACTORY", "MILL":
				tag = "SHED_FACTORY" if role == "FACTORY" else "SHED_MILL"
				shed = sim.commands.get(tag, false)
				active = not shed
			"DISTRICT":
				tag = "CONNECT_DISTRICT"
				active = sim.commands.get(tag, false)
				shed = not active
			"LAMP":
				tag = "LAMP"
				active = sim.commands.get(tag, false)
			"HOME", "CLINIC", "WATER": active = true
		if sim.mission == 0:
			active = role in ["LAMP", "HOME"] and sim.commands.get("LAMP", false)
			generation = false
		if sim.failed:
			active = false
			state = "OUTAGE"
		elif shed: state = "DISCONNECTED"
		elif charging and active: state = "CHARGING"
		elif active: state = "FLOW"
		var source: Vector2 = site.position if generation else hub
		var destination: Vector2 = hub if generation else site.position
		var points := route_points(source, destination, site, map)
		var color := generation_color if generation else charging_color if charging else delivery_color
		if not active: color = fault_color if sim.failed else charging_color if shed else disconnected_color
		routes.append({"role": role, "node": site.name, "from": role if generation else "GRID", "to": "GRID" if generation else role, "active": active, "state": state, "points": points, "color": color, "highlight": tag != "" and tag == selected_command})
	queue_redraw()

func clear_segment(a: Vector2, b: Vector2, obstacles: Array[Rect2]) -> bool:
	for rect in obstacles:
		if absf(a.x - b.x) < 0.01:
			if a.x > rect.position.x and a.x < rect.end.x and maxf(a.y, b.y) > rect.position.y and minf(a.y, b.y) < rect.end.y: return false
		else:
			if a.y > rect.position.y and a.y < rect.end.y and maxf(a.x, b.x) > rect.position.x and minf(a.x, b.x) < rect.end.x: return false
	return true

func route_points(source: Vector2, destination: Vector2, endpoint: VillageBuilding, map: Node) -> PackedVector2Array:
	var key := str(source) + ":" + str(destination)
	if route_cache.has(key): return route_cache[key]
	var obstacles: Array[Rect2] = []
	for other in map.get_children():
		if other is VillageBuilding and other != endpoint and other.role != "GRID":
			obstacles.append(Rect2(other.position - Vector2(53, 61), Vector2(106, 146)))
	var candidates: Array[PackedVector2Array] = [
		PackedVector2Array([source, Vector2(destination.x, source.y), destination]),
		PackedVector2Array([source, Vector2(source.x, destination.y), destination])]
	# Fixed reference corridors lie between the authored building columns. Cache the
	# shortest clear orthogonal route so a line cannot imply it feeds an idle bystander.
	for y in [55.0, 480.0, 190.0, 345.0, source.y - 75, destination.y - 75]:
		for x in [85.0, 245.0, 450.0, 660.0, 845.0]:
			y = clampf(y, 55, 480)
			candidates.append(PackedVector2Array([source, Vector2(source.x, y), Vector2(x, y), Vector2(x, destination.y), destination]))
			candidates.append(PackedVector2Array([source, Vector2(x, source.y), Vector2(x, y), Vector2(destination.x, y), destination]))
	var best := PackedVector2Array([source, Vector2(destination.x, source.y), destination])
	var best_length := INF
	for points in candidates:
		var length := 0.0
		var clear := true
		for i in range(points.size() - 1):
			if not clear_segment(points[i], points[i+1], obstacles):
				clear = false
				break
			length += points[i].distance_to(points[i+1])
		if clear and length < best_length:
			best = points
			best_length = length
	route_cache[key] = best
	return best

func point_at(points: PackedVector2Array, distance: float) -> Dictionary:
	for i in range(points.size() - 1):
		var length := points[i].distance_to(points[i+1])
		if length < 0.001: continue
		if distance <= length:
			return {"position": points[i].lerp(points[i+1], clampf(distance / length, 0, 1)), "direction": (points[i+1] - points[i]).normalized()}
		distance -= length
	return {"position": points[-1], "direction": (points[-1] - points[0]).normalized()}

func _draw() -> void:
	for route in routes:
		var points: PackedVector2Array = route.points
		var color: Color = route.color
		var total := 0.0
		for i in range(points.size()-1): total += points[i].distance_to(points[i+1])
		if total < 2: continue
		if route.active:
			draw_polyline(points, color.darkened(0.65), line_width + 5, true)
			draw_polyline(points, color, line_width + (2 if route.highlight else 0), true)
			var phase := 0.0 if reduced_motion else fmod(clock * flow_speed, arrow_spacing)
			var distance := 45.0 + phase
			while distance < total - 40:
				var sample := point_at(points, distance)
				var p: Vector2 = sample.position
				var direction: Vector2 = sample.direction
				var side := Vector2(-direction.y, direction.x)
				draw_colored_polygon(PackedVector2Array([p + direction * 9, p - direction * 5 + side * 6, p - direction * 5 - side * 6]), Color("f0fff7"))
				distance += arrow_spacing
		else:
			var distance := 0.0
			while distance < total:
				var a: Vector2 = point_at(points, distance).position
				var b: Vector2 = point_at(points, minf(total, distance + 12)).position
				draw_line(a, b, color.darkened(0.25), 3, true)
				distance += 22
			if route.state in ["DISCONNECTED", "OUTAGE"]:
				var p: Vector2 = point_at(points, maxf(25, total - 60)).position
				draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), color, 3, true)
				draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), color, 3, true)

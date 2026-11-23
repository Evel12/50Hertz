extends Node2D
## Stage-specific devices layered over the untouched authored village.
const UI := preload("res://scripts/upper_hud_skin.gd")
const VisualState := preload("res://scripts/output_visual_state.gd")
const MOTOR := preload("res://Kenney Asset/kenney_tiny-factory/Tiles/tile_0094.png")
const GEAR := preload("res://Kenney Asset/kenney_tiny-factory/Tiles/tile_0114.png")
const TANK := preload("res://Kenney Asset/kenney_tiny-factory/Tiles/tile_0086.png")
var level: Dictionary
var world: Node2D
var values: Dictionary = {}
var context: Dictionary = {}
var markers: Array[Dictionary] = []
var states: Dictionary = {}
var selected_output := ""
var anim_time := 0.0
var cable_layer: Node2D
var tank_position := Vector2.ZERO

func _ready() -> void:
	z_index = 32
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bindings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/output_visuals.json"))
	for output in level["outputs"]:
		if not bindings.has(output):
			push_error("Missing output visual: "+str(output))
			continue
		var item: Dictionary = bindings[output].duplicate(true)
		item["output"] = output
		var offset: Array = item["offset"]
		item["at"] = world.zone_anchors[item["zone"]]+Vector2(offset[0],offset[1])
		var source := Vector2.ZERO
		if item.has("source_pole"):
			source = world.pole_anchors[item["source_pole"]]
		else:
			var extra: Array = item["source_offset"]
			source = world.zone_anchors[item["source_zone"]]+Vector2(extra[0],extra[1])
		var endpoint: Vector2 = item["at"]+Vector2(-24,8)
		var points := PackedVector2Array([source,Vector2(source.x,endpoint.y),endpoint])
		if output=="PERINTAH_DIESEL": points.reverse()
		item["route"] = points
		markers.append(item)
		states[output] = VisualState.resolve(output,{})
	tank_position = world.zone_anchors["pltmh"]+Vector2(248,180)
	cable_layer = Node2D.new()
	cable_layer.name = "MissionPowerCables"
	cable_layer.z_index = -31
	cable_layer.draw.connect(func(): _draw_routes(cable_layer))
	add_child(cable_layer)

func set_context(next_context: Dictionary) -> void:
	context = next_context
	values = context.get("outputs",{})
	for marker in markers:
		states[marker["output"]] = VisualState.resolve(marker["output"],context)
	queue_redraw()
	if cable_layer != null: cable_layer.queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	anim_time += delta
	queue_redraw()
	if cable_layer != null: cable_layer.queue_redraw()

func visual_state(output: String) -> Dictionary:
	return states.get(output,{})

func marker_for(output: String) -> Dictionary:
	for marker in markers:
		if marker["output"]==output: return marker
	return {}

func hit_test_output(point: Vector2) -> String:
	for marker in markers:
		var at: Vector2 = marker["at"]
		if Rect2(at-Vector2(36,44),Vector2(72,72)).has_point(point) or _label_rect(marker).has_point(point):
			return marker["output"]
	return ""

func _draw_routes(canvas: Node2D) -> void:
	for marker in markers:
		var state: Dictionary = states[marker["output"]]
		var points: PackedVector2Array = marker["route"]
		var active := bool(state["cable_active"])
		var color := Color("70ed9d") if active else Color("385758")
		canvas.draw_polyline(points,Color("142b2b"),6,false)
		for i in range(1,points.size()):
			var a := points[i-1]
			var b := points[i]
			if state["connected"]:
				canvas.draw_line(a,b,color,3,false)
			else:
				var length := a.distance_to(b)
				for step in range(0,int(length),16):
					canvas.draw_line(a.move_toward(b,step),a.move_toward(b,minf(step+7,length)),Color("78908b"),2,false)
		if active:
			var length := 0.0
			for i in range(1,points.size()): length += points[i-1].distance_to(points[i])
			for index in range(3):
				var travel := fmod(anim_time*65+index*length/3,maxf(1,length))
				for i in range(1,points.size()):
					var segment := points[i-1].distance_to(points[i])
					if travel<=segment:
						var at := points[i-1].move_toward(points[i],travel)
						canvas.draw_circle(at,7,Color(0.45,1,0.65,0.16))
						canvas.draw_circle(at,3,Color("eaffc7"))
						break
					travel -= segment
		if marker["kind"]=="pump":
			var at: Vector2 = marker["at"]
			var pipe := PackedVector2Array([at+Vector2(16,18),Vector2(at.x+16,tank_position.y),tank_position])
			canvas.draw_polyline(pipe,Color("294f57"),9,false)
			canvas.draw_polyline(pipe,Color("63bdd0") if active else Color("46747d"),4,false)
			if active:
				var flow := fmod(anim_time*55,at.distance_to(tank_position))
				canvas.draw_circle(pipe[0].move_toward(pipe[1],flow),3,Color("c3f3f6"))

func _draw() -> void:
	var has_pump := false
	for marker in markers:
		var at: Vector2 = marker["at"]
		var state: Dictionary = states[marker["output"]]
		var active := bool(state["running"])
		var color: Color = state["color"]
		if marker["output"]==selected_output:
			draw_rect(Rect2(at-Vector2(36,46),Vector2(72,78)),Color(1,0.86,0.35,0.55+0.3*sin(anim_time*4)),false,2)
		match marker["kind"]:
			"lamp": _draw_lamp(at,active)
			"pump":
				has_pump = true
				draw_texture_rect(MOTOR,Rect2(at-Vector2(24,24),Vector2(48,48)),false)
				_draw_rotor(at+Vector2(0,7),active,8)
				_led(at+Vector2(28,-16),color)
			"mill":
				_draw_contactor(at+Vector2(-12,0),active,color)
				draw_set_transform(at+Vector2(30,-5),anim_time*2 if active else 0)
				draw_texture_rect(GEAR,Rect2(-24,-24,48,48),false)
				draw_set_transform(Vector2.ZERO)
			"contactor", "diesel":
				_draw_contactor(at,active,color)
				if marker["kind"]=="diesel":
					_draw_rotor(at+Vector2(0,-32),active,10)
			"indicator":
				draw_style_box(UI.frame(),Rect2(at-Vector2(30,22),Vector2(60,44)))
				var sensors: Dictionary = context.get("sensors",{})
				_led(at+Vector2(-15,-5),Color("70ed9d") if sensors.get("PERINTAH_UJI",false) else Color("385758"))
				_led(at+Vector2(15,-5),Color("70ed9d") if sensors.get("STATUS_UJI",false) else Color("385758"))
				_led(at+Vector2(0,12),Color("ffcd64") if active else Color("385758"))
			"alarm":
				draw_rect(Rect2(at+Vector2(-20,10),Vector2(40,12)),Color("344c4b"))
				var flash := active and fmod(anim_time,0.8)<0.5
				if flash:
					draw_circle(at,42,Color(1,0.18,0.13,0.16))
					for i in range(4):
						var ray := Vector2.from_angle(i*PI/2+anim_time)*28
						draw_line(at+ray*0.8,at+ray*1.25,Color("ffcd64"),3)
				draw_rect(Rect2(at-Vector2(15,18),Vector2(30,28)),Color("ff7874") if flash else Color("634544"))
				draw_rect(Rect2(at-Vector2(11,14),Vector2(8,7)),Color("ffe9ae") if flash else Color("856764"))
		var caption: String = marker["name"]
		var label_rect := _label_rect(marker)
		draw_style_box(UI.frame(),label_rect)
		draw_string(UI.FONT,label_rect.position+Vector2(8,12),caption,HORIZONTAL_ALIGNMENT_LEFT,156,7,UI.INK)
		draw_string(UI.FONT,label_rect.position+Vector2(8,25),state["status"],HORIZONTAL_ALIGNMENT_LEFT,156,6,Color("43534b"))
		_led(at+Vector2(-30,25),color)
	if has_pump:
		draw_texture_rect(TANK,Rect2(tank_position-Vector2(24,24),Vector2(48,48)),false)
		var fill := clampf(float(context.get("tank_level",25))/100.0,0,1)
		draw_rect(Rect2(tank_position+Vector2(28,-22),Vector2(8,44)),Color("233e4a"))
		draw_rect(Rect2(tank_position+Vector2(29,21-42*fill),Vector2(6,42*fill)),Color("73d5e5"))
		draw_string(UI.FONT,tank_position+Vector2(-42,34),"TANGKI %d%%" % int(fill*100),HORIZONTAL_ALIGNMENT_LEFT,110,7,Color("ffeac2"))

func _draw_lamp(at: Vector2, active: bool) -> void:
	var bulb := at+Vector2(0,-30)
	if active:
		draw_circle(bulb,32,Color(1,0.9,0.42,0.15))
		draw_colored_polygon(PackedVector2Array([bulb,at+Vector2(-26,20),at+Vector2(26,20)]),Color(1,0.9,0.42,0.12))
	draw_rect(Rect2(at+Vector2(-3,-26),Vector2(6,46)),Color("40524c"))
	draw_rect(Rect2(at+Vector2(-9,18),Vector2(18,5)),Color("263e39"))
	draw_rect(Rect2(bulb-Vector2(14,10),Vector2(28,20)),Color("263e39"))
	draw_rect(Rect2(bulb-Vector2(10,6),Vector2(20,12)),Color("ffdf74") if active else Color("60716b"))

func _draw_contactor(at: Vector2, closed: bool, color: Color) -> void:
	draw_style_box(UI.frame(),Rect2(at-Vector2(28,24),Vector2(56,48)))
	draw_circle(at+Vector2(-14,-5),4,Color("2c4442"))
	draw_circle(at+Vector2(14,-5),4,Color("2c4442"))
	draw_line(at+Vector2(-14,-5),at+Vector2(14,-5 if closed else -18),Color("70ed9d") if closed else Color("526760"),4)
	_led(at+Vector2(0,13),color)

func _draw_rotor(at: Vector2, active: bool, radius: float) -> void:
	draw_circle(at,radius+2,Color("314744"))
	for i in range(4):
		var angle: float = i*PI/2+(anim_time*5 if active else 0)
		draw_line(at,at+Vector2.from_angle(angle)*radius,Color("ffcf7a") if active else Color("7f9290"),3)
	draw_circle(at,3,Color("e2e6ce"))

func _led(at: Vector2, color: Color) -> void:
	draw_circle(at,6,Color("203b38"))
	draw_circle(at,4,color)

func _label_rect(marker: Dictionary) -> Rect2:
	var offset: Array = marker.get("label_offset",[-86,34])
	return Rect2(marker["at"]+Vector2(offset[0],offset[1]),Vector2(172,34))

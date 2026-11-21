extends Node2D
class_name VillageWorld

# Full-screen editable 2D Desa Sukamaju world backed by scenes/village_world.tscn
# (13 Godot TileMapLayers using all 3 Kenney packs + editable Marker2D Landmarks & PowerPoles).
# Any tile or Marker2D edited in the Godot 2D Editor automatically updates glows,
# overhead power lines, blackout dimming, camera focus, and clickable zones at runtime!

signal gardu_clicked()
signal zoom_changed(new_zoom: float)

const TOWN_TILEMAP_PATH := "res://Kenney Asset/kenney_tiny-town/Tilemap/tilemap_packed.png"
const CITY_TILEMAP_PATH := "res://Kenney Asset/kenney_tiny-city/Tilemap/tilemap_packed.png"
const FACTORY_TILEMAP_PATH := "res://Kenney Asset/kenney_tiny-factory/Tilemap/tilemap_packed.png"
const GRASS_EXTRA_PATH := "res://asset tambahan/GrassNormalTile.png"
const GRASS_POLOS_PATH := "res://asset tambahan/GrassPolosTile (1).png"
const GROUND_TILESET_PATH := "res://asset tambahan/GroundTileSet.png"
const SMOKE_WHITE_DIR := "res://Kenney Asset/kenney_smoke-particles/PNG/White puff/"
const SMOKE_BLACK_DIR := "res://Kenney Asset/kenney_smoke-particles/PNG/Black smoke/"
const RIVER_SHADER_PATH := "res://shaders/river_water.gdshader"

const CELL_PX := 48.0 # 16px Kenney tile * 3x MapLayers scale
const COLS := 44
const ROWS := 28
const WORLD_W := COLS * CELL_PX # 2112.0
const WORLD_H := ROWS * CELL_PX # 1344.0

const CAM_PAD_TOP := 110.0
const CAM_PAD_BOTTOM := 320.0
const CAM_PAD_SIDE := 80.0

const MIN_ZOOM := 0.58
const MAX_ZOOM := 1.65
const DEFAULT_OVERVIEW_ZOOM := 0.66

# Scene child references (from scenes/village_world.tscn)
var cam: Camera2D
var map_layers: Node2D
var pltmh_layer: TileMapLayer
var plts_layer: TileMapLayer
var pltd_layer: TileMapLayer
var diesel_units_layer: TileMapLayer
var gardu_layer: TileMapLayer
var puskesmas_layer: TileMapLayer
var dusun1_layer: TileMapLayer
var dusun2_layer: TileMapLayer
var dusun3_layer: TileMapLayer
var street_props_layer: TileMapLayer
var water_gear: Sprite2D
var river_water: ColorRect
var river_mat: ShaderMaterial
var water_spray_particles: CPUParticles2D
var water_foam_particles: CPUParticles2D
var cables_overlay: Node2D
var effects_overlay: Node2D

# Auto-detected dynamic glow coordinates & electrical pole/house anchors from the TileMapLayers!
var window_glows: Array[Dictionary] = [] # { "pos": Vector2, "sector": String }
var lamp_glows: Array[Dictionary] = []   # { "pos": Vector2, "sector": String }
var detected_poles: Array[Dictionary] = [] # { "cell": Vector2i, "pos": Vector2 }
var sector_houses: Dictionary = {} # sector -> Array[Vector2] sorted left-to-right

# Reactive simulation state
var sun_factor: float = 0.55
var cloud_cover: float = 0.0
var rain_intensity: float = 0.0
var is_rice_mill_active: bool = false
var is_sahur_surge: bool = false
var pltmh_kw: float = 42.0
var plts_kw: float = 40.0
var diesel_kw: float = 0.0
var diesel_on: bool = false
var shed_d3_on: bool = false
var frequency: float = 50.0
var dusun1_powered: bool = true
var dusun2_powered: bool = true
var dusun3_powered: bool = true
var puskesmas_powered: bool = true
var cascade_stage: int = 0
var is_interactive: bool = false
var is_blackout_banner: bool = false

# Camera focus, zoom & drag-pan state
var cam_target_pos: Vector2 = Vector2(WORLD_W * 0.5, WORLD_H * 0.52)
var cam_target_zoom: float = DEFAULT_OVERVIEW_ZOOM
var shake_trauma: float = 0.0

var is_dragging_cam: bool = false
var drag_moved_enough: bool = false
var drag_start_screen: Vector2 = Vector2.ZERO
var drag_last_screen: Vector2 = Vector2.ZERO
var drag_button: int = -1

# Animation & procedural effects
var anim_time: float = 0.0
var lightning_alpha: float = 0.0
var next_lightning_cd: float = 3.5
var gardu_hovered: bool = false
var gardu_world_rect: Rect2 = Rect2(19.0 * CELL_PX, 10.0 * CELL_PX, 6.0 * CELL_PX, 5.0 * CELL_PX)

var smoke_particles: Array[Dictionary] = []
var spark_particles: Array[Dictionary] = []
var rain_drops: Array[Vector2] = []
var cloud_shadows: Array[Dictionary] = []
var callouts: Array[Dictionary] = []

var white_puff_textures: Array[Texture2D] = []
var black_smoke_textures: Array[Texture2D] = []

var zone_anchors: Dictionary = {}
var pole_anchors: Dictionary = {}


static func load_texture_safe(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res: Resource = load(res_path)
		if res is Texture2D:
			return res
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	push_warning("VillageWorld: Failed to load texture at %s" % res_path)
	return null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	cam = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		cam = Camera2D.new()
		add_child(cam)
	cam.position = Vector2(WORLD_W * 0.5, WORLD_H * 0.52)
	cam.zoom = Vector2(DEFAULT_OVERVIEW_ZOOM, DEFAULT_OVERVIEW_ZOOM)
	cam.limit_left = int(-CAM_PAD_SIDE)
	cam.limit_top = int(-CAM_PAD_TOP)
	cam.limit_right = int(WORLD_W + CAM_PAD_SIDE)
	cam.limit_bottom = int(WORLD_H + CAM_PAD_BOTTOM)
	cam.limit_smoothed = true
	cam.make_current()

	map_layers = get_node_or_null("MapLayers") as Node2D
	if map_layers != null:
		pltmh_layer = map_layers.get_node_or_null("PLTMHLayer") as TileMapLayer
		plts_layer = map_layers.get_node_or_null("PLTSLayer") as TileMapLayer
		pltd_layer = map_layers.get_node_or_null("PLTDLayer") as TileMapLayer
		diesel_units_layer = map_layers.get_node_or_null("DieselUnitsLayer") as TileMapLayer
		gardu_layer = map_layers.get_node_or_null("GarduLayer") as TileMapLayer
		puskesmas_layer = map_layers.get_node_or_null("PuskesmasLayer") as TileMapLayer
		dusun1_layer = map_layers.get_node_or_null("Dusun1Layer") as TileMapLayer
		dusun2_layer = map_layers.get_node_or_null("Dusun2Layer") as TileMapLayer
		dusun3_layer = map_layers.get_node_or_null("Dusun3Layer") as TileMapLayer
		street_props_layer = map_layers.get_node_or_null("StreetPropsLayer") as TileMapLayer
		_ensure_tileset_textures_loaded()
		_setup_layer_z_order()
		_scan_dynamic_lights_from_tilemaps()
		_scan_poles_and_houses_from_tilemaps()

	water_gear = get_node_or_null("WaterGear") as Sprite2D
	if water_gear != null and water_gear.texture == null:
		water_gear.texture = load_texture_safe(FACTORY_TILEMAP_PATH)

	_setup_river_water()
	_load_markers_from_scene()

	# CablesOverlay sits at z_index = 1: ABOVE ground/roads (0) and BEHIND all buildings, trees & poles (2)!
	cables_overlay = Node2D.new()
	cables_overlay.name = "CablesOverlay"
	cables_overlay.z_index = 1
	add_child(cables_overlay)
	cables_overlay.draw.connect(_draw_cables)

	effects_overlay = get_node_or_null("EffectsOverlay") as Node2D
	if effects_overlay == null:
		effects_overlay = Node2D.new()
		effects_overlay.z_index = 10
		add_child(effects_overlay)
	effects_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	effects_overlay.draw.connect(_draw_effects)

	_load_smoke_textures()

	for i in range(10):
		cloud_shadows.append({
			"x": float(i) * 260.0 - 180.0,
			"y": 95.0 + float(i % 4) * 290.0 + float((i * 37) % 60),
			"w": 260.0 + float(i % 3) * 85.0,
			"h": 145.0 + float(i % 3) * 35.0,
			"speed": 34.0 + float(i * 5),
			"p1": i % 8,
			"p2": (i + 3) % 8,
			"p3": (i + 5) % 8,
			"rot": float(i % 5 - 2) * 0.08
		})

	for i in range(140):
		rain_drops.append(Vector2(randf() * WORLD_W, randf() * WORLD_H))

	# Enable interactive zoom & pan automatically when previewing village_world.tscn standalone (F6)!
	if get_parent() == get_tree().root:
		is_interactive = true


func _setup_river_water() -> void:
	# Pure Godot Engine river water: GPU CanvasItem shader + CPUParticles2D splash & foam!
	river_water = get_node_or_null("RiverWater") as ColorRect
	if river_water == null:
		river_water = ColorRect.new()
		river_water.name = "RiverWater"
		river_water.z_index = 1
		river_water.position = Vector2.ZERO
		river_water.size = Vector2(178.0, WORLD_H)
		river_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(river_water)
	else:
		river_water.z_index = 1
		river_water.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if river_water.material is ShaderMaterial:
		river_mat = river_water.material as ShaderMaterial
	else:
		var sh: Resource = load(RIVER_SHADER_PATH)
		if sh is Shader:
			river_mat = ShaderMaterial.new()
			river_mat.shader = sh as Shader
			river_water.material = river_mat

	var gear_p: Vector2 = water_gear.position if water_gear != null else Vector2(148.8, 600.0)
	if river_mat != null:
		river_mat.set_shader_parameter("river_size", river_water.size)
		river_mat.set_shader_parameter("gear_world_pos", gear_p)

	# 1. Crisp pixel-art water droplet spray flung off the spinning WaterGear!
	var spray_grad := Gradient.new()
	spray_grad.set_color(0, Color(0.88, 0.98, 1.0, 0.95))
	spray_grad.set_color(1, Color(0.55, 0.85, 1.0, 0.0))

	water_spray_particles = CPUParticles2D.new()
	water_spray_particles.name = "WaterSprayParticles"
	water_spray_particles.z_index = 12
	water_spray_particles.position = gear_p + Vector2(-4.0, 14.0)
	water_spray_particles.amount = 10
	water_spray_particles.lifetime = 0.55
	water_spray_particles.preprocess = 0.5
	water_spray_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	water_spray_particles.emission_sphere_radius = 14.0
	water_spray_particles.direction = Vector2(-0.45, 0.85)
	water_spray_particles.spread = 45.0
	water_spray_particles.gravity = Vector2(0.0, 110.0)
	water_spray_particles.initial_velocity_min = 26.0
	water_spray_particles.initial_velocity_max = 56.0
	water_spray_particles.scale_amount_min = 3.0
	water_spray_particles.scale_amount_max = 4.0
	water_spray_particles.color_ramp = spray_grad
	add_child(water_spray_particles)

	# 2. Gentle downstream pixel foam dots drifting south with the river current!
	var foam_grad := Gradient.new()
	foam_grad.set_color(0, Color(0.76, 0.94, 1.0, 0.65))
	foam_grad.set_color(1, Color(0.36, 0.72, 0.90, 0.0))

	water_foam_particles = CPUParticles2D.new()
	water_foam_particles.name = "WaterFoamParticles"
	water_foam_particles.z_index = 4
	water_foam_particles.position = gear_p + Vector2(-6.0, 18.0)
	water_foam_particles.amount = 12
	water_foam_particles.lifetime = 1.4
	water_foam_particles.preprocess = 1.0
	water_foam_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	water_foam_particles.emission_rect_extents = Vector2(14.0, 4.0)
	water_foam_particles.direction = Vector2(0.0, 1.0)
	water_foam_particles.spread = 14.0
	water_foam_particles.gravity = Vector2(0.0, 18.0)
	water_foam_particles.initial_velocity_min = 34.0
	water_foam_particles.initial_velocity_max = 54.0
	water_foam_particles.scale_amount_min = 3.0
	water_foam_particles.scale_amount_max = 4.5
	water_foam_particles.color_ramp = foam_grad
	add_child(water_foam_particles)


func _load_smoke_textures() -> void:
	white_puff_textures.clear()
	black_smoke_textures.clear()
	var indices: Array[int] = [0, 3, 6, 9, 12, 15, 18, 21]
	for idx in indices:
		var num: String = "%02d" % idx
		var wt: Texture2D = load_texture_safe(SMOKE_WHITE_DIR + "whitePuff" + num + ".png")
		if wt != null:
			white_puff_textures.append(wt)
		var bt: Texture2D = load_texture_safe(SMOKE_BLACK_DIR + "blackSmoke" + num + ".png")
		if bt != null:
			black_smoke_textures.append(bt)


func _ensure_tileset_textures_loaded() -> void:
	# Bulletproof fallback: if Godot hasn't imported the PNGs into .ctex yet,
	# patch the TileSet's 3 atlas sources directly via ImageTexture so all TileMapLayers render!
	var sample_layer: TileMapLayer = map_layers.get_node_or_null("GroundLayer") as TileMapLayer
	if sample_layer == null or sample_layer.tile_set == null:
		return
	var ts: TileSet = sample_layer.tile_set
	var paths: Array[String] = [TOWN_TILEMAP_PATH, CITY_TILEMAP_PATH, FACTORY_TILEMAP_PATH, GRASS_EXTRA_PATH, GRASS_POLOS_PATH, GROUND_TILESET_PATH]
	for src_id in range(paths.size()):
		if ts.has_source(src_id):
			var src: TileSetSource = ts.get_source(src_id)
			if src is TileSetAtlasSource:
				var atlas_src: TileSetAtlasSource = src
				if atlas_src.texture == null:
					atlas_src.texture = load_texture_safe(paths[src_id])


func _load_markers_from_scene() -> void:
	# Fallback defaults (overridden by any Marker2D positioned in scenes/village_world.tscn!)
	zone_anchors = {
		"overview": Vector2(WORLD_W * 0.5, WORLD_H * 0.52),
		"pltmh": Vector2(6.5 * CELL_PX, 11.8 * CELL_PX),
		"plts": Vector2(11.0 * CELL_PX, 6.0 * CELL_PX),
		"pltd": Vector2(10.5 * CELL_PX, 21.0 * CELL_PX),
		"gardu": Vector2(23.0 * CELL_PX, 10.0 * CELL_PX),
		"puskesmas": Vector2(23.0 * CELL_PX, 19.5 * CELL_PX),
		"dusun1": Vector2(34.5 * CELL_PX, 4.5 * CELL_PX),
		"masjid": Vector2(40.5 * CELL_PX, 4.5 * CELL_PX),
		"dusun2": Vector2(36.0 * CELL_PX, 11.0 * CELL_PX),
		"dusun3": Vector2(36.0 * CELL_PX, 19.5 * CELL_PX)
	}

	var lm_root: Node = get_node_or_null("Landmarks")
	if lm_root != null:
		var map_names: Dictionary = {
			"PLTMH": "pltmh", "PLTS": "plts", "PLTD": "pltd", "Gardu": "gardu",
			"Puskesmas": "puskesmas", "Dusun1": "dusun1", "Masjid": "masjid",
			"Dusun2": "dusun2", "Dusun3": "dusun3"
		}
		for node_name in map_names.keys():
			var m: Marker2D = lm_root.get_node_or_null(String(node_name)) as Marker2D
			if m != null:
				zone_anchors[String(map_names[node_name])] = m.position

	# Center Gardu clickable rect around the editable Gardu Marker2D!
	var gp: Vector2 = zone_anchors["gardu"]
	gardu_world_rect = Rect2(gp.x - 3.0 * CELL_PX, gp.y - 3.0 * CELL_PX, 6.0 * CELL_PX, 6.0 * CELL_PX)

	pole_anchors = {
		"nw": Vector2(16.5 * CELL_PX, 5.35 * CELL_PX),
		"w":  Vector2(16.5 * CELL_PX, 11.35 * CELL_PX),
		"sw": Vector2(16.5 * CELL_PX, 19.35 * CELL_PX),
		"ne": Vector2(29.5 * CELL_PX, 5.35 * CELL_PX),
		"e":  Vector2(29.5 * CELL_PX, 11.35 * CELL_PX),
		"se": Vector2(29.5 * CELL_PX, 19.35 * CELL_PX)
	}
	var pp_root: Node = get_node_or_null("PowerPoles")
	if pp_root != null:
		var p_names: Dictionary = {
			"PoleNW": "nw", "PoleW": "w", "PoleSW": "sw",
			"PoleNE": "ne", "PoleE": "e", "PoleSE": "se"
		}
		for p_node in p_names.keys():
			var pm: Marker2D = pp_root.get_node_or_null(String(p_node)) as Marker2D
			if pm != null:
				pole_anchors[String(p_names[p_node])] = pm.position


func _setup_layer_z_order() -> void:
	# Keep ground & roads at z_index = 0, power cables at z_index = 1,
	# and all buildings, nature & electrical poles at z_index = 2 so cables tuck cleanly BEHIND buildings!
	if map_layers == null:
		return
	for child in map_layers.get_children():
		if child is TileMapLayer:
			var tml: TileMapLayer = child
			if tml.name == "GroundLayer" or tml.name == "RoadLayer":
				tml.z_index = 0
			else:
				tml.z_index = 2


func _scan_poles_and_houses_from_tilemaps() -> void:
	# Auto-detect every wooden electrical pole (Tiny City atlas 3,7) & house gable roof across all TileMapLayers!
	detected_poles.clear()
	sector_houses.clear()
	if map_layers == null:
		return

	for child in map_layers.get_children():
		if child is TileMapLayer:
			var tml: TileMapLayer = child
			for cell in tml.get_used_cells():
				var sid: int = tml.get_cell_source_id(cell)
				var ac: Vector2i = tml.get_cell_atlas_coords(cell)
				# Wooden power pole top crossbar (Tiny City source 1, atlas 3,7 -> crossbar sits at row 7.5/16 = 0.47)
				if sid == 1 and ac == Vector2i(3, 7):
					detected_poles.append({
						"cell": cell,
						"pos": Vector2((float(cell.x) + 0.5) * CELL_PX, (float(cell.y) + 0.47) * CELL_PX)
					})

	# Scan house center gable roof tiles (Tiny Town source 0, atlas 3,5 blue or 7,5 red) per sector!
	var house_layers: Array[Dictionary] = [
		{"layer": pltmh_layer, "sector": "pltmh"},
		{"layer": dusun1_layer, "sector": "dusun1"},
		{"layer": dusun2_layer, "sector": "dusun2"},
		{"layer": dusun3_layer, "sector": "dusun3"}
	]
	for entry in house_layers:
		var layer: TileMapLayer = entry["layer"]
		var sec: String = String(entry["sector"])
		var found: Array[Vector2] = []
		if layer != null:
			for cell in layer.get_used_cells():
				var sid: int = layer.get_cell_source_id(cell)
				var ac: Vector2i = layer.get_cell_atlas_coords(cell)
				if sid == 0 and (ac == Vector2i(3, 5) or ac == Vector2i(7, 5)):
					found.append(Vector2((float(cell.x) + 0.5) * CELL_PX, (float(cell.y) + 0.4) * CELL_PX))
		found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		sector_houses[sec] = found


func _nearest_pole(target_cell: Vector2, fallback: Vector2, max_dist_cells: float = 5.0) -> Vector2:
	var best_pos: Vector2 = fallback
	var best_d: float = max_dist_cells
	for p in detected_poles:
		var c: Vector2i = p["cell"]
		var d: float = Vector2(float(c.x), float(c.y)).distance_to(target_cell)
		if d < best_d:
			best_d = d
			best_pos = p["pos"]
	return best_pos


func _scan_dynamic_lights_from_tilemaps() -> void:
	# Automatically detect every house/building window & streetlamp painted in the TileMapLayers!
	window_glows.clear()
	lamp_glows.clear()

	var sector_layers: Array[Dictionary] = [
		{"layer": pltmh_layer, "sector": "pltmh"},
		{"layer": pltd_layer, "sector": "pltd"},
		{"layer": gardu_layer, "sector": "gardu"},
		{"layer": dusun1_layer, "sector": "dusun1"},
		{"layer": dusun2_layer, "sector": "dusun2"},
		{"layer": dusun3_layer, "sector": "dusun3"},
		{"layer": puskesmas_layer, "sector": "puskesmas"}
	]
	for entry in sector_layers:
		var layer: TileMapLayer = entry["layer"]
		var sec: String = String(entry["sector"])
		if layer == null:
			continue
		for cell in layer.get_used_cells():
			var sid: int = layer.get_cell_source_id(cell)
			var ac: Vector2i = layer.get_cell_atlas_coords(cell)
			# Tiny Town windows: (0,7) & (4,7); Tiny City windows: red-wall (4,3) & brown-wall (10,3)
			var is_town_win: bool = (sid == 0 and (ac == Vector2i(0, 7) or ac == Vector2i(4, 7)))
			var is_city_win: bool = (sid == 1 and (ac == Vector2i(4, 3) or ac == Vector2i(10, 3)))
			if is_town_win or is_city_win:
				window_glows.append({
					"pos": Vector2((float(cell.x) + 0.5) * CELL_PX, (float(cell.y) + 0.48) * CELL_PX),
					"sector": sec,
					"cool": (sid == 1 and ac == Vector2i(4, 3))
				})

	if street_props_layer != null:
		for cell in street_props_layer.get_used_cells():
			var sid: int = street_props_layer.get_cell_source_id(cell)
			var ac: Vector2i = street_props_layer.get_cell_atlas_coords(cell)
			# Tiny City streetlamp top: tile 86 -> (2, 7)
			if sid == 1 and ac == Vector2i(2, 7):
				var sec: String = "dusun1"
				if cell.x >= 19 and cell.x <= 26 and cell.y >= 15:
					sec = "puskesmas"
				elif cell.y >= 15 and cell.x >= 29:
					sec = "dusun3"
				elif cell.y >= 9 and cell.y <= 14 and cell.x >= 29:
					sec = "dusun2"
				lamp_glows.append({
					"pos": Vector2((float(cell.x) + 0.5) * CELL_PX, (float(cell.y) + 0.45) * CELL_PX),
					"sector": sec
				})


func set_title_ambience() -> void:
	sun_factor = 0.24
	cloud_cover = 0.14
	rain_intensity = 0.0
	is_rice_mill_active = false
	is_sahur_surge = false
	diesel_on = true
	shed_d3_on = false
	dusun1_powered = true
	dusun2_powered = true
	dusun3_powered = true
	puskesmas_powered = true
	cascade_stage = 0
	is_blackout_banner = false
	is_interactive = false
	is_dragging_cam = false
	focus_zone("overview", DEFAULT_OVERVIEW_ZOOM)


func focus_zone(zone_name: String, target_zoom: float = DEFAULT_OVERVIEW_ZOOM) -> void:
	if zone_anchors.has(zone_name):
		var p: Vector2 = zone_anchors[zone_name]
		cam_target_pos = p
	else:
		cam_target_pos = Vector2(WORLD_W * 0.5, WORLD_H * 0.52)
	cam_target_zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom_changed.emit(cam_target_zoom)


func reset_camera_view() -> void:
	focus_zone("overview", DEFAULT_OVERVIEW_ZOOM)


func zoom_by_step(delta_zoom: float) -> void:
	var new_z: float = clampf(cam_target_zoom + delta_zoom, MIN_ZOOM, MAX_ZOOM)
	if not is_equal_approx(new_z, cam_target_zoom):
		cam_target_zoom = new_z
		zoom_changed.emit(cam_target_zoom)


func _zoom_toward_mouse(factor: float) -> void:
	var old_z: float = cam_target_zoom
	var new_z: float = clampf(old_z * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_z, old_z):
		return
	var mouse_world_before: Vector2 = get_global_mouse_position()
	cam_target_zoom = new_z
	if factor > 1.0:
		var pull: float = 1.0 - (old_z / new_z)
		cam_target_pos = cam_target_pos.lerp(mouse_world_before, clampf(pull * 0.75, 0.0, 0.5))
	zoom_changed.emit(cam_target_zoom)


func get_current_zoom() -> float:
	return cam_target_zoom


func add_shake(amount: float) -> void:
	shake_trauma = clampf(shake_trauma + amount, 0.0, 1.0)


func spawn_callout(zone_name: String, text: String, col: Color) -> void:
	var anchor: Vector2 = zone_anchors.get(zone_name, Vector2(WORLD_W * 0.5, WORLD_H * 0.45))
	callouts.append({
		"pos": anchor + Vector2(0.0, -48.0),
		"text": text,
		"color": col,
		"age": 0.0,
		"duration": 2.5
	})


func spawn_sparks(zone_name: String, count: int = 16) -> void:
	var anchor: Vector2 = zone_anchors.get(zone_name, Vector2(WORLD_W * 0.5, WORLD_H * 0.5))
	for i in range(count):
		var ang: float = randf() * TAU
		var spd: float = randf_range(65.0, 210.0)
		spark_particles.append({
			"pos": anchor + Vector2(randf_range(-24.0, 24.0), randf_range(-18.0, 18.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 50.0),
			"age": 0.0,
			"max_age": randf_range(0.35, 0.75)
		})


func update_from_sim(state: Dictionary) -> void:
	var prev_diesel: bool = diesel_on
	var prev_cascade: int = cascade_stage

	sun_factor = float(state.get("sun_factor", 1.0))
	cloud_cover = float(state.get("cloud_cover", 0.0))
	rain_intensity = float(state.get("rain_intensity", 0.0))
	is_rice_mill_active = bool(state.get("is_rice_mill_active", false))
	is_sahur_surge = bool(state.get("is_sahur_surge", false))
	pltmh_kw = float(state.get("pltmh_kw", 42.0))
	plts_kw = float(state.get("plts_kw", 0.0))
	diesel_kw = float(state.get("diesel_kw", 0.0))
	diesel_on = bool(state.get("diesel_on", false))
	shed_d3_on = bool(state.get("shed_d3_on", false))
	frequency = float(state.get("frequency", 50.0))
	dusun1_powered = bool(state.get("dusun1_powered", true))
	dusun2_powered = bool(state.get("dusun2_powered", true))
	dusun3_powered = bool(state.get("dusun3_powered", true))
	puskesmas_powered = bool(state.get("puskesmas_powered", true))
	cascade_stage = int(state.get("cascade_stage", 0))

	if diesel_on and not prev_diesel:
		spawn_sparks("pltd", 14)
		add_shake(0.18)

	if cascade_stage > prev_cascade:
		add_shake(0.35 + float(cascade_stage) * 0.2)
		if cascade_stage == 1:
			spawn_sparks("dusun3", 16)
		elif cascade_stage == 2:
			spawn_sparks("dusun2", 18)
		elif cascade_stage >= 3:
			spawn_sparks("gardu", 30)
			spawn_sparks("pltd", 24)
			is_blackout_banner = true
	elif cascade_stage == 0:
		is_blackout_banner = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_interactive:
		gardu_hovered = false
		is_dragging_cam = false
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_toward_mouse(1.14)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_toward_mouse(1.0 / 1.14)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_dragging_cam = true
				drag_button = mb.button_index
				drag_moved_enough = false
				drag_start_screen = mb.position
				drag_last_screen = mb.position
			else:
				if is_dragging_cam and mb.button_index == drag_button:
					var was_click: bool = (not drag_moved_enough) and (drag_button == MOUSE_BUTTON_LEFT)
					is_dragging_cam = false
					drag_button = -1
					if was_click:
						var world_m: Vector2 = get_global_mouse_position()
						if gardu_world_rect.has_point(world_m):
							gardu_clicked.emit()
							get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if is_dragging_cam:
			var delta_scr: Vector2 = mm.position - drag_last_screen
			drag_last_screen = mm.position
			if mm.position.distance_to(drag_start_screen) > 6.0:
				drag_moved_enough = true
			if drag_moved_enough:
				cam_target_pos -= delta_scr / maxf(0.25, cam.zoom.x)
				get_viewport().set_input_as_handled()
		else:
			var world_m: Vector2 = get_global_mouse_position()
			gardu_hovered = gardu_world_rect.has_point(world_m)


func _process(delta: float) -> void:
	anim_time += delta

	if is_dragging_cam and (drag_button < 0 or not Input.is_mouse_button_pressed(drag_button)):
		is_dragging_cam = false
		drag_button = -1

	if is_interactive:
		var pan_dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan_dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan_dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan_dir.y += 1.0
		if pan_dir != Vector2.ZERO:
			var pan_spd: float = 560.0 / maxf(0.5, cam.zoom.x)
			cam_target_pos += pan_dir.normalized() * pan_spd * delta

	var target_z := Vector2(cam_target_zoom, cam_target_zoom)
	cam.zoom = cam.zoom.lerp(target_z, clampf(delta * 8.5, 0.0, 1.0))

	var vp_size: Vector2 = get_viewport_rect().size
	var half_w: float = (vp_size.x * 0.5) / maxf(0.25, cam.zoom.x)
	var half_h: float = (vp_size.y * 0.5) / maxf(0.25, cam.zoom.y)
	var min_x: float = minf(-CAM_PAD_SIDE + half_w, WORLD_W * 0.5)
	var max_x: float = maxf(WORLD_W + CAM_PAD_SIDE - half_w, WORLD_W * 0.5)
	var min_y: float = minf(-CAM_PAD_TOP + half_h, WORLD_H * 0.5)
	var max_y: float = maxf(WORLD_H + CAM_PAD_BOTTOM - half_h, WORLD_H * 0.5)
	cam_target_pos.x = clampf(cam_target_pos.x, min_x, max_x)
	cam_target_pos.y = clampf(cam_target_pos.y, min_y, max_y)

	var pos_lerp: float = 16.0 if is_dragging_cam else 6.0
	cam.position = cam.position.lerp(cam_target_pos, clampf(delta * pos_lerp, 0.0, 1.0))

	var shake_off := Vector2.ZERO
	if shake_trauma > 0.001:
		var mag: float = shake_trauma * shake_trauma * 20.0
		shake_off = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
		shake_trauma = maxf(0.0, shake_trauma - delta * 1.4)
	elif frequency > 0.1 and (frequency < 49.55 or frequency > 50.45):
		shake_off = Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
	cam.offset = shake_off

	# Update dynamic TileMapLayer lighting, blackout dimming, spinning water gear & diesel vibration!
	var env_tint: Color = _compute_env_tint()
	if map_layers != null:
		map_layers.modulate = env_tint
	if water_gear != null:
		water_gear.rotation += delta * (2.2 + rain_intensity * 0.9)
		water_gear.modulate = env_tint
	if river_mat != null:
		var flow_spd: float = clampf(0.85 + (pltmh_kw / 42.0) * 0.35 + rain_intensity * 0.65, 0.75, 2.2)
		river_mat.set_shader_parameter("env_tint", env_tint)
		river_mat.set_shader_parameter("sun_factor", sun_factor)
		river_mat.set_shader_parameter("rain_intensity", rain_intensity)
		river_mat.set_shader_parameter("flow_speed", flow_spd)
		river_mat.set_shader_parameter("lightning_flash", lightning_alpha)
		if water_gear != null:
			river_mat.set_shader_parameter("gear_world_pos", water_gear.position)
	if water_spray_particles != null:
		water_spray_particles.modulate = env_tint.lerp(Color.WHITE, 0.25)
		if water_gear != null:
			water_spray_particles.position = water_gear.position + Vector2(-4.0, 14.0)
	if water_foam_particles != null:
		water_foam_particles.modulate = env_tint.lerp(Color.WHITE, 0.22)
		if water_gear != null:
			water_foam_particles.position = water_gear.position + Vector2(-8.0, 20.0)
	if plts_layer != null:
		plts_layer.modulate = Color(0.84, 0.98, 1.18) if plts_kw >= 8.0 else Color(0.62, 0.72, 0.86)
	if diesel_units_layer != null:
		if diesel_on:
			diesel_units_layer.position = Vector2(sin(anim_time * 42.0) * 0.65, cos(anim_time * 36.0) * 0.45)
			diesel_units_layer.modulate = Color(1.22, 1.16, 1.05)
		else:
			diesel_units_layer.position = Vector2.ZERO
			diesel_units_layer.modulate = Color.WHITE
	if gardu_layer != null:
		gardu_layer.modulate = Color(1.24, 1.24, 1.24) if (is_interactive and gardu_hovered) else Color.WHITE
	if puskesmas_layer != null:
		puskesmas_layer.modulate = Color.WHITE if puskesmas_powered else Color(0.32, 0.32, 0.40)
	if dusun1_layer != null:
		dusun1_layer.modulate = Color.WHITE if dusun1_powered else Color(0.32, 0.32, 0.40)
	if dusun2_layer != null:
		dusun2_layer.modulate = Color.WHITE if dusun2_powered else Color(0.32, 0.32, 0.40)
	if dusun3_layer != null:
		dusun3_layer.modulate = Color.WHITE if dusun3_powered else Color(0.28, 0.28, 0.36)

	# Clouds drift across village
	var cloud_spd_mult: float = 1.9 if cloud_cover >= 0.45 else 0.55
	for c in cloud_shadows:
		var cx: float = float(c["x"]) + float(c["speed"]) * delta * cloud_spd_mult
		if cx > WORLD_W + 280.0:
			cx = -float(c["w"]) - 160.0
		c["x"] = cx

	# Diesel & blackout smoke plumes (Kenney Smoke Particles!)
	if diesel_on:
		if randf() < delta * 12.0:
			var pltd_p: Vector2 = zone_anchors["pltd"]
			var side_x: float = randf_range(-105.0, 105.0)
			smoke_particles.append({
				"pos": pltd_p + Vector2(side_x, randf_range(-88.0, -54.0)),
				"age": 0.0,
				"max_age": randf_range(1.7, 2.3),
				"drift": randf_range(-18.0, 26.0),
				"rot": randf() * TAU,
				"rot_spd": randf_range(-0.85, 0.85),
				"tex_idx": randi() % 8,
				"dark": cascade_stage >= 2 or (frequency > 0.1 and frequency < 49.65)
			})
	if cascade_stage >= 3:
		if randf() < delta * 7.0:
			var g_p: Vector2 = zone_anchors["gardu"]
			smoke_particles.append({
				"pos": g_p + Vector2(randf_range(-56.0, 56.0), randf_range(-52.0, -24.0)),
				"age": 0.0,
				"max_age": randf_range(1.8, 2.4),
				"drift": randf_range(-20.0, 20.0),
				"rot": randf() * TAU,
				"rot_spd": randf_range(-0.7, 0.7),
				"tex_idx": randi() % 8,
				"dark": true
			})

	for i in range(smoke_particles.size() - 1, -1, -1):
		var sp: Dictionary = smoke_particles[i]
		var age: float = float(sp["age"]) + delta
		var max_age: float = float(sp.get("max_age", 2.0))
		var pos: Vector2 = sp["pos"]
		var drift: float = float(sp["drift"])
		var rot: float = float(sp.get("rot", 0.0)) + float(sp.get("rot_spd", 0.0)) * delta
		pos.y -= delta * 48.0
		pos.x += drift * delta
		sp["age"] = age
		sp["pos"] = pos
		sp["rot"] = rot
		if age >= max_age:
			smoke_particles.remove_at(i)

	# Electrical spark bursts
	for i in range(spark_particles.size() - 1, -1, -1):
		var sk: Dictionary = spark_particles[i]
		var age: float = float(sk["age"]) + delta
		var max_age: float = float(sk["max_age"])
		var pos: Vector2 = sk["pos"]
		var vel: Vector2 = sk["vel"]
		vel.y += 280.0 * delta
		pos += vel * delta
		sk["age"] = age
		sk["pos"] = pos
		sk["vel"] = vel
		if age >= max_age:
			spark_particles.remove_at(i)

	# Rain & Lightning
	if rain_intensity > 0.1:
		for i in range(rain_drops.size()):
			var rd: Vector2 = rain_drops[i]
			rd.x -= 180.0 * delta
			rd.y += 560.0 * delta
			if rd.y > WORLD_H:
				rd.y = -20.0
				rd.x = randf() * (WORLD_W + 260.0)
			rain_drops[i] = rd

		next_lightning_cd -= delta
		if next_lightning_cd <= 0.0:
			lightning_alpha = 0.55
			next_lightning_cd = randf_range(3.8, 7.2)
	if lightning_alpha > 0.0:
		lightning_alpha = maxf(0.0, lightning_alpha - delta * 2.2)

	# Floating world callouts
	for i in range(callouts.size() - 1, -1, -1):
		var co: Dictionary = callouts[i]
		var age: float = float(co["age"]) + delta
		var dur: float = float(co["duration"])
		var pos: Vector2 = co["pos"]
		pos.y -= delta * 26.0
		co["age"] = age
		co["pos"] = pos
		if age >= dur:
			callouts.remove_at(i)

	queue_redraw()
	if cables_overlay != null:
		cables_overlay.queue_redraw()
	if effects_overlay != null:
		effects_overlay.queue_redraw()


func _compute_env_tint() -> Color:
	var day_col := Color(1.0, 1.0, 0.98)
	var dusk_col := Color(0.95, 0.68, 0.55)
	var night_col := Color(0.32, 0.39, 0.64)
	if is_sahur_surge:
		night_col = Color(0.36, 0.40, 0.68)

	var base_col := day_col
	if sun_factor >= 0.55:
		var t: float = clampf((sun_factor - 0.55) / 0.45, 0.0, 1.0)
		base_col = dusk_col.lerp(day_col, t)
	else:
		var t: float = clampf(sun_factor / 0.55, 0.0, 1.0)
		base_col = night_col.lerp(dusk_col, t)

	if cloud_cover > 0.25:
		var ov_col := Color(0.55, 0.62, 0.72)
		base_col = base_col.lerp(ov_col * base_col.v, cloud_cover * 0.42)

	if lightning_alpha > 0.01:
		base_col = base_col.lerp(Color(1.0, 1.0, 1.0), lightning_alpha * 0.75)

	return base_col


func _draw() -> void:
	# Background fill behind MapLayers for camera pan headroom (matches GrassPolosTile RGB!)
	var env_tint: Color = _compute_env_tint()
	var bg_grass := Color(0.369, 0.569, 0.298) * env_tint
	draw_rect(Rect2(-CAM_PAD_SIDE - 400.0, -CAM_PAD_TOP - 400.0, WORLD_W + CAM_PAD_SIDE * 2.0 + 800.0, WORLD_H + CAM_PAD_TOP + CAM_PAD_BOTTOM + 800.0), bg_grass, true)


func _is_sector_powered(sec: String) -> bool:
	match sec:
		"dusun1": return dusun1_powered
		"dusun2": return dusun2_powered
		"dusun3": return dusun3_powered
		"puskesmas": return puskesmas_powered
		"gardu": return cascade_stage < 3
		"pltd": return diesel_on or cascade_stage < 3
		_: return true


func _draw_cables() -> void:
	# Drawn on CablesOverlay (z_index = 1): ABOVE ground/roads (0) and BEHIND all buildings, trees & poles (2)!
	if cables_overlay == null:
		return
	var cv: Node2D = cables_overlay

	# Subtle Gardu status aura behind the Gardu Induk building (never blocks the doors!)
	var core_pos: Vector2 = zone_anchors["gardu"]
	var grid_ok: bool = (cascade_stage == 0 and frequency >= 49.50 and frequency <= 50.50)
	var core_col := Color(0.25, 1.0, 0.60) if grid_ok else Color(1.0, 0.25, 0.25)
	var gardu_center := core_pos + Vector2(0.0, -32.0)
	var ring_r: float = 96.0 + 6.0 * sin(anim_time * 4.5)
	cv.draw_circle(gardu_center, ring_r, Color(core_col.r, core_col.g, core_col.b, 0.14))

	# Snap automatically to the exact wooden electrical poles the user placed in StreetPropsLayer!
	var p_plts: Vector2    = _nearest_pole(Vector2(14.0, 2.0),  pole_anchors["nw"])
	var p_pltmh: Vector2   = _nearest_pole(Vector2(11.0, 11.0), Vector2(11.5 * CELL_PX, 11.47 * CELL_PX))
	var p_w: Vector2       = _nearest_pole(Vector2(16.0, 11.0), pole_anchors["w"])
	var p_sw: Vector2      = _nearest_pole(Vector2(16.0, 19.0), pole_anchors["sw"])
	var p_gardu_w: Vector2 = _nearest_pole(Vector2(20.0, 7.0),  core_pos + Vector2(-120.0, -96.0))
	var p_gardu_e: Vector2 = _nearest_pole(Vector2(25.0, 7.0),  core_pos + Vector2(120.0, -96.0))
	var p_ne: Vector2      = _nearest_pole(Vector2(29.0, 5.0),  pole_anchors["ne"])
	var p_e: Vector2       = _nearest_pole(Vector2(29.0, 11.0), pole_anchors["e"])
	var p_se: Vector2      = _nearest_pole(Vector2(29.0, 19.0), pole_anchors["se"])

	# Building roof attachment anchors (tuck cleanly behind the buildings!)
	var gardu_in: Vector2  = core_pos + Vector2(-52.0, -72.0)
	var gardu_out: Vector2 = core_pos + Vector2(52.0, -72.0)
	var gardu_bot: Vector2 = core_pos + Vector2(0.0, 24.0)

	var plts_anchor: Vector2 = zone_anchors["plts"] + Vector2(104.0, -76.0)
	var pltmh_houses: Array = sector_houses.get("pltmh", [])
	var pltmh_anchor: Vector2 = pltmh_houses[0] if pltmh_houses.size() > 0 else zone_anchors["pltmh"]
	var pltd_anchor: Vector2 = zone_anchors["pltd"] + Vector2(60.0, -56.0)
	var pusk_anchor: Vector2 = zone_anchors["puskesmas"] + Vector2(0.0, -72.0)

	var col_solar := Color(0.45, 0.95, 1.0)
	var col_hydro := Color(0.28, 0.85, 1.0)
	var col_diesel := Color(1.0, 0.78, 0.28)
	var col_dist := Color(0.28, 1.0, 0.62)

	# --- GENERATION FEEDERS (West -> Gardu West Pole -> behind Gardu roof) ---
	# 1. PLTS Solar -> PLTS Pole (14,2) -> Gardu West Pole (20,7) -> behind Gardu
	_draw_catenary_line(cv, plts_anchor, p_plts, plts_kw > 4.0, col_solar)
	_draw_catenary_line(cv, p_plts, p_gardu_w + Vector2(-6.0, 0.0), plts_kw > 4.0, col_solar)
	_draw_catenary_line(cv, p_gardu_w, gardu_in, plts_kw > 4.0, col_solar)

	# 2. PLTMH Hydro -> Relay Pole (11,11) -> West Pole (16,11) -> Gardu West Pole (20,7) -> behind Gardu
	_draw_catenary_line(cv, pltmh_anchor, p_pltmh, pltmh_kw > 1.0, col_hydro)
	_draw_catenary_line(cv, p_pltmh, p_w + Vector2(-6.0, 0.0), pltmh_kw > 1.0, col_hydro)
	_draw_catenary_line(cv, p_w + Vector2(-6.0, 0.0), p_gardu_w + Vector2(0.0, 0.0), pltmh_kw > 1.0, col_hydro)
	_draw_catenary_line(cv, p_gardu_w, gardu_in, pltmh_kw > 1.0, col_hydro)

	# 3. PLTD Diesel -> SW Pole (16,19) -> West Pole (16,11) -> Gardu West Pole (20,7) -> behind Gardu
	_draw_catenary_line(cv, pltd_anchor, p_sw, diesel_on, col_diesel)
	_draw_catenary_line(cv, p_sw + Vector2(6.0, 0.0), p_w + Vector2(6.0, 0.0), diesel_on, col_diesel)
	_draw_catenary_line(cv, p_w + Vector2(6.0, 0.0), p_gardu_w + Vector2(6.0, 0.0), diesel_on, col_diesel)
	_draw_catenary_line(cv, p_gardu_w, gardu_in + Vector2(0.0, 12.0), diesel_on, col_diesel)

	# --- DISTRIBUTION FEEDERS (behind Gardu -> Gardu East Pole -> East Poles -> behind Houses!) ---
	# 4. Puskesmas (straight clean feeder behind Gardu -> behind Puskesmas roof)
	_draw_catenary_line(cv, gardu_bot, pusk_anchor, puskesmas_powered, col_dist)

	# 5. Dusun 1 & Masjid: behind Gardu -> Gardu East Pole (25,7) -> NE Pole (29,5) -> House 1 -> House 2 -> Masjid
	_draw_catenary_line(cv, gardu_out, p_gardu_e, dusun1_powered or dusun2_powered or dusun3_powered, col_dist)
	_draw_catenary_line(cv, p_gardu_e + Vector2(-4.0, 0.0), p_ne, dusun1_powered, col_dist)
	var d1_houses: Array = sector_houses.get("dusun1", [])
	if d1_houses.size() > 0:
		var prev_d1: Vector2 = p_ne
		for hp in d1_houses:
			var h_pos: Vector2 = hp
			_draw_catenary_line(cv, prev_d1, h_pos, dusun1_powered, col_dist)
			prev_d1 = h_pos
	else:
		_draw_catenary_line(cv, p_ne, zone_anchors["dusun1"], dusun1_powered, col_dist)
		_draw_catenary_line(cv, zone_anchors["dusun1"], zone_anchors["masjid"], dusun1_powered, col_dist)

	# 6. Dusun 2 (Rice Mill): Gardu East Pole (25,7) -> E Pole (29,11) -> Dusun 2 House(s)
	_draw_catenary_line(cv, p_gardu_e + Vector2(2.0, 0.0), p_e + Vector2(-5.0, 0.0), dusun2_powered, col_dist)
	var d2_houses: Array = sector_houses.get("dusun2", [])
	if d2_houses.size() > 0:
		var prev_d2: Vector2 = p_e
		for hp in d2_houses:
			var h_pos: Vector2 = hp
			_draw_catenary_line(cv, prev_d2, h_pos, dusun2_powered, col_dist)
			prev_d2 = h_pos
	else:
		_draw_catenary_line(cv, p_e, zone_anchors["dusun2"], dusun2_powered, col_dist)

	# 7. Dusun 3: Gardu East Pole (25,7) -> E Pole (29,11) -> SE Pole (29,19) -> House 1 -> House 2
	_draw_catenary_line(cv, p_gardu_e + Vector2(8.0, 0.0), p_e + Vector2(6.0, 0.0), dusun3_powered, col_dist)
	_draw_catenary_line(cv, p_e + Vector2(6.0, 0.0), p_se + Vector2(6.0, 0.0), dusun3_powered, col_dist)
	var d3_houses: Array = sector_houses.get("dusun3", [])
	if d3_houses.size() > 0:
		var prev_d3: Vector2 = p_se
		for hp in d3_houses:
			var h_pos: Vector2 = hp
			_draw_catenary_line(cv, prev_d3, h_pos, dusun3_powered, col_dist)
			prev_d3 = h_pos
	else:
		_draw_catenary_line(cv, p_se, zone_anchors["dusun3"], dusun3_powered, col_dist)


func _draw_effects() -> void:
	if effects_overlay == null:
		return
	var env_tint: Color = _compute_env_tint()
	var cv: Node2D = effects_overlay

	# 1. Steel Drive Shaft linking spinning WaterGear into PLTA pipe (river itself is rendered by GPU RiverWater shader!)
	var gear_c: Vector2 = water_gear.position if water_gear != null else Vector2(3.1 * CELL_PX, zone_anchors["pltmh"].y + 24.0)
	cv.draw_line(gear_c, Vector2(4.2 * CELL_PX, gear_c.y), Color(0.22, 0.28, 0.34) * env_tint, 9.0)
	cv.draw_line(gear_c, Vector2(4.2 * CELL_PX, gear_c.y), Color(0.62, 0.70, 0.78) * env_tint, 4.0)

	# 1b. Subtle sunlight glint shimmer across the PLTS Glass Solar Panels when generating!
	if plts_kw >= 8.0:
		var plts_p: Vector2 = zone_anchors["plts"]
		var glint_a: float = 0.14 + 0.12 * sin(anim_time * 3.2)
		for row_idx in range(2):
			for col_idx in range(3):
				var gx: float = plts_p.x - 144.0 + float(col_idx) * 96.0 + 10.0
				var gy: float = plts_p.y - 96.0 + float(row_idx) * 96.0 + 10.0
				cv.draw_rect(Rect2(gx, gy, 76.0, 32.0), Color(0.65, 0.95, 1.0, glint_a), true)
				cv.draw_line(Vector2(gx + 10.0, gy + 28.0), Vector2(gx + 30.0, gy + 4.0), Color(1.0, 1.0, 1.0, glint_a * 2.2), 3.0)

	# 2. Puskesmas Red Cross Emblem & Masjid Dome Glow (follow Marker2Ds!)
	var pusk_p: Vector2 = zone_anchors["puskesmas"]
	var mx: float = pusk_p.x
	var my: float = pusk_p.y - 72.0
	var cross_col := Color(1.0, 0.25, 0.28) if puskesmas_powered else Color(0.35, 0.18, 0.18)
	cv.draw_rect(Rect2(mx - 14.0, my - 14.0, 28.0, 28.0), Color(0.95, 0.97, 1.0, 0.92 if puskesmas_powered else 0.35), true)
	cv.draw_rect(Rect2(mx - 4.0, my - 10.0, 8.0, 20.0), cross_col, true)
	cv.draw_rect(Rect2(mx - 10.0, my - 4.0, 20.0, 8.0), cross_col, true)

	var masjid_p: Vector2 = zone_anchors["masjid"]
	var dome_p := masjid_p + Vector2(0.0, -56.0)
	var dome_col := Color(0.25, 0.85, 0.55) if dusun1_powered else Color(0.20, 0.30, 0.26)
	cv.draw_circle(dome_p, 16.0, dome_col)
	if dusun1_powered and (sun_factor < 0.45 or is_sahur_surge):
		cv.draw_circle(dome_p, 34.0, Color(1.0, 0.90, 0.42, 0.26))

	# 3. Auto-detected House Window Glows & Streetlamp Halos (from TileMapLayers!)
	var dark_boost: float = clampf(1.15 - sun_factor, 0.25, 1.0)
	for wg in window_glows:
		var sec: String = String(wg["sector"])
		if not _is_sector_powered(sec):
			continue
		var wc: Vector2 = wg["pos"]
		var cool: bool = bool(wg["cool"])
		var pulse: float = 0.88 + 0.12 * sin(anim_time * 3.8 + wc.x * 0.05)
		if cool:
			cv.draw_circle(wc, 24.0, Color(0.75, 0.95, 1.0, 0.24 * dark_boost * pulse))
		else:
			cv.draw_circle(wc, 34.0, Color(1.0, 0.78, 0.22, 0.15 * dark_boost * pulse))
			cv.draw_circle(wc, 17.0, Color(1.0, 0.86, 0.35, 0.28 * dark_boost * pulse))
			cv.draw_rect(Rect2(wc.x - 9.0, wc.y - 8.0, 18.0, 16.0), Color(1.0, 0.95, 0.62, 0.88 * dark_boost * pulse), true)

	if sun_factor < 0.55:
		var la: float = clampf((0.55 - sun_factor) * 1.4, 0.15, 0.85)
		for lg in lamp_glows:
			if not _is_sector_powered(String(lg["sector"])):
				continue
			var lc: Vector2 = lg["pos"]
			cv.draw_circle(lc, 32.0, Color(1.0, 0.84, 0.36, 0.20 * la))
			cv.draw_circle(lc, 12.0, Color(1.0, 0.94, 0.62, 0.52 * la))

	# 4. Alarm Sirens, Diesel Engine Glow, Rice Mill Active Glow & Gardu Core Ring
	var is_alarm: bool = (frequency <= 0.1 or frequency < 49.65 or frequency > 50.35)
	if diesel_on:
		var pltd_p: Vector2 = zone_anchors["pltd"]
		cv.draw_circle(pltd_p + Vector2(0.0, -8.0), 30.0, Color(1.0, 0.68, 0.18, 0.22))
	if is_alarm:
		var sa: float = 0.40 + 0.45 * absf(sin(anim_time * 9.0))
		cv.draw_circle(zone_anchors["pltd"] + Vector2(-192.0, 72.0), 26.0, Color(1.0, 0.18, 0.20, sa))
		cv.draw_circle(zone_anchors["pltd"] + Vector2(192.0, 72.0), 26.0, Color(1.0, 0.18, 0.20, sa))
		cv.draw_circle(zone_anchors["gardu"] + Vector2(-120.0, 72.0), 24.0, Color(1.0, 0.18, 0.20, sa))
		cv.draw_circle(zone_anchors["gardu"] + Vector2(120.0, 72.0), 24.0, Color(1.0, 0.18, 0.20, sa))
	if is_rice_mill_active and dusun2_powered:
		cv.draw_circle(zone_anchors["dusun2"] + Vector2(-72.0, 24.0), 24.0, Color(1.0, 0.85, 0.30, 0.28))

	var core_pos: Vector2 = zone_anchors["gardu"]
	var grid_ok: bool = (cascade_stage == 0 and frequency >= 49.50 and frequency <= 50.50)
	if is_interactive and gardu_hovered:
		cv.draw_rect(gardu_world_rect, Color(0.30, 0.95, 1.0, 0.90), false, 3.0)

	# (Overhead power cables are drawn cleanly BEHIND buildings on CablesOverlay at z_index = 1!)

	# 6. Diesel & Blackout Smoke Plumes (Kenney Smoke Particles) & Electrical Sparks
	for sp in smoke_particles:
		var pos: Vector2 = sp["pos"]
		var age: float = float(sp["age"])
		var max_age: float = float(sp.get("max_age", 2.0))
		var is_dark: bool = bool(sp["dark"])
		var rot: float = float(sp.get("rot", 0.0))
		var tex_idx: int = int(sp.get("tex_idx", 0))
		var life_t: float = clampf(age / maxf(0.1, max_age), 0.0, 1.0)
		var fade_in: float = clampf(age / 0.28, 0.0, 1.0)
		var fade_out: float = clampf(1.0 - life_t, 0.0, 1.0)
		var a: float = fade_in * fade_out * (0.82 if is_dark else 0.62)
		var sz: float = 34.0 + life_t * 82.0
		var tex: Texture2D = null
		if is_dark and black_smoke_textures.size() > 0:
			tex = black_smoke_textures[tex_idx % black_smoke_textures.size()]
		elif white_puff_textures.size() > 0:
			tex = white_puff_textures[tex_idx % white_puff_textures.size()]
		if tex != null:
			var tint: Color = Color(0.75, 0.75, 0.78, a) if is_dark else Color(0.88 * env_tint.r, 0.90 * env_tint.g, 0.94 * env_tint.b, a)
			cv.draw_set_transform(pos, rot, Vector2.ONE)
			cv.draw_texture_rect(tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, tint)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var col := Color(0.18, 0.18, 0.20, a) if is_dark else Color(0.84, 0.88, 0.92, a)
			cv.draw_circle(pos, sz * 0.35, col)

	for sk in spark_particles:
		var pos: Vector2 = sk["pos"]
		var age: float = float(sk["age"])
		var max_age: float = float(sk["max_age"])
		var a: float = clampf(1.0 - (age / max_age), 0.0, 1.0)
		cv.draw_circle(pos, 5.0 * a + 1.5, Color(1.0, 0.88, 0.35, a))
		cv.draw_circle(pos, 2.4 * a + 1.0, Color(1.0, 1.0, 0.92, a))

	# 7. Volumetric Kenney Clouds, Ground Shadows, Rain & Lightning
	if cloud_cover > 0.12:
		var c_strength: float = clampf((cloud_cover - 0.10) / 0.85, 0.0, 1.0)
		var shadow_a: float = clampf(c_strength * 0.36, 0.05, 0.38)
		var puff_a: float = clampf(0.16 + c_strength * 0.56, 0.14, 0.74)
		var is_storm: bool = (rain_intensity > 0.1 or cloud_cover >= 0.75)
		var base_cloud_col: Color = Color(0.48, 0.54, 0.65) if is_storm else Color(0.94, 0.97, 1.0)
		var lit_cloud_col: Color = base_cloud_col * env_tint
		if lightning_alpha > 0.01:
			lit_cloud_col = lit_cloud_col.lerp(Color(1.0, 1.0, 1.0), lightning_alpha * 0.75)
		lit_cloud_col.a = puff_a

		var has_puffs: bool = white_puff_textures.size() > 0
		var has_dark: bool = black_smoke_textures.size() > 0
		for c in cloud_shadows:
			var cx: float = float(c["x"])
			var cy: float = float(c["y"])
			var cw: float = float(c["w"])
			var ch: float = float(c["h"])
			var p1: int = int(c.get("p1", 0))
			var p2: int = int(c.get("p2", 1))
			var p3: int = int(c.get("p3", 2))
			var crot: float = float(c.get("rot", 0.0))
			var center := Vector2(cx + cw * 0.5, cy + ch * 0.5)
			if has_puffs:
				var lobe_offsets: Array[Vector2] = [
					Vector2(-cw * 0.28, ch * 0.06),
					Vector2(0.0, -ch * 0.10),
					Vector2(cw * 0.28, ch * 0.08)
				]
				var lobe_sizes: Array[float] = [ch * 1.15, ch * 1.48, ch * 1.12]
				var lobe_ids: Array[int] = [p1, p2, p3]
				# Soft puffy ground shadow cast underneath each cloud
				if has_dark:
					var sh_col := Color(0.05, 0.08, 0.16, shadow_a)
					for k in range(3):
						var stex: Texture2D = black_smoke_textures[lobe_ids[k] % black_smoke_textures.size()]
						var ssz: float = lobe_sizes[k] * 1.05
						cv.draw_set_transform(center + lobe_offsets[k] + Vector2(24.0, 42.0), crot, Vector2.ONE)
						cv.draw_texture_rect(stex, Rect2(-ssz * 0.5, -ssz * 0.42, ssz, ssz * 0.84), false, sh_col)
				# Volumetric Kenney cloud puffs drifting overhead
				for k in range(3):
					var wtex: Texture2D = white_puff_textures[lobe_ids[k] % white_puff_textures.size()]
					var wsz: float = lobe_sizes[k]
					cv.draw_set_transform(center + lobe_offsets[k], crot + float(k - 1) * 0.12, Vector2.ONE)
					cv.draw_texture_rect(wtex, Rect2(-wsz * 0.5, -wsz * 0.44, wsz, wsz * 0.88), false, lit_cloud_col)
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				cv.draw_rect(Rect2(cx, cy, cw, ch), Color(0.06, 0.10, 0.18, shadow_a), true)

	if rain_intensity > 0.1:
		for rd in rain_drops:
			cv.draw_line(rd, rd + Vector2(-10.0, 28.0), Color(0.62, 0.84, 1.0, 0.55 * rain_intensity), 1.8)
	if lightning_alpha > 0.01:
		cv.draw_rect(Rect2(0.0, 0.0, WORLD_W, WORLD_H), Color(0.85, 0.92, 1.0, lightning_alpha * 0.35), true)

	# 8. Diegetic World Tags
	var plts_active: bool = plts_kw >= 8.0
	_draw_world_tag(cv, zone_anchors["pltmh"] + Vector2(0.0, -108.0), "PLTMH • %d kW" % int(pltmh_kw), true, false)
	_draw_world_tag(cv, zone_anchors["plts"] + Vector2(0.0, -148.0), "PLTS Surya • %d kW" % int(plts_kw), plts_active, false)
	_draw_world_tag(cv, zone_anchors["pltd"] + Vector2(0.0, -162.0), "PLTD Diesel • %d kW" % int(diesel_kw), diesel_on, false)
	var gardu_txt := "⚡ GARDU INDUK (KLIK / TAB)" if (is_interactive and gardu_hovered) else "GARDU INDUK"
	_draw_world_tag(cv, zone_anchors["gardu"] + Vector2(0.0, -162.0), gardu_txt, grid_ok, false)
	_draw_world_tag(cv, zone_anchors["puskesmas"] + Vector2(0.0, 176.0), "PUSKESMAS" + ("" if puskesmas_powered else " • PADAM!"), puskesmas_powered, false)
	_draw_world_tag(cv, zone_anchors["dusun1"] + Vector2(0.0, -96.0), "DUSUN 1", dusun1_powered, false)
	_draw_world_tag(cv, zone_anchors["masjid"] + Vector2(0.0, -96.0), "MASJID", dusun1_powered, false)
	var d2_txt := "PENGGILINGAN PADI" if is_rice_mill_active else "DUSUN 2"
	_draw_world_tag(cv, zone_anchors["dusun2"] + Vector2(0.0, -112.0), d2_txt, dusun2_powered, false)
	var d3_txt := "DUSUN 3 • LEPAS BEBAN" if shed_d3_on else "DUSUN 3"
	_draw_world_tag(cv, zone_anchors["dusun3"] + Vector2(0.0, 146.0), d3_txt, dusun3_powered, shed_d3_on)

	# 9. Floating World Callouts & Blackout Stamp
	var font := ThemeDB.fallback_font
	for co in callouts:
		var pos: Vector2 = co["pos"]
		var txt: String = String(co["text"])
		var col: Color = co["color"]
		var age: float = float(co["age"])
		var dur: float = float(co["duration"])
		var a: float = clampf(1.0 - maxf(0.0, (age - dur * 0.55) / (dur * 0.45)), 0.0, 1.0)
		var ts: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		var br := Rect2(pos.x - ts.x * 0.5 - 12.0, pos.y - 18.0, ts.x + 24.0, 28.0)
		cv.draw_rect(br, Color(0.04, 0.07, 0.11, 0.90 * a), true)
		cv.draw_rect(br, Color(col.r, col.g, col.b, a), false, 2.0)
		cv.draw_string(font, Vector2(br.position.x + 12.0, br.position.y + 19.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col.r, col.g, col.b, a))

	if is_blackout_banner:
		var pulse_a: float = 0.72 + 0.25 * sin(anim_time * 8.0)
		var btxt := "BLACKOUT"
		var bsize: Vector2 = font.get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 56)
		var bp := Vector2(core_pos.x - bsize.x * 0.5, core_pos.y - 14.0)
		cv.draw_rect(Rect2(bp.x - 28.0, bp.y - 52.0, bsize.x + 56.0, 74.0), Color(0.18, 0.02, 0.04, 0.88), true)
		cv.draw_rect(Rect2(bp.x - 28.0, bp.y - 52.0, bsize.x + 56.0, 74.0), Color(1.0, 0.22, 0.25, pulse_a), false, 3.5)
		cv.draw_string(font, bp, btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.30, 0.32, pulse_a))


func _draw_catenary_line(cv: Node2D, p1: Vector2, p2: Vector2, active: bool, active_col: Color) -> void:
	var segs: int = 14
	var dist: float = p1.distance_to(p2)
	var horiz_ratio: float = absf(p2.x - p1.x) / maxf(1.0, dist)
	var sag: float = clampf(dist * 0.08, 6.0, 30.0) * horiz_ratio
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var pt: Vector2 = p1.lerp(p2, t)
		pt.y += sin(t * PI) * sag
		pts.append(pt)

	cv.draw_polyline(pts, Color(0.03, 0.05, 0.08, 0.85), 5.5, true)
	var line_col := Color(active_col.r, active_col.g, active_col.b, 0.80) if active else Color(0.45, 0.22, 0.24, 0.45)
	cv.draw_polyline(pts, line_col, 2.4, true)

	if active:
		for k in range(2):
			var u: float = fmod(anim_time * 0.55 + float(k) * 0.5, 1.0)
			var pulse_p: Vector2 = p1.lerp(p2, u)
			pulse_p.y += sin(u * PI) * sag
			cv.draw_circle(pulse_p, 7.0, Color(active_col.r, active_col.g, active_col.b, 0.32))
			cv.draw_circle(pulse_p, 3.6, Color(0.92, 1.0, 0.96))


func _draw_world_tag(cv: Node2D, center: Vector2, text: String, active: bool, is_shed: bool) -> void:
	var font := ThemeDB.fallback_font
	var fsize: int = 13
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var rect := Rect2(center.x - ts.x * 0.5 - 14.0, center.y - 12.0, ts.x + 28.0, 24.0)

	var bg := Color(0.04, 0.11, 0.10, 0.88)
	var border := Color(0.22, 0.92, 0.58, 0.90)
	var dot := Color(0.28, 1.0, 0.62)

	if not active:
		if is_shed:
			bg = Color(0.18, 0.13, 0.03, 0.92)
			border = Color(1.0, 0.74, 0.20, 0.92)
			dot = Color(1.0, 0.78, 0.22)
		else:
			bg = Color(0.18, 0.05, 0.06, 0.90)
			border = Color(0.95, 0.28, 0.30, 0.90)
			dot = Color(1.0, 0.32, 0.32)

	cv.draw_rect(rect, bg, true)
	cv.draw_rect(rect, border, false, 1.6)
	cv.draw_circle(Vector2(rect.position.x + 10.0, rect.position.y + 12.0), 4.0, dot)
	cv.draw_string(font, Vector2(rect.position.x + 18.0, rect.position.y + 16.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.94, 0.98, 1.0))

@tool
class_name VillageBuilding
extends Node2D

@export_enum("HOME", "HYDRO", "SOLAR", "BACKUP", "CLINIC", "FACTORY", "BATTERY", "MILL", "WATER", "GRID", "LAMP", "DISTRICT") var role := "HOME":
	set(value):
		role = value
		queue_redraw()
@export var display_name := "Home":
	set(value):
		display_name = value
		queue_redraw()
@export_range(0, 4) var appearance := 0:
	set(value):
		appearance = value
		queue_redraw()
@export var wall_color := Color("7b9f91"):
	set(value):
		wall_color = value
		queue_redraw()
@export var roof_color := Color("aa7563"):
	set(value):
		roof_color = value
		queue_redraw()
var powered := true
var status := "ONLINE"
var intentional := false
var fault := false
var stressed := false
var night := false
var command := -1
var preview_command := -1
var energy_fraction := 0.6
var animation := 0.0
var reduced_motion := false

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var accent := Color("ff7185") if fault else Color("ffce78") if intentional or stressed else Color("4be0a0") if powered else Color("8297a5")
	var windows := Color("ffce78") if powered else Color("162432")
	var wall := wall_color.darkened(0.4) if night else wall_color
	var height := 40 + appearance * 6
	if role == "GRID":
		draw_rect(Rect2(-32, -28, 64, 56), Color("1e455c"))
		draw_line(Vector2(-12, -12), Vector2(9, 0), accent, 5)
		draw_line(Vector2(9, 0), Vector2(-5, 18), accent, 5)
	elif role == "SOLAR":
		for y in range(2):
			for x in range(3):
				draw_rect(Rect2(-45 + x * 30, -25 + y * 24, 27, 21), Color("3988b5") if powered else Color("2c4358"))
				draw_rect(Rect2(-45 + x * 30, -25 + y * 24, 27, 21), Color("93cde6"), false, 1)
	elif role == "BATTERY":
		draw_rect(Rect2(-32, -30, 64, 56), Color("2d4a60"))
		draw_rect(Rect2(-24, 20 - 42 * energy_fraction, 48, 42 * energy_fraction), accent)
		draw_rect(Rect2(-12, -37, 24, 7), Color("bacbd4"))
	elif role == "LAMP":
		draw_circle(Vector2.ZERO, 25, windows)
		if powered: draw_arc(Vector2.ZERO, 34, 0, TAU, 24, accent, 2)
		draw_rect(Rect2(-12, 24, 24, 12), Color("8ca6b4"))
	else:
		draw_rect(Rect2(-40, -height * 0.5, 80, height), wall)
		if role in ["HOME", "DISTRICT", "CLINIC", "MILL"]:
			draw_colored_polygon(PackedVector2Array([Vector2(-47, -height * 0.5), Vector2(0, -height * 0.5 - 22 - appearance * 2), Vector2(47, -height * 0.5)]), roof_color)
		else:
			draw_rect(Rect2(-44, -height * 0.5 - 8, 88, 9), roof_color)
		for x in range(3): draw_rect(Rect2(-28 + x * 21, -8, 12, 16), windows)
		if role == "CLINIC":
			draw_line(Vector2(-9, -height * 0.5 - 9), Vector2(9, -height * 0.5 - 9), Color("ff7185"), 5)
			draw_line(Vector2(0, -height * 0.5 - 18), Vector2(0, -height * 0.5), Color("ff7185"), 5)
		if role in ["FACTORY", "BACKUP"]:
			draw_rect(Rect2(22, -height * 0.5 - 28, 13, 28), Color("778e9c"))
			if powered and not reduced_motion:
				for i in range(3): draw_circle(Vector2(28 + i * 5, -height * 0.5 - 36 - fmod(animation * 10 + i * 9, 25)), 4 + i, Color(0.65, 0.72, 0.76, 0.5))
		if role == "HYDRO":
			draw_arc(Vector2(-39, 0), 20, 0, TAU, 24, accent, 3)
			for i in range(5): draw_line(Vector2(-39, 0), Vector2(-39, 0) + Vector2.from_angle(animation + i * TAU / 5) * 18, accent, 2)
		if role == "WATER":
			draw_rect(Rect2(-27, -51, 54, 25), Color("6cabca"))
			draw_line(Vector2(-23, -26), Vector2(-23, -18), Color("9ab7c6"), 4)
			draw_line(Vector2(23, -26), Vector2(23, -18), Color("9ab7c6"), 4)
	if intentional or fault or stressed:
		draw_rect(Rect2(-48, -44, 96, 86), accent, false, 3)

func _process(_delta: float) -> void:
	if not has_node("NameLabel"): return
	var accent := Color("ff7185") if fault else Color("ffce78") if intentional or stressed else Color("4be0a0") if powered else Color("8297a5")
	$NameLabel.text = display_name
	$StatusLabel.text = status
	$ControlLabel.text = "CONTROL %d | NEXT %d" % [command, preview_command]
	$ControlLabel.visible = command >= 0
	$FaultBadge.visible = fault
	$NameLabel.modulate = accent
	$StatusLabel.modulate = accent

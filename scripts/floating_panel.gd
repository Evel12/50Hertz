extends Control
## A small title drag surface and corner grip; editor input stays on the canvas.
signal rect_changed(rect: Rect2)
const UI := preload("res://scripts/upper_hud_skin.gd")
var target: Control
var minimum := Vector2(420,180)
var header_width := 210.0
var enabled := true
var dragging := false
var resizing := false
var start_mouse := Vector2.ZERO
var start_rect := Rect2()
var header: Control
var grip: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 15
	header = Control.new()
	header.position = Vector2(12,7)
	if header_width <= 0:
		header.anchor_right = 1.0
		header.offset_right = -12
		header.offset_bottom = 40
	else:
		header.size = Vector2(header_width,33)
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.tooltip_text = "Tarik judul untuk memindahkan panel"
	header.gui_input.connect(func(event): _begin(event,false))
	add_child(header)
	target.get_parent().resized.connect(func(): call_deferred("_fit_in_parent"))

func set_enabled(value: bool) -> void:
	enabled = value
	if header != null: header.visible = value
	if grip != null: grip.visible = value
	dragging = false
	resizing = false

func _begin(event: InputEvent, resize: bool) -> void:
	if not enabled: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_rect = Rect2(target.position,target.size)
			start_mouse = target.get_parent().get_local_mouse_position()
			dragging = not resize
			resizing = resize
			# Detach anchors only after an intentional move, preserving the visible rect.
			target.position = start_rect.position
			target.size = start_rect.size
		else:
			dragging = false
			resizing = false
		accept_event()

func _input(event: InputEvent) -> void:
	if not (dragging or resizing): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		resizing = false
		rect_changed.emit(Rect2(target.position,target.size))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var delta: Vector2 = target.get_parent().get_local_mouse_position()-start_mouse
		apply_rect(Rect2(start_rect.position,start_rect.size+delta) if resizing else Rect2(start_rect.position+delta,start_rect.size))
		get_viewport().set_input_as_handled()

func apply_rect(rect: Rect2) -> void:
	var bounds: Vector2 = target.get_parent().size
	var lower_bound := minimum
	if target.has_method("set_minimized") and bool(target.get("minimized")): lower_bound.y = 44
	var wanted := rect.size.clamp(lower_bound,Vector2(maxf(minimum.x,bounds.x-20),maxf(minimum.y,bounds.y-82)))
	var at := rect.position.clamp(Vector2(0,72),Vector2(maxf(0,bounds.x-wanted.x),maxf(72,bounds.y-wanted.y)))
	target.position = at
	target.size = wanted
	rect_changed.emit(Rect2(at,wanted))

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		dragging = false
		resizing = false

func _fit_in_parent() -> void:
	if not enabled or not is_instance_valid(target): return
	apply_rect(Rect2(target.position,target.size))

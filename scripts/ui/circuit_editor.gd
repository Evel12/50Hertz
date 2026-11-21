class_name CircuitEditor
extends VBoxContainer

signal changed
signal notice(message: String)
signal selected(id: int)
var board
var graph: GraphEdit
var palette: HFlowContainer
var locked := false
var drawing := false
var wire_active := false
var selected_id := -1
var snap := true
var controls := {}
var inputs := {}
var labels := {}
var gates := []
var standalone_preview := false
const CYAN = Color("74d7f2")
const GREEN = Color("4be0a0")
const AMBER = Color("ffce78")

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette = get_node("Palette")
	graph = get_node("CircuitBoard")
	for button in palette.get_children():
		button.pressed.connect(place_component.bind(str(button.get_meta("gate_kind"))))
	graph.connection_request.connect(connect_wire)
	graph.disconnection_request.connect(disconnect_wire)
	graph.delete_nodes_request.connect(delete_selected)
	graph.begin_node_move.connect(func():
		if not locked and board != null: board.checkpoint())
	graph.end_node_move.connect(func(): changed.emit())
	graph.node_selected.connect(func(node):
		selected_id = int(str(node.name))
		selected.emit(selected_id))
	graph.connection_drag_started.connect(func(_node, _port, _output): wire_active = true)
	graph.connection_drag_ended.connect(func(): wire_active = false)
	call_deferred("ensure_preview_board")

func ensure_preview_board() -> void:
	if board != null: return
	standalone_preview = true
	var catalog = preload("res://resources/stages/stage_catalog.gd")
	bind_board(catalog.starter(1), ["NOT"])

func _process(_delta: float) -> void:
	if standalone_preview and board != null:
		board.tick({"DAY": true}, 0)
		update_signals({"DAY": true})

func bind_board(value, available: Array) -> void:
	board = value
	gates = available
	for button in palette.get_children():
		button.visible = str(button.get_meta("gate_kind")) in available
	rebuild()
	call_deferred("fit")

func place_component(kind: String) -> void:
	if locked or board == null or kind not in gates: return
	board.checkpoint()
	selected_id = board.add(kind, (graph.scroll_offset + graph.size * 0.3) / graph.zoom)
	rebuild()
	selected.emit(selected_id)
	changed.emit()

func rebuild() -> void:
	drawing = true
	graph.clear_connections()
	for c in graph.get_children():
		if c is GraphNode:
			graph.remove_child(c)
			c.queue_free()
	controls.clear()
	labels.clear()
	inputs.clear()
	for n in board.nodes:
		# Cards instantiate authored templates; no control/label/layout construction here.
		var template: PackedScene = load("res://scenes/ui/components/%s.tscn" % str(n.kind).to_lower())
		var card: GraphNode = template.instantiate()
		card.name = str(n.id)
		card.title = n.tag if n.kind in ["SENSOR", "OUTPUT"] else n.kind
		card.position_offset = n.pos
		card.draggable = not locked
		card.position_offset_changed.connect(func():
			if not drawing and not locked: n.pos = card.position_offset)
		graph.add_child(card)
		controls[n.id] = card
		var rows: Array = [card.get_node("Signal")]
		if card.has_node("SignalB"): rows.append(card.get_node("SignalB"))
		labels[n.id] = rows
		inputs[n.id] = []
	for w in board.wires: graph.connect_node(str(w.source), 0, str(w.target), w.port)
	drawing = false
	set_locked(locked)

func set_locked(value: bool) -> void:
	locked = value
	for c in palette.get_children(): c.disabled = locked
	for id in controls: controls[id].draggable = not locked

func update_signals(sensors: Dictionary) -> void:
	if board == null: return
	for n in board.nodes:
		if not labels.has(n.id): continue
		var value = board.values.get(n.id, false)
		var output := str(int(value)) if value is bool else "%.1f" % float(value)
		var rows: Array = labels[n.id]
		for p in range(rows.size()):
			if n.kind == "SENSOR": rows[p].text = "SIGNAL " + output
			else:
				var input = board.input_value(n.id, p, sensors)
				var input_label := "SET" if n.kind == "LATCH" and p == 0 else "RESET" if n.kind == "LATCH" else "A" if p == 0 else "B"
				rows[p].text = "%s: %s   |   OUT: %s" % [input_label, str(int(input)) if input is bool else "%.1f" % float(input), output]
			var color := GREEN if bool(value) else Color("6e8596")
			controls[n.id].set_slot_color_right(p, color)
			controls[n.id].set_slot_color_left(p, GREEN if bool(board.input_value(n.id, p, sensors)) else Color("6e8596"))
	for w in board.wires:
		var traced: bool = selected_id != -1 and (board.has_path(selected_id, w.source) or board.has_path(w.target, selected_id))
		graph.set_connection_activity(str(w.source), 0, str(w.target), w.port, 1.0 if traced else 0.65 if bool(board.values.get(w.source, false)) else 0.0)

func connect_wire(from: StringName, _from_port: int, to: StringName, port: int) -> void:
	wire_active = false
	if board == null: return
	if locked:
		notice.emit("Pause before editing the controller.")
		return
	board.checkpoint()
	if board.connect_nodes(int(str(from)), int(str(to)), port):
		graph.connect_node(from, 0, to, port)
		changed.emit()
	else: notice.emit(board.error)

func disconnect_wire(from: StringName, from_port: int, to: StringName, port: int) -> void:
	if locked or board == null: return
	board.checkpoint()
	board.wires = board.wires.filter(func(w): return not (w.source == int(str(from)) and w.target == int(str(to)) and w.port == port))
	graph.disconnect_node(from, from_port, to, port)
	changed.emit()

func delete_selected(names: Array[StringName]) -> void:
	if locked or board == null: return
	board.checkpoint()
	for id in names: board.remove_node(int(str(id)))
	rebuild()
	changed.emit()

func disconnect_input(id: int, port: int) -> void:
	if locked: return
	for w in board.wires.duplicate():
		if w.target == id and w.port == port: disconnect_wire(str(w.source), 0, str(id), port)

func cancel_wire() -> bool:
	if not wire_active: return false
	if graph.has_method("force_connection_drag_end"): graph.call("force_connection_drag_end")
	wire_active = false
	return true

func fit() -> void:
	if board == null or board.nodes.is_empty() or graph.size.x < 1: return
	var bounds := Rect2(board.nodes[0].pos, Vector2(190, 130))
	for n in board.nodes: bounds = bounds.merge(Rect2(n.pos, Vector2(190, 130)))
	graph.zoom = clampf(minf((graph.size.x - 70) / maxf(1, bounds.size.x), (graph.size.y - 65) / maxf(1, bounds.size.y)), 0.3, 1.0)
	graph.scroll_offset = bounds.position * graph.zoom - Vector2(30, 65)

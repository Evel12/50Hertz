extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	change_scene_to_file("res://tests/fixtures/legacy_main.tscn")
	for i in range(12): await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/gameplay.tscn":
		print("FAIL: old root did not recover to gameplay")
		quit(1)
		return
	if not current_scene.has_node("UIViews") or current_scene.editor == null:
		print("FAIL: recovered gameplay did not bind authored UI")
		quit(1)
		return
	current_scene.menus.g = null
	print("LEGACY ENTRY: PASS — old root routes to authored gameplay without missing-node errors")
	quit(0)

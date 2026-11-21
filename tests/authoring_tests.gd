extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL AUTHORING: ", message)
func settle() -> void:
	for i in range(4): await process_frame
func run() -> void:
	var packed = load("res://main.tscn")
	var game = packed.instantiate()
	check(load("res://scenes/gameplay.tscn").get_state().get_node_count() > 40, "UI is serialized, not an empty runtime root")
	check(game.get_node("%RunButton") is Button and game.get_node("%VillageView") is Control, "Scene owns editable controls")
	var signatures := []
	for i in range(10):
		var stage = load("res://scenes/stages/stage_%02d.tscn" % [i + 1]).instantiate()
		var signature := ""
		var count := 0
		for site in stage.get_children():
			if site is VillageBuilding:
				count += 1
				signature += site.role + str(site.position) + str(site.appearance)
		check(count >= 3, "Stage %d contains editable building instances" % [i+1])
		check(signature not in signatures, "Distinct village arrangement stage %d" % [i+1])
		signatures.append(signature)
		stage.free()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.menus.close_modal()
	game.game_active = true
	game.setup_stage(1)
	await settle()
	var home
	var backup
	for site in game.village.map_root.get_children():
		if site is VillageBuilding:
			if site.role == "HOME": home = site
			if site.role == "BACKUP": backup = site
	var moved: Vector2 = home.position + Vector2(13, 7)
	home.position = moved
	await settle()
	check(home.position == moved, "Building transforms are not overwritten by rendering")
	# Incorrect DAY -> BACKUP must run and visibly start equipment in daylight.
	game.editor.connect_wire(str(game.Catalog.terminal(game.board, "DAY")), 0, str(game.Catalog.terminal(game.board, "BACKUP")), 0)
	game.prediction = 1
	game.toggle_run()
	check(game.running, "Incorrect controller is permitted to run")
	for i in range(30): game.advance()
	game.refresh()
	await settle()
	check(backup.powered and backup.command == 1 and game.sim.frequency > 50.5, "Wrong controller causes visible backup and surplus stress")
	check(home.stressed and home.status.contains("UNSTABLE"), "Stress reaches building visual state")
	game.running = false
	game.restart()
	game.board.wires.clear()
	game.board.validate(game.stage.sensors, game.stage.outputs, game.stage.gates)
	while not game.sim.failed and not game.sim.completed: game.advance()
	game.refresh()
	await settle()
	check(game.sim.failed and not home.powered and home.fault, "Missing backup causes dark fault-marked homes")
	game.menus.close_modal()
	game.setup_stage(6)
	game.sim.commands = {"SHED_FACTORY": true}
	await settle()
	for site in game.village.map_root.get_children():
		if site is VillageBuilding and site.role == "FACTORY": check(site.intentional and not site.powered and not site.fault, "Intentional shed differs from outage")
	game.menus.g = null
	game.free()
	# Render saved scene without its runtime UI controller: approximates the 2D authoring preview.
	var preview = packed.instantiate()
	preview.set_script(null)
	root.add_child(preview)
	preview.get_node("%VillageView").make_preview()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/authoring_preview.png")
	preview.free()
	await process_frame
	print("AUTHORING RESULT: %d/%d passed; %d failures" % [checks - failures, checks, failures])
	quit(0 if failures == 0 else 1)

extends SceneTree
## Test real UI event routing, world/screen conversion and orbit picking.
const World = preload("res://scripts/table_world.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
var failures := 0
var checks := 0
var main: Control
var board: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	board = main.get_node("Table")
	check(board.is_visible_in_tree(), "table visible on normal startup")
	check(board.get("_world").get("_pieces").size() == 4, "offline preview has four miniatures")
	check(not root.get_node("Session").connected, "preview creates no network room")
	var camera: Camera3D = board.get("_world").camera
	for pose in [0, 1, 2]:
		if pose == 1:
			board.top_view()
		elif pose == 2:
			board.set("_yaw", -0.65)
			board.set("_pitch", 0.67)
			board.call("_update_camera")
		await process_frame
		for cell in [Vector2i(2, 3), Vector2i(3, 6), Vector2i(10, 3), Vector2i(10, 6), Vector2i(7, 5)]:
			var point := World.cell_position(cell)
			point.y = World.MAP_Y
			var screen := camera.unproject_position(point)
			check(board.cell_at(screen) == cell, "cell picking at camera pose %s: %s" % [pose, cell])
	board.reset_camera()
	check(board.cell_at(Vector2(-20, -20)) == Vector2i(-1, -1), "outside viewport ignored")
	var rotation := InputEventMouseMotion.new()
	rotation.position = Vector2(640, 300)
	rotation.relative = Vector2(80, -20)
	rotation.button_mask = MOUSE_BUTTON_MASK_RIGHT
	var old_yaw: float = board.get("_yaw")
	board.call("_gui_input", rotation)
	check(not is_equal_approx(board.get("_yaw"), old_yaw), "right drag rotates camera")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	for index in range(40):
		board.call("_gui_input", wheel)
	check(is_equal_approx(board.get("_distance"), 7.5), "zoom clamp")
	board.reset_camera()
	await process_frame
	# Use actual viewport input so transparent HUD containers cannot swallow clicks.
	main.get("_port").value = 24570
	main.get("_token_choice").select(1)
	await click_at(main.get("_host").get_global_rect().get_center())
	check(root.get_node("Session").hosting, "host button works through UI")
	check(root.get_node("Session").state.players[0].token == "mage", "chosen PNG appearance sent to host")
	check(main.get("_start").is_visible_in_tree(), "start button visible in lobby")
	await click_at(main.get("_start").get_global_rect().get_center())
	check(root.get_node("Session").my_turn(), "start button begins game")
	var target := World.cell_position(Vector2i(2, 4))
	target.y = World.MAP_Y
	await click_at(camera.unproject_position(target))
	var state: Dictionary = root.get_node("Session").state
	check(int(state.players[0].y) == 4 and int(state.moves_left) == 2, "click through HUD moves token on 3D map")
	await create_timer(0.28).timeout
	var world: Node3D = board.get("_world")
	var piece: Node3D = world.get("_pieces")[1]
	check(piece.position.is_equal_approx(World.cell_position(Vector2i(2, 4))), "miniature reaches authoritative target")
	var portrait: Sprite3D = piece.get_node("Portrait")
	check(portrait.texture.resource_path.ends_with("mage.png"), "piece uses selected PNG texture")
	check(portrait.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, "PNG stays upright while facing camera")
	check(world.get("_pieces").has("enemy:collector"), "enemy PNG displayed on table")
	var image := portrait.texture.get_image()
	if image.is_compressed():
		image.decompress()
	check(image.get_pixel(0, 0).a == 0, "PNG background is transparent")
	var foe_position := World.cell_position(Vector2i(4, 5))
	foe_position.y = World.MAP_Y
	await click_at(camera.unproject_position(foe_position))
	check(main.get("_target_id") == "collector" and int(root.get_node("Session").state.moves_left) == 2, "enemy click selects without spending movement")
	var enemy_piece: Node3D = world.get("_pieces")["enemy:collector"]
	var enemy_portrait: Sprite3D = enemy_piece.get_node("Portrait")
	check(world.pick_piece(camera.unproject_position(enemy_piece.position + enemy_portrait.position)) == Vector2i(4, 5), "visible PNG body is clickable above its base")
	await click_at(main.get("_attack").get_global_rect().get_center())
	check(int(root.get_node("Session").state.actions_left) == 1, "distant UI attack rejected without spending action")
	for cell in [Vector2i(3, 4), Vector2i(3, 5)]:
		var point := World.cell_position(cell)
		point.y = World.MAP_Y
		await click_at(camera.unproject_position(point))
	check(int(root.get_node("Session").state.moves_left) == 0, "can approach enemy using remaining moves")
	await click_at(main.get("_attack").get_global_rect().get_center())
	check(int(root.get_node("Session").state.actions_left) == 0, "attack button executes adjacent attack")
	check(root.get_node("Session").state.last_roll.get("attacker") == "Путник", "UI shows authoritative attack result")
	check(main.get("_attack").disabled, "attack button prevents second attack")
	root.get_node("Session").leave_room(false)
	await process_frame
	check(world.get("_pieces").size() == 4, "preview returns after leaving")
	root.get_node("Session").host_room("Создатель", 24570)
	var workshop: Window = main.get("_workshop")
	workshop.popup_centered()
	await process_frame
	await process_frame
	check(workshop.visible and workshop.get("_mode").selected == 0, "workshop defaults to clearly marked non-AI test mode")
	workshop.get("_prompt").text = "Гном в бирюзовом плаще"
	var generate_button: Button = workshop.get("_generate")
	await click_at(Vector2(workshop.position) + generate_button.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 5000
	while root.get_node("Session").get("_generation_busy") or not root.get_node("Session").get("_generation_queue").is_empty():
		if Time.get_ticks_msec() > deadline:
			check(false, "workshop generation timeout")
			break
		await process_frame
	var generated_token: String = root.get_node("Session").state.players[0].token
	check(generated_token.begins_with("generated:"), "workshop button generates and applies portrait")
	check(world.get("_pieces")[1].get_node("Portrait").texture == Tokens.texture(generated_token), "generated portrait displayed on 3D standee")
	check(workshop.get("_preview").texture == Tokens.texture(generated_token), "workshop preview displays same generated PNG")
	var tabs: TabContainer = workshop.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 3
	await process_frame
	check(not workshop.get("_mode").visible and workshop.get("_director_mode").is_visible_in_tree(), "party tab shows director settings without portrait mode")
	check(not workshop.get("_save_game").disabled and workshop.get("_load_game").disabled, "save enabled for solo host; loading blocked in live room")
	root.get_node("Session").set_director_mode("test")
	check(workshop.get("_director_mode").selected == 1, "director selector reflects host setting")
	root.get_node("Session").leave_room(false)
	check(workshop.get("_save_game").disabled and not workshop.get("_load_game").disabled, "offline party tab enables loading")
	workshop.hide()
	root.get_node("Session").leave_room(false)
	main.queue_free()
	await process_frame
	print("TABLE: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)

func click_at(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

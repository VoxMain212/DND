extends SceneTree
## Optional visual check: requires a graphical Godot session.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.get("_name").text = "Гробослав"
	main.get("_port").value = 24569
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/dndfun-preview-3d.png")
	root.get_node("Session").host_room("Гробослав", 24569)
	var workshop: Window = main.get("_workshop")
	workshop.popup_centered()
	root.get_node("Session").generate("character", "Гном-некромант с бухгалтерской книгой", "sketch")
	while root.get_node("Session").get("_generation_busy") or not root.get_node("Session").get("_generation_queue").is_empty():
		await process_frame
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/dndfun-workshop.png")
	root.get_node("Session").set_director_mode("test")
	var tabs: TabContainer = workshop.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 3
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/dndfun-session.png")
	workshop.hide()
	root.get_node("Session").send_command("start")
	root.get_node("Session").send_command("say", {"text": "иду вниз"})
	while root.get_node("Session").get("_director_busy"):
		await process_frame
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var path := "/tmp/dndfun-preview.png"
	root.get_texture().get_image().save_png(path)
	print("PREVIEW: " + path)
	# Walk to the skeleton using normal commands and record a real attack.
	for cell in [Vector2i(3, 4), Vector2i(3, 5)]:
		root.get_node("Session").send_command("move", {"x": cell.x, "y": cell.y})
	root.get_node("Session").send_command("attack", {"target": "collector"})
	main.get("_room_panel").visible = false
	main.get("_journal_panel").visible = true
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/dndfun-combat.png")
	# Check a second camera angle with both side panels hidden.
	main.get("_room_panel").visible = false
	main.get("_journal_panel").visible = false
	main.get("_board").top_view()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/dndfun-top-3d.png")
	root.get_node("Session").leave_room(false)
	quit()

extends SceneTree
const Tokens = preload("res://scripts/token_catalog.gd")
const Rules = preload("res://scripts/room_state.gd")
var failures := 0
var checks := 0
var mock_url := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mock-url="):
			mock_url = arg.trim_prefix("--mock-url=")
		if arg.begins_with("--cache-dir="):
			Tokens.cache_dir = arg.trim_prefix("--cache-dir=")
	call_deferred("_run")

func _run() -> void:
	var forge := root.get_node("Forge")
	forge.ollama_url = mock_url
	forge.comfy_url = mock_url
	forge.checkpoint = "v1-5-pruned-emaonly.safetensors"
	var result: Dictionary = await forge.generate("character", "Гном с бухгалтерской книгой", "sketch", "mage")
	check(result.ok and result.profile.mode == "sketch", "sketch explicitly marked as non-AI")
	check(Rules.valid_profile(result.profile) and Tokens.valid_png(result.png), "sketch produces validated profile and PNG")
	var hash := Tokens.store(result.png)
	check(Tokens.valid_hash(hash) and Tokens.has_portrait(hash), "generated asset stored under content hash")
	check(Tokens.png(hash) == result.png, "PNG persists unchanged")
	check(Tokens.texture("generated:" + hash) != Tokens.TEXTURES.warrior, "generated texture used instead of placeholder")
	check(Tokens.store(result.png, "0".repeat(64)).is_empty(), "wrong hash rejected")
	check(Tokens.png("../path").is_empty(), "cache cannot read arbitrary path")
	var oversized: PackedByteArray = result.png.duplicate()
	oversized.resize(Tokens.MAX_BYTES + 1)
	check(not Tokens.valid_png(oversized), "oversized image bytes rejected")
	var invalid: PackedByteArray = result.png.duplicate()
	invalid[16] = 127
	check(not Tokens.valid_png(invalid), "oversized decoded dimensions rejected before PNG decoding")
	result = await forge.generate("character", "a".repeat(600), "sketch", "rogue")
	check(Rules.valid_profile(result.profile), "maximum prompt length fits generated biography")
	result = await forge.generate("character", "Усталый некромант", "local_ai", "mage")
	check(result.ok and result.profile.name == "Мортис" and result.profile.mode == "local_ai", "AI protocol pipeline returns character")
	check(not result.profile.has("hp") and not result.profile.has("token"), "model stat/path injection discarded")
	check(Tokens.valid_png(result.png), "image service output becomes a bounded PNG")
	var image := Image.new()
	image.load_png_from_buffer(result.png)
	check(image.get_size() == Vector2i(256, 384) and image.get_pixel(0, 0).a == 0, "white background removed and portrait normalized")
	var white_inside := false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a > 0.9 and color.r > 0.95 and color.g > 0.95 and color.b > 0.95:
				white_inside = true
	check(white_inside, "enclosed white clothing retained by border flood-fill")
	var room = Rules.new()
	room.add_player(1, "Герой")
	var key := Tokens.store(result.png)
	check(room.apply_character(1, result.profile, key).is_empty(), "generated profile applied to owner")
	check(int(room.player(1).hp) == 12 and room.player(1).token == "generated:" + key, "appearance changes without combat stat changes")
	room.start(1)
	check(not room.apply_character(1, result.profile, key).is_empty(), "cannot replace character during combat")
	result = await forge.generate("story", "Скелеты требуют выходной", "local_ai", "warrior")
	check(result.ok and result.story.title == "Отдел посмертных сборов", "story generated through text protocol")
	var lobby = Rules.new()
	lobby.add_player(1, "Хост")
	lobby.add_player(2, "Гость")
	check(not lobby.apply_adventure(2, result.story).is_empty(), "guest cannot replace adventure")
	check(lobby.apply_adventure(1, result.story).is_empty(), "host applies validated adventure")
	lobby.start(1)
	check(result.story.opening in " ".join(lobby.data.log), "generated opening enters shared journal at start")
	result = await forge.generate("character", "INVALID_PROFILE", "local_ai", "warrior")
	check(not result.ok and not result.has("png"), "invalid model JSON cannot generate a replacement")
	forge.comfy_url = mock_url + "/missing"
	result = await forge.generate("character", "Герой", "local_ai", "warrior")
	check(not result.ok and not result.has("profile"), "unavailable backend does not silently fall back to sketch")
	var session := root.get_node("Session")
	session.host_room("Хост", 24571)
	session.generate("character", "Маг для теста очереди", "sketch")
	session.send_command("start")
	check(session.state.phase == "lobby", "start blocked while generation queued")
	await _wait_generation(session)
	check(session.state.players[0].token.begins_with("generated:") and session.state.players[0].generation_mode == "sketch", "queued result applied and snapshot updated")
	session.leave_room(false)
	session.host_room("Старая комната", 24571)
	session.generate("character", "Уходящий персонаж", "sketch")
	await process_frame
	session.leave_room(false)
	session.host_room("Новая комната", 24571)
	await _wait_generation(session)
	check(session.state.players[0].name == "Новая комната" and session.state.players[0].token == "warrior", "late result cannot mutate a new room")
	session.leave_room(false)
	print("GENERATION: %s checks, %s failures (mock model APIs, no model quality claim)" % [checks, failures])
	quit(1 if failures else 0)

func _wait_generation(session: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while session.get("_generation_busy") or not session.get("_generation_queue").is_empty():
		if Time.get_ticks_msec() > deadline:
			check(false, "generation timeout")
			return
		await process_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

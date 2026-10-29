extends SceneTree
const Rules = preload("res://scripts/room_state.gd")
const Saves = preload("res://scripts/save_store.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
var checks := 0
var failures := 0
var session: Node
var mock_url := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mock-url="):
			mock_url = arg.trim_prefix("--mock-url=")
		if arg.begins_with("--cache-dir="):
			var directory := arg.trim_prefix("--cache-dir=")
			Tokens.cache_dir = directory.path_join("portraits")
			Saves.directory = directory.path_join("saves")
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("Session")
	root.get_node("Forge").ollama_url = mock_url
	session.host_room("Хост", 24573)
	session.set_director_mode("test")
	session.send_command("start")
	session.send_command("say", {"text": "иду вниз"})
	check(session.state.narrator.busy and not session.my_turn(), "pending intent locks commands")
	session.send_command("move", {"x": 3, "y": 3})
	await idle()
	check(session.state.players[0].x == 2 and session.state.players[0].y == 4 and session.state.moves_left == 2, "text moves exactly once; concurrent button rejected")
	check("Тестовый ведущий:" in " ".join(session.state.log), "non-AI narration clearly labeled")
	var before: Dictionary = session._rules.snapshot()
	session.send_command("say", {"text": "создаю дракона"})
	await idle()
	check(session._rules.snapshot() == before, "clarification spends no resources or turns")
	session.set_director_mode("local_ai")
	session.send_command("say", {"text": "BAD_INTENT"})
	before = session._rules.snapshot()
	await idle()
	check(session._rules.snapshot() == before, "unknown model intent cannot alter world")
	session.send_command("say", {"text": "BAD_JSON"})
	await idle()
	check(session._rules.snapshot() == before, "malformed model JSON rejected without spending turn")
	session.send_command("say", {"text": "MOVE"})
	await idle()
	check(session.state.players[0].y == 5 and session.state.moves_left == 1, "Ollama intent executes through host rules")
	session.send_command("say", {"text": "SLOW"})
	session.cancel_director()
	before = session._rules.snapshot()
	await create_timer(0.6).timeout
	check(session._rules.snapshot() == before and not session.state.narrator.busy, "cancel before commit ignores late model output")
	session.send_command("say", {"text": "MOVE SLOW_NARRATION"})
	var deadline := Time.get_ticks_msec() + 3000
	while not session._director_committed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(session._director_committed, "mechanics commit before delayed narration")
	session.cancel_director()
	before = session._rules.snapshot()
	await create_timer(0.6).timeout
	check(session._rules.snapshot() == before and session.state.players[0].y == 6 and session.state.moves_left == 0, "cancel after commit preserves one movement and ignores late narration")
	# Reset the tactical position to test an attack with failed narration.
	session._rules.data.players[0].y = 5
	session._rules.data.moves_left = 1
	session._publish()
	session.send_command("move", {"x": 3, "y": 5})
	session._rules._rng.seed = 7
	session.send_command("say", {"text": "ATTACK FAIL_NARRATION"})
	await idle()
	check(session.state.actions_left == 0 and session.state.last_roll.damage < 9999, "model cannot inject damage")
	check("Описание ведущего недоступно" in " ".join(session.state.log), "failed narration retains committed mechanics")
	var roll: Dictionary = session.state.last_roll.duplicate(true)
	session.send_command("say", {"text": "ATTACK"})
	await idle()
	check(session.state.last_roll == roll, "retry cannot reroll spent attack")
	# Rule-level validation of model values is independent of the JSON schema.
	var rules := Rules.new()
	rules.add_player(1, "Герой")
	rules.start(1)
	check(not rules.execute_intent(1, {"kind": "move", "x": 2.5, "y": 4}).is_empty(), "fractional coordinates rejected")
	check(not rules.execute_intent(1, {"kind": "move", "x": "2", "y": 4}).is_empty(), "string coordinates rejected")
	check(not rules.execute_intent(1, {"kind": "attack", "target": 1}).is_empty(), "non-string target rejected")
	check(not rules.execute_intent(2, {"kind": "end_turn"}).is_empty(), "director cannot act for another player")
	# A delayed response from an old room must never touch a new one.
	session.send_command("say", {"text": "SLOW"})
	session.leave_room(false)
	session.host_room("Новая комната", 24573)
	before = session._rules.snapshot()
	await create_timer(0.6).timeout
	check(session._rules.snapshot() == before, "old room response cannot alter new room")
	# Save and restore a generated PNG, damaged hero, exact RNG and remaining resources.
	var forge := root.get_node("Forge")
	var generated: Dictionary = await forge.generate("character", "Маг с фонарём", "sketch", "mage")
	var key := Tokens.store(generated.png)
	session._rules.apply_character(1, generated.profile, key)
	session._rules.apply_adventure(1, {"title": "Бухгалтерия", "opening": "Скелет требует отчёт.", "objective": "Победить скелета."})
	session.set_director_mode("test")
	session.send_command("start")
	session.send_command("move", {"x": 2, "y": 4})
	session._rules.data.players[0].hp = 9
	session._rules._rng.seed = 123456
	session._publish()
	before = session._rules.snapshot()
	var rng: int = session._rules._rng.state
	session.save_game()
	var saved := Saves.read_slot()
	check(saved.ok and saved.state == before and saved.rng == rng, "save roundtrip preserves snapshot and exact 64-bit RNG")
	check(saved.portraits[key] == generated.png, "PNG embedded without loss")
	check(Saves.read_slot("autosave").ok, "manual save enables independent autosave")
	session.send_command("move", {"x": 3, "y": 4})
	check(Saves.read_slot().state.players[0].x == 2 and Saves.read_slot("autosave").state.players[0].x == 3, "autosave advances without overwriting manual slot")
	session.load_game("manual", 24573)
	check(session.state.players[0].x == 3, "loading cannot replace a live room")
	session.leave_room(false)
	Tokens._generated.clear()
	DirAccess.remove_absolute(Tokens.cache_dir.path_join(key + ".png"))
	session.load_game("manual", 24573)
	check(session.hosting and session._rules.snapshot() == before and Tokens.png(key) == generated.png, "offline load restores combat and missing portrait cache")
	check(session.my_turn() and session.state.moves_left == 2 and session.state.players[0].hp == 9, "restore resumes current turn without healing or reset")
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = rng
	check(session._rules._rng.randi() == expected_rng.randi(), "next random result survives restart")
	session.save_game() # Creates .bak.
	var path := Saves.directory.path_join("manual.json")
	var original := FileAccess.get_file_as_string(path)
	write_text(path, "{broken")
	saved = Saves.read_slot()
	check(saved.ok and saved.recovered, "damaged primary falls back to checked backup")
	DirAccess.remove_absolute(path + ".bak")
	var doc: Dictionary = JSON.parse_string(original)
	doc.state.players[0].max_hp = 9999
	write_text(path, JSON.stringify(doc))
	check(not Saves.read_slot().ok, "tampered combat stats rejected")
	doc = JSON.parse_string(original)
	doc.portraits[key] = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))
	write_text(path, JSON.stringify(doc))
	check(not Saves.read_slot().ok, "corrupt embedded PNG rejected")
	doc = JSON.parse_string(original)
	doc.state.players[0].x = "oops"
	write_text(path, JSON.stringify(doc))
	check(not Saves.read_slot().ok, "wrong save value types rejected safely")
	write_text(path, "x".repeat(Saves.MAX_FILE + 1))
	check(not Saves.read_slot().ok, "oversized save rejected before parsing")
	write_text(path, original)
	session._rules.data.phase = "lobby"
	session._rules.add_player(2, "Гость")
	check(not Saves.write_slot(session._rules).is_empty(), "multiplayer save blocked until reconnect support exists")
	check(FileAccess.get_file_as_string(path) == original, "unsupported save cannot overwrite good slot")
	session.leave_room(false)
	print("DIRECTOR/SAVES: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)

func idle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while session._director_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not session._director_busy, "director finishes within fixture deadline")

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

extends SceneTree
## Real ENet transfer between isolated portrait caches (not a shared filesystem hit).
const Tokens = preload("res://scripts/token_catalog.gd")
var session: Node
var role := ""
var port := 24572
var stage := 0
var started := 0
var finished := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--cache-dir="):
			Tokens.cache_dir = arg.trim_prefix("--cache-dir=")
	call_deferred("_begin")

func _begin() -> void:
	session = root.get_node("Session")
	session.notice.connect(_notice)
	started = Time.get_ticks_msec()
	if role == "host":
		session.host_room("Хост", port)
		session.generate("character", "Хост с необычной мантией", "sketch")
	else:
		session.join_room("Гость", "127.0.0.1", port, "mage")

func _process(_delta: float) -> bool:
	if session == null or finished:
		return false
	if Time.get_ticks_msec() - started > 14000:
		_fail("timeout at stage " + str(stage))
		return false
	if session.state.is_empty():
		return false
	var players: Array = session.state.players
	if role == "host":
		if stage == 0 and players[0].token.begins_with("generated:") and not session.state.generation.busy:
			stage = 1
			print("HOST_READY")
		elif stage == 1 and players.size() == 2 and players[1].token.begins_with("generated:"):
			var key: String = players[1].token.trim_prefix("generated:")
			if Tokens.png(key).is_empty() or players[1].generation_mode != "sketch":
				_fail("host did not persist generated client image")
				return false
			print("GEN_HOST_TOKEN:" + key)
			stage = 2
		elif stage == 2 and players.size() == 1:
			finished = true
			print("GEN_NETWORK_HOST_PASS")
			session.leave_room(false)
			quit()
	else:
		if stage == 0 and players[0].token.begins_with("generated:"):
			var key: String = players[0].token.trim_prefix("generated:")
			if not Tokens.has_portrait(key):
				return false
			if Tokens.png(key).is_empty():
				_fail("late joiner did not receive host PNG")
				return false
			stage = 1
			session.generate("character", "Гость в зелёной мантии", "sketch")
		elif stage == 1:
			for player in players:
				if int(player.id) == session.local_id() and player.token.begins_with("generated:"):
					var key: String = player.token.trim_prefix("generated:")
					if not Tokens.has_portrait(key):
						return false
					if Tokens.digest(Tokens.png(key)) != key or player.generation_mode != "sketch":
						_fail("received PNG hash or profile differs")
						return false
					print("GEN_CLIENT_TOKEN:" + key)
					stage = 2
					session.generate("story", "Недопустимая смена сюжета гостем", "sketch")
	return false

func _notice(message: String) -> void:
	if role == "client" and stage == 2 and "только хост" in message:
		finished = true
		print("GEN_NETWORK_CLIENT_PASS")
		session.leave_room(false)
		quit()

func _fail(message: String) -> void:
	finished = true
	printerr("GEN_NETWORK_FAIL " + role + ": " + message)
	quit(1)

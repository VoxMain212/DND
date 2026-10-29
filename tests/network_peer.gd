extends SceneTree
## Run by run_tests.py as two independent Godot processes over real ENet/UDP.

var session: Node
var role := ""
var stage := 0
var started := 0
var rejection_seen := false
var finished := false
var port := 24568
var host_turn_at := 0
var attack_seen := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	call_deferred("_begin")

func _begin() -> void:
	session = root.get_node("Session")
	session.notice.connect(_notice)
	if role == "host":
		session.changed.connect(_observe_attack)
	started = Time.get_ticks_msec()
	if role == "host":
		session.host_room("Хост", port)
		if not session.hosting:
			_fail("host did not start")
		print("HOST_READY")
	else:
		session.join_room("Гость", "127.0.0.1", port, "mage")

func _process(_delta: float) -> bool:
	if session == null or finished:
		return false
	if Time.get_ticks_msec() - started > 12000:
		_fail("timeout, stage=" + str(stage))
		return false
	if session.state.is_empty():
		return false
	var state: Dictionary = session.state
	if role == "host":
		if stage == 0 and state.players.size() == 2:
			stage = 1
			session.set_director_mode("test")
			session.send_command("start")
			# A durable target lets every possible d20 outcome complete the test.
			session.get("_rules").data.enemies[0].hp = 100
			session.get("_rules").data.enemies[0].max_hp = 100
			session.call("_publish")
			host_turn_at = Time.get_ticks_msec()
		elif stage == 1 and Time.get_ticks_msec() - host_turn_at > 700:
			stage = 2
			session.send_command("move", {"x": 2, "y": 4})
			session.send_command("end_turn")
		elif stage == 2 and int(state.active) == 1 and int(state.round) == 2 and not state.narrator.busy:
			if not attack_seen or state.players[1].token != "mage":
				_fail("attack or selected PNG was not replicated")
				return false
			if int(state.players[0].y) != 4 or int(state.players[1].y) != 5:
				_fail("positions do not match expected moves")
				return false
			var found := false
			for line in state.log:
				if "Проверяю книгу жалоб" in line:
					found = true
			if not found:
				_fail("text action missing from authoritative journal")
				return false
			if not "Тестовый ведущий:" in " ".join(state.log):
				_fail("director narration was not replicated")
				return false
			stage = 3
			finished = true
			session.leave_room(false)
			print("NETWORK_HOST_PASS")
			quit()
	else:
		if stage == 0 and state.phase == "playing":
			stage = 1
			session.send_command("move", {"x": 3, "y": 5})
		elif stage == 1 and session.my_turn():
			if not rejection_seen:
				_fail("out-of-turn command was not rejected")
				return false
			if int(state.players[0].y) != 4:
				_fail("host movement was not replicated")
				return false
			stage = 2
			session.send_command("say", {"text": "иду вверх"})
		elif stage == 2:
			for entry in state.players:
				if int(entry.id) == session.local_id() and int(entry.y) == 5 and not state.narrator.busy:
					stage = 3
					session.send_command("attack", {"target": "collector"})
		elif stage == 3 and int(state.actions_left) == 0:
			if state.last_roll.get("attacker") != "Гость" or int(state.enemies[0].hp) != 100 - int(state.last_roll.damage):
				_fail("client damage disagrees with authoritative d20 result")
				return false
			print("CLIENT_ROLL:" + JSON.stringify(state.last_roll))
			stage = 4
			session.send_command("say", {"text": "говорю: Проверяю книгу жалоб"})
	return false

func _notice(message: String) -> void:
	if "Сейчас ход другого" in message:
		rejection_seen = true
	if role == "client" and stage == 4 and "Хост закрыл" in message:
		finished = true
		print("NETWORK_CLIENT_PASS")
		quit()

func _observe_attack() -> void:
	var state: Dictionary = session.state
	if attack_seen or state.get("last_roll", {}).get("attacker") != "Гость":
		return
	if int(state.enemies[0].hp) != 100 - int(state.last_roll.damage):
		_fail("host damage disagrees with roll")
		return
	attack_seen = true
	print("HOST_ROLL:" + JSON.stringify(state.last_roll))

func _fail(message: String) -> void:
	finished = true
	printerr("NETWORK_FAIL " + role + ": " + message)
	quit(1)

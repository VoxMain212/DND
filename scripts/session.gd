extends Node
## All commands run on the host. Clients only receive authoritative snapshots.

signal changed
signal notice(message: String)

const Rules = preload("res://scripts/room_state.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
const Saves = preload("res://scripts/save_store.gd")
const PROTOCOL := 4
const DEFAULT_PORT := 24567

var state: Dictionary = {}
var connected := false
var hosting := false
var connecting := false
var room_port := DEFAULT_PORT
var _name := "Путник"
var _token := "warrior"
var _rules = null
var _sequence := 0
var _rates: Dictionary = {}
var _pending: Dictionary = {}
var _connect_timer: Timer
var _generation_epoch := 0
var _generation_queue: Array[Dictionary] = []
var _generation_pending: Dictionary = {}
var _generation_busy := false
var _active_generation: Dictionary = {}
var _generation_stage := ""
var _generation_limits: Dictionary = {}
var _incoming: Dictionary = {}
var _requested_portraits: Dictionary = {}
var _sending: Dictionary = {}
var _director_busy := false
var _director_actor := 0
var _director_stage := ""
var _director_ticket := 0
var _director_committed := false
var _autosave := false
var _saved_version := -1

func _ready() -> void:
	Forge.progress.connect(_forge_progress)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_left)
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = 10.0
	_connect_timer.timeout.connect(_connection_failed)
	add_child(_connect_timer)

func host_room(player_name: String, port: int, token := "warrior") -> void:
	leave_room(false)
	if port < 1024 or port > 65535:
		notice.emit("Порт должен быть от 1024 до 65535.")
		return
	if token not in Rules.TOKEN_KEYS:
		notice.emit("Выберите образ персонажа из списка.")
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, Rules.MAX_PLAYERS - 1)
	if error != OK:
		notice.emit("Не удалось открыть UDP-порт %s: %s" % [port, error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	hosting = true
	connected = true
	room_port = port
	_name = Rules.clean_name(player_name)
	_token = token
	_rules = Rules.new()
	_rules.add_player(1, _name, _token)
	_publish()
	notice.emit("Комната открыта. Порт %s / UDP." % port)

func join_room(player_name: String, address: String, port: int, token := "warrior") -> void:
	leave_room(false)
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		notice.emit("Укажите адрес и порт от 1024 до 65535.")
		return
	_name = Rules.clean_name(player_name)
	_token = token
	room_port = port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		notice.emit("Не удалось начать подключение: %s" % error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	connecting = true
	_connect_timer.start()
	changed.emit()
	notice.emit("Подключение к %s:%s…" % [address.strip_edges(), port])

func leave_room(announce := true) -> void:
	Director.cancel()
	_director_ticket += 1
	_director_busy = false
	_director_committed = false
	_director_stage = ""
	_autosave = false
	_saved_version = -1
	_generation_epoch += 1
	_generation_queue.clear()
	_generation_pending.clear()
	_generation_limits.clear()
	_incoming.clear()
	_requested_portraits.clear()
	_sending.clear()
	if _connect_timer != null:
		_connect_timer.stop()
	connected = false
	hosting = false
	connecting = false
	state = {}
	_rules = null
	_rates.clear()
	_pending.clear()
	_sequence = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	changed.emit()
	if announce:
		notice.emit("Вы вышли из комнаты.")

func local_id() -> int:
	return multiplayer.get_unique_id() if connected else 0

func my_turn() -> bool:
	return connected and not state.get("narrator", {}).get("busy", false) and state.get("phase") == "playing" and int(state.get("active", 0)) == local_id()

func send_command(kind: String, extra: Dictionary = {}) -> void:
	if not connected or state.is_empty():
		return
	_sequence += 1
	var packet := extra.duplicate()
	packet["kind"] = kind
	packet["request_id"] = _sequence
	packet["version"] = int(state.version)
	if hosting:
		_handle_command(1, packet)
	else:
		_request_command.rpc_id(1, packet)

func _on_connected() -> void:
	_register.rpc_id(1, _name, PROTOCOL, _token)

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, protocol: int, token := "warrior") -> void:
	if not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _pending.has(sender):
		return
	_pending.erase(sender)
	var error: String = "Разные версии игры. Обновите прототип у всех игроков." if protocol != PROTOCOL else _rules.add_player(sender, player_name, token)
	if not error.is_empty():
		_admission_denied.rpc_id(sender, error)
		# Let the reliable rejection arrive before disconnecting.
		await get_tree().create_timer(0.3).timeout
		if hosting and multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	_publish()

@rpc("authority", "call_remote", "reliable")
func _admission_denied(message: String) -> void:
	leave_room(false)
	notice.emit(message)

@rpc("any_peer", "call_remote", "reliable")
func _request_command(packet: Dictionary) -> void:
	if hosting:
		_handle_command(multiplayer.get_remote_sender_id(), packet)

func _handle_command(sender: int, packet: Dictionary) -> void:
	if _rules == null:
		return
	if _director_busy:
		_generation_notice(sender, "Дождитесь ведущего или отмените его запрос в мастерской.")
		return
	if packet.get("kind") == "start" and (_generation_busy or not _generation_queue.is_empty()):
		_generation_notice(sender, "Дождитесь завершения генерации перед началом партии.")
		return
	var now := Time.get_ticks_msec()
	var rate: Dictionary = _rates.get(sender, {"at": now, "count": 0})
	if now - int(rate.at) >= 1000:
		rate = {"at": now, "count": 0}
	rate.count += 1
	_rates[sender] = rate
	if int(rate.count) > 12:
		return
	if packet.get("kind") == "say" and _rules.data.director_mode != "off":
		var reserved := packet.duplicate()
		reserved.kind = "prepare_text"
		var rejection: String = _rules.command(sender, reserved)
		if not rejection.is_empty():
			_generation_notice(sender, rejection)
			return
		_run_director(sender, packet.text)
		return
	var error: String = _rules.command(sender, packet)
	if not error.is_empty():
		if sender == 1:
			notice.emit(error)
		else:
			_rejected.rpc_id(sender, error)
		return
	_publish()

@rpc("authority", "call_remote", "reliable")
func _rejected(message: String) -> void:
	notice.emit(message)

func _publish() -> void:
	state = _rules.snapshot()
	state.narrator = {"busy": _director_busy, "actor": _director_actor, "stage": _director_stage}
	state.generation = {"busy": _generation_busy, "queued": _generation_queue.size(), "stage": _generation_stage,
		"requesters": _generation_pending.keys()}
	_snapshot.rpc(state)
	changed.emit()
	if _autosave and int(state.version) != _saved_version and state.players.size() == 1:
		_saved_version = int(state.version)
		var error := Saves.write_slot(_rules, "autosave")
		if not error.is_empty():
			notice.emit("Автосохранение: " + error)

@rpc("authority", "call_remote", "reliable")
func _snapshot(snapshot: Dictionary) -> void:
	if hosting:
		return
	state = snapshot
	connected = true
	connecting = false
	_connect_timer.stop()
	_request_missing_portraits()
	changed.emit()

func _peer_connected(peer_id: int) -> void:
	if not hosting:
		return
	_pending[peer_id] = true
	await get_tree().create_timer(8.0).timeout
	if hosting and _pending.has(peer_id):
		_pending.erase(peer_id)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func _peer_left(peer_id: int) -> void:
	if hosting:
		if _director_busy:
			_cancel_director()
		_generation_queue = _generation_queue.filter(func(job): return int(job.peer) != peer_id)
		_generation_pending.erase(peer_id)
		_pending.erase(peer_id)
		_rates.erase(peer_id)
		_rules.remove_player(peer_id)
		_publish()

func _connection_failed() -> void:
	leave_room(false)
	notice.emit("Подключиться не удалось. Проверьте IP, порт и доступность хоста.")

func _server_left() -> void:
	leave_room(false)
	notice.emit("Хост закрыл комнату или соединение прервалось.")

func generate(kind: String, prompt: String, mode: String) -> void:
	if not connected:
		notice.emit("Сначала создайте комнату или подключитесь к хосту.")
		return
	if hosting:
		_queue_generation(1, kind, prompt, mode)
	else:
		_request_generation.rpc_id(1, kind, prompt, mode)

@rpc("any_peer", "call_remote", "reliable")
func _request_generation(kind: String, prompt: String, mode: String) -> void:
	if hosting:
		_queue_generation(multiplayer.get_remote_sender_id(), kind, prompt, mode)

func _queue_generation(peer: int, kind: String, prompt: String, mode: String) -> void:
	if _rules == null or _rules.player(peer) == null:
		return
	if _director_busy:
		_generation_notice(peer, "Сначала дождитесь ведущего или отмените его запрос.")
		return
	if kind not in ["character", "story"] or mode not in ["sketch", "local_ai"] or prompt.strip_edges().is_empty() or prompt.length() > 600:
		_generation_notice(peer, "Укажите запрос от 1 до 600 символов и режим генерации.")
		return
	if _rules.data.phase not in ["lobby", "finished"] or (kind == "story" and peer != 1):
		_generation_notice(peer, "Персонажей создают до боя; завязку выбирает только хост.")
		return
	if _generation_pending.has(peer) or _generation_queue.size() >= 4:
		_generation_notice(peer, "Ваш запрос уже в очереди или очередь заполнена.")
		return
	var now := Time.get_ticks_msec()
	if now - int(_generation_limits.get(peer, -10000)) < 3000:
		_generation_notice(peer, "Подождите три секунды перед следующей генерацией.")
		return
	_generation_limits[peer] = now
	_generation_pending[peer] = true
	var token: String = _rules.player(peer).token
	if token not in Rules.TOKEN_KEYS:
		token = "warrior"
	_generation_queue.append({"peer": peer, "kind": kind, "prompt": prompt.strip_edges(), "mode": mode, "token": token, "epoch": _generation_epoch})
	_publish()
	_generation_notice(peer, "Запрос добавлен в очередь хоста.")
	_process_generation.call_deferred()

func _process_generation() -> void:
	if _generation_busy:
		return
	_generation_busy = true
	while not _generation_queue.is_empty():
		var job: Dictionary = _generation_queue.pop_front()
		_active_generation = job
		_generation_stage = "Начинаем генерацию…"
		if hosting:
			_publish()
		var result: Dictionary = await Forge.generate(job.kind, job.prompt, job.mode, job.token)
		if not hosting or int(job.epoch) != _generation_epoch:
			continue
		_generation_pending.erase(int(job.peer))
		if _rules.player(int(job.peer)) == null:
			continue
		var error := ""
		if not result.get("ok", false):
			error = result.get("error", "Ошибка генерации.")
		elif job.kind == "character":
			var digest := Tokens.store(result.png)
			error = "Не удалось сохранить PNG-фишку (проверьте размер и число портретов)." if digest.is_empty() else _rules.apply_character(int(job.peer), result.profile, digest)
		else:
			error = _rules.apply_adventure(int(job.peer), result.story)
		_generation_notice(int(job.peer), "Готово. Результат добавлен в комнату." if error.is_empty() else error)
	_generation_busy = false
	_active_generation = {}
	_generation_stage = ""
	if hosting:
		_publish()

func _forge_progress(message: String) -> void:
	if hosting and int(_active_generation.get("epoch", -1)) == _generation_epoch:
		_generation_stage = message
		_publish()

func _generation_notice(peer: int, message: String) -> void:
	if peer == 1:
		notice.emit(message)
	elif connected and hosting and peer in multiplayer.get_peers():
		_generation_message.rpc_id(peer, message)

@rpc("authority", "call_remote", "reliable")
func _generation_message(message: String) -> void:
	notice.emit(message)

func set_director_mode(mode: String) -> void:
	if not hosting or _rules == null or _director_busy or mode not in ["off", "test", "local_ai"]:
		return
	_rules.data.director_mode = mode
	_rules._event("Ведущий: " + {"off": "выключен", "test": "тест без ИИ", "local_ai": "локальная модель Ollama"}[mode])
	_publish()

func cancel_director() -> void:
	if hosting:
		_cancel_director()
	elif connected:
		_request_cancel_director.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_cancel_director() -> void:
	if hosting and multiplayer.get_remote_sender_id() == _director_actor:
		_cancel_director()

func _cancel_director() -> void:
	if not _director_busy:
		return
	Director.cancel()
	_director_ticket += 1
	_director_busy = false
	_director_stage = ""
	if _director_committed:
		_rules._event("Описание ведущего отменено. Рассчитанный результат действия сохранён.")
	_director_committed = false
	_publish()

func _run_director(actor: int, text: String) -> void:
	_director_ticket += 1
	var ticket := _director_ticket
	var epoch := _generation_epoch
	var version: int = _rules.data.version
	var mode: String = _rules.data.director_mode
	_director_busy = true
	_director_committed = false
	_director_actor = actor
	_director_stage = "Ведущий разбирает действие…"
	_publish()
	var context := {"actor": _rules.player(actor).duplicate(true), "players": _rules.data.players.duplicate(true),
		"enemies": _rules.data.enemies.duplicate(true), "blocked": [], "moves_left": _rules.data.moves_left,
		"actions_left": _rules.data.actions_left, "adventure": _rules.data.adventure.duplicate(true)}
	for cell in Rules.BLOCKED:
		context.blocked.append({"x": cell.x, "y": cell.y})
	var reply: Dictionary = await Director.interpret(text, context, mode)
	if not _director_valid(ticket, epoch):
		return
	var error: String = reply.get("error", "")
	if int(_rules.data.version) != version:
		error = "Стол изменился. Повторите действие."
	if reply.get("ok", false) and error.is_empty():
		var intent: Dictionary = reply.value
		if intent.get("kind") == "clarify":
			var question = intent.get("question", "Уточните действие.")
			error = question.left(300) if typeof(question) == TYPE_STRING else "Уточните действие."
		else:
			var before_log: Array = _rules.data.log.duplicate()
			error = _rules.execute_intent(actor, intent)
			if error.is_empty():
				_director_committed = true
				var facts: Array = []
				# Events can roll over the bounded log; compare the shared suffix.
				var overlap := mini(before_log.size(), _rules.data.log.size())
				while overlap > 0 and before_log.slice(before_log.size() - overlap) != _rules.data.log.slice(0, overlap):
					overlap -= 1
				facts = _rules.data.log.slice(overlap)
				_rules._event("%s: %s" % [_rules.player(actor).name, text.replace("\n", " ")])
				_director_stage = "Действие рассчитано. Ведущий описывает результат…"
				_publish() # Persist the dice before awaiting flavor; never execute them twice.
				var narration: Dictionary = await Director.narrate(text, facts, mode)
				if not _director_valid(ticket, epoch):
					return
				var line = narration.get("value", {}).get("narration", "")
				if narration.get("ok", false) and typeof(line) == TYPE_STRING and not line.strip_edges().is_empty() and line.length() <= 600:
					_rules._event(("Тестовый ведущий: " if mode == "test" else "ИИ-ведущий: ") + line.strip_edges())
				else:
					_rules._event("Описание ведущего недоступно. Результат в журнале правил уже применён; повторного броска нет.")
	elif error.is_empty():
		error = "Ведущий не смог разобрать действие."
	_director_busy = false
	_director_committed = false
	_director_stage = ""
	_publish()
	if not error.is_empty():
		_generation_notice(actor, error)

func _director_valid(ticket: int, epoch: int) -> bool:
	return hosting and _rules != null and _director_ticket == ticket and _generation_epoch == epoch

func save_game() -> void:
	if not hosting or _rules == null or _director_busy or _generation_busy:
		notice.emit("Сохранение доступно хосту после завершения текущего запроса.")
		return
	var error := Saves.write_slot(_rules)
	if error.is_empty():
		_autosave = true
		_saved_version = -1
		_publish()
		notice.emit("Партия сохранена. Автосохранение включено до выхода из комнаты.")
	else:
		notice.emit(error)

func load_game(slot: String, port: int) -> void:
	if connected or connecting or _generation_busy or _director_busy:
		notice.emit("Для загрузки сначала выйдите из комнаты и дождитесь завершения генерации.")
		return
	var saved := Saves.read_slot(slot)
	if not saved.ok:
		notice.emit(saved.error)
		return
	for key in saved.portraits:
		if Tokens.store(saved.portraits[key], key).is_empty():
			notice.emit("Не удалось восстановить PNG персонажа.")
			return
	host_room(saved.state.players[0].name, port)
	if not hosting:
		return
	_rules.data = saved.state
	_rules._rng.state = saved.rng
	_autosave = true
	_saved_version = int(_rules.data.version)
	_publish()
	notice.emit("Партия восстановлена из резервной копии." if saved.recovered else "Партия восстановлена. Можно продолжать ход.")

func _request_missing_portraits() -> void:
	for player in state.get("players", []):
		var token: String = player.token
		if not token.begins_with("generated:"):
			continue
		var key := token.trim_prefix("generated:")
		if not Tokens.valid_hash(key) or Tokens.has_portrait(key) or _requested_portraits.has(key):
			continue
		_requested_portraits[key] = Time.get_ticks_msec()
		_request_portrait.rpc_id(1, key)

@rpc("any_peer", "call_remote", "reliable", 1)
func _request_portrait(key: String) -> void:
	if not hosting or _rules == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	if _rules.player(peer) == null:
		return
	for player in _rules.data.players:
		if player.token == "generated:" + key:
			_send_portrait(peer, key)
			return

func _send_portrait(peer: int, key: String) -> void:
	var ticket := "%s:%s" % [peer, key]
	if _sending.has(ticket):
		return
	var bytes := Tokens.png(key)
	if bytes.is_empty():
		return
	_sending[ticket] = true
	var epoch := _generation_epoch
	_portrait_begin.rpc_id(peer, key, bytes.size())
	for offset in range(0, bytes.size(), 16384):
		if not hosting or epoch != _generation_epoch or peer not in multiplayer.get_peers():
			break
		_portrait_chunk.rpc_id(peer, key, offset, bytes.slice(offset, mini(offset + 16384, bytes.size())))
		await get_tree().process_frame
	if epoch == _generation_epoch:
		_sending.erase(ticket)

@rpc("authority", "call_remote", "reliable", 1)
func _portrait_begin(key: String, total: int) -> void:
	if not Tokens.valid_hash(key) or total < 33 or total > Tokens.MAX_BYTES or _incoming.size() >= 4 or Tokens.has_portrait(key):
		return
	var at := Time.get_ticks_msec()
	_incoming[key] = {"total": total, "data": PackedByteArray(), "at": at}
	await get_tree().create_timer(30.0).timeout
	if _incoming.has(key) and int(_incoming[key].at) == at:
		_incoming.erase(key)
		_requested_portraits.erase(key)
		notice.emit("Не удалось получить PNG-фишку. Попробуйте переподключиться.")

@rpc("authority", "call_remote", "reliable", 1)
func _portrait_chunk(key: String, offset: int, chunk: PackedByteArray) -> void:
	if not _incoming.has(key):
		return
	var transfer: Dictionary = _incoming[key]
	var bytes: PackedByteArray = transfer.data
	if offset != bytes.size() or chunk.size() > 16384 or bytes.size() + chunk.size() > int(transfer.total):
		_incoming.erase(key)
		_requested_portraits.erase(key)
		return
	bytes.append_array(chunk)
	transfer.data = bytes
	if bytes.size() == int(transfer.total):
		_incoming.erase(key)
		_requested_portraits.erase(key)
		if Tokens.store(bytes, key).is_empty():
			notice.emit("Полученная PNG-фишка не прошла проверку.")
		else:
			changed.emit()

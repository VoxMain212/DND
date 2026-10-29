extends RefCounted
## Bounded JSON only. No object deserialization or external image paths.
const Rules = preload("res://scripts/room_state.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
const MAX_FILE := 1048576
static var directory := "user://saves"

static func write_slot(rules, slot := "manual") -> String:
	if slot not in ["manual", "autosave"]:
		return "Неизвестный слот."
	if rules.data.players.size() != 1 or int(rules.data.players[0].id) != 1:
		return "Пока сохраняются только партии с одним игроком. Сетевое восстановление ещё не готово."
	var portraits := {}
	var token: String = rules.data.players[0].token
	if token.begins_with("generated:"):
		var key := token.trim_prefix("generated:")
		var png := Tokens.png(key)
		if png.is_empty():
			return "PNG персонажа недоступна. Сохранение не изменено."
		portraits[key] = Marshalls.raw_to_base64(png)
	var document := {"format": 1, "state": rules.snapshot(), "rng": str(rules._rng.state), "portraits": portraits}
	var text := JSON.stringify(document)
	if text.to_utf8_buffer().size() > MAX_FILE:
		return "Сохранение превышает допустимый размер."
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Не удалось создать каталог сохранений."
	var path := directory.path_join(slot + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "Не удалось записать сохранение."
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "Ошибка записи сохранения; прежний файл оставлен."
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			return "Не удалось сохранить резервную копию."
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return "Не удалось завершить запись; доступна резервная копия."
	return ""

static func read_slot(slot := "manual") -> Dictionary:
	if slot not in ["manual", "autosave"]:
		return {"ok": false, "error": "Неизвестный слот."}
	var path := directory.path_join(slot + ".json")
	var result := _read(path)
	if not result.ok:
		var backup := _read(path + ".bak")
		if backup.ok:
			backup.recovered = true
			return backup
	return result

static func _read(path: String) -> Dictionary:
	var failure := {"ok": false, "error": "Сохранение отсутствует, повреждено или имеет несовместимую версию."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE:
		return failure
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return failure
	var document = _integers(parser.data)
	if typeof(document) != TYPE_DICTIONARY or document.get("format") != 1 or typeof(document.get("rng")) != TYPE_STRING or not document.rng.is_valid_int():
		return failure
	if typeof(document.get("state")) != TYPE_DICTIONARY or typeof(document.get("portraits")) != TYPE_DICTIONARY:
		return failure
	var data: Dictionary = document.state
	var rules := Rules.new()
	if not _shape(data, rules.data) or data.phase not in ["lobby", "playing", "finished"] or data.director_mode not in ["off", "test", "local_ai"]:
		return failure
	if data.players.size() != 1 or data.enemies.size() > 1 or data.log.size() > 80 or data.host_id != 1 or data.round < 1 or data.round > 1000000 or data.version < 0:
		return failure
	if data.moves_left < 0 or data.moves_left > 3 or data.actions_left < 0 or data.actions_left > 1 or data.outcome not in ["", "victory", "defeat"]:
		return failure
	rules.add_player(1, "Путник")
	var hero = data.players[0]
	if not _actor(hero, rules.data.players[0]) or hero.id != 1:
		return failure
	rules.start(1)
	for enemy in data.enemies:
		if not _actor(enemy, rules.data.enemies[0]) or enemy.id != "collector" or enemy.token != "skeleton" or enemy.speed != 2:
			return failure
	if data.phase == "playing" and (data.active != 1 or data.enemies.size() != 1 or hero.hp <= 0):
		return failure
	if data.phase != "playing" and data.active != 0:
		return failure
	for line in data.log:
		if typeof(line) != TYPE_STRING or line.length() > 2000:
			return failure
	if not data.adventure.is_empty() and not rules.apply_adventure(1, data.adventure).is_empty():
		# apply_adventure is allowed in the lobby/finished phase only.
		rules.data.phase = "lobby"
		if not rules.apply_adventure(1, data.adventure).is_empty():
			return failure
	if not data.last_roll.is_empty():
		rules._resolve_attack(rules.data.players[0], rules.data.enemies[0])
		if not _shape(data.last_roll, rules.data.last_roll) or data.last_roll.damage_rolls.size() > 2:
			return failure
	var portraits := {}
	if document.portraits.size() > 1:
		return failure
	if hero.token.begins_with("generated:"):
		var key: String = hero.token.trim_prefix("generated:")
		if not Tokens.valid_hash(key) or typeof(document.portraits.get(key)) != TYPE_STRING:
			return failure
		var png := Marshalls.base64_to_raw(document.portraits[key])
		if not Tokens.valid_png(png) or Tokens.digest(png) != key:
			return failure
		portraits[key] = png
	elif hero.token not in Rules.TOKEN_KEYS:
		return failure
	return {"ok": true, "state": data, "rng": document.rng.to_int(), "portraits": portraits, "recovered": false}

static func _actor(value, template: Dictionary) -> bool:
	if not _shape(value, template):
		return false
	if not Rules.walkable(Vector2i(value.x, value.y)) or value.name.length() > 24 or value.color != template.color:
		return false
	for field in ["max_hp", "ac", "attack_bonus", "damage_die", "damage_bonus"]:
		if value[field] != template[field]:
			return false
	return value.hp >= 0 and value.hp <= value.max_hp and typeof(value.get("bio", "")) == TYPE_STRING and value.get("bio", "").length() <= 600

static func _shape(value, template) -> bool:
	if typeof(value) != typeof(template):
		return false
	if typeof(template) == TYPE_DICTIONARY:
		for key in template:
			if not value.has(key) or not _shape(value[key], template[key]):
				return false
	return true

static func _integers(value, depth := 0):
	if depth > 20:
		return null
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and abs(value) < 9007199254740992.0:
		return int(value)
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			value[key] = _integers(value[key], depth + 1)
	if typeof(value) == TYPE_ARRAY:
		for index in value.size():
			value[index] = _integers(value[index], depth + 1)
	return value

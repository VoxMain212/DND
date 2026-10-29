extends RefCounted
## Pure authoritative rules; no network or UI dependencies.

const WIDTH := 14
const HEIGHT := 10
const MAX_PLAYERS := 4
const SPAWNS := [Vector2i(2, 3), Vector2i(3, 6), Vector2i(10, 3), Vector2i(10, 6)]
const COLORS := ["#e7b86b", "#78c8c4", "#c395db", "#de8e82"]
const TOKEN_KEYS := ["warrior", "mage", "rogue", "cleric"]
const BLOCKED := [Vector2i(6, 3), Vector2i(7, 3), Vector2i(6, 4), Vector2i(7, 4), Vector2i(6, 6), Vector2i(7, 6)]

var data: Dictionary = {}
var _seen: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	data = {"phase": "lobby", "players": [], "active": 0, "round": 1,
		"moves_left": 3, "actions_left": 1, "enemies": [], "last_roll": {},
		"outcome": "", "version": 0, "log": [], "host_id": 1, "adventure": {}, "director_mode": "off"}

func add_player(peer_id: int, player_name: String, token := "warrior") -> String:
	if data.phase != "lobby":
		return "Партия уже началась. Подключение возможно в следующем лобби."
	if player(peer_id) != null:
		return "Игрок уже в комнате."
	if data.players.size() >= MAX_PLAYERS:
		return "В комнате уже четыре игрока."
	if token not in TOKEN_KEYS:
		return "Неизвестный образ персонажа."
	var slot: int = data.players.size()
	for candidate in range(MAX_PLAYERS):
		var taken := false
		for existing in data.players:
			if existing.color == COLORS[candidate]:
				taken = true
		if not taken:
			slot = candidate
			break
	var spawn: Vector2i = SPAWNS[slot]
	data.players.append({"id": peer_id, "name": clean_name(player_name),
		"x": spawn.x, "y": spawn.y, "color": COLORS[slot], "token": token,
		"hp": 12, "max_hp": 12, "ac": 12, "attack_bonus": 4, "damage_die": 6, "damage_bonus": 2})
	_event("%s входит в таверну. Некромант проверяет наличие пульса." % clean_name(player_name))
	return ""

func remove_player(peer_id: int) -> void:
	var who = player(peer_id)
	if who == null:
		return
	var old_active: int = int(data.active)
	data.players.erase(who)
	_seen.erase(peer_id)
	if data.phase in ["playing", "finished"]:
		# A disconnected participant ends the scene; no ambiguous lost turn.
		data.phase = "lobby"
		data.active = 0
		data.enemies = []
		data.outcome = ""
		data.last_roll = {}
		_event("%s отключился. Партия возвращена в лобби; хост может начать заново." % who.name)
	else:
		data.active = old_active if player(old_active) != null else 0
		_event("%s покидает комнату." % who.name)

func start(peer_id: int) -> String:
	if peer_id != int(data.host_id):
		return "Начать партию может только создатель комнаты."
	if data.phase not in ["lobby", "finished"]:
		return "Партия уже идёт."
	if data.players.is_empty():
		return "В комнате нет игроков."
	for index in range(data.players.size()):
		var spawn: Vector2i = SPAWNS[index]
		data.players[index].x = spawn.x
		data.players[index].y = spawn.y
		data.players[index].hp = data.players[index].max_hp
	data.phase = "playing"
	data.active = int(data.players[0].id)
	data.round = 1
	data.moves_left = 3
	data.actions_left = 1
	data.outcome = ""
	data.last_roll = {}
	data.enemies = [{"id": "collector", "name": "Скелет-сборщик", "x": 4, "y": 5,
		"token": "skeleton", "color": "#d87b71", "hp": 10, "max_hp": 10, "ac": 11,
		"attack_bonus": 2, "damage_die": 4, "damage_bonus": 0, "speed": 2}]
	_event("Таверна «Последний вздох». Скелет-сборщик требует оплатить прошлую жизнь. Победите его: подойдите на соседнюю клетку и атакуйте.")
	if not data.adventure.is_empty():
		_event(data.adventure.title + ": " + data.adventure.opening)
		_event("Цель: " + data.adventure.objective)
	return ""

func apply_character(peer_id: int, profile: Dictionary, portrait_hash: String) -> String:
	var who = player(peer_id)
	if who == null or data.phase not in ["lobby", "finished"]:
		return "Персонаж уже вышел или партия началась."
	if not valid_profile(profile) or portrait_hash.length() != 64:
		return "Генератор вернул неверную карточку персонажа."
	who.name = clean_name(profile.name)
	who.bio = profile.bio.strip_edges()
	who.token = "generated:" + portrait_hash
	who.generation_mode = profile.get("mode", "local_ai")
	_event("%s готов к приключению. PNG-фишка создана (%s)." % [who.name, "тест без ИИ" if who.generation_mode == "sketch" else "локальный ИИ"])
	return ""

static func valid_profile(profile: Dictionary) -> bool:
	for field in ["name", "bio", "image_prompt"]:
		if typeof(profile.get(field)) != TYPE_STRING or profile[field].strip_edges().is_empty():
			return false
	return profile.name.length() <= 24 and profile.bio.length() <= 600 and profile.image_prompt.length() <= 1000

func apply_adventure(peer_id: int, story: Dictionary) -> String:
	if peer_id != int(data.host_id) or data.phase not in ["lobby", "finished"]:
		return "Завязку выбирает хост до начала партии."
	for field in ["title", "opening", "objective"]:
		if typeof(story.get(field)) != TYPE_STRING or story[field].strip_edges().is_empty():
			return "Генератор вернул неверное приключение."
	if story.title.length() > 80 or story.opening.length() > 1400 or story.objective.length() > 300:
		return "Слишком длинное приключение."
	data.adventure = {"title": story.title, "opening": story.opening, "objective": story.objective, "mode": story.get("mode", "local_ai")}
	_event("Завязка готова: %s (%s)." % [story.title, "тест без ИИ" if story.get("mode") == "sketch" else "локальный ИИ"])
	return ""

func command(peer_id: int, packet: Dictionary) -> String:
	var who = player(peer_id)
	if who == null:
		return "Сначала войдите в комнату."
	if typeof(packet.get("request_id")) != TYPE_INT or typeof(packet.get("version")) != TYPE_INT:
		return "Неверный формат команды."
	var request_id: int = packet.request_id
	if request_id <= int(_seen.get(peer_id, 0)):
		return "Повтор команды отклонён."
	_seen[peer_id] = request_id
	if int(packet.version) != int(data.version):
		return "Состояние стола изменилось. Повторите действие."
	var kind = packet.get("kind", "")
	if kind == "start":
		return start(peer_id)
	if data.phase != "playing":
		return "Сначала начните партию."
	if int(data.active) != peer_id:
		return "Сейчас ход другого игрока."
	match kind:
		"attack":
			if typeof(packet.get("target")) != TYPE_STRING:
				return "Выберите цель атаки."
			return _attack(who, packet.target)
		"move":
			if typeof(packet.get("x")) != TYPE_INT or typeof(packet.get("y")) != TYPE_INT:
				return "Неверные координаты."
			return _move(who, Vector2i(packet.x, packet.y))
		"end_turn":
			_next_turn()
			return ""
		"say":
			if typeof(packet.get("text")) != TYPE_STRING:
				return "Неверный текст."
			var line: String = packet.text.strip_edges()
			if line.is_empty() or line.length() > 280:
				return "Действие должно содержать от 1 до 280 символов."
			_event("%s: %s" % [who.name, line.replace("\n", " ")])
			_event("Тестовый ведущий: бармен записал ваше намерение в книгу жалоб. Свободные действия пока не меняют мир — ИИ ещё не подключён.")
			_next_turn()
			return ""
		"prepare_text":
			# Reserve the request number before asynchronous interpretation; spend nothing.
			if typeof(packet.get("text")) != TYPE_STRING or packet.text.strip_edges().is_empty() or packet.text.length() > 280:
				return "Действие должно содержать от 1 до 280 символов."
			return ""
		_:
			return "Неизвестное действие."

func execute_intent(peer_id: int, intent: Dictionary) -> String:
	if data.phase != "playing" or int(data.active) != peer_id:
		return "Ход уже изменился."
	var who: Dictionary = player(peer_id)
	match intent.get("kind", ""):
		"move":
			for key in ["x", "y"]:
				if typeof(intent.get(key)) not in [TYPE_INT, TYPE_FLOAT] or float(intent[key]) != floor(float(intent[key])) or abs(float(intent[key])) > 100:
					return "Ведущий не указал целую координату клетки."
			return _move(who, Vector2i(int(intent.x), int(intent.y)))
		"attack":
			if typeof(intent.get("target")) != TYPE_STRING:
				return "Ведущий не выбрал цель."
			return _attack(who, intent.target)
		"end_turn":
			_next_turn()
			return ""
		"speak":
			_next_turn()
			return ""
	return "Это действие пока не поддерживается правилами. Уточните намерение."

func _move(who: Dictionary, target: Vector2i) -> String:
	if int(data.moves_left) <= 0:
		return "Шаги закончились. Завершите ход."
	if not walkable(target):
		return "Там стена или мебель."
	if absi(target.x - int(who.x)) + absi(target.y - int(who.y)) != 1:
		return "Выберите соседнюю клетку по горизонтали или вертикали."
	for other in data.players:
		if int(other.x) == target.x and int(other.y) == target.y:
			return "Клетка занята другой фишкой."
	for other in data.enemies:
		if int(other.hp) > 0 and Vector2i(int(other.x), int(other.y)) == target:
			return "Клетка занята врагом. Выберите его и атакуйте с соседней клетки."
	who.x = target.x
	who.y = target.y
	data.moves_left -= 1
	_event("%s перемещается. Осталось шагов: %s." % [who.name, data.moves_left])
	return ""

func _next_turn() -> void:
	var current_index := 0
	for index in range(data.players.size()):
		if int(data.players[index].id) == int(data.active):
			current_index = index
	for step in range(1, data.players.size() + 1):
		var next_index: int = (current_index + step) % data.players.size()
		if next_index == 0:
			_enemy_phase()
			if data.phase != "playing":
				return
			data.round += 1
		if int(data.players[next_index].hp) > 0:
			data.active = int(data.players[next_index].id)
			data.moves_left = 3
			data.actions_left = 1
			_event("Ходит %s." % data.players[next_index].name)
			return
	_finish("defeat")

func _attack(who: Dictionary, target_id: String) -> String:
	if int(data.actions_left) <= 0:
		return "Вы уже атаковали в этом ходу. Можно переместиться или завершить ход."
	var target = enemy(target_id)
	if target == null or int(target.hp) <= 0:
		return "Этой живой цели нет на столе."
	if _distance(who, target) != 1:
		return "Для атаки подойдите на соседнюю клетку без диагонали."
	data.actions_left = 0
	_resolve_attack(who, target)
	var any_alive := false
	for other in data.enemies:
		if int(other.hp) > 0:
			any_alive = true
	if not any_alive:
		_finish("victory")
	return ""

func _resolve_attack(attacker: Dictionary, target: Dictionary) -> void:
	var die := _roll(20)
	var total: int = die + int(attacker.attack_bonus)
	var critical := die == 20
	var hit: bool = die != 1 and (critical or total >= int(target.ac))
	var damage_rolls: Array[int] = []
	var damage := 0
	if hit:
		for index in range(2 if critical else 1):
			var amount := _roll(int(attacker.damage_die))
			damage_rolls.append(amount)
			damage += amount
		damage += int(attacker.damage_bonus)
		target.hp = maxi(0, int(target.hp) - damage)
	data.last_roll = {"attacker": attacker.name, "target": target.name, "d20": die,
		"bonus": attacker.attack_bonus, "total": total, "ac": target.ac, "hit": hit,
		"critical": critical, "damage": damage, "damage_rolls": damage_rolls,
		"damage_die": attacker.damage_die, "damage_bonus": attacker.damage_bonus}
	var result := "критическое попадание" if critical else "попадание" if hit else "промах"
	_event("%s → %s. d20: %s + %s = %s против КД %s — %s.%s" % [attacker.name, target.name,
		die, attacker.attack_bonus, total, target.ac, result, " Урон: %s. HP: %s/%s." % [damage, target.hp, target.max_hp] if hit else ""])
	if int(target.hp) == 0:
		_event("%s повержен. Бухгалтерия выражает соболезнования." % target.name)

func _enemy_phase() -> void:
	for foe in data.enemies:
		if int(foe.hp) <= 0:
			continue
		var best_path: Array[Vector2i] = []
		var target = null
		for hero in data.players:
			if int(hero.hp) <= 0:
				continue
			var path := _path_to(foe, hero)
			if not path.is_empty() and (target == null or path.size() < best_path.size()):
				target = hero
				best_path = path
		if target == null:
			_event("%s не может найти путь. Требует у мебели пропуск." % foe.name)
			continue
		var steps: int = mini(int(foe.speed), best_path.size() - 1)
		if steps > 0:
			foe.x = best_path[steps - 1].x
			foe.y = best_path[steps - 1].y
			_event("%s подходит к %s на %s клетки." % [foe.name, target.name, steps])
		if _distance(foe, target) == 1:
			_resolve_attack(foe, target)
	var survivors := false
	for hero in data.players:
		if int(hero.hp) > 0:
			survivors = true
	if not survivors:
		_finish("defeat")

func _path_to(foe: Dictionary, hero: Dictionary) -> Array[Vector2i]:
	var origin := Vector2i(int(foe.x), int(foe.y))
	var goal := Vector2i(int(hero.x), int(hero.y))
	var queue: Array[Vector2i] = [origin]
	var previous: Dictionary = {origin: origin}
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		if here == goal:
			var path: Array[Vector2i] = []
			while here != origin:
				path.push_front(here)
				here = previous[here]
			return path
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = here + direction
			if previous.has(next) or not walkable(next):
				continue
			var occupied := false
			for body in data.players + data.enemies:
				if Vector2i(int(body.x), int(body.y)) == next and next != goal and (body in data.players or int(body.hp) > 0):
					occupied = true
			if not occupied:
				previous[next] = here
				queue.append(next)
	return []

func _finish(outcome: String) -> void:
	data.phase = "finished"
	data.outcome = outcome
	data.active = 0
	data.moves_left = 0
	data.actions_left = 0
	_event("Победа! Скелет списан в расход. Хост может начать новый бой." if outcome == "victory" else "Группа повержена. Скелет оформляет вас в штат. Хост может начать новый бой.")

func _roll(sides: int) -> int:
	return _rng.randi_range(1, sides)

static func _distance(a: Dictionary, b: Dictionary) -> int:
	return absi(int(a.x) - int(b.x)) + absi(int(a.y) - int(b.y))

func enemy(enemy_id: String):
	for entry in data.enemies:
		if entry.id == enemy_id:
			return entry
	return null

func player(peer_id: int):
	for entry in data.players:
		if int(entry.id) == peer_id:
			return entry
	return null

static func walkable(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.x < WIDTH - 1 and cell.y > 0 and cell.y < HEIGHT - 1 and cell not in BLOCKED

static func clean_name(value: String) -> String:
	var result := value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(24)
	return result if not result.is_empty() else "Путник"

func _event(line: String) -> void:
	data.log.append(line)
	if data.log.size() > 80:
		data.log.pop_front()
	data.version += 1

func snapshot() -> Dictionary:
	return data.duplicate(true)

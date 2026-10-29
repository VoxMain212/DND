extends SceneTree
const Rules = preload("res://scripts/room_state.gd")
var failures := 0
var checks := 0
var sequence := 0

class FixedRules extends "res://scripts/room_state.gd":
	var rolls: Array = []
	func _roll(_sides: int) -> int:
		return rolls.pop_front() if not rolls.is_empty() else 1

func _initialize() -> void:
	var room = battle()
	var before: Dictionary = room.snapshot()
	check(not act(room, 1, "attack", {"target": "collector"}).is_empty(), "distant attack rejected")
	check(room.snapshot() == before, "invalid attack spends neither action nor roll")
	check(not act(room, 1, "attack", {"target": "missing"}).is_empty(), "unknown enemy rejected")
	check(not act(room, 1, "attack", {"target": 1}).is_empty(), "target must be string ID")
	room.data.enemies[0].x = 3
	room.data.enemies[0].y = 3
	check(not act(room, 1, "move", {"x": 3, "y": 3}).is_empty(), "living enemy occupies tile")
	room.rolls = [15, 4]
	check(act(room, 1, "attack", {"target": "collector"}).is_empty(), "adjacent attack accepted")
	check(int(room.data.enemies[0].hp) == 4, "d6 plus damage bonus applied")
	check(int(room.data.last_roll.total) == 19 and room.data.last_roll.hit, "attack roll stored")
	check(int(room.data.actions_left) == 0 and int(room.data.moves_left) == 3, "attack budget independent of movement")
	before = room.snapshot()
	check(not act(room, 1, "attack", {"target": "collector"}).is_empty() and room.snapshot() == before, "second attack has no effects")
	check(act(room, 1, "move", {"x": 2, "y": 4}).is_empty(), "can move after attacking")
	room = battle(true)
	room.data.enemies[0].ac = -100
	room.rolls = [1]
	act(room, 1, "attack", {"target": "collector"})
	check(not room.data.last_roll.hit and int(room.data.enemies[0].hp) == 10, "natural one always misses")
	check(int(room.data.actions_left) == 0, "miss spends action")
	room = battle(true)
	room.data.enemies[0].ac = 99
	room.rolls = [20, 3, 4]
	act(room, 1, "attack", {"target": "collector"})
	check(room.data.last_roll.critical and room.data.last_roll.hit, "natural twenty always hits")
	check(int(room.data.last_roll.damage) == 9 and room.data.last_roll.damage_rolls == [3, 4], "critical doubles dice, not flat bonus")
	check(int(room.data.enemies[0].hp) == 1, "critical damage authoritative")
	room = battle(true)
	room.data.enemies[0].ac = 99
	room.rolls = [19]
	act(room, 1, "attack", {"target": "collector"})
	check(not room.data.last_roll.hit and not room.data.last_roll.critical, "ordinary attack respects armor")
	room = battle(true)
	room.data.enemies[0].hp = 1
	room.rolls = [12, 1]
	sequence += 1
	var packet := {"request_id": sequence, "version": int(room.data.version), "kind": "attack", "target": "collector"}
	check(room.command(1, packet).is_empty(), "lethal attack")
	check(room.data.phase == "finished" and room.data.outcome == "victory" and int(room.data.active) == 0, "victory stops turns")
	check(int(room.data.enemies[0].hp) == 0, "HP clamped to zero")
	before = room.snapshot()
	check(not room.command(1, packet).is_empty() and room.snapshot() == before, "repeated lethal attack does not reroll")
	check(not act(room, 1, "move", {"x": 2, "y": 4}).is_empty(), "finished battle blocks actions")
	check(act(room, 1, "start").is_empty(), "host can restart finished encounter")
	check(int(room.player(1).hp) == 12 and int(room.data.enemies[0].hp) == 10 and room.data.last_roll.is_empty(), "restart resets combat state")
	room = battle(true)
	room.rolls = [12, 2]
	act(room, 1, "end_turn")
	check(int(room.player(1).hp) == 10, "adjacent enemy attacks at round boundary")
	check(room.data.last_roll.attacker == "Скелет-сборщик", "enemy roll replicated in same format")
	check(int(room.data.round) == 2 and int(room.data.active) == 1 and int(room.data.actions_left) == 1, "new round resets player action")
	room = battle()
	act(room, 1, "end_turn")
	var foe: Dictionary = room.data.enemies[0]
	check(Rules.walkable(Vector2i(int(foe.x), int(foe.y))) and absi(int(foe.x) - 4) + absi(int(foe.y) - 5) == 2, "enemy walks at most two reachable cells")
	check(int(room.player(1).hp) == 12, "enemy cannot attack outside melee range")
	room = battle(true)
	room.player(1).hp = 1
	room.rolls = [20, 1, 1]
	act(room, 1, "end_turn")
	check(room.data.phase == "finished" and room.data.outcome == "defeat", "total party defeat")
	check(int(room.player(1).hp) == 0 and int(room.data.active) == 0, "fallen player gets no extra turn")
	room = FixedRules.new()
	for id in range(1, 4):
		room.add_player(id, "Герой %s" % id, Rules.TOKEN_KEYS[id - 1])
	room.start(1)
	room.player(2).hp = 0
	check(not act(room, 2, "attack", {"target": "collector"}).is_empty(), "other player cannot attack outside turn")
	act(room, 1, "end_turn")
	check(int(room.data.active) == 3 and int(room.data.round) == 1, "fallen teammate skipped without premature enemy turn")
	# Living hero is enclosed by the map edges and fallen teammates.
	room.player(1).x = 1
	room.player(1).y = 1
	room.player(2).x = 1
	room.player(2).y = 2
	room.player(3).x = 2
	room.player(3).y = 1
	room.player(3).hp = 0
	room.data.active = 1
	act(room, 1, "end_turn")
	check(int(room.data.active) == 1 and int(room.data.round) == 2, "unreachable enemy still advances round correctly")
	check(int(room.data.enemies[0].x) == 4 and int(room.data.enemies[0].y) == 5, "enemy does not walk through occupied cells")
	var lobby = Rules.new()
	check(not lobby.add_player(1, "Путник", "../bad.png").is_empty(), "network cannot supply image path")
	check(lobby.add_player(1, "Путник", "mage").is_empty() and lobby.player(1).token == "mage", "appearance is a validated ID")
	print("COMBAT: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)

func battle(adjacent := false):
	var room = FixedRules.new()
	room.add_player(1, "Воин")
	room.start(1)
	if adjacent:
		room.data.enemies[0].x = 3
		room.data.enemies[0].y = 3
	return room

func act(room, who: int, kind: String, extra: Dictionary = {}) -> String:
	sequence += 1
	var packet := extra.duplicate()
	packet.merge({"kind": kind, "request_id": sequence, "version": int(room.data.version)})
	return room.command(who, packet)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

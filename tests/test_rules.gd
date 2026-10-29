extends SceneTree

const Rules = preload("res://scripts/room_state.gd")
var failures := 0
var checks := 0
var sequence := 0

func _initialize() -> void:
	var room = Rules.new()
	check(room.add_player(1, "Хост").is_empty(), "host admission")
	check(room.add_player(2, "Гость").is_empty(), "client admission")
	check(not room.start(2).is_empty(), "only host can start")
	check(room.start(1).is_empty(), "start game")
	var before: Dictionary = room.snapshot()
	check(not act(room, 2, "move", {"x": 3, "y": 5}).is_empty(), "out of turn denied")
	check(room.snapshot() == before, "rejected move leaves snapshot intact")
	check(not act(room, 1, "move", {"x": 12, "y": 8}).is_empty(), "teleport denied")
	check(act(room, 1, "move", {"x": 3, "y": 3}).is_empty(), "adjacent move")
	check(act(room, 1, "move", {"x": 4, "y": 3}).is_empty(), "second step")
	check(act(room, 1, "move", {"x": 5, "y": 3}).is_empty(), "third step")
	check(not act(room, 1, "move", {"x": 5, "y": 2}).is_empty(), "movement budget enforced")
	check(act(room, 1, "end_turn").is_empty(), "end turn")
	check(int(room.data.active) == 2 and int(room.data.moves_left) == 3, "turn advances and resets budget")
	check(act(room, 2, "say", {"text": "Скелет требует отпуск"}).is_empty(), "text action")
	check(int(room.data.active) == 1 and int(room.data.round) == 2, "text ends turn and advances round")
	check(not act(room, 1, "move", {"x": 6, "y": 3}).is_empty(), "furniture blocks movement")
	check(not act(room, 1, "move", {"x": "4", "y": 3}).is_empty(), "coordinate types validated")
	check(not act(room, 1, "say", {"text": "a".repeat(281)}).is_empty(), "text limit")
	var stale := {"request_id": sequence + 1, "version": 0, "kind": "end_turn"}
	sequence += 1
	check(not room.command(1, stale).is_empty(), "stale state denied")
	sequence += 1
	var packet := {"request_id": sequence, "version": int(room.data.version), "kind": "end_turn"}
	check(room.command(1, packet).is_empty(), "new request accepted")
	var accepted: Dictionary = room.snapshot()
	check(not room.command(1, packet).is_empty() and room.snapshot() == accepted, "duplicate has no side effects")
	check(not room.add_player(3, "Поздний").is_empty(), "late join denied")
	room.remove_player(2)
	check(room.data.phase == "lobby" and room.data.players.size() == 1, "disconnect returns to lobby")
	check(room.start(1).is_empty() and int(room.player(1).x) == 2, "restart resets positions")
	var lobby = Rules.new()
	for id in range(1, 5):
		check(lobby.add_player(id, "Игрок").is_empty(), "four seats")
	check(not lobby.add_player(5, "Пятый").is_empty(), "capacity limit")
	check(not Rules.walkable(Vector2i(-1, 2)) and not Rules.walkable(Vector2i(0, 2)), "map boundaries")
	# Occupancy is checked separately from distance and obstacles.
	var occupied = Rules.new()
	occupied.add_player(1, "A")
	occupied.add_player(2, "B")
	occupied.start(1)
	occupied.player(2).x = 3
	occupied.player(2).y = 3
	check(not act(occupied, 1, "move", {"x": 3, "y": 3}).is_empty(), "occupied tile denied")
	print("RULES: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)

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

extends Control

const Rules = preload("res://scripts/room_state.gd")
const Workshop = preload("res://scripts/workshop.gd")
const INK := Color("#e8e3d6")
const MUTED := Color("#a1afb3")
const GOLD := Color("#e7b86b")

var _name: LineEdit
var _address: LineEdit
var _port: SpinBox
var _host: Button
var _join: Button
var _leave: Button
var _start: Button
var _end: Button
var _send: Button
var _attack: Button
var _target_info: Label
var _roll_info: Label
var _token_choice: OptionButton
var _target_id := ""
var _action: LineEdit
var _status: Label
var _connection: Label
var _turn: Label
var _round: Label
var _roster: VBoxContainer
var _journal: RichTextLabel
var _board: Control
var _room_panel: PanelContainer
var _journal_panel: PanelContainer
var _last_log_size := -1
var _last_version := -1
var _directions: Array[Button] = []
var _workshop: Window

func _ready() -> void:
	Engine.max_fps = 60
	_board = $Table
	_board.cell_clicked.connect(_move_to)
	_apply_theme()
	_build_ui()
	get_viewport().gui_embed_subwindows = true
	_workshop = Workshop.new()
	_workshop.visible = false
	_workshop.theme = theme
	add_child(_workshop)
	Session.changed.connect(_refresh)
	Session.notice.connect(_show_notice)
	_refresh()
	_show_notice("Создайте комнату или подключитесь к другу. Для двух окон на одном ПК используйте 127.0.0.1.")

func _apply_theme() -> void:
	var skin := Theme.new()
	skin.default_font_size = 16
	skin.set_color("font_color", "Label", INK)
	skin.set_color("font_color", "Button", INK)
	skin.set_color("font_hover_color", "Button", Color.WHITE)
	skin.set_color("font_disabled_color", "Button", Color("#6e7d83"))
	skin.set_stylebox("normal", "Button", _style("#293a42", "#42535a", 8))
	skin.set_stylebox("hover", "Button", _style("#354c56", "#c7a367", 8))
	skin.set_stylebox("pressed", "Button", _style("#1b2c33", "#e7b86b", 8))
	skin.set_stylebox("disabled", "Button", _style("#1a252c", "#29363e", 8))
	skin.set_stylebox("focus", "Button", _style("#00000000", "#e7b86b", 8))
	skin.set_color("font_color", "LineEdit", INK)
	skin.set_color("font_placeholder_color", "LineEdit", Color("#7d8c94"))
	skin.set_color("caret_color", "LineEdit", GOLD)
	skin.set_stylebox("normal", "LineEdit", _style("#111e26", "#3a4d56", 8))
	skin.set_stylebox("focus", "LineEdit", _style("#182831", "#b09560", 8))
	skin.set_color("default_color", "RichTextLabel", INK)
	theme = skin

func _style(background: String, border: String, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(background)
	box.border_color = Color(border)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var toolbar := PanelContainer.new()
	toolbar.add_theme_stylebox_override("panel", _style("#111c24eb", "#43504e", 10))
	root.add_child(toolbar)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	toolbar.add_child(header)
	var title := _label("DND FUN / ПОСЛЕДНИЙ ВЗДОХ", 19, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Мастерская", func(): _workshop.popup_centered()))
	header.add_child(_button("Комната", func(): _room_panel.visible = not _room_panel.visible))
	header.add_child(_button("Журнал", func(): _journal_panel.visible = not _journal_panel.visible))
	header.add_child(_button("Вид сверху", func(): _board.top_view()))
	header.add_child(_button("К столу", func(): _board.reset_camera()))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_room_panel = PanelContainer.new()
	_room_panel.custom_minimum_size.x = 260
	_room_panel.add_theme_stylebox_override("panel", _style("#14232def", "#43504e", 10))
	body.add_child(_room_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_room_panel.add_child(scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 6)
	scroll.add_child(sidebar)
	sidebar.add_child(_label("ПРИСАЖИВАЙТЕСЬ К СТОЛУ", 14, GOLD))
	sidebar.add_child(_label("Имя персонажа", 12, MUTED))
	_name = _make_input("Например, Гробослав", "Путник")
	_name.max_length = 24
	sidebar.add_child(_name)
	var appearance := _label("PNG-фишка", 12, MUTED)
	appearance.tooltip_text = "Пока это только внешний вид: характеристики всех образов одинаковые."
	sidebar.add_child(appearance)
	_token_choice = OptionButton.new()
	for label in ["Воин", "Маг", "Плут", "Жрец"]:
		_token_choice.add_item(label)
	sidebar.add_child(_token_choice)
	sidebar.add_child(_label("IP или адрес хоста", 12, MUTED))
	_address = _make_input("127.0.0.1", "127.0.0.1")
	_address.max_length = 253
	sidebar.add_child(_address)
	sidebar.add_child(_label("UDP-порт", 12, MUTED))
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Session.DEFAULT_PORT
	_port.rounded = true
	sidebar.add_child(_port)
	_host = _button("Создать комнату", func(): Session.host_room(_name.text, int(_port.value), Rules.TOKEN_KEYS[_token_choice.selected]))
	sidebar.add_child(_host)
	_join = _button("Подключиться", func(): Session.join_room(_name.text, _address.text, int(_port.value), Rules.TOKEN_KEYS[_token_choice.selected]))
	sidebar.add_child(_join)
	_leave = _button("Выйти из комнаты", func(): Session.leave_room())
	sidebar.add_child(_leave)
	_connection = _label("", 12, MUTED)
	_connection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_connection)
	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_label("УЧАСТНИКИ", 13, GOLD))
	_roster = VBoxContainer.new()
	sidebar.add_child(_roster)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(space)
	_journal_panel = PanelContainer.new()
	_journal_panel.custom_minimum_size.x = 260
	_journal_panel.add_theme_stylebox_override("panel", _style("#14232de8", "#43504e", 10))
	_journal_panel.visible = false
	body.add_child(_journal_panel)
	var journal_column := VBoxContainer.new()
	journal_column.add_theme_constant_override("separation", 12)
	_journal_panel.add_child(journal_column)
	journal_column.add_child(_label("ЖУРНАЛ ПРИКЛЮЧЕНИЯ", 14, GOLD))
	_journal = RichTextLabel.new()
	_journal.bbcode_enabled = false
	_journal.scroll_following = true
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.custom_minimum_size = Vector2(230, 100)
	journal_column.add_child(_journal)
	var help := _label("ПКМ + мышь — вращение\nКолесо — приближение\nСКМ + мышь — сдвиг\nЛКМ — ход на соседнюю клетку", 13, MUTED)
	journal_column.add_child(help)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _style("#111c24ed", "#43504e", 10))
	root.add_child(footer)
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	footer.add_child(bottom)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	bottom.add_child(controls)
	_turn = _label("Предпросмотр стола", 17, INK)
	_turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_turn)
	_round = _label("", 13, GOLD)
	controls.add_child(_round)
	_start = _button("Начать партию", func(): Session.send_command("start"))
	controls.add_child(_start)
	for direction in [["←", Vector2i.LEFT], ["↑", Vector2i.UP], ["↓", Vector2i.DOWN], ["→", Vector2i.RIGHT]]:
		var offset: Vector2i = direction[1]
		var button := _button(direction[0], func(): _step(offset))
		button.custom_minimum_size.x = 38
		controls.add_child(button)
		_directions.append(button)
	_end = _button("Завершить ход →", func(): Session.send_command("end_turn"))
	controls.add_child(_end)
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 12)
	bottom.add_child(target_row)
	_target_info = _label("Выберите врага на карте", 14, INK)
	_target_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(_target_info)
	_roll_info = _label("", 13, GOLD)
	target_row.add_child(_roll_info)
	_attack = _button("Атаковать", func(): Session.send_command("attack", {"target": _target_id}))
	target_row.add_child(_attack)
	var action_row := HBoxContainer.new()
	bottom.add_child(action_row)
	_action = _make_input("Опишите действие… (пока тестовый ведущий)", "")
	_action.max_length = 280
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.text_submitted.connect(func(_text): _submit_action())
	action_row.add_child(_action)
	_send = _button("Действовать", _submit_action)
	action_row.add_child(_send)
	_status = _label("", 13, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size.y = 32
	bottom.add_child(_status)
	_pass_mouse(margin)

func _pass_mouse(node: Node) -> void:
	# Empty overlay space must let the 3D viewport receive mouse input.
	if node is Control and not node is PanelContainer and not node is BaseButton and not node is LineEdit and not node is SpinBox and not node is ScrollContainer and not node is ScrollBar and not node is RichTextLabel:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_pass_mouse(child)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_input(placeholder: String, value: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = value
	field.custom_minimum_size.y = 36
	return field

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	return button

func _refresh() -> void:
	var online: bool = Session.connected
	var busy: bool = online or Session.connecting
	_host.disabled = busy
	_join.disabled = busy
	_leave.disabled = not busy
	_name.editable = not busy
	_address.editable = not busy
	_port.editable = not busy
	_token_choice.disabled = busy
	var phase: String = Session.state.get("phase", "")
	_start.visible = Session.hosting and phase in ["lobby", "finished"]
	_start.disabled = phase not in ["lobby", "finished"]
	if Session.state.get("generation", {}).get("busy", false) or int(Session.state.get("generation", {}).get("queued", 0)) > 0:
		_start.disabled = true
	_start.text = "Новый бой" if phase == "finished" else "Начать партию"
	_end.disabled = not Session.my_turn()
	_action.editable = Session.my_turn()
	_action.placeholder_text = "Действие: иду вниз, атакую, говорю…" if Session.state.get("director_mode", "off") != "off" else "Реплика (ведущий выключен)"
	_send.disabled = not Session.my_turn()
	for button in _directions:
		button.disabled = not Session.my_turn() or int(Session.state.get("moves_left", 0)) <= 0
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	_board.display_state(Session.state, Session.local_id())
	_connection.text = "Не в комнате. До 4 игроков."
	if Session.connecting:
		_connection.text = "Подключение… Таймаут 10 секунд."
	elif online:
		_connection.text = ("Вы — хост. Порт %s / UDP.\n" % Session.room_port) if Session.hosting else "Подключено к хосту.\n"
		if Session.hosting:
			var addresses: PackedStringArray = []
			for address in IP.get_local_addresses():
				if ":" not in address and not address.begins_with("127."):
					addresses.append(address)
			addresses.sort()
			# Prefer typical home LAN addresses; leave all interfaces in the tooltip.
			var preferred: PackedStringArray = []
			for address in addresses:
				if address.begins_with("192.168.") or address.begins_with("10."):
					preferred.append(address)
			if preferred.is_empty():
				preferred = addresses
			_connection.text += "Локальные IP: " + (", ".join(preferred.slice(0, 2)) if not preferred.is_empty() else "127.0.0.1")
			_connection.tooltip_text = "Все интерфейсы: " + ", ".join(addresses)
	for entry in Session.state.get("players", []):
		var tag := "  ·  вы" if int(entry.id) == Session.local_id() else ""
		if int(entry.id) == int(Session.state.get("active", 0)):
			tag += "  ◀"
		_roster.add_child(_label("●  " + str(entry.name) + tag + "\n    HP %s/%s  ·  КД %s" % [entry.hp, entry.max_hp, entry.ac], 14, Color(entry.color)))
	if Session.state.get("players", []).is_empty():
		_roster.add_child(_label("Здесь пока тихо. Подозрительно.", 13, MUTED))
	_turn.text = "Лобби — ожидаем начала" if online else "Предпросмотр стола"
	_round.text = "ЛОББИ" if online else "ПКМ: ВРАЩЕНИЕ / КОЛЕСО: МАСШТАБ"
	if Session.state.get("phase") == "playing":
		var active_name := ""
		for entry in Session.state.players:
			if int(entry.id) == int(Session.state.active):
				active_name = entry.name
		_turn.text = "Ваш ход" if Session.my_turn() else "Ход: " + active_name
		_round.text = "КРУГ %s / ШАГИ %s / АТАКА %s" % [Session.state.round, Session.state.moves_left, Session.state.actions_left]
	if phase == "finished":
		_turn.text = "Победа!" if Session.state.outcome == "victory" else "Группа повержена"
		_round.text = "БОЙ ЗАВЕРШЁН"
	_refresh_target()
	var lines: Array = Session.state.get("log", [])
	var version: int = Session.state.get("version", -1)
	if version != _last_version and not lines.is_empty():
		_status.text = lines.back()
	if Session.state.get("generation", {}).get("busy", false):
		_status.text = Session.state.generation.stage
	if Session.state.get("narrator", {}).get("busy", false):
		_status.text = Session.state.narrator.stage
	_last_version = version
	_journal.text = "\n\n".join(PackedStringArray(lines)) if not lines.is_empty() else "Фишки на столе — образцы для предпросмотра.\n\nСоздайте комнату и начните партию, чтобы управлять своим персонажем."
	if lines.size() != _last_log_size:
		_last_log_size = lines.size()
		_journal.scroll_to_line(maxi(0, _journal.get_line_count() - 1))

func _show_notice(message: String) -> void:
	_status.text = message

func _move_to(cell: Vector2i) -> void:
	for foe in Session.state.get("enemies", []):
		if int(foe.hp) > 0 and Vector2i(int(foe.x), int(foe.y)) == cell:
			_target_id = foe.id
			_refresh_target()
			return
	if not Session.my_turn():
		_show_notice("Начните партию и дождитесь своего хода.")
		return
	Session.send_command("move", {"x": cell.x, "y": cell.y})

func _refresh_target() -> void:
	var selected = null
	var enemies: Array = Session.state.get("enemies", [])
	for foe in enemies:
		if foe.id == _target_id:
			selected = foe
	if selected == null and not enemies.is_empty():
		selected = enemies[0]
		_target_id = selected.id
	if enemies.is_empty():
		_target_id = ""
	_target_info.text = "Начните партию — на карте появится противник"
	_attack.disabled = true
	if selected != null:
		_target_info.text = "%s · HP %s/%s · КД %s" % [selected.name, selected.hp, selected.max_hp, selected.ac]
		_attack.disabled = not Session.my_turn() or int(Session.state.get("actions_left", 0)) <= 0 or int(selected.hp) <= 0
		_attack.tooltip_text = "Ближняя атака: подойдите на соседнюю клетку без диагонали."
	_board.select_enemy(_target_id)
	var roll: Dictionary = Session.state.get("last_roll", {})
	_roll_info.text = "d20 — бросает хост"
	if not roll.is_empty():
		_roll_info.text = "d20: %s + %s = %s · %s" % [roll.d20, roll.bonus, roll.total, "урон %s" % roll.damage if roll.hit else "промах"]
		_roll_info.tooltip_text = "%s → %s. КД %s. %s" % [roll.attacker, roll.target, roll.ac, "Критическое попадание!" if roll.critical else ""]

func _step(offset: Vector2i) -> void:
	for entry in Session.state.get("players", []):
		if int(entry.id) == Session.local_id():
			_move_to(Vector2i(int(entry.x), int(entry.y)) + offset)
			return

func _submit_action() -> void:
	if not Session.my_turn() or _action.text.strip_edges().is_empty():
		return
	Session.send_command("say", {"text": _action.text})
	_action.clear()

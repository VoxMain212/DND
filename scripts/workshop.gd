extends Window
## Character/portrait generation and a small adventure hook, before combat.
const Tokens = preload("res://scripts/token_catalog.gd")
var _mode: OptionButton
var _hint: Label
var _prompt: TextEdit
var _story_prompt: TextEdit
var _generate: Button
var _generate_story: Button
var _preview: TextureRect
var _bio: RichTextLabel
var _story: RichTextLabel
var _progress: Label
var _text_model: LineEdit
var _checkpoint: LineEdit
var _save: Button
var _director_mode: OptionButton
var _cancel_director: Button
var _save_game: Button
var _load_game: Button
var _load_auto: Button
var _load_port: SpinBox
var _last_notice := "Создайте комнату, затем опишите персонажа или завязку."

func _ready() -> void:
	title = "Мастерская персонажей и приключений"
	size = Vector2i(700, 690)
	min_size = size
	unresizable = true
	transient = true
	exclusive = true
	close_requested.connect(hide)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#14232d")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	root.add_child(_label("МАСТЕРСКАЯ", 24))
	_mode = OptionButton.new()
	_mode.add_item("Тест без ИИ — эскиз из готового рисунка")
	_mode.add_item("Локальный ИИ — описание + новая PNG")
	_mode.item_selected.connect(func(_index): _refresh())
	root.add_child(_mode)
	_hint = _label("", 14)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.y = 44
	root.add_child(_hint)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(index):
		_mode.visible = index < 2
		_hint.visible = index < 2)
	root.add_child(tabs)
	var character := _tab(tabs, "Персонаж")
	character.add_child(_label("Кем хотите играть? До 600 символов.", 15))
	_prompt = _edit("Усталый гном-некромант в бордовом плаще, с фонарём и бухгалтерской книгой.")
	character.add_child(_prompt)
	_generate = _button("Создать персонажа и PNG-фишку", func(): Session.generate("character", _prompt.text, _selected_mode()))
	character.add_child(_generate)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	character.add_child(row)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(100, 128)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_preview)
	_bio = RichTextLabel.new()
	_bio.add_theme_font_size_override("normal_font_size", 14)
	_bio.custom_minimum_size.y = 128
	_bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bio)
	var adventure := _tab(tabs, "Приключение")
	adventure.add_child(_label("Тема сцены в таверне. Пока один бой со скелетом.", 15))
	_story_prompt = _edit("Профсоюз скелетов требует оплатить сверхурочную смерть. Чёрный юмор и абсурд.")
	adventure.add_child(_story_prompt)
	_generate_story = _button("Создать завязку (только хост)", func(): Session.generate("story", _story_prompt.text, _selected_mode()))
	adventure.add_child(_generate_story)
	_story = RichTextLabel.new()
	_story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	adventure.add_child(_story)
	var settings := _tab(tabs, "Модели хоста")
	settings.add_child(_label("Ollama: имя установленной текстовой модели", 15))
	_text_model = LineEdit.new()
	_text_model.text = Forge.model
	settings.add_child(_text_model)
	settings.add_child(_label("ComfyUI: имя установленного checkpoint SD 1.5", 15))
	_checkpoint = LineEdit.new()
	_checkpoint.text = Forge.checkpoint
	settings.add_child(_checkpoint)
	_save = _button("Сохранить настройки на этом ПК", func():
		Forge.save_settings(_text_model.text, _checkpoint.text)
		_last_notice = "Настройки сохранены. Модели нужно установить отдельно."
		_refresh())
	settings.add_child(_save)
	var explanation := _label("Игра обращается к Ollama (127.0.0.1:11434) и ComfyUI (127.0.0.1:8188) только на ПК хоста.\n\nТекст: CPU, до четырёх потоков, контекст 4096, выгрузка после ответа. Картинка: 512×512, одно задание.\n\nУстановка моделей описана в docs/LOCAL_AI.md. Автоматического скачивания нет.", 14)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(explanation)
	var session_tab := _tab(tabs, "Партия")
	session_tab.add_child(_label("Ведущий во время боя (выбирает хост)", 15))
	_director_mode = OptionButton.new()
	for caption in ["Выключен — запись реплик", "Тест без ИИ — простые команды", "Локальный ИИ — Ollama"]:
		_director_mode.add_item(caption)
	_director_mode.item_selected.connect(func(index): Session.set_director_mode(["off", "test", "local_ai"][index]))
	session_tab.add_child(_director_mode)
	var guide := _label("Тест: «иду вниз», «иду вправо», «атакую», «говорю …», «завершаю ход». Один запрос — одно действие. Разговор завершает ход. Неизвестное действие требует уточнения.\n\nИИ распознаёт намерение и описывает результат. Броски, шаги и HP рассчитывает игра. Новые способности и изменение карты пока не поддерживаются.", 14)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session_tab.add_child(guide)
	_cancel_director = _button("Отменить запрос ведущему", Session.cancel_director)
	session_tab.add_child(_cancel_director)
	_save_game = _button("Сохранить партию и включить автосохранение", Session.save_game)
	session_tab.add_child(_save_game)
	var save_hint := _label("Пока только один игрок: сохраняются бой, журнал, завязка, персонаж и PNG. Ручной слот и автосохранение раздельные; есть резервная копия. Для загрузки выйдите из комнаты. Файлы: user://saves.", 14)
	save_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session_tab.add_child(save_hint)
	var port_row := HBoxContainer.new()
	port_row.add_child(_label("UDP-порт при загрузке", 14))
	_load_port = SpinBox.new()
	_load_port.min_value = 1024
	_load_port.max_value = 65535
	_load_port.value = Session.DEFAULT_PORT
	port_row.add_child(_load_port)
	session_tab.add_child(port_row)
	_load_game = _button("Загрузить ручное сохранение", func(): Session.load_game("manual", int(_load_port.value)))
	session_tab.add_child(_load_game)
	_load_auto = _button("Загрузить последнее автосохранение", func(): Session.load_game("autosave", int(_load_port.value)))
	session_tab.add_child(_load_auto)
	_progress = _label("", 14)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress.custom_minimum_size.y = 40
	root.add_child(_progress)
	root.add_child(_button("Закрыть", hide))
	Session.changed.connect(_refresh)
	Session.notice.connect(_notice)
	_refresh()

func _refresh() -> void:
	_hint.text = "Тест без нейросети: меняет палитру готовой фишки и сохраняет ваш запрос в биографии. Этот режим проверяет очередь и передачу PNG." if _mode.selected == 0 else "Нейросеть создаёт имя и описание, затем рисует новую PNG. На ПК хоста должны быть установлены Ollama, ComfyUI и модели. Ошибка не заменяет результат тестовым рисунком."
	var generation: Dictionary = Session.state.get("generation", {})
	var narrator: Dictionary = Session.state.get("narrator", {})
	var narrator_busy: bool = narrator.get("busy", false)
	_director_mode.select(["off", "test", "local_ai"].find(Session.state.get("director_mode", "off")))
	_director_mode.disabled = not Session.hosting or narrator_busy
	_cancel_director.disabled = not narrator_busy or (not Session.hosting and int(narrator.get("actor", 0)) != Session.local_id())
	_save_game.disabled = not Session.hosting or narrator_busy or generation.get("busy", false) or Session.state.get("players", []).size() != 1
	_load_game.disabled = Session.connected or Session.connecting or generation.get("busy", false)
	_load_auto.disabled = _load_game.disabled
	var own_pending: bool = Session.local_id() in generation.get("requesters", [])
	var allowed: bool = Session.connected and Session.state.get("phase") in ["lobby", "finished"]
	_generate.disabled = not allowed or own_pending
	_generate_story.disabled = not allowed or own_pending or not Session.hosting
	_save.disabled = (Session.connected and not Session.hosting) or generation.get("busy", false)
	_text_model.editable = not _save.disabled
	_checkpoint.editable = not _save.disabled
	_progress.text = str(generation.get("stage", "")) + " Очередь: %s." % generation.get("queued", 0) if generation.get("busy", false) else _last_notice
	if narrator_busy:
		_progress.text = narrator.get("stage", "")
	_preview.texture = Tokens.TEXTURES.warrior
	_bio.text = "После генерации здесь появятся имя, биография и PNG. Игровые характеристики останутся прежними."
	for player in Session.state.get("players", []):
		if int(player.id) == Session.local_id():
			_preview.texture = Tokens.texture(player.token)
			_bio.text = str(player.name) + "\n\n" + str(player.get("bio", "Готовый образ. Опишите своего героя и создайте фишку."))
	var story: Dictionary = Session.state.get("adventure", {})
	_story.text = str(story.get("title", "Завязки пока нет.")) + "\n\n" + str(story.get("opening", "")) + "\n\n" + str(story.get("objective", ""))

func _notice(message: String) -> void:
	_last_notice = message
	_refresh()

func _selected_mode() -> String:
	return "sketch" if _mode.selected == 0 else "local_ai"

func _tab(parent: TabContainer, caption: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = caption
	for edge in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	parent.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	return column

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _edit(value: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.text = value
	edit.custom_minimum_size.y = 80
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit

func _button(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	return button

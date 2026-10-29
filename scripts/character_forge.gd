extends Node
## Sequential asynchronous local generation. No model installation or cloud calls.
signal progress(message: String)
const Rules = preload("res://scripts/room_state.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
const SETTINGS := "user://ai_settings.cfg"
var ollama_url := "http://127.0.0.1:11434"
var comfy_url := "http://127.0.0.1:8188"
var model := "qwen3:4b-instruct-2507-q4_K_M"
var checkpoint := "v1-5-pruned-emaonly.safetensors"
var _templates: Dictionary = {}
var _thread: Thread

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

func _ready() -> void:
	var template_path := "res://assets/generation/sketch_templates.json"
	if FileAccess.file_exists(template_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(template_path))
		if parsed is Dictionary:
			_templates = parsed
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		model = str(config.get_value("models", "text", model))
		checkpoint = str(config.get_value("models", "checkpoint", checkpoint))

func save_settings(text_model: String, image_checkpoint: String) -> void:
	model = text_model.strip_edges().left(120)
	checkpoint = image_checkpoint.strip_edges().left(180)
	var config := ConfigFile.new()
	config.set_value("models", "text", model)
	config.set_value("models", "checkpoint", checkpoint)
	config.save(SETTINGS)

func generate(kind: String, prompt: String, mode: String, base_token: String) -> Dictionary:
	if mode == "sketch":
		progress.emit("Тест без ИИ: готовим эскиз из шаблона…")
		await get_tree().process_frame
		if kind == "story":
			return {"ok": true, "story": {"title": "Профсоюз последнего вздоха", "opening": "Тестовая завязка без ИИ. В таверне скелет-сборщик требует задолженность за прошлую жизнь. Ваш запрос: " + prompt,
				"objective": "Победить скелета-сборщика и выяснить, кто начисляет проценты покойникам.", "mode": "sketch"}}
		if not _templates.get(base_token) is String:
			return _error("Шаблон тестового эскиза отсутствует в сборке.")
		var result: Dictionary = await _worker(_render_sketch.bind(str(_templates.get(base_token, _templates.warrior)), randi()))
		if not result.get("ok", false):
			return result
		result.profile = {"name": "Путник %04d" % randi_range(0, 9999), "bio": ("Тестовый эскиз без ИИ на основе готового рисунка. Запрос: " + prompt).left(600),
			"image_prompt": prompt, "mode": "sketch"}
		return result
	if mode != "local_ai":
		return _error("Неизвестный режим генерации.")
	if kind == "character":
		progress.emit("Проверяем локальный генератор картинок…")
		var ready: Dictionary = await _comfy_ready()
		if not ready.ok:
			return ready
		var freed: Dictionary = await _request(comfy_url + "/free", HTTPClient.METHOD_POST, {"unload_models": true, "free_memory": true})
		if not freed.ok:
			return _error("ComfyUI не смог освободить память перед генерацией текста.")
	progress.emit("Локальный ИИ пишет описание…")
	var description: Dictionary = await _describe(kind, prompt)
	if not description.ok:
		return description
	if kind == "story":
		description.data.mode = "local_ai"
		return {"ok": true, "story": description.data}
	progress.emit("Локальный ИИ рисует персонажа…")
	var generated: Dictionary = await _draw(description.data.image_prompt)
	# Release image model memory after a completed image job, including decode errors.
	if generated.get("completed", false):
		var released: Dictionary = await _request(comfy_url + "/free", HTTPClient.METHOD_POST, {"unload_models": true, "free_memory": true})
		if not released.ok:
			return _error("PNG готова, но ComfyUI не подтвердил освобождение памяти. Проверьте его окно.")
	if not generated.ok:
		return generated
	progress.emit("Вырезаем фон и готовим PNG-фишку…")
	var processed: Dictionary = await _worker(_cutout.bind(generated.bytes))
	if not processed.ok:
		return processed
	description.data.mode = "local_ai"
	processed.profile = description.data
	return processed

func _describe(kind: String, prompt: String) -> Dictionary:
	var fields: Dictionary
	var system := "Ты ведущий русскоязычной настольной RPG. Стиль: чёрный юмор, абсурд, сухая ирония. Верни только JSON по схеме. Не меняй игровые характеристики, правила, броски и карту. "
	if kind == "character":
		fields = {"name": {"type": "string", "maxLength": 24}, "bio": {"type": "string", "maxLength": 600}, "image_prompt": {"type": "string", "maxLength": 1000}}
		system += "Придумай имя и краткую биографию персонажа на русском. image_prompt напиши на английском: только внешний вид одного героя в полный рост для картонной фишки, без фона, текста и декораций."
	else:
		fields = {"title": {"type": "string", "maxLength": 80}, "opening": {"type": "string", "maxLength": 1400}, "objective": {"type": "string", "maxLength": 300}}
		system += "Напиши короткую завязку по запросу игроков. Текущая игровая сцена фиксирована: таверна и один скелет-сборщик, которого нужно победить. Дай ему мотив, нелепую причину конфликта и цель. Не обещай ещё не реализованные способности или новые сцены."
	var schema := {"type": "object", "properties": fields, "required": fields.keys(), "additionalProperties": false}
	var body := {"model": model, "stream": false, "think": false, "keep_alive": 0, "format": schema,
		"options": {"num_ctx": 4096, "num_predict": 700, "num_thread": 4, "num_gpu": 0, "temperature": 0.8},
		"messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}]}
	var response: Dictionary = await _request(ollama_url + "/api/chat", HTTPClient.METHOD_POST, body, 150.0)
	if not response.ok:
		return _error("Ollama недоступна или модель не загружена. " + response.error)
	var payload = JSON.parse_string(response.bytes.get_string_from_utf8())
	if not payload is Dictionary or not payload.get("message") is Dictionary:
		return _error("Ollama вернула неверный ответ.")
	var data = JSON.parse_string(str(payload.message.get("content", "")))
	if not data is Dictionary:
		return _error("Модель не вернула корректный JSON. Попробуйте ещё раз.")
	if kind == "character":
		if not Rules.valid_profile(data):
			return _error("Описание персонажа не прошло проверку структуры и длины.")
	else:
		var limits := {"title": 80, "opening": 1400, "objective": 300}
		for key in limits:
			if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length() > int(limits[key]):
				return _error("Завязка не прошла проверку структуры и длины.")
	# Discard every unsolicited field, including any attempted HP/stat changes.
	var clean := {}
	for key in fields:
		clean[key] = data[key].strip_edges()
	return {"ok": true, "data": clean}

func _comfy_ready() -> Dictionary:
	var response: Dictionary = await _request(comfy_url + "/object_info/CheckpointLoaderSimple")
	if not response.ok:
		return _error("ComfyUI не запущен на компьютере хоста (127.0.0.1:8188).")
	var parsed = JSON.parse_string(response.bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return _error("ComfyUI вернул неверный список моделей.")
	var available = _value_at(parsed, ["CheckpointLoaderSimple", "input", "required", "ckpt_name"], [])
	if not available is Array or available.is_empty() or not available[0] is Array or checkpoint not in available[0]:
		return _error("В ComfyUI нет выбранной SD 1.5 модели: " + checkpoint)
	response = await _request(comfy_url + "/queue")
	if not response.ok:
		return response
	parsed = JSON.parse_string(response.bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("queue_running") is Array or not parsed.get("queue_pending") is Array:
		return _error("ComfyUI вернул неверный статус очереди.")
	if not parsed.queue_running.is_empty() or not parsed.queue_pending.is_empty():
		return _error("ComfyUI занят другой задачей. Дождитесь её завершения.")
	return {"ok": true}

func workflow(image_prompt: String, seed: int) -> Dictionary:
	return {
		"4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint}},
		"5": {"class_type": "EmptyLatentImage", "inputs": {"width": 512, "height": 512, "batch_size": 1}},
		"6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["4", 1], "text": "single full body fantasy character, tabletop standee illustration, centered, boots visible, plain pure white background, no scenery, clean silhouette, " + image_prompt}},
		"7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["4", 1], "text": "text, watermark, scenery, landscape, multiple people, cropped feet, cropped head, frame, border"}},
		"3": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": 16, "cfg": 6.5, "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0, "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
		"8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
		"9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "dndfun", "images": ["8", 0]}}
	}

func _draw(image_prompt: String) -> Dictionary:
	var response: Dictionary = await _request(comfy_url + "/prompt", HTTPClient.METHOD_POST, {"prompt": workflow(image_prompt, randi()), "client_id": "dndfun"})
	if not response.ok:
		return _error("ComfyUI не принял задание: " + response.error)
	var parsed = JSON.parse_string(response.bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("prompt_id") is String:
		return _error("ComfyUI не вернул номер задания.")
	var prompt_id: String = parsed.prompt_id
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.75).timeout
		response = await _request(comfy_url + "/history/" + prompt_id.uri_encode())
		if not response.ok:
			return response
		parsed = JSON.parse_string(response.bytes.get_string_from_utf8())
		if not parsed is Dictionary:
			return _error("ComfyUI вернул неверный статус задания.")
		if not parsed.has(prompt_id):
			continue
		if not parsed[prompt_id] is Dictionary:
			return _error("ComfyUI вернул неверную запись истории.")
		var history: Dictionary = parsed[prompt_id]
		if _value_at(history, ["status", "status_str"], "") == "error":
			return {"ok": false, "error": "ComfyUI сообщил об ошибке генерации. Проверьте его окно, в том числе доступную память.", "completed": true}
		var images = _value_at(history, ["outputs", "9", "images"], [])
		if not images is Array or images.is_empty():
			if _value_at(history, ["status", "completed"], false):
				return {"ok": false, "error": "В завершённом задании нет картинки.", "completed": true}
			continue
		if not images[0] is Dictionary:
			return {"ok": false, "error": "ComfyUI вернул неверное описание картинки.", "completed": true}
		var info: Dictionary = images[0]
		var url := comfy_url + "/view?filename=" + str(info.get("filename", "")).uri_encode() + "&subfolder=" + str(info.get("subfolder", "")).uri_encode() + "&type=output"
		response = await _request(url)
		response.completed = true
		return response
	return _error("Истекло время ожидания картинки. Проверьте ComfyUI и дождитесь завершения задания перед новой попыткой.")

func _request(url: String, method := HTTPClient.METHOD_GET, body: Dictionary = {}, seconds := 10.0) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = seconds
	request.body_size_limit = 2 * 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	var error := request.request(url, ["Content-Type: application/json"], method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if error != OK:
		request.queue_free()
		return _error("Не удалось начать HTTP-запрос: " + error_string(error))
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) < 200 or int(result[1]) >= 300:
		return _error("Ошибка соединения или HTTP %s." % result[1])
	return {"ok": true, "bytes": result[3]}

func _worker(task: Callable) -> Dictionary:
	_thread = Thread.new()
	if _thread.start(task) != OK:
		return _error("Не удалось начать обработку картинки.")
	while _thread.is_alive():
		await get_tree().create_timer(0.02).timeout
	return _thread.wait_to_finish()

static func _render_sketch(source: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var base := Color.from_hsv(rng.randf(), 0.45, 0.78)
	for color in ["#cc9359", "#8b96cb", "#609f9b", "#cb8094"]:
		source = source.replace(color, "#" + base.to_html(false))
	for color in ["#6c4443", "#51446f", "#30494c", "#724b6c"]:
		source = source.replace(color, "#" + base.darkened(0.50).to_html(false))
	var image := Image.new()
	if image.load_svg_from_string(source) != OK:
		return _error("Не удалось нарисовать тестовый эскиз.")
	return {"ok": true, "png": image.save_png_to_buffer()}

static func _cutout(bytes: PackedByteArray) -> Dictionary:
	if not Tokens.valid_png(bytes, 2 * 1024 * 1024):
		return _error("Генератор вернул слишком большую или неверную PNG-картинку.")
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return _error("Не удалось прочитать PNG генератора.")
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var seen := PackedByteArray()
	seen.resize(width * height)
	var queue := PackedInt32Array()
	for x in range(width):
		queue.append(x)
		queue.append((height - 1) * width + x)
	for y in range(height):
		queue.append(y * width)
		queue.append(y * width + width - 1)
	var cursor := 0
	var removed := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		if seen[at]:
			continue
		seen[at] = 1
		var x := at % width
		var y: int = at / width
		var color := image.get_pixel(x, y)
		if color.a > 0.05 and (minf(color.r, minf(color.g, color.b)) < 0.86 or maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) > 0.12):
			continue
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		removed += 1
		if x > 0:
			queue.append(at - 1)
		if x < width - 1:
			queue.append(at + 1)
		if y > 0:
			queue.append(at - width)
		if y < height - 1:
			queue.append(at + width)
	var used := image.get_used_rect()
	if removed < width * height / 30 or used.get_area() < 100:
		return _error("Фон не удалось вырезать. Попросите один персонаж на чистом белом фоне и повторите генерацию.")
	var cropped := image.get_region(used.grow(4).intersection(Rect2i(0, 0, width, height)))
	var scale := minf(244.0 / cropped.get_width(), 372.0 / cropped.get_height())
	cropped.resize(maxi(1, int(cropped.get_width() * scale)), maxi(1, int(cropped.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(256, 384, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), Vector2i((256 - cropped.get_width()) / 2, 378 - cropped.get_height()))
	return {"ok": true, "png": canvas.save_png_to_buffer()}

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _value_at(data, path: Array, fallback):
	for key in path:
		if not data is Dictionary or not data.has(key):
			return fallback
		data = data[key]
	return data

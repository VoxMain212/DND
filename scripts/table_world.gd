@tool
extends Node3D
## Asset-free tabletop, also generated in the editor. No network dependencies.
const Rules = preload("res://scripts/room_state.gd")
const Tokens = preload("res://scripts/token_catalog.gd")
const CELL := 0.6
const MAP_Y := 0.055
var camera: Camera3D
var _wood: StandardMaterial3D
var _brass: StandardMaterial3D
var _dark: StandardMaterial3D
var _pieces: Dictionary = {}
var _tweens: Dictionary = {}
var _move_markers: Node3D
var _hover: MeshInstance3D
var _alpha_images: Dictionary = {}

func _ready() -> void:
	_build_lighting()
	_build_table()
	_build_map()
	_build_props()
	_move_markers = Node3D.new()
	add_child(_move_markers)
	_hover = _box(self, Vector3(0.57, 0.008, 0.57), Vector3.ZERO, _material(Color(0.95, 0.77, 0.35, 0.3), true))
	_hover.visible = false
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 65
	camera.fov = 43
	camera.current = true
	add_child(camera)

func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#171d25")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#b5c3d4")
	environment.environment.ambient_light_energy = 0.30
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -32, 0)
	key.light_color = Color("#ffe0ad")
	key.light_energy = 0.75
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 28
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_color = Color("#a6c8e5")
	fill.light_energy = 0.18
	add_child(fill)

func _build_table() -> void:
	_wood = _material(Color("#74503a"))
	_wood.albedo_texture = _wood_texture()
	_wood.roughness = 0.72
	_brass = _material(Color("#bd9654"))
	_brass.metallic = 0.65
	_brass.roughness = 0.38
	_dark = _material(Color("#282d30"))
	_box(self, Vector3(12.2, 0.5, 9.0), Vector3(0, -0.32, 0), _wood)
	for index in range(12):
		_box(self, Vector3(0.995, 0.15, 8.8), Vector3(-5.5 + index, -0.075, 0), _wood)
	for x in [-6.05, 6.05]:
		_box(self, Vector3(0.12, 0.12, 8.96), Vector3(x, -0.02, 0), _brass)
	for z in [-4.45, 4.45]:
		_box(self, Vector3(12.1, 0.12, 0.12), Vector3(0, -0.02, z), _brass)
	for x in [-5.1, 5.1]:
		for z in [-3.4, 3.4]:
			_box(self, Vector3(0.65, 3.1, 0.65), Vector3(x, -2.05, z), _wood)
	_box(self, Vector3(50, 0.15, 50), Vector3(0, -3.7, 0), _material(Color("#20252a")))
	for z in [-5.25, 5.25]:
		_box(self, Vector3(2.3, 0.2, 1.5), Vector3(0, -1.25, z), _wood)
		_box(self, Vector3(2.1, 0.13, 1.35), Vector3(0, -1.08, z), _material(Color("#56383a")))
		_box(self, Vector3(2.3, 2.6, 0.19), Vector3(0, -0.5, z + signf(z) * 0.8), _wood)
		for x in [-0.85, 0.85]:
			_box(self, Vector3(0.17, 2.3, 0.17), Vector3(x, -2.45, z), _wood)

func _build_map() -> void:
	var paper := _material(Color.WHITE)
	paper.albedo_texture = _map_texture()
	paper.roughness = 1.0
	_box(self, Vector3(8.55, 0.035, 6.15), Vector3(0, 0.018, 0), _material(Color("#594a35")))
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(Rules.WIDTH, Rules.HEIGHT) * CELL
	_mesh(self, sheet, Vector3(0, MAP_Y, 0), paper)
	var stone := _material(Color("#777065"))
	for x in range(Rules.WIDTH):
		for y in range(Rules.HEIGHT):
			if (x == 0 or x == Rules.WIDTH - 1 or y == 0 or y == Rules.HEIGHT - 1) and not (y == Rules.HEIGHT - 1 and x in [6, 7]):
				_box(self, Vector3(0.54, 0.14, 0.54), cell_position(Vector2i(x, y)) + Vector3(0, 0.07, 0), stone)
	for cell in Rules.BLOCKED:
		_box(self, Vector3(0.49, 0.16, 0.49), cell_position(cell) + Vector3(0, 0.08, 0), _wood)
	var title := Label3D.new()
	title.text = "ПОСЛЕДНИЙ ВЗДОХ"
	title.font_size = 64
	title.pixel_size = 0.004
	title.modulate = Color("#dec58e")
	title.outline_size = 0
	title.rotation_degrees.x = -90
	title.position = Vector3(0, 0.015, -3.5)
	add_child(title)

func _build_props() -> void:
	for position in [Vector3(-5.1, 0, 2.7), Vector3(5.1, 0, -2.8)]:
		_candle(position)
	_book(Vector3(-5.03, 0.05, -1.85))
	_tankard(Vector3(-5.0, 0.05, 0.3))
	_tankard(Vector3(4.9, 0.05, -0.2))
	for index in range(3):
		var dice := Node3D.new()
		dice.position = Vector3(4.65 + (index % 2) * 0.53, 0.22, 1.7 + index * 0.45)
		dice.rotation.y = index * 0.37 - 0.3
		add_child(dice)
		_box(dice, Vector3.ONE * 0.37, Vector3.ZERO, _material(Color("#d8c9a3") if index != 1 else Color("#884744")))
		for pip in [Vector2(-0.085, -0.085), Vector2(0.085, 0.085), Vector2.ZERO]:
			_cylinder(dice, 0.028, 0.008, Vector3(pip.x, 0.19, pip.y), _dark)
	for index in range(3):
		var screen := Node3D.new()
		screen.position = Vector3(-1.55 + index * 1.55, 0.55, -3.95 + absf(index - 1) * 0.18)
		screen.rotation.y = (index - 1) * -0.18
		add_child(screen)
		_box(screen, Vector3(1.53, 1.08, 0.09), Vector3.ZERO, _wood)
		_box(screen, Vector3(1.32, 0.87, 0.025), Vector3(0, 0, 0.06), _material(Color("#3c5552")))
		var crest := Label3D.new()
		crest.text = ["I", "DND", "IV"][index]
		crest.font_size = 72
		crest.pixel_size = 0.006
		crest.modulate = Color("#d2b67c")
		crest.outline_size = 0
		crest.position = Vector3(0, 0, 0.09)
		screen.add_child(crest)

func _candle(position: Vector3) -> void:
	_cylinder(self, 0.32, 0.07, position + Vector3(0, 0.035, 0), _brass)
	_cylinder(self, 0.09, 0.22, position + Vector3(0, 0.17, 0), _brass)
	_cylinder(self, 0.15, 0.55, position + Vector3(0, 0.51, 0), _material(Color("#d5bd8e")))
	var flame := _material(Color("#ffc768"))
	flame.emission_enabled = true
	flame.emission = Color("#ffa034")
	flame.emission_energy_multiplier = 1.8
	_sphere(self, 0.07, position + Vector3(0, 0.85, 0), flame).scale = Vector3(0.75, 1.8, 0.75)
	var light := OmniLight3D.new()
	light.position = position + Vector3(0, 1.0, 0)
	light.light_color = Color("#ffc17a")
	light.light_energy = 0.35
	light.omni_range = 3.8
	light.shadow_enabled = false
	add_child(light)

func _book(position: Vector3) -> void:
	var book := Node3D.new()
	book.position = position
	book.rotation.y = -0.18
	add_child(book)
	var cover := _material(Color("#66373b"))
	_box(book, Vector3(1.1, 0.08, 1.55), Vector3(0, 0.04, 0), cover)
	_box(book, Vector3(1.02, 0.19, 1.44), Vector3(0, 0.17, 0), _material(Color("#c9b68b")))
	_box(book, Vector3(1.1, 0.08, 1.55), Vector3(0, 0.3, 0), cover)
	_box(book, Vector3(0.08, 0.015, 1.2), Vector3(0, 0.35, 0), _brass)
	_box(book, Vector3(0.7, 0.015, 0.08), Vector3(0, 0.35, 0), _brass)

func _tankard(position: Vector3) -> void:
	_cylinder(self, 0.29, 0.55, position + Vector3(0, 0.28, 0), _wood)
	for height in [0.08, 0.49]:
		_cylinder(self, 0.31, 0.06, position + Vector3(0, height, 0), _brass)
	_cylinder(self, 0.26, 0.01, position + Vector3(0, 0.558, 0), _material(Color("#372821")))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.16
	handle.outer_radius = 0.23
	handle.rings = 12
	handle.ring_segments = 8
	_mesh(self, handle, position + Vector3(0.35, 0.29, 0), _brass).rotation.x = PI / 2

func sync_state(state: Dictionary, my_id: int) -> void:
	var preview: bool = state.is_empty()
	var entries: Array = state.get("players", []).duplicate(true)
	for foe in state.get("enemies", []):
		var entry: Dictionary = foe.duplicate()
		entry.id = "enemy:" + str(foe.id)
		entry.is_enemy = true
		entries.append(entry)
	if preview:
		entries = []
		for index in range(4):
			entries.append({"id": -index - 1, "x": Rules.SPAWNS[index].x, "y": Rules.SPAWNS[index].y,
				"name": ["Воин", "Маг", "Плут", "Жрец"][index], "color": Rules.COLORS[index], "token": Rules.TOKEN_KEYS[index], "hp": 12, "max_hp": 12})
	var present: Array = []
	for entry in entries:
		var id = entry.id
		present.append(id)
		if not _pieces.has(id):
			_pieces[id] = _make_piece(entry)
			_pieces[id].position = cell_position(Vector2i(int(entry.x), int(entry.y)))
		var piece: Node3D = _pieces[id]
		var target := cell_position(Vector2i(int(entry.x), int(entry.y)))
		piece.set_meta("cell", Vector2i(int(entry.x), int(entry.y)))
		if not piece.position.is_equal_approx(target):
			if _tweens.has(id) and _tweens[id].is_valid():
				_tweens[id].kill()
			var tween := create_tween()
			tween.tween_property(piece, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tweens[id] = tween
		piece.get_node("ActiveRing").visible = not entry.get("is_enemy", false) and not preview and state.get("phase") == "playing" and id == state.get("active", 0)
		piece.get_node("YourMark").visible = not entry.get("is_enemy", false) and id == my_id and not preview
		var dead: bool = int(entry.get("hp", 12)) <= 0
		piece.set_meta("dead", dead)
		var image: Sprite3D = piece.get_node("Portrait")
		image.texture = Tokens.texture(str(entry.get("token", "warrior")))
		image.pixel_size = minf(1.15 / image.texture.get_height(), 0.78 / image.texture.get_width())
		image.modulate = Color("#777777") if dead else Color.WHITE
		image.billboard = BaseMaterial3D.BILLBOARD_DISABLED if dead else BaseMaterial3D.BILLBOARD_FIXED_Y
		image.rotation.x = -PI / 2 if dead else 0.0
		image.position.y = 0.12 if dead else 0.12 + image.texture.get_height() * image.pixel_size / 2.0
		var health: Label3D = piece.get_node("Health")
		health.text = "%s/%s" % [entry.get("hp", 12), entry.get("max_hp", 12)]
		health.visible = not preview
		health.modulate = Color("#e99080") if dead or entry.get("is_enemy", false) else Color("#e8e3d6")
	for id in _pieces.keys():
		if id not in present:
			if _tweens.has(id) and _tweens[id].is_valid():
				_tweens[id].kill()
			_tweens.erase(id)
			_pieces[id].queue_free()
			_pieces.erase(id)
	for marker in _move_markers.get_children():
		marker.queue_free()
	if state.get("phase") != "playing" or int(state.get("active", 0)) != my_id or int(state.get("moves_left", 0)) <= 0:
		return
	for entry in entries:
		if entry.get("is_enemy", false) or entry.id != my_id:
			continue
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = Vector2i(int(entry.x), int(entry.y)) + offset
			var occupied := false
			for other in entries:
				if Vector2i(int(other.x), int(other.y)) == cell and (not other.get("is_enemy", false) or int(other.hp) > 0):
					occupied = true
			if Rules.walkable(cell) and not occupied:
				_cylinder(_move_markers, 0.11, 0.008, cell_position(cell) + Vector3(0, 0.01, 0), _material(Color("#499186"), true))

func _make_piece(entry: Dictionary) -> Node3D:
	var piece := Node3D.new()
	add_child(piece)
	var color := Color(entry.color)
	_cylinder(piece, 0.235, 0.08, Vector3(0, 0.04, 0), _dark)
	_cylinder(piece, 0.22, 0.025, Vector3(0, 0.09, 0), _material(color))
	var image := Sprite3D.new()
	image.name = "Portrait"
	image.texture = Tokens.texture(str(entry.get("token", "warrior")))
	image.pixel_size = 0.003
	image.position.y = 0.65
	image.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	image.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	image.alpha_scissor_threshold = 0.35
	image.shaded = false
	image.double_sided = true
	piece.add_child(image)
	var health := Label3D.new()
	health.name = "Health"
	health.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health.pixel_size = 0.0045
	health.font_size = 44
	health.outline_size = 6
	health.position.y = 1.28
	piece.add_child(health)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.29
	ring.rings = 24
	ring.ring_segments = 8
	var active := _mesh(piece, ring, Vector3(0, 0.035, 0), _material(Color("#e99080") if entry.get("is_enemy", false) else Color("#ffcf78"), true))
	active.name = "ActiveRing"
	var mark := _sphere(piece, 0.036, Vector3(0, 0.12, 0.18), _material(Color.WHITE, true))
	mark.name = "YourMark"
	return piece

func select_enemy(enemy_id: String) -> void:
	for id in _pieces:
		if id is String:
			_pieces[id].get_node("ActiveRing").visible = id == "enemy:" + enemy_id and not _pieces[id].get_meta("dead", false)

func pick_piece(screen_position: Vector2) -> Vector2i:
	# Intersect the same upright billboard plane the player sees, then test PNG alpha.
	var origin := camera.project_ray_origin(screen_position)
	var ray := camera.project_ray_normal(screen_position)
	var normal := camera.global_basis.z
	normal.y = 0
	normal = normal.normalized()
	var right := Vector3.UP.cross(normal)
	var nearest := INF
	var cell := Vector2i(-1, -1)
	for piece in _pieces.values():
		if piece.get_meta("dead", false):
			continue
		var portrait: Sprite3D = piece.get_node("Portrait")
		var center: Vector3 = piece.position + portrait.position
		var hit = Plane(normal, normal.dot(center)).intersects_ray(origin, ray)
		if hit == null:
			continue
		var delta: Vector3 = hit - center
		var u: float = delta.dot(right) / (portrait.texture.get_width() * portrait.pixel_size) + 0.5
		var v: float = 0.5 - delta.y / (portrait.texture.get_height() * portrait.pixel_size)
		if u < 0 or u >= 1 or v < 0 or v >= 1:
			continue
		var key := str(portrait.texture.get_instance_id())
		if not _alpha_images.has(key):
			var image := portrait.texture.get_image()
			if image.is_compressed():
				image.decompress()
			_alpha_images[key] = image
		var alpha: Image = _alpha_images[key]
		if alpha.get_pixel(int(u * alpha.get_width()), int(v * alpha.get_height())).a < portrait.alpha_scissor_threshold:
			continue
		var distance: float = origin.distance_squared_to(hit)
		if distance < nearest:
			nearest = distance
			cell = piece.get_meta("cell")
	return cell

func hover_cell(cell: Vector2i) -> void:
	_hover.visible = Rules.walkable(cell)
	if _hover.visible:
		_hover.position = cell_position(cell) + Vector3(0, 0.018, 0)

static func cell_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5 - Rules.WIDTH / 2.0) * CELL, MAP_Y + 0.007, (cell.y + 0.5 - Rules.HEIGHT / 2.0) * CELL)

static func position_cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL + Rules.WIDTH / 2.0), floori(position.z / CELL + Rules.HEIGHT / 2.0))

func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = dimensions
	return _mesh(parent, box, at, material)

func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 20
	return _mesh(parent, cylinder, at, material)

func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 12
	sphere.rings = 6
	return _mesh(parent, sphere, at, material)

func _map_texture() -> ImageTexture:
	const PIXELS := 72
	var image := Image.create(Rules.WIDTH * PIXELS, Rules.HEIGHT * PIXELS, false, Image.FORMAT_RGB8)
	image.fill(Color("#c5b68d"))
	for y in range(Rules.HEIGHT):
		for x in range(Rules.WIDTH):
			var wall := x == 0 or x == Rules.WIDTH - 1 or y == 0 or y == Rules.HEIGHT - 1
			var color := Color("#978465") if wall else Color("#baa57d") if (x + y) % 2 == 0 else Color("#b5a079")
			image.fill_rect(Rect2i(x * PIXELS + 1, y * PIXELS + 1, PIXELS - 2, PIXELS - 2), color)
	image.fill_rect(Rect2i(4 * PIXELS + 6, 2 * PIXELS + 6, 6 * PIXELS - 12, 6 * PIXELS - 12), Color("#996f5e"))
	image.fill_rect(Rect2i(4 * PIXELS + 13, 2 * PIXELS + 13, 6 * PIXELS - 26, 6 * PIXELS - 26), Color("#b88c70"))
	for x in range(1, Rules.WIDTH):
		image.fill_rect(Rect2i(x * PIXELS, PIXELS, 1, (Rules.HEIGHT - 2) * PIXELS), Color("#8b795d"))
	for y in range(1, Rules.HEIGHT):
		image.fill_rect(Rect2i(PIXELS, y * PIXELS, (Rules.WIDTH - 2) * PIXELS, 1), Color("#8b795d"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 109
	for index in range(13000):
		var x := rng.randi_range(0, image.get_width() - 1)
		var y := rng.randi_range(0, image.get_height() - 1)
		image.set_pixel(x, y, image.get_pixel(x, y).darkened(rng.randf_range(0.01, 0.10)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _wood_texture() -> ImageTexture:
	var image := Image.create(128, 256, false, Image.FORMAT_RGB8)
	for x in range(128):
		for y in range(256):
			var grain := sin(x * 1.7 + sin(y * 0.037) * 1.1) * 0.07 + sin(x * 0.18 + sin(y * 0.021)) * 0.12
			image.set_pixel(x, y, Color(0.76 + grain, 0.65 + grain, 0.52 + grain))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

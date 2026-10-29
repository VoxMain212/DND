@tool
extends SubViewportContainer
## Orbit/pan camera and picking against the paper plane, independent of physics.
signal cell_clicked(cell: Vector2i)
const World = preload("res://scripts/table_world.gd")
const INVALID_CELL := Vector2i(-1, -1)
var _viewport: SubViewport
var _world: Node3D
var _yaw := 0.12
var _pitch := 0.83
var _distance := 15.8
var _focus := Vector3.ZERO

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.positional_shadow_atlas_size = 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_world = World.new()
	_viewport.add_child(_world)
	_update_camera()
	_world.sync_state({}, 0)
	mouse_exited.connect(func(): _world.hover_cell(INVALID_CELL))

func display_state(state: Dictionary, my_id: int) -> void:
	_world.sync_state(state, my_id)

func select_enemy(enemy_id: String) -> void:
	_world.select_enemy(enemy_id)

func reset_camera() -> void:
	_yaw = 0.12
	_pitch = 0.83
	_distance = 15.8
	_focus = Vector3.ZERO
	_update_camera()

func top_view() -> void:
	_yaw = 0.0
	_pitch = 1.30
	_distance = 13.3
	_focus = Vector3.ZERO
	_update_camera()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance * 0.91, 7.5, 23.0)
			_update_camera()
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance / 0.91, 7.5, 23.0)
			_update_camera()
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = _world.pick_piece(event.position)
			if cell == INVALID_CELL:
				cell = cell_at(event.position)
			if cell != INVALID_CELL:
				cell_clicked.emit(cell)
			accept_event()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= event.relative.x * 0.006
			_pitch = clampf(_pitch + event.relative.y * 0.006, 0.40, 1.40)
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right: Vector3 = _world.camera.global_basis.x
			var forward := Vector3(-right.z, 0, right.x)
			_focus += (-right * event.relative.x - forward * event.relative.y) * _distance * 0.0013
			_focus.x = clampf(_focus.x, -3.0, 3.0)
			_focus.z = clampf(_focus.z, -2.0, 2.0)
			_update_camera()
		_world.hover_cell(cell_at(event.position))

func _update_camera() -> void:
	if _world == null or _world.camera == null:
		return
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_world.camera.position = _focus + offset
	_world.camera.look_at(_focus, Vector3.UP)

func cell_at(screen_position: Vector2) -> Vector2i:
	if _world == null or not Rect2(Vector2.ZERO, size).has_point(screen_position):
		return INVALID_CELL
	var camera: Camera3D = _world.camera
	var origin := camera.project_ray_origin(screen_position)
	var ray := camera.project_ray_normal(screen_position)
	var hit = Plane(Vector3.UP, World.MAP_Y).intersects_ray(origin, ray)
	if hit == null:
		return INVALID_CELL
	var cell: Vector2i = World.position_cell(hit)
	if cell.x < 0 or cell.y < 0 or cell.x >= World.Rules.WIDTH or cell.y >= World.Rules.HEIGHT:
		return INVALID_CELL
	return cell

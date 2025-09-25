extends CharacterBody3D

@export var look_sensitivity: float = 0.002
@export var jump_velocity: float = 6.0
@export var auto_bhop: bool = true

const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY: float = 2.4
var headbob_time: float = 0.0

@export_category("Ground Movement")
@export var walk_speed: float = 7.0
@export var sprint_speed: float = 8.5
@export var ground_acceleration: float = 14.0
@export var ground_deceleration: float = 10.0
@export var ground_friction: float = 6.0

@export_category("Air Movement")
@export var air_cap: float = 0.85
@export var air_acceleration: float = 800.0
@export var air_move_speed: float = 500.0

var wish_direction: Vector3 = Vector3.ZERO
var camera_aligned_wish_direction: Vector3 = Vector3.ZERO

var noclip_speed_multiplier: float = 3.0
var noclip: bool = false

const MAX_STEP_HEIGHT: float = 0.5
var _snapped_to_stairs_last_frame: bool = false
var _last_frame_was_on_floor: float = -INF

var _saved_camera_global_position = null


func get_move_speed() -> float:
	return sprint_speed if Input.is_action_pressed("sprint") else walk_speed


func clip_velocity(normal: Vector3, overbounce: float) -> void:
	var backoff: float = self.velocity.dot(normal) * overbounce

	if backoff >= 0:
		return

	var change: Vector3 = normal * backoff
	self.velocity -= change

	var adjust: float = self.velocity.dot(normal)
	if adjust < 0.0:
		self.velocity -= normal * adjust


func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle


func _ready() -> void:
	for child: Node in %WorldModel.find_children("*", "VisualInstance3D"):
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sensitivity)
			%Camera3D.rotate_x(-event.relative.y * look_sensitivity)
			%Camera3D.rotation.x = clamp(%Camera3D.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _physics_process(delta: float) -> void:
	if is_on_floor():
		_last_frame_was_on_floor = Engine.get_physics_frames()

	var input_direction: Vector2 = (
		Input.get_vector("move_left", "move_right", "move_forward", "move_backward").normalized()
	)

	wish_direction = (
		self.global_transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)
	)
	camera_aligned_wish_direction = (
		%Camera3D.global_transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)
	)

	if not _handle_noclip(delta):
		if is_on_floor() or _snapped_to_stairs_last_frame:
			if (
				Input.is_action_just_pressed("jump")
				or (auto_bhop and Input.is_action_pressed("jump"))
			):
				self.velocity.y = jump_velocity

			_handle_ground_physics(delta)
		else:
			_handle_air_physics(delta)

		if not _snap_up_to_stairs_check(delta):
			move_and_slide()
			_snap_down_to_stairs_check()

	_slide_camera_smooth_back_to_origin(delta)


func _headbob_effect(delta: float) -> void:
	headbob_time += delta * self.velocity.length()
	%Camera3D.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)


func _run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool:
	if not result:
		result = PhysicsTestMotionResult3D.new()

	var parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	parameters.from = from
	parameters.motion = motion

	return PhysicsServer3D.body_test_motion(self.get_rid(), parameters, result)


func _handle_air_physics(delta: float) -> void:
	self.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var current_speed_in_wish_direction: float = self.velocity.dot(wish_direction)
	var capped_speed: float = min((air_move_speed * wish_direction).length(), air_cap)
	var add_speed_until_cap: float = capped_speed - current_speed_in_wish_direction

	if add_speed_until_cap > 0:
		var acceleration_speed: float = air_acceleration * air_move_speed * delta
		acceleration_speed = min(acceleration_speed, add_speed_until_cap)
		self.velocity += acceleration_speed * wish_direction

	if is_on_wall():
		if is_surface_too_steep(get_wall_normal()):
			self.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		else:
			self.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

		clip_velocity(get_wall_normal(), 1)  # Allows surf


func _handle_ground_physics(delta: float) -> void:
	var current_speed_in_wish_direction: float = self.velocity.dot(wish_direction)
	var add_speed_until_cap: float = get_move_speed() - current_speed_in_wish_direction

	if add_speed_until_cap > 0:
		var acceleration_speed: float = ground_acceleration * delta * get_move_speed()
		acceleration_speed = min(acceleration_speed, add_speed_until_cap)
		self.velocity += acceleration_speed * wish_direction

	# Apply friction
	var control: float = max(self.velocity.length(), ground_deceleration)
	var drop: float = control * ground_friction * delta
	var new_speed: float = max(self.velocity.length() - drop, 0.0)

	if self.velocity.length() > 0:
		new_speed /= self.velocity.length()
	self.velocity *= new_speed

	_headbob_effect(delta)


func _handle_noclip(delta: float) -> bool:
	if Input.is_action_just_pressed("noclip") and OS.has_feature("debug"):
		noclip = !noclip

	$CollisionShape3D.disabled = noclip

	if not noclip:
		return false

	var speed: float = get_move_speed() * noclip_speed_multiplier
	if Input.is_action_pressed("sprint"):
		speed *= 3.0

	self.velocity = camera_aligned_wish_direction * speed
	global_position += self.velocity * delta

	return true


func _snap_up_to_stairs_check(delta: float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame:
		return false

	# Don't snap stairs if trying to jump, also no need to check for stairs ahead if not moving
	if self.velocity.y > 0 or (self.velocity * Vector3(1, 0, 1)).length() == 0:
		return false

	var expected_move_motion: Vector3 = self.velocity * Vector3(1, 0, 1) * delta
	var step_position_with_clearance: Transform3D = self.global_transform.translated(
		expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0)
	)
	var down_check_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

	if (
		_run_body_test_motion(
			step_position_with_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_check_result
		)
		and (
			down_check_result.get_collider().is_class("StaticBody3D")
			or down_check_result.get_collider().is_class("CSGShape3D")
		)
	):
		var step_height: float = (
			(
				(step_position_with_clearance.origin + down_check_result.get_travel())
				- self.global_position
			)
			. y
		)

		if (
			step_height > MAX_STEP_HEIGHT
			or step_height <= 0.01  # 0.01 is a magic number found through testing to prevent some glitchiness in the physics
			or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT
		):
			return false

		%StairsAheadRayCast3D.global_position = (
			down_check_result.get_collision_point()
			+ Vector3(0, MAX_STEP_HEIGHT, 0)
			+ expected_move_motion.normalized() * 0.1
		)
		%StairsAheadRayCast3D.force_raycast_update()
		if (
			%StairsAheadRayCast3D.is_colliding()
			and not is_surface_too_steep(%StairsAheadRayCast3D.get_collision_normal())
		):
			_save_camera_position_for_smoothing()
			self.global_position = (
				step_position_with_clearance.origin + down_check_result.get_travel()
			)
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true

			return true

	return false


func _snap_down_to_stairs_check() -> void:
	var did_snap: bool = false
	var floor_below: bool = (
		%StairsBelowRayCast3D.is_colliding()
		and not is_surface_too_steep(%StairsBelowRayCast3D.get_collision_normal())
	)
	var was_on_floor_last_frame: bool = Engine.get_physics_frames() - _last_frame_was_on_floor == 1

	if (
		not is_on_floor()
		and velocity.y <= 0
		and (was_on_floor_last_frame or _snapped_to_stairs_last_frame)
		and floor_below
	):
		var body_test_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

		if _run_body_test_motion(
			self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result
		):
			_save_camera_position_for_smoothing()

			var translate_y: float = body_test_result.get_travel().y

			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true

	_snapped_to_stairs_last_frame = did_snap


func _save_camera_position_for_smoothing() -> void:
	if _saved_camera_global_position == null:
		_saved_camera_global_position = %CameraSmooth.global_position


func _slide_camera_smooth_back_to_origin(delta: float) -> void:
	if _saved_camera_global_position == null:
		return

	%CameraSmooth.global_position.y = _saved_camera_global_position.y
	%CameraSmooth.position.y = clamp(%CameraSmooth.position.y, -0.7, 0.7)  # Clamp incase teleported

	var move_amount: float = max(self.velocity.length() * delta, walk_speed / 2 * delta)

	%CameraSmooth.position.y = move_toward(%CameraSmooth.position.y, 0.0, move_amount)
	_saved_camera_global_position = %CameraSmooth.global_position

	if %CameraSmooth.position.y == 0:
		_saved_camera_global_position = null  # Stop smoothing the camera
